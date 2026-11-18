#if DEBUG
import SwiftUI

/// The catalog's "Nocturne · controls" section (design.md §P5-11; T5.0-A): the pill in every style, size and state with the
/// icon table, the toggle, the icon disc and both links. Its own file, so the other tickets' sections merge beside it.
/// Verbatim words: the screens own the strings.
struct NocturneControlsCatalog: View {
    @State private var reminder = true
    @State private var alarm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("pill · primary, secondary, destructive · idle, busy, disabled")
            ForEach(Self.styles, id: \.title) { entry in
                PillButton(Text(verbatim: entry.title), style: entry.style) {}
                PillButton(Text(verbatim: entry.title), style: entry.style, busy: true) {}
                PillButton(Text(verbatim: entry.title), style: entry.style) {}
                    .disabled(true)
            }
            caption("pill · icon table (§P5-1.2)")
            ForEach(Self.icons, id: \.title) { entry in
                PillButton(Text(verbatim: entry.title), systemImage: entry.glyph) {}
            }
            caption("pill · two outlines side by side")
            HStack(spacing: Theme.Metrics.itemSpacing) {
                PillButton(Text(verbatim: "Sync now"), style: .secondary) {}
                PillButton(Text(verbatim: "Full re-sync"), style: .destructive) {}
            }
            caption("pill · compact · idle, busy, disabled")
            ForEach([false, true], id: \.self) { busy in
                compactRow(busy: busy)
            }
            compactRow(busy: false)
                .disabled(true)
            caption("toggle · on, off, disabled, in a row")
            VStack(alignment: .leading, spacing: 4) {
                Toggle(isOn: $reminder) { rowTitle("Bedtime reminder") }
                Toggle(isOn: $alarm) { rowTitle("Wake alarm") }
                Toggle(isOn: .constant(true)) { rowTitle("Disabled, on") }
                    .disabled(true)
                Toggle(isOn: .constant(false)) { rowTitle("Disabled, off") }
                    .disabled(true)
            }
            Toggle(isOn: $reminder) {
                VStack(alignment: .leading, spacing: 2) {
                    rowTitle("Save workouts to Apple Health")
                    Text(verbatim: "Sessions you log in Train").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius, style: .continuous))
            caption("icon disc · 36, 40, in a row")
            HStack(spacing: Theme.Metrics.itemSpacing) {
                IconDisc(systemImage: "figure.run")
                IconDisc(systemImage: "dumbbell")
                IconDisc(systemImage: "bed.double")
                IconDisc(systemImage: "figure.run", size: .large)
                IconDisc(systemImage: "applewatch", size: .large, accessibilityLabel: Text(verbatim: "Apple Watch"))
            }
            HStack(spacing: Theme.Metrics.itemSpacing) {
                IconDisc(systemImage: "figure.run", size: .large)
                VStack(alignment: .leading, spacing: 2) {
                    rowTitle("Morning run")
                    Text(verbatim: "07:10 · 42 min · 7.8 km").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius, style: .continuous))
            caption("link · standalone, disabled, inline")
            Button {} label: { Text(verbatim: "Forgot password?") }
                .ryftLink()
            Button {} label: { Text(verbatim: "Use another email") }
                .ryftLink()
                .disabled(true)
            Text(InlineLink.styled(Self.sentence))
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
        }
        .toggleStyle(.ryft)
    }

    /// The pill never shrinks: a row that no longer fits (AX sizes) stacks.
    private func compactRow(busy: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { compactPills(busy: busy) }
            VStack(alignment: .leading, spacing: 8) { compactPills(busy: busy) }
        }
    }

    @ViewBuilder private func compactPills(busy: Bool) -> some View {
        PillButton(Text(verbatim: "Save"), size: .compact, busy: busy) {}
        PillButton(Text(verbatim: "Finish"), style: .secondary, size: .compact, busy: busy) {}
        PillButton(Text(verbatim: "Delete"), style: .destructive, size: .compact, busy: busy) {}
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
    }

    private func rowTitle(_ text: String) -> some View {
        Text(verbatim: text).font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
    }

    private static let styles: [(title: String, style: PillButton.Style)] = [
        ("Continue", .primary), ("Sync now", .secondary), ("Delete account", .destructive),
    ]

    private static let icons: [(title: String, glyph: String)] = [
        ("Log in", PillButton.Icon.forward), ("Save", PillButton.Icon.confirm), ("Send reset link", PillButton.Icon.send),
        ("Open Health", PillButton.Icon.linkOut), ("Export data", PillButton.Icon.download),
        ("Start workout", PillButton.Icon.start), ("Try again", PillButton.Icon.retry),
    ]

    /// Markdown without the catalog (the words are not the app's).
    private static let sentence = (try? AttributedString(markdown: "By creating an account you agree to the [Terms](https://example.com/terms) "
                                                             + "and the [Privacy Policy](https://example.com/privacy).")) ?? AttributedString()
}

#Preview("Nocturne · controls") {
    ScrollView {
        NocturneControlsCatalog()
            .padding(Theme.Metrics.screenPadding)
    }
    .background(Theme.background)
    .previewEnvironment()
}

#Preview("Nocturne · controls · AX3") {
    ScrollView {
        NocturneControlsCatalog()
            .padding(Theme.Metrics.screenPadding)
    }
    .background(Theme.background)
    .previewEnvironment()
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
