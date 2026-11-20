import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes T5.0-A's controls (the catalog's "Nocturne · controls" section in pages, the way its previews show them) as 3x PNGs at
/// the default size and at AX3 when `CONTROLS_SHOTS_DIR` is set; otherwise does nothing. Run it with
/// `TEST_RUNNER_CONTROLS_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/NocturneControlsShotsTests test`. Drawn from a real
/// window (`drawHierarchy`), so the busy spinners show; `ImageRenderer` leaves them out. For comparing with the spec, not a
/// golden-file test.
@MainActor
@Suite("Nocturne controls, shots", .serialized)
struct NocturneControlsShotsTests {
    private struct Page<Content: View>: View {
        @ViewBuilder var content: () -> Content

        var body: some View {
            content()
                .padding(Theme.Metrics.screenPadding)
                .frame(width: 390, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.background)
                .toggleStyle(.ryft)
        }
    }

    private struct Pills: View {
        var body: some View {
            VStack(spacing: 12) {
                ForEach([PillButton.Style.primary, .secondary, .destructive], id: \.self) { style in
                    let title = style == .primary ? "Continue" : style == .secondary ? "Sync now" : "Delete account"
                    PillButton(Text(verbatim: title), style: style) {}
                    PillButton(Text(verbatim: title), style: style, busy: true) {}
                    PillButton(Text(verbatim: title), style: style) {}
                        .disabled(true)
                }
            }
        }
    }

    private struct Icons: View {
        var body: some View {
            VStack(spacing: 12) {
                PillButton(Text(verbatim: "Log in")) {}
                PillButton(Text(verbatim: "Save"), systemImage: PillButton.Icon.confirm) {}
                PillButton(Text(verbatim: "Send reset link"), systemImage: PillButton.Icon.send) {}
                PillButton(Text(verbatim: "Open Health"), systemImage: PillButton.Icon.linkOut) {}
                PillButton(Text(verbatim: "Export data"), systemImage: PillButton.Icon.download) {}
                PillButton(Text(verbatim: "Start workout"), systemImage: PillButton.Icon.start) {}
                PillButton(Text(verbatim: "Try again"), systemImage: PillButton.Icon.retry) {}
                HStack(spacing: 12) {
                    PillButton(Text(verbatim: "Sync now"), style: .secondary) {}
                    PillButton(Text(verbatim: "Full re-sync"), style: .destructive) {}
                }
            }
        }
    }

    private struct Compact: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                ForEach([false, true], id: \.self) { busy in
                    row(busy: busy)
                }
                row(busy: false)
                    .disabled(true)
                // A sheet header's commit beside a close button, its type capped as B S1 asks.
                HStack {
                    CircleButton(systemImage: "xmark", accessibilityLabel: Text(verbatim: "Close")) {}
                    Spacer()
                    Text(verbatim: "Add activity").font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    PillButton(Text(verbatim: "Save"), size: .compact) {}
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// The pill never shrinks, so a row that no longer fits stacks (as the catalog does).
        private func row(busy: Bool) -> some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { pills(busy: busy) }
                VStack(alignment: .leading, spacing: 8) { pills(busy: busy) }
            }
        }

        @ViewBuilder private func pills(busy: Bool) -> some View {
            PillButton(Text(verbatim: "Save"), size: .compact, busy: busy) {}
            PillButton(Text(verbatim: "Finish"), style: .secondary, size: .compact, busy: busy) {}
            PillButton(Text(verbatim: "Delete"), style: .destructive, size: .compact, busy: busy) {}
        }
    }

    private struct Rest: View {
        @State private var on = true
        @State private var off = false

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $on) { title("Bedtime reminder") }
                Toggle(isOn: $off) { title("Wake alarm") }
                Toggle(isOn: .constant(true)) { title("Disabled, on") }.disabled(true)
                Toggle(isOn: .constant(false)) { title("Disabled, off") }.disabled(true)
                Toggle(isOn: $on) {
                    VStack(alignment: .leading, spacing: 2) {
                        title("Save workouts to Apple Health")
                        Text(verbatim: "Sessions you log in Train").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius, style: .continuous))
                HStack(spacing: 12) {
                    IconDisc(systemImage: "figure.run")
                    IconDisc(systemImage: "dumbbell")
                    IconDisc(systemImage: "bed.double")
                    IconDisc(systemImage: "figure.run", size: .large)
                    IconDisc(systemImage: "applewatch", size: .large)
                }
                HStack(spacing: 12) {
                    IconDisc(systemImage: "figure.run", size: .large)
                    VStack(alignment: .leading, spacing: 2) {
                        title("Morning run")
                        Text(verbatim: "07:10 · 42 min · 7.8 km").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius, style: .continuous))
                Button {} label: { Text(verbatim: "Forgot password?") }.ryftLink()
                Button {} label: { Text(verbatim: "Use another email") }.ryftLink().disabled(true)
                Text(InlineLink.styled(Self.sentence))
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        }

        private func title(_ text: String) -> some View {
            Text(verbatim: text).font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
        }

        static let sentence = (try? AttributedString(markdown: "By creating an account you agree to the [Terms](https://example.com/terms) "
                                                         + "and the [Privacy Policy](https://example.com/privacy).")) ?? AttributedString()
    }

    @Test func writeShots() async throws {
        guard let dir = ProcessInfo.processInfo.environment["CONTROLS_SHOTS_DIR"] else { return }
        let pages: [(String, AnyView, CGFloat, CGFloat)] = [
            ("pills", AnyView(Page { Pills() }), 640, 1_500),
            ("pill-icons", AnyView(Page { Icons() }), 560, 1_700),
            ("pill-compact", AnyView(Page { Compact() }), 300, 700),
            ("toggle-disc-link", AnyView(Page { Rest() }), 720, 2_000),
        ]
        for (name, page, height, ax3Height) in pages {
            for (size, typeSize, category, h) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large, height),
                                                  ("ax3", .accessibility3, .accessibilityExtraLarge, ax3Height)] {
                try await HostedWindow.run(width: 390, height: h, bottomInset: 0, typeSize: typeSize, category: category, page) { w in
                    try await w.settle()
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 3
                    format.opaque = true
                    let image = UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
                        w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
                    }
                    let data = try #require(image.pngData())
                    try data.write(to: URL(fileURLWithPath: "\(dir)/controls-\(name)-\(size).png"))
                }
            }
        }
    }
}
