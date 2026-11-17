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

    /// The same, but a cancelled caller stops waiting (nil); the write goes on. For waits with a deadline.
    func committedUnlessCancelled() async -> WriteReceipt? {
        await box.receiptUnlessCancelled()
    }

    /// A write that was never queued (an answer for someone else, `Repository.store(user:asOf:)`).
    static var dropped: WriteTicket {
        let box = TicketBox()
        box.resolve(WriteReceipt(dropped: true))
        return WriteTicket(box: box)
    }
}

/// One ticket's result, and whoever waits for it.
private final class TicketBox: Sendable {
    private struct State: Sendable {
        var receipt: WriteReceipt?
        var waiters: [CheckedContinuation<WriteReceipt, Never>] = []
        /// Waits that a cancellation may end early, by id.
        var cancellable: [UUID: CheckedContinuation<WriteReceipt?, Never>] = [:]
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

    func receiptUnlessCancelled() async -> WriteReceipt? {
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<WriteReceipt?, Never>) in
                let now = state.withLock { s -> (ready: Bool, receipt: WriteReceipt?) in
                    if let r = s.receipt { return (true, r) }
                    // Cancelled before it got here: the handler found nothing to resume.
                    if Task.isCancelled { return (true, nil) }
                    s.cancellable[id] = c
                    return (false, nil)
                }
                if now.ready { c.resume(returning: now.receipt) }
            }
        } onCancel: {
            state.withLock { $0.cancellable.removeValue(forKey: id) }?.resume(returning: nil)
        }
    }

    func resolve(_ receipt: WriteReceipt) {
        let waiting = state.withLock { s -> State? in
            guard s.receipt == nil else { return nil }
            s.receipt = receipt
            defer {
                s.waiters = []
                s.cancellable = [:]
            }
            return s
        }
        for waiter in waiting?.waiters ?? [] { waiter.resume(returning: receipt) }
        for waiter in (waiting?.cancellable ?? [:]).values { waiter.resume(returning: receipt) }
    }
}

/// The read models' write queue (ADR 0018). The Repository submits synchronously, in the same main-actor step as its
/// account check; the drain applies what's pending in submit order, one batch at a time, through the store's
/// `ReadModelWriter`, then has the Repository commit on the main actor and resolves the batch's tickets.
///
/// - **Submit order**: Swift actors run jobs by priority, not first in, first out, so the order lives in this queue.
/// - **Priority**: the drain runs at `.userInitiated`, whoever submitted first. Awaiting a ticket doesn't raise it (a
///   continuation doesn't escalate the task that resumes it), and a pull's write mustn't wait at a background sync's.
/// - **Batches** never span a store, an epoch or a seed: one save each, and one revision bump per kind.
/// - **Off the main actor, by structure**: the writer is private to this file, and only this actor makes it and awaits
///   it, both on its own executor. Which of the two decides a `@ModelActor` job's thread depends on the OS (T0.1): the
///   thread that made the actor on iOS 17.0, the thread that awaits it on iOS 27.2. Made and awaited off main, its jobs
///   run off main on both, and no main-actor code can reach one.
/// - **The wipe**: a batch whose epoch is over is dropped; the writer saves inside `StoreEpoch.ifCurrent`; a new epoch or
///   a seed gets a new writer, so no context keeps rows the wipe deleted or a seed changed. A writer whose epoch is
///   over goes when the drain falls idle and at `retireWiped()` (the Repository's `invalidate()`), so the rows its
///   context registered don't outlive the wipe in memory either. A store the Repository let go of (`retire(_:)`, demo
///   data's at the switch) has its epoch moved on, so the same holds: its writes still queued drop, a batch in its
///   writer doesn't save (or commits as not current), and its writer goes. Nothing is submitted to it afterwards: the
///   Repository builds each write's `Target` from its current store, in the step that submits it.
/// - **Paused** (`pause()`, before a system completion whose wait ran out): no batch starts until `resume()`, so none
///   is mid-save in the App Group's store when iOS suspends the app (0xdead10cc); the batch in progress finishes
///   (`batchInProgress`).
actor ReadModelDrain {
    /// Where a write goes: one store's container, its wipe epoch, and how often the Repository seeded it.
    struct Target: Sendable {
        let container: ModelContainer
        let epoch: StoreEpoch
        /// `Repository.seed` writes on a context of its own: the writer after it is a new one.
        let generation: Int
        var store: StoreID { epoch.store }
    }

    /// Tests watch (and hold) the writer through these. Every closure runs off the main thread: on the writer's, but
    /// `beforeCommit` on the drain's.
    struct Hooks: Sendable {
        /// Each writer job, with whether it ran on the main thread.
        var job: (@Sendable (_ onMainThread: Bool) -> Void)?
        /// Inside the save's critical section, before the save: a wipe that starts now waits.
        var insideSave: (@Sendable () -> Void)?
        /// After each save the store took.
        var saved: (@Sendable () -> Void)?
        /// Each new writer (the first write to a store, the first after a wipe or a seed), with whether it was made on
        /// the main thread.
        var writerMade: (@Sendable (_ onMainThread: Bool) -> Void)?
        /// Inside the save's critical section: true makes this save fail as a refused one does (rolled back).
        var refusesSave: (@Sendable () -> Bool)?
        /// After a batch's save, before its commit hops to the main actor (on the drain's executor).
        var beforeCommit: (@Sendable () -> Void)?
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
        /// `pause()` until `resume()`: no batch starts.
        var paused = false
        /// The batch being written, by its last ticket; nil between batches.
        var writing: TicketBox?
    }

    private struct WriterKey: Equatable {
        let epoch: Int
        let generation: Int
    }

    private struct CachedWriter {
        let key: WriterKey
        let writer: ReadModelWriter
        /// Its store's epoch: once it has moved on, the writer is retired.
        let epoch: StoreEpoch
    }

    private let queue = OSAllocatedUnfairLock(initialState: Queue())
    private let commit: Commit
    private var writers: [StoreID: CachedWriter] = [:]

    init(commit: @escaping Commit) {
        self.commit = commit
    }

    /// Queues `op` for `target` at `epoch` (the store's current one when nil) and starts the drain if it's idle. Never
    /// awaits. An `epoch` from before a wipe makes the write drop.
    nonisolated func submit(_ op: ReadModelWrite, to target: Target, at epoch: Int? = nil, now: Date) -> WriteTicket {
        let ticket = TicketBox()
        let item = Submitted(op: op, now: now, target: target, epoch: epoch ?? target.epoch.current, ticket: ticket)
        let start = queue.withLock { q -> Bool in
            q.pending.append(item)
            q.last = ticket
            guard !q.draining else { return false }
            q.draining = true
            return true
        }
        // Not the submitter's priority: a background submitter's would hold back a pull's write queued behind it.
        if start { Task(priority: .userInitiated) { await self.drain() } }
        return WriteTicket(box: ticket)
    }

    /// Retires the writers whose epoch is over (the Repository's `invalidate()`, after a wipe): their contexts let go
    /// of the rows they registered.
    nonisolated func retireWiped() {
        Task(priority: .userInitiated) { await self.retireWipedWriters() }
    }

    /// The store of `epoch` is gone (the Repository let go of demo data's): its epoch moves on, so a batch in its writer
    /// doesn't save (or, saved, commits as not current: no widget, no second try), a write still queued for it drops,
    /// and its writer and container go too. Every write for it was submitted before this, at an epoch from then: the
    /// epoch alone tells them apart. On the main actor this waits for a save of that store in progress (an in-memory
    /// one: milliseconds), as a wipe's `advance()` does.
    nonisolated func retire(_ epoch: StoreEpoch) {
        epoch.advance()
        Task(priority: .userInitiated) { await self.retireWipedWriters() }
    }

    /// No batch starts from now until `resume()`; the one in progress finishes, and is returned (in the same step, so
    /// no batch can start between the two). Writes submitted meanwhile wait in the queue.
    @discardableResult
    nonisolated func pause() -> WriteTicket? {
        queue.withLock { q -> WriteTicket? in
            q.paused = true
            return q.writing.map(WriteTicket.init(box:))
        }
    }

    /// Batches start again, the writes queued meanwhile first.
    nonisolated func resume() {
        let start = queue.withLock { q -> Bool in
            q.paused = false
            guard !q.draining, !q.pending.isEmpty else { return false }
            q.draining = true
            return true
        }
        if start { Task(priority: .userInitiated) { await self.drain() } }
    }

    /// Batches wait for `resume()` (tests).
    nonisolated var isPaused: Bool { queue.withLock { $0.paused } }

    /// The batch being written now, if any: its ticket resolves once it's committed (or dropped).
    nonisolated var batchInProgress: WriteTicket? { queue.withLock { $0.writing.map(WriteTicket.init(box:)) } }

    /// The epoch of each store's cached writer (tests).
    var writerEpochs: [StoreID: Int] { writers.mapValues(\.key.epoch) }

    /// Nothing is queued or being written.
    nonisolated var isIdle: Bool { queue.withLock { !$0.draining && $0.pending.isEmpty } }

    /// The last write submitted: once it's resolved, every earlier one is.
    nonisolated var lastSubmitted: WriteTicket? { queue.withLock { $0.last.map(WriteTicket.init(box:)) } }

    nonisolated func setHooks(_ hooks: Hooks) {
        queue.withLock { $0.hooks = hooks }
    }

    private func drain() async {
        var next = nextBatch()
        while let batch = next, let first = batch.first {
            let receipt = await write(batch)
            queue.withLock { $0.hooks }.beforeCommit?()
            await commit(receipt, first.target, first.epoch)
            // Idle before the last tickets resolve: whoever awaited them may `seed` next.
            next = nextBatch()
            for item in batch { item.ticket.resolve(receipt) }
        }
        retireWipedWriters()
    }

    /// Drops the writers whose epoch is over: a wipe's, or a retired store's.
    private func retireWipedWriters() {
        writers = writers.filter { $0.value.epoch.current == $0.value.key.epoch }
    }

    /// Everything pending up to the first change of store, epoch or seed; nil, and the drain idle, when nothing is or
    /// the drain is paused.
    private nonisolated func nextBatch() -> [Submitted]? {
        queue.withLock { q -> [Submitted]? in
            guard !q.paused, let first = q.pending.first else {
                q.draining = false
                q.writing = nil
                return nil
            }
            let count = q.pending.prefix {
                $0.target.store == first.target.store && $0.epoch == first.epoch
                    && $0.target.generation == first.target.generation
            }.count
            let batch = Array(q.pending.prefix(count))
            q.pending.removeFirst(count)
            q.writing = batch.last?.ticket
            return batch
        }
    }

    private func write(_ batch: [Submitted]) async -> WriteReceipt {
        guard let first = batch.first else { return WriteReceipt() }
        // A wipe since it was submitted, or its store let go of (`retire`): nothing to write, and no writer for it.
        guard first.target.epoch.current == first.epoch else { return WriteReceipt(dropped: true) }
        let key = WriterKey(epoch: first.epoch, generation: first.target.generation)
        let writer: ReadModelWriter
        if let cached = writers[first.target.store], cached.key == key {
            writer = cached.writer
        } else {
            // The first write, a wipe or a seed: a context that holds nothing from before. Made here, on this actor's
            // executor: on iOS 17 the thread that makes a model actor runs its jobs (T0.1).
            queue.withLock { $0.hooks }.writerMade?(MainThread.isCurrent)
            MainThread.assertOff("Making a read-model writer")
            writer = ReadModelWriter(modelContainer: first.target.container)
            writers[first.target.store] = CachedWriter(key: key, writer: writer, epoch: first.target.epoch)
        }
        let hooks = queue.withLock { $0.hooks }
        let receipt = await writer.apply(batch.map { ReadModelWriteItem(op: $0.op, now: $0.now) },
                                         batchEpoch: first.epoch, of: first.target.epoch, hooks: hooks)
        // Not saved: the batch's changes are still in the writer's context (`ReadModelWriter.apply` doesn't roll back),
        // so the next batch gets a new writer, whose context has only what the store has.
        if !receipt.saved, writers[first.target.store]?.writer === writer { writers[first.target.store] = nil }
        return receipt
    }
}

private struct ReadModelWriteItem: Sendable {
    let op: ReadModelWrite
    let now: Date
}

/// The store's one writer of the read models (ADR 0018): a `@ModelActor` on its own container, never a second container.
/// Private to this file: only `ReadModelDrain` makes it and awaits it, both from its own executor, so its jobs run off
/// the main thread whichever of the two the OS goes by (T0.1).
@ModelActor
private actor ReadModelWriter {
    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "reads")

    /// Applies `items` in order and saves once, inside `epoch.ifCurrent(batchEpoch)`. A wipe in between: `dropped`. A
    /// refused save: nothing saved; the kinds still go to the readers, who read what the store has. Neither is rolled
    /// back: on iOS 17.0 rolling back a refused change to rows the store has (the user's delete and insert in the older
    /// of two containers, T0.6) traps inside SwiftData. The drain lets go of this writer instead, and of the change in
    /// its context (`ReadModelDrain.write`).
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
            if hooks.refusesSave?() == true { return false }
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
            receipt.saved = false
            receipt.publishesWidget = false
            return receipt
        case nil:
            return WriteReceipt(dropped: true)
        }
    }
}
