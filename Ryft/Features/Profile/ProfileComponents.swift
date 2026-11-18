import SwiftUI

/// A setting you can tap: title and value, where the value comes from underneath, a chevron.
struct SettingRow: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingRowLabel(title: title, value: value, detail: detail)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the editor"))
    }
}

/// `SettingRow`'s look, for a `NavigationLink` too. At accessibility sizes the value goes
/// under the title instead of fighting it for the line.
struct SettingRowLabel: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.ryft(.body))
                                .foregroundStyle(Theme.textPrimary)
                            Text(value)
                                .font(.ryft(.body))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer(minLength: 8)
                    } else {
                        Text(title)
                            .font(.ryft(.body))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        Text(value)
                            .font(.ryft(.body))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityHidden(true)
                }
                if let detail {
                    Text(detail)
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
}

/// A sheet's title between its two buttons: smaller rather than cut off (German runs long).
struct SheetTitle: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }
}

/// How the rescore went; a failure with its request ID.
struct RescoreStatus: View {
    let editor: BodySettingsEditor

    var body: some View {
        if let details = editor.rescoreDetails, let status = editor.rescoreStatus {
            InlineMessage(message: status, systemImage: "exclamationmark.circle", details: details)
        } else if let status = editor.rescoreStatus {
            Text(status)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct ProfileSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).ryftLabelStyle()
                // A label, not a headline: past AX3 it would crowd out the content.
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            Card {
                VStack(alignment: .leading, spacing: 14) { content() }
            }
        }
    }
}

struct LinkRow: View {
    let title: LocalizedStringKey
    let url: URL?

    var body: some View {
        if let url {
            Link(destination: url) {
                HStack {
                    Text(title)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
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
