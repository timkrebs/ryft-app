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
        var formats: [any TrainImportFormat] = []
        for file in files {
            formats.append(try format(of: file, limits: limits))
        }
        guard let first = formats.first else { throw ImportError.empty }
        guard formats.allSatisfy({ $0.id == first.id }) else { throw ImportError.mixedFormats }
        var merged: ImportBundle?
        for (index, (file, format)) in zip(files, formats).enumerated() {
            try Task.checkCancellation()
            let bundle = try parse(file, index: index, format: format, limits: limits)
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
        let format = try format(of: file, limits: limits)
        let bundle = try parse(file, index: index, format: format, limits: limits)
        log(bundle, files: 1)
        return bundle
    }

    // MARK: Private

    private static func format(of file: ImportFile, limits: ImportLimits) throws -> any TrainImportFormat {
        let data = file.data
        guard data.count <= limits.maxFileBytes else { throw ImportError.tooLarge(bytes: data.count) }
        guard !ImportHygiene.isUnsupportedEncoding(data) else { throw ImportError.unsupportedEncoding }
        guard !ImportHygiene.isBlank(data) else { throw ImportError.empty }
        guard let (format, _) = TrainImportFormats.best(for: ImportHygiene.head(of: data)) else {
            throw ImportError.notRecognised
        }
        return format
    }

    private static func parse(_ file: ImportFile, index: Int, format: any TrainImportFormat,
                              limits: ImportLimits) throws -> ImportBundle {
        let signpost = ImportLog.signposter.beginInterval("parse", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("parse", signpost) }
        return try format.parse(file.data, limits: limits).inFile(index)
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
