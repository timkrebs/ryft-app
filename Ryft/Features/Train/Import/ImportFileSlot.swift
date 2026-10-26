import SwiftUI

/// A file in the import's first two steps (ui.md §4, §5, §9): an outline slot to choose into, a file being read (a bare
/// hairline track, never a spinner), a file read (what it holds), or one that failed (its reason). At accessibility
/// sizes the text stacks under the glyph and the remove button moves under the name, still 44 × 44.
struct ImportFileSlot: View {
    enum State: Equatable {
        /// Step 1's hint: "Plans file · Optional".
        case empty(title: String, systemImage: String)
        case reading(name: String, progress: String?)
        case read(name: String, caption: String)
        case failed(name: String, reason: String)
    }

    let state: State
    /// The trailing ✕ (D6); nil: none.
    var onRemove: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            Image(systemName: glyph)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(glyphColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: title)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if case .reading = state {
                    Capsule().fill(Theme.separator).frame(height: 2).padding(.vertical, 2)
                }
                if let caption {
                    Text(verbatim: caption)
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Remove file", comment: "Training import, step 2: remove a file from the import."))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, onRemove == nil ? 14 : 4)
        .padding(.vertical, onRemove == nil ? 14 : 4)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
        .accessibilityElement(children: onRemove == nil ? .ignore : .contain)
        .accessibilityLabel(Text(verbatim: [title, caption].compactMap { $0 }.joined(separator: ", ")))
    }

    private var glyph: String {
        switch state {
        case let .empty(_, systemImage): systemImage
        case .reading: "doc.text"
        case .read: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }

    private var glyphColor: Color {
        if case .failed = state { return Theme.warning }
        return Theme.textSecondary
    }

    private var title: String {
        switch state {
        case let .empty(title, _): title
        case let .reading(name, _), let .read(name, _), let .failed(name, _): name
        }
    }

    private var caption: String? {
        switch state {
        case .empty: String(localized: "Optional")
        case let .reading(_, progress):
            progress ?? String(localized: "Reading…", comment: "Training import: a file is being read.")
        case let .read(_, caption): caption
        case let .failed(_, reason): reason
        }
    }
}

extension ImportPickedFile {
    /// The slot this file shows as in step 2's list.
    var slotState: ImportFileSlot.State {
        switch status {
        case .reading: .reading(name: name, progress: nil)
        case .read: .read(name: name, caption: contentCaption)
        case let .failed(problem): .failed(name: name, reason: problem.shortReason)
        }
    }

    private var contentCaption: String {
        switch content {
        case .plans: String(localized: "Plans")
        case .workouts: String(localized: "Workout history", comment: "Training import, step 3: the history toggle.")
        case .plansAndWorkouts:
            String(localized: "Plans and workouts", comment: "Training import, step 2: what a file holds.")
        case .nothing, nil:
            String(localized: "No plan and no workouts", comment: "Training import, step 2: a recognised file that holds nothing.")
        }
    }
}

extension ImportFileProblem {
    /// A file row's reason in step 2.
    var shortReason: String {
        switch self {
        case .notCSV: String(localized: "Not a CSV file", comment: "Training import, step 2: why a file can't be read.")
        case .tooLarge: String(localized: "Larger than 8 MB", comment: "Training import, step 2: why a file can't be read.")
        case .unreadable: String(localized: "Couldn't be read", comment: "Training import, step 2: why a file can't be read.")
        case .empty: String(localized: "Empty", comment: "Training import, step 2: why a file can't be read.")
        case .notSupported: String(localized: "Not a supported format", comment: "Training import, step 2: why a file can't be read.")
        }
    }

    /// The message for a file (ui.md P3 to P6): the headline with the file's name, a caption, and the one action.
    func message(name: String) -> (text: String, caption: String?, systemImage: String, retry: String) {
        let another = String(localized: "Choose another file", comment: "Training import: pick a different file.")
        switch self {
        case .notCSV:
            return (String(localized: "“\(name)” isn't a CSV file.", comment: "Training import P3; the file's name."),
                    String(localized: "RYFT can read CSV and plain text files.", comment: "Training import P3."),
                    "doc.badge.ellipsis", another)
        case .tooLarge:
            return (String(localized: "“\(name)” is larger than 8 MB.", comment: "Training import P4; the file's name."),
                    String(localized: "Training exports are usually well under 1 MB. Is this the right file?",
                           comment: "Training import P4."),
                    "doc.badge.ellipsis", another)
        case .unreadable:
            return (String(localized: "RYFT couldn't read “\(name)”.", comment: "Training import P5; the file's name."),
                    String(localized: "If it's in iCloud Drive, open Files and let it finish downloading, then try again.",
                           comment: "Training import P5."),
                    "exclamationmark.circle",
                    String(localized: "Try again"))
        case .empty:
            return (String(localized: "“\(name)” is empty.", comment: "Training import P6; the file's name."), nil,
                    "doc", another)
        case .notSupported:
            return (String(localized: "RYFT can import exports from Alpha Progression. “\(name)” doesn't look like one.",
                           comment: "Training import D5; the file's name. Alpha Progression is a data source, named factually."),
                    String(localized: "More apps may come. Nothing was imported.", comment: "Training import D5."),
                    "questionmark.folder", another)
        }
    }
}

#Preview("File slots", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 10) {
            ImportFileSlot(state: .empty(title: "Plans file", systemImage: "list.bullet.rectangle"))
            ImportFileSlot(state: .reading(name: "Upper-Lower_Workouts.csv", progress: nil))
            ImportFileSlot(state: .read(name: "Upper-Lower_Plans.csv", caption: "Plans"), onRemove: {})
            ImportFileSlot(state: .failed(name: "notes.txt", reason: "Not a supported format"), onRemove: {})
        }
    }
}

#Preview("File slots · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 10) {
            ImportFileSlot(state: .empty(title: "Workouts file", systemImage: "clock.arrow.circlepath"))
            ImportFileSlot(state: .read(name: "Upper-Lower_Plans.csv", caption: "Plans"), onRemove: {})
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
