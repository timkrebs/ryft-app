// A wipe that was started and hasn't finished, written down before its first destructive step. A file, not
// UserDefaults, which may not reach the disk before a crash.
import Foundation
import OSLog

/// What a started wipe still owes. The file format: an entry may outlive the build that wrote it.
struct OwedWipe: Equatable {
    /// Reason, account and first date. A retry runs it as it is, so `Wipe.parking` stays the one derivation.
    var wipe: AuthService.Wipe
    /// The first pass reached the device steps: a retry runs only the store step.
    var deviceStepsDone = false
    /// The wipe succeeded and only file residue is left.
    var scrubOnly = false

    /// The first `begin`: stamped as `parkedAt`, and it starts the 30-day bound.
    var since: Date { wipe.since }
}

/// A key this build doesn't know yet, or one a build before it didn't write, reads as false: a retry that does too much.
extension OwedWipe: Codable {
    private enum CodingKeys: String, CodingKey { case wipe, deviceStepsDone, scrubOnly }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        wipe = try values.decode(AuthService.Wipe.self, forKey: .wipe)
        deviceStepsDone = try values.decodeIfPresent(Bool.self, forKey: .deviceStepsDone) ?? false
        scrubOnly = try values.decodeIfPresent(Bool.self, forKey: .scrubOnly) ?? false
    }
}

/// At most one entry, and a later wipe merges into it. Memory first, so a full disk can't lose it during this run.
@MainActor
final class WipeLedger {
    /// Same protection as the Keychain session, so a background launch after the first unlock can read it.
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    private static let log = Logger(subsystem: "dev.timkrebs.ryft", category: "auth")

    nonisolated static var liveFile: URL {
        URL.applicationSupportDirectory.appendingPathComponent("account-wipe.json")
    }

    /// `nil` keeps everything in memory: previews, and tests that aren't about the file.
    private let file: URL?
    private var held: OwedWipe?

    init(file: URL?) {
        self.file = file
    }

    /// Read again while there's nothing in memory: before the first unlock the file can't be read, and it can later.
    /// A file that can't be decoded counts as no entry and stays where it is.
    var entry: OwedWipe? {
        if held == nil, let file { held = Self.read(file) }
        return held
    }

    /// Records `wipe`, merged with what's already owed: the earliest date stays, and parking only ever narrows, so a
    /// wipe for another account or another reason can't keep rows the entry doesn't.
    func begin(_ wipe: AuthService.Wipe, at now: Date) {
        if var owed = entry {
            owed.wipe = Self.merged(owed.wipe, wipe, since: min(owed.since, now))
            held = owed
        } else {
            var first = wipe
            first.since = now
            held = OwedWipe(wipe: first)
        }
        write()
    }

    func update(_ change: (inout OwedWipe) -> Void) {
        guard var owed = entry else { return }
        change(&owed)
        held = owed
        write()
    }

    func clear() {
        held = nil
        guard let file else { return }
        do {
            try FileManager.default.removeItem(at: file)
        } catch CocoaError.fileNoSuchFile {
            // Nothing reached the disk, or an earlier clear got there.
        } catch {
            logFailure("clear", error)
        }
    }

    /// A deletion's reason always comes through: its notice is owed too.
    private static func merged(_ owed: AuthService.Wipe, _ next: AuthService.Wipe, since: Date) -> AuthService.Wipe {
        var merged = owed
        merged.since = since
        let keeps = owed.parking == nil || owed.parking == next.parking
        if !keeps || next.reason?.isDeletion == true { merged.reason = next.parking == nil ? next.reason : nil }
        return merged
    }

    private static func read(_ file: URL) -> OwedWipe? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(OwedWipe.self, from: data)
    }

    private func write() {
        guard let file, let held else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(held).write(to: file, options: Self.writeOptions)
        } catch {
            logFailure("write", error)
        }
    }

    /// Domain and code only: a description can quote the path.
    private func logFailure(_ step: String, _ error: Error) {
        let e = error as NSError
        Self.log.error("Wipe ledger \(step, privacy: .public): \(e.domain, privacy: .public) \(e.code, privacy: .public)")
    }
}
