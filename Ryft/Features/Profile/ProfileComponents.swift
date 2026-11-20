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

struct PrimaryButton: View {
    enum Style { case primary, secondary, destructive }

    let title: Text
    var style: Style = .primary
    var busy = false
    let action: () async -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(title: LocalizedStringKey, style: Style = .primary, busy: Bool = false, action: @escaping () async -> Void) {
        self.init(text: Text(title), style: style, busy: busy, action: action)
    }

    /// A title that holds outside text (a tracker's app name from the catalog): never parsed as a key or Markdown.
    init(verbatim title: String, style: Style = .primary, busy: Bool = false, action: @escaping () async -> Void) {
        self.init(text: Text(verbatim: title), style: style, busy: busy, action: action)
    }

    private init(text: Text, style: Style, busy: Bool, action: @escaping () async -> Void) {
        title = text
        self.style = style
        self.busy = busy
        self.action = action
    }

    var body: some View {
        Button {
            Task { await action() }
        } label: {
            ZStack {
                if busy {
                    ProgressView().controlSize(.small).tint(foreground)
                } else {
                    title
                        .font(.ryft(.callout))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(background, in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(busy)
    }

    private var foreground: Color {
        switch style {
        case .primary: return Theme.onAccent
        case .secondary: return Theme.textPrimary
        case .destructive: return Theme.alert
        }
    }

    private var background: Color {
        switch style {
        case .primary: return Theme.accent
        case .secondary: return Theme.surfaceRaised
        case .destructive: return Theme.alert.opacity(0.14)
        }
    }
}
