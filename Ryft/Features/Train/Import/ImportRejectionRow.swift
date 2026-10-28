import SwiftUI

/// The platform's per-item `code` for a refused import item, as plain words (`API.md` → Training import). An unknown or
/// missing code is the generic refusal.
enum ImportRejectionCode: Equatable {
    case invalid, unknownExercise, unknownPlanReference, idTaken, newerOnServer, unknown

    init(_ raw: String?) {
        switch raw {
        case "invalid": self = .invalid
        case "unknown_exercise": self = .unknownExercise
        case "unknown_plan_reference": self = .unknownPlanReference
        case "id_taken": self = .idTaken
        case "newer_on_server": self = .newerOnServer
        default: self = .unknown
        }
    }
}

/// The words of a refused item and its Details.
enum ImportRejectionText {
    /// One calm sentence by code. `newer_on_server` is not a failure; it reads as the app's version being kept.
    static func reason(_ item: ImportItemSummary) -> String {
        if item.blocked {
            return String(localized: "The exercise wasn't found", comment: "Training import I4: a reason.")
        }
        switch ImportRejectionCode(item.code) {
        case .invalid:
            return String(localized: "Some of its values are missing or out of range.",
                          comment: "Training import I4: the platform's code invalid.")
        case .unknownExercise:
            return String(localized: "This item uses an exercise RYFT doesn't know.",
                          comment: "Training import I4: the platform's code unknown_exercise.")
        case .unknownPlanReference:
            return String(localized: "This item points to a plan day RYFT doesn't have.",
                          comment: "Training import I4: the platform's code unknown_plan_reference.")
        case .idTaken:
            return String(localized: "RYFT already has a different item with the same ID.",
                          comment: "Training import I4: the platform's code id_taken.")
        case .newerOnServer:
            return leftAsIs
        case .unknown:
            return String(localized: "RYFT didn't accept this one.", comment: "Training import I4: a refusal with no code this build knows.")
        }
    }

    /// "Left as it is in RYFT": you changed it there (`newer_on_server`).
    static var leftAsIs: String {
        String(localized: "Left as it is in RYFT. You changed it there.",
               comment: "Training import: newer_on_server, the app's version is kept; not an error.")
    }

    /// The server's message is kept short: it never holds file values, but it is only ever shown in Details.
    static let messageLimit = 200

    /// Request ID and the server's message for Details, one per line; nil when there is neither.
    static func details(_ item: ImportItemSummary) -> String? {
        var lines: [String] = []
        if let id = item.requestID?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
            lines.append(String(localized: "Request ID \(id)", comment: "Training import, Details: the X-Request-ID of the answer."))
        }
        if let code = item.code, !code.isEmpty {
            lines.append(String(localized: "Code \(code)", comment: "Training import, Details: the platform's code for the item."))
        }
        if let message = item.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty, !item.blocked {
            let shown = message.count > messageLimit ? String(message.prefix(messageLimit)) + "…" : message
            lines.append(String(localized: "Message: \(shown)", comment: "Training import, Details: the platform's message for the item."))
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }
}

/// A refused item: date and title, the reason in plain words, and a Details toggle with the request ID.
struct ImportRejectionRow: View {
    let item: ImportItemSummary
    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: [item.date.map(Fmt.date), item.title].compactMap { $0 }.joined(separator: " · "))
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: ImportRejectionText.reason(item))
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let details = ImportRejectionText.details(item) {
                Button {
                    showsDetails.toggle()
                } label: {
                    Text("Details", comment: "Training import: show the request ID of a refused item.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(showsDetails ? Text("Expanded") : Text("Collapsed"))
                if showsDetails {
                    Text(verbatim: details)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Rejected items", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(MockTrainImport.rejectionSamples) { ImportRejectionRow(item: $0) }
        }
        .padding()
    }
}

#Preview("Rejected items · AX5", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(MockTrainImport.rejectionSamples.prefix(2)) { ImportRejectionRow(item: $0) }
        }
        .padding()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
