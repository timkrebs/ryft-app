import Foundation
import os
import SwiftData

/// A submitted read-model write: `committed()` returns once its batch is readable through the Repository, or was
/// dropped. Its completion is a continuation the drain resumes, never a writer job, so awaiting it from the main actor
/// never runs SwiftData work there (ADR 0018).
struct WriteTicket: Sendable {
    fileprivate let box: TicketBox

    /// Not cancellable: the write is queued and ends either way, within one batch.
    @discardableResult
    func committed() async -> WriteReceipt {
        await box.receipt()
    }
}

/// One ticket's result, and whoever waits for it.
private final class TicketBox: Sendable {
    private struct State: Sendable {
        var receipt: WriteReceipt?
        var waiters: [CheckedContinuation<WriteReceipt, Never>] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func receipt() async -> WriteReceipt {
        await withCheckedContinuation { (c: CheckedContinuation<WriteReceipt, Never>) in
            let ready = state.withLock { s -> WriteReceipt? in
                if let r = s.receipt { return r }
                s.waiters.append(c)
                return nil
            }
            if let ready { c.resume(returning: ready) }
        }
    }

    func resolve(_ receipt: WriteReceipt) {
        let waiters = state.withLock { s -> [CheckedContinuation<WriteReceipt, Never>] in
            guard s.receipt == nil else { return [] }
            s.receipt = receipt
            defer { s.waiters = [] }
            return s.waiters
        }
        for waiter in waiters { waiter.resume(returning: receipt) }
    }
}

/// The read models' write queue (ADR 0018). The Repository submits synchronously, in the same main-actor step as its
/// account check; the drain applies what's pending in submit order, one batch at a time, through the store's
/// `ReadModelWriter`, then has the Repository commit on the main actor and resolves the batch's tickets.
///
/// - **Submit order**: Swift actors run jobs by priority, not first in, first out, so the order lives in this queue.
/// - **Batches** never span a store, an epoch or a seed: one save each, and one revision bump per kind.
/// - **Off the main actor, by structure**: the writer is private to this file, and only this actor awaits it. A
///   `@ModelActor`'s job runs on the thread that awaits it (T0.1, iOS 27.2), so no main-actor code can reach one.
/// - **The wipe**: a batch whose epoch is over is dropped; the writer saves inside `StoreEpoch.ifCurrent`; a new epoch or
///   a seed gets a new writer, so no context keeps rows the wipe deleted or a seed changed.
actor ReadModelDrain {
    /// Where a write goes: one store's container, its wipe epoch, and how often the Repository seeded it.
    struct Target: Sendable {
        let container: ModelContainer
        let epoch: StoreEpoch
        /// `Repository.seed` writes on a context of its own: the writer after it is a new one.
        let generation: Int
        var store: ObjectIdentifier { ObjectIdentifier(container) }
    }

    /// Tests watch (and hold) the writer through these. Every closure runs on the writer's thread.
    struct Hooks: Sendable {
        /// Each writer job, with whether it ran on the main thread.
        var job: (@Sendable (_ onMainThread: Bool) -> Void)?
        /// Inside the save's critical section, before the save: a wipe that starts now waits.
        var insideSave: (@Sendable () -> Void)?
        /// After each save the store took.
        var saved: (@Sendable () -> Void)?
        /// Each new writer (the first write to a store, the first after a wipe or a seed).
        var writerMade: (@Sendable () -> Void)?
    }

    /// The Repository's commit on the main actor: a new read context for the store, the receipt's kinds forgotten.
    /// With the batch's target and epoch: a wipe may have come after its save.
    typealias Commit = @MainActor @Sendable (WriteReceipt, _ target: Target, _ epoch: Int) -> Void

    private struct Submitted: Sendable {
        let op: ReadModelWrite
        let now: Date
        let target: Target
        let epoch: Int
        let ticket: TicketBox
    }

    private struct Queue: Sendable {
        var pending: [Submitted] = []
        var draining = false
        var last: TicketBox?
        var hooks = Hooks()
    }

    private struct WriterKey: Equatable {
        let epoch: Int
        let generation: Int
    }

    private let queue = OSAllocatedUnfairLock(initialState: Queue())
    private let commit: Commit
    private var writers: [ObjectIdentifier: (key: WriterKey, writer: ReadModelWriter)] = [:]

    init(commit: @escaping Commit) {
        self.commit = commit
    }

    /// Queues `op` for `target` at the store's current epoch and starts the drain if it's idle. Never awaits.
    nonisolated func submit(_ op: ReadModelWrite, to target: Target, now: Date) -> WriteTicket {
        let ticket = TicketBox()
        let item = Submitted(op: op, now: now, target: target, epoch: target.epoch.current, ticket: ticket)
        let start = queue.withLock { q -> Bool in
            q.pending.append(item)
            q.last = ticket
            guard !q.draining else { return false }
            q.draining = true
            return true
        }
        // Inherits the submitter's priority.
        if start { Task { await self.drain() } }
        return WriteTicket(box: ticket)
    }

    /// Nothing is queued or being written.
    nonisolated var isIdle: Bool { queue.withLock { !$0.draining } }

    /// The last write submitted: once it's resolved, every earlier one is.
    nonisolated var lastSubmitted: WriteTicket? { queue.withLock { $0.last.map(WriteTicket.init(box:)) } }

    nonisolated func setHooks(_ hooks: Hooks) {
        queue.withLock { $0.hooks = hooks }
    }

    private func drain() async {
        var next = nextBatch()
        while let batch = next, let first = batch.first {
            let receipt = await write(batch)
            await commit(receipt, first.target, first.epoch)
            // Idle before the last tickets resolve: whoever awaited them may `seed` next.
            next = nextBatch()
            for item in batch { item.ticket.resolve(receipt) }
        }
    }

    /// Everything pending up to the first change of store, epoch or seed; nil, and the drain idle, when nothing is.
    private nonisolated func nextBatch() -> [Submitted]? {
        queue.withLock { q -> [Submitted]? in
            guard let first = q.pending.first else {
                q.draining = false
                return nil
            }
            let count = q.pending.prefix {
                $0.target.store == first.target.store && $0.epoch == first.epoch
                    && $0.target.generation == first.target.generation
            }.count
            let batch = Array(q.pending.prefix(count))
            q.pending.removeFirst(count)
            return batch
        }
    }

    private func write(_ batch: [Submitted]) async -> WriteReceipt {
        guard let first = batch.first else { return WriteReceipt() }
        // A wipe since it was submitted: nothing to write, and no writer for an epoch that's over.
        guard first.target.epoch.current == first.epoch else { return WriteReceipt(dropped: true) }
        let key = WriterKey(epoch: first.epoch, generation: first.target.generation)
        let writer: ReadModelWriter
        if let cached = writers[first.target.store], cached.key == key {
            writer = cached.writer
        } else {
            // The first write, a wipe or a seed: a context that holds nothing from before.
            writer = ReadModelWriter(modelContainer: first.target.container)
            writers[first.target.store] = (key, writer)
            queue.withLock { $0.hooks }.writerMade?()
        }
        let hooks = queue.withLock { $0.hooks }
        return await writer.apply(batch.map { ReadModelWriteItem(op: $0.op, now: $0.now) }, batchEpoch: first.epoch,
                                  of: first.target.epoch, hooks: hooks)
    }
}

private struct ReadModelWriteItem: Sendable {
    let op: ReadModelWrite
    let now: Date
}

/// The store's one writer of the read models (ADR 0018): a `@ModelActor` on its own container, never a second container.
/// Private to this file: only `ReadModelDrain` awaits it, from its own executor, so its jobs run off the main thread.
@ModelActor
private actor ReadModelWriter {
    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "reads")

    /// Applies `items` in order and saves once, inside `epoch.ifCurrent(batchEpoch)`. A wipe in between: rolled back,
    /// `dropped`. A refused save: rolled back, nothing saved; the kinds still go to the readers, who read what the store
    /// has.
    func apply(_ items: [ReadModelWriteItem], batchEpoch: Int, of epoch: StoreEpoch,
               hooks: ReadModelDrain.Hooks) -> WriteReceipt {
        hooks.job?(MainThread.isCurrent)
        MainThread.assertOff("A read-model write")
        let signposts = Signposts.reads
        let interval = signposts.beginInterval("write", id: signposts.makeSignpostID(), "\(items.count, privacy: .public) ops")
        defer { signposts.endInterval("write", interval) }
        modelContext.autosaveEnabled = false
        var receipt = WriteReceipt()
        for item in items {
            ReadModelWrites.apply(item.op, in: modelContext, now: item.now, into: &receipt)
        }
        let saved = epoch.ifCurrent(batchEpoch) { () -> Bool in
            hooks.insideSave?()
            guard modelContext.hasChanges else { return true }
            do {
                try modelContext.save()
                hooks.saved?()
                return true
            } catch {
                // Domain and code only: a store error's description can quote values.
                let e = error as NSError
                Self.log.error("Read-model save failed: \(e.domain, privacy: .public) \(e.code, privacy: .public)")
                return false
            }
        }
        switch saved {
        case true?:
            receipt.saved = true
            return receipt
        case false?:
            modelContext.rollback()
            receipt.saved = false
            receipt.publishesWidget = false
            return receipt
        case nil:
            modelContext.rollback()
            return WriteReceipt(dropped: true)
        }
    }
}
