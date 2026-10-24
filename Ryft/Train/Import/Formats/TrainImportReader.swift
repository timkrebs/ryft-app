import Foundation
import os

/// The import flow's one entry to parsing (design §2): detect, parse and merge picked files, off the main actor.
enum TrainImportReader {
    /// Every file is detected before any is parsed, so a refusal costs no parse. Throws `.empty` for no files,
    /// `.tooManyFiles` or `.tooLarge` over `maxFiles` or `maxTotalBytes`, the first file's own `ImportError`,
    /// `.mixedFormats` when files come from different apps, or `CancellationError`. Files that are recognised but hold
    /// no plan and no workout give an empty bundle with their warnings (ui.md D7), not an error.
    @concurrent
    static func read(_ files: [ImportFile], limits: ImportLimits = .standard) async throws -> ImportBundle {
        MainThread.assertOff("Reading an import")
        let signpost = ImportLog.signposter.beginInterval("read", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("read", signpost) }
        guard !files.isEmpty else { throw ImportError.empty }
        guard files.count <= limits.maxFiles else { throw ImportError.tooManyFiles(count: files.count) }
        let totalBytes = files.reduce(0) { $0 + $1.data.count }
        guard totalBytes <= limits.maxTotalBytes else { throw ImportError.tooLarge(bytes: totalBytes) }
        var prepared: [PreparedFile] = []
        for file in files {
            prepared.append(try prepare(file, limits: limits))
        }
        guard let first = prepared.first else { throw ImportError.empty }
        guard prepared.allSatisfy({ $0.format.id == first.format.id }) else { throw ImportError.mixedFormats }
        var merged: ImportBundle?
        for (index, file) in prepared.enumerated() {
            try Task.checkCancellation()
            let bundle = try parse(file, index: index, limits: limits)
            merged = merged?.merging(bundle, maxWarnings: limits.maxWarnings) ?? bundle
        }
        guard let bundle = merged else { throw ImportError.empty }
        log(bundle, files: files.count)
        return bundle
    }

    /// One file on its own, for a flow that shows a result per file (ui.md D6) and merges with
    /// `ImportBundle.merging`. `index` is the file's place among the picked ones (`SourceLine.file`). A recognised
    /// file with no plan and no workout gives an empty bundle with its warnings (D7); `.empty` is for a blank file (P6).
    @concurrent
    static func read(_ file: ImportFile, index: Int, limits: ImportLimits = .standard) async throws -> ImportBundle {
        MainThread.assertOff("Reading an import file")
        let bundle = try parse(prepare(file, limits: limits), index: index, limits: limits)
        log(bundle, files: 1)
        return bundle
    }

    // MARK: Private

    /// A picked file, checked and decoded once: detection and parsing read the same UTF-8 text, so a Windows-1252
    /// export (`4 Sätze`) is recognised by the same tokens that parse it.
    private struct PreparedFile {
        let text: ImportHygiene.DecodedText
        let format: any TrainImportFormat
    }

    private static func prepare(_ file: ImportFile, limits: ImportLimits) throws -> PreparedFile {
        let data = file.data
        guard data.count <= limits.maxFileBytes else { throw ImportError.tooLarge(bytes: data.count) }
        guard !ImportHygiene.isUnsupportedEncoding(data) else { throw ImportError.unsupportedEncoding }
        guard !ImportHygiene.isBlank(data) else { throw ImportError.empty }
        let text = ImportHygiene.decode(data)
        guard let (format, _) = TrainImportFormats.best(for: ImportHygiene.head(of: text.utf8)) else {
            throw ImportError.notRecognised
        }
        return PreparedFile(text: text, format: format)
    }

    private static func parse(_ file: PreparedFile, index: Int, limits: ImportLimits) throws -> ImportBundle {
        let signpost = ImportLog.signposter.beginInterval("parse", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("parse", signpost) }
        // The size cap was checked on the picked file; its UTF-8 copy may be larger (umlauts take two bytes).
        var textLimits = limits
        textLimits.maxFileBytes = max(limits.maxFileBytes, file.text.utf8.count)
        var bundle = try file.format.parse(file.text.utf8, limits: textLimits)
        if file.text.isLegacy {
            bundle.warnings.insert(ImportWarning(at: SourceLine(file: 0, line: 1), kind: .legacyEncoding), at: 0)
            bundle.capWarnings(at: limits.maxWarnings)
        }
        return bundle.inFile(index)
    }

    /// Counts and warning kinds only: never names, dates, weights or line text (design §10).
    private static func log(_ bundle: ImportBundle, files: Int) {
        let kinds = Dictionary(bundle.warnings.map { ($0.kind.name, 1) }, uniquingKeysWith: +)
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
        let sets = bundle.sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } }
        ImportLog.logger.info("""
        Read \(files, privacy: .public) file(s), \(bundle.lineCount, privacy: .public) lines: \
        \(bundle.plans.count, privacy: .public) plans, \(bundle.sessions.count, privacy: .public) sessions, \
        \(sets, privacy: .public) sets; warnings \(bundle.warnings.count, privacy: .public) \
        (+\(bundle.suppressedWarnings, privacy: .public)) \(kinds, privacy: .public)
        """)
    }
}

enum ImportLog {
    static let logger = Logger(subsystem: "dev.timkrebs.ryft", category: "import")
    static let signposter = OSSignposter(subsystem: "dev.timkrebs.ryft", category: "import")
}

extension ImportBundle {
    /// Sources and warnings moved to the picked file at `index` (a format parses one file, as file 0).
    func inFile(_ index: Int) -> ImportBundle {
        var copy = self
        copy.plans = plans.map { plan in
            var plan = plan
            plan.source = SourceLine(file: index, line: plan.source.line)
            return plan
        }
        copy.sessions = sessions.map { session in
            var session = session
            session.source = SourceLine(file: index, line: session.source.line)
            return session
        }
        copy.warnings = warnings.map { ImportWarning(at: SourceLine(file: index, line: $0.at.line), kind: $0.kind) }
        return copy
    }

    /// At most `limit` warnings; the rest are counted in `suppressedWarnings`.
    mutating func capWarnings(at limit: Int) {
        let limit = max(0, limit)
        guard warnings.count > limit else { return }
        suppressedWarnings += warnings.count - limit
        warnings = Array(warnings.prefix(limit))
    }
}
