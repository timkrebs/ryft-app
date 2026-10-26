import SwiftUI

/// The import job on My Plans (ui.md §3.1, §8.2): uploading with its count and a 2 pt bar, paused, needing attention,
/// saved on this iPhone, or finished and not seen yet (with Dismiss). A row in the list, never a banner over content.
/// Tapping it opens step 6.
struct ImportResumeRow: View {
    let status: ImportJobStatus
    let open: () -> Void
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 14) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40, height: 40)
                        .background(Theme.accent.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: ImportResumeText.row(status))
                            .font(.ryft(.body))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        if status.phase == .uploading || status.phase == .preparing {
                            ImportProgressBar(fraction: status.progress, height: 2)
                        }
                    }
                    Spacer(minLength: 8)
                    if dismiss == nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens the import", comment: "Training import, VoiceOver: the resume row."))
            .accessibilityIdentifier("import.resume")
            if let dismiss {
                Button(action: dismiss) {
                    Text("Dismiss", comment: "Training import: hide a finished import's row.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(minHeight: 56)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
    }
}

/// A file that arrived while it couldn't be opened (ui.md E7, E9): a quiet row with "Open now" (enabled once it can)
/// or "View progress".
struct ImportWaitingFileRow: View {
    let name: String
    let reason: ImportCoordinator.Waiting
    let canOpen: Bool
    let open: () -> Void
    let viewProgress: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ImportNoteLine(systemImage: "doc.text", text: text)
            HStack(spacing: 18) {
                Button(action: open) {
                    Text("Open now", comment: "Training import: open a waiting file (E7).")
                }
                .disabled(!canOpen)
                if reason == .upload {
                    Button(action: viewProgress) {
                        Text("View progress", comment: "Training import: open step 6 of the running import (E9).")
                    }
                }
            }
            .font(.ryft(.callout))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
    }

    private var text: String {
        switch reason {
        case .workout:
            String(localized: "File waiting: \(name). Open it after your workout.", comment: "Training import E7; the file's name.")
        case .upload:
            String(localized: "An import is still uploading. Open this file when it's done.", comment: "Training import E9.")
        }
    }
}

/// The resume row's and the Profile row's words (ui.md §3.2, §8.2).
enum ImportResumeText {
    static func row(_ status: ImportJobStatus) -> String {
        switch status.phase {
        case .preparing, .uploading:
            String(localized: "Import uploading · \(status.sessions.done) of \(status.sessions.total)",
                   comment: "Training import: the resume row while it uploads.")
        case .paused(.notAvailable):
            String(localized: "Import saved on this iPhone", comment: "Training import: the resume row (I9).")
        case .paused(.waitingForAccount), .paused(.needsAttention):
            String(localized: "Import needs attention", comment: "Training import: the resume row.")
        case .paused(.held):
            String(localized: "Import paused", comment: "Training import: the resume row, held for a reason the user can't act on.")
        case .paused:
            String(localized: "Import paused · waiting for a connection", comment: "Training import: the resume row.")
        case .finished where status.hasRejected:
            String(localized: "Import needs attention", comment: "Training import: the resume row.") + " · "
                + String(localized: "\(status.sessions.rejected + status.sessions.blocked) workouts not imported",
                         comment: "Training import I4.")
        case .finished:
            String(localized: "Import finished: \(status.sessions.done) workouts", comment: "Training import: a finished import not opened yet.")
        }
    }

    /// Profile → Data's detail line: idle, or the job.
    static func profileDetail(_ status: ImportJobStatus?) -> String {
        guard let status, !status.resultSeen else {
            return String(localized: "From a CSV file", comment: "Training import: Profile → Data's row detail.")
        }
        switch status.phase {
        case .preparing, .uploading:
            return String(localized: "\(status.sessions.done) of \(status.sessions.total) workouts uploaded",
                          comment: "Training import: Profile → Data's row while it uploads.")
        case .paused(.notAvailable):
            return String(localized: "Import saved on this iPhone", comment: "Training import: the resume row (I9).")
        case .paused(.waitingForAccount), .paused(.needsAttention):
            return String(localized: "Needs your attention", comment: "Training import: step 4's section, and Profile → Data's row.")
        case .paused(.held):
            return String(localized: "Import paused", comment: "Training import: the resume row, held for a reason the user can't act on.")
        case .paused:
            return String(localized: "Waiting for a connection", comment: "Training import: Profile → Data's row.")
        case .finished where status.hasRejected:
            return String(localized: "Needs your attention", comment: "Training import: step 4's section, and Profile → Data's row.")
        case .finished:
            return String(localized: "Import finished: \(status.sessions.done) workouts", comment: "Training import: a finished import not opened yet.")
        }
    }
}

#if DEBUG
#Preview("Resume rows", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 10) {
            ImportResumeRow(status: MockTrainImport.uploading, open: {})
            ImportResumeRow(status: MockTrainImport.offline, open: {})
            ImportResumeRow(status: MockTrainImport.partlyDone, open: {})
            ImportResumeRow(status: MockTrainImport.savedOnPhone, open: {})
            ImportResumeRow(status: MockTrainImport.done, open: {}, dismiss: {})
            ImportWaitingFileRow(name: "Workouts.csv", reason: .workout, canOpen: false, open: {}, viewProgress: {})
            ImportWaitingFileRow(name: "Workouts.csv", reason: .upload, canOpen: false, open: {}, viewProgress: {})
        }
    }
}

#Preview("Resume rows · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 10) {
            ImportResumeRow(status: MockTrainImport.uploading, open: {})
            ImportResumeRow(status: MockTrainImport.done, open: {}, dismiss: {})
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
