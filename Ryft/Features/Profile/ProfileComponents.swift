import SwiftUI

/// How the rescore went; a failure with its request ID.
struct RescoreStatus: View {
    let editor: BodySettingsEditor

    /// How the footer shows the rescore: a failure (offline too, without details) as a notice with the error glyph, and
    /// Details when RYFT answered; otherwise the status in words.
    enum Look: Equatable {
        case failure(String, details: String?)
        case note(String)
    }

    @MainActor
    static func look(_ editor: BodySettingsEditor) -> Look? {
        guard let status = editor.rescoreStatus else { return nil }
        return editor.rescoreFailed ? .failure(status, details: editor.rescoreDetails) : .note(status)
    }

    var body: some View {
        switch Self.look(editor) {
        case .failure(let status, let details)?:
            InlineMessage(message: status, systemImage: "exclamationmark.circle", details: details)
                .accessibilityIdentifier("profile.rescoreFailed")
        case .note(let status)?:
            Text(status)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
        case nil:
            EmptyView()
        }
    }
}
