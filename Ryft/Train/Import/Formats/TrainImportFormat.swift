import Foundation

/// A training-export format (design §2). Later formats (header-row CSVs from other apps) join here with their own
/// `ImportFormatID`; nothing after `ImportBundle` changes.
protocol TrainImportFormat: Sendable {
    var id: ImportFormatID { get }
    /// The source app, named factually (a data source, never a comparison).
    var displayName: LocalizedStringResource { get }
    /// From at most the first 64 KiB. Pure; never throws.
    func detect(_ head: Data) -> ImportConfidence
    /// Pure and synchronous. Throws only `ImportError` (whole-file refusals) or `CancellationError`.
    func parse(_ data: Data, limits: ImportLimits) throws -> ImportBundle
}

enum TrainImportFormats {
    static let all: [any TrainImportFormat] = [AlphaProgressionFormat()]

    /// The format most confident about `head`, or nil when none recognises it. Ties go to the earlier format.
    static func best(for head: Data) -> (any TrainImportFormat, ImportConfidence)? {
        var best: (any TrainImportFormat, ImportConfidence)?
        for format in all {
            let confidence = format.detect(head)
            if confidence > (best?.1 ?? .none) { best = (format, confidence) }
        }
        return best
    }
}
