import Foundation
import UniformTypeIdentifiers

/// Reads picked or opened files into memory (design §9, §10): security-scoped, refused over the size cap before and
/// while reading, coordinated (an iCloud file downloads first), and never written anywhere. A copy iOS put inside the
/// app's own container for us (an `Inbox` or `tmp` copy, e.g. from Mail) is deleted once read, so nothing of the file
/// stays on this iPhone after the import.
enum ImportFileAccess {
    /// Why a file couldn't be read (ui.md P3 to P6). Never carries the file's text.
    enum Problem: Error, Equatable, Sendable {
        /// Not a text type (P3).
        case notText
        /// Over `ImportLimits.maxFileBytes` (P4).
        case tooLarge
        /// No permission, not downloaded, or the read failed (P5).
        case unreadable
        /// 0 bytes (P6).
        case empty
    }

    /// One file: its name (shown in steps 1 and 2 only, never stored or logged) and its bytes or the reason.
    struct Loaded: Sendable {
        let name: String
        let result: Result<Data, Problem>

        var file: ImportFile? { (try? result.get()).map { ImportFile(name: name, data: $0) } }
    }

    /// Every URL in order. `owned`: the app's own directories whose copies are deleted after the read (the default is
    /// the container's `Documents/Inbox` and `tmp`; tests pass theirs).
    @concurrent
    static func load(_ urls: [URL], limits: ImportLimits = .standard, owned: [URL]? = nil) async -> [Loaded] {
        MainThread.assertOff("Reading picked files")
        let owned = owned ?? ownedDirectories
        var out: [Loaded] = []
        for url in urls {
            out.append(load(url, limits: limits, owned: owned))
        }
        let failed = out.filter { (try? $0.result.get()) == nil }.count
        ImportLog.logger.info("Read \(urls.count, privacy: .public) picked file(s), \(failed, privacy: .public) refused")
        return out
    }

    /// Where iOS puts copies for this app: `Documents/Inbox` (older share paths) and `tmp`.
    static var ownedDirectories: [URL] {
        [URL.documentsDirectory.appendingPathComponent("Inbox", isDirectory: true), FileManager.default.temporaryDirectory]
    }

    // MARK: Private

    private static func load(_ url: URL, limits: ImportLimits, owned: [URL]) -> Loaded {
        let name = url.lastPathComponent
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let result = read(url, limits: limits)
        if isInside(url, owned) { try? FileManager.default.removeItem(at: url) }
        return Loaded(name: name, result: result)
    }

    private static func read(_ url: URL, limits: ImportLimits) -> Result<Data, Problem> {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        if let type = values?.contentType, !type.conforms(to: .text) { return .failure(.notText) }
        // The cap before reading, from the file system's size (not a timestamp: no Required Reason API).
        if let size = values?.fileSize, size > limits.maxFileBytes { return .failure(.tooLarge) }
        var coordinationError: NSError?
        var result: Result<Data, Problem> = .failure(.unreadable)
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readable in
            result = readCapped(readable, cap: limits.maxFileBytes)
        }
        if coordinationError != nil { return .failure(.unreadable) }
        return result
    }

    /// At most `cap + 1` bytes: one more than the cap is enough to refuse, and a file that grew since its size was
    /// read is still refused without reading it all.
    static func readCapped(_ url: URL, cap: Int) -> Result<Data, Problem> {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .failure(.unreadable) }
        defer { try? handle.close() }
        var data = Data()
        while data.count <= cap {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: min(64 << 10, cap + 1 - data.count))
            } catch {
                return .failure(.unreadable)
            }
            guard let chunk, !chunk.isEmpty else { break }
            data.append(chunk)
        }
        if data.count > cap { return .failure(.tooLarge) }
        return data.isEmpty ? .failure(.empty) : .success(data)
    }

    /// Inside one of `directories` (resolved, so `/private/var` and `/var` compare equal).
    static func isInside(_ url: URL, _ directories: [URL]) -> Bool {
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return directories.contains { directory in
            let base = directory.resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
        }
    }
}
