import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes PR 4's shared components (the four glow kinds, the 2-up's fallback, Reduce Transparency, the sparkline, the
/// hypnogram plot, the header rows, the dot row's no-data mark, Profile's Hero numbers row) at 3x, at the default text size
/// and at AX3, when `PR4_SHOTS_DIR` is set; otherwise does nothing. Run it with
/// `TEST_RUNNER_PR4_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/NocturneSharedShotsTests test`. The images are
/// for comparing with the board, not a golden-file test. Today's and Sleep's screens compose these (T4.2, T4.3).
@MainActor
@Suite struct NocturneSharedShotsTests {
    /// The board's tiles at 350 wide, with the board's words (verbatim: the screens own the strings).
    private struct Kinds: View {
        var flat = false
        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                pair
                GlowTile(Theme.metricStrain, kind: .strain, reduceTransparency: flat) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: "Strain").ryftGlowLabelStyle()
                            Spacer(minLength: 0)
                            Text(verbatim: "12.4").font(.ryftNumber(size: 30, weight: .light))
                            Text(verbatim: "of 21 · moderate").ryftGlowLabelStyle()
                        }
                        // Fixed spacing, no Spacer: a flexible tile would take the page's slack from the others.
                        RulerScale(range: 0...21, value: 12.4, zone: 10...14, tickCount: RulerScale.Ticks.strainCompact,
                                   size: .compact, accessibilityLabel: Text(verbatim: "Strain scale"),
                                   accessibilityValue: Text(verbatim: "12.4"), reduceMotion: true)
                            .padding(.top, 8)
                    }
                }
                HypnogramShot(flat: flat)
            }
        }

        @ViewBuilder private var pair: some View {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                GlowTile(Theme.recovery, kind: .twoUp, reduceTransparency: flat) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            Text(verbatim: "Recovery").ryftGlowLabelStyle()
                            Spacer(minLength: 8)
                            Sparkline(values: [58, 51, 60, 55, 62, 57, 66])
                        }
                        Spacer(minLength: 8)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(verbatim: "82").font(.ryftNumber(size: 34, weight: .light))
                            Text(verbatim: "%").ryftGlowLabelStyle()
                            Spacer(minLength: 4)
                            Text(verbatim: "HRV 66").ryftGlowLabelStyle(.caption)
                        }
                    }
                }
                GlowTile(Theme.metricSleep, kind: .twoUp, reduceTransparency: flat) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top) {
                            Text(verbatim: "Sleep").ryftGlowLabelStyle()
                            Spacer(minLength: 8)
                            DotRow([.full, .missed, .noData, .full, .missed, .full, .today],
                                   accessibilityLabel: Text(verbatim: "Slept enough on 4 of the last 7 nights"))
                                .padding(.top, 4)
                        }
                        Spacer(minLength: 8)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(verbatim: "7:48").font(.ryftNumber(size: 34, weight: .light))
                            Spacer(minLength: 4)
                            Text(verbatim: "94 %").ryftGlowLabelStyle(.caption)
                        }
                    }
                }
            }
        }
    }

    private struct HypnogramShot: View {
        var flat = false

        var body: some View {
            let sleep = MockData.todayDetail.sleep
            GlowTile(Theme.metricSleep, kind: .hypnogram, reduceTransparency: flat) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: "Hypnogram").ryftGlowLabelStyle()
                        Spacer(minLength: 8)
                        Text(verbatim: "22:50 – 07:00").ryftGlowLabelStyle(.caption)
                    }
                    if let sleep, let start = sleep.start, let end = sleep.end {
                        HypnogramPlot(segments: sleep.segments, start: start, end: end,
                                      stageNames: ["Awake", "REM", "Light", "Deep"])
                            .padding(.top, 10)
                    }
                    Text(verbatim: "Deep 1:35 · REM 1:45 · Light 4:28 · Awake 0:22")
                        .ryftGlowLabelStyle(.caption)
                        .padding(.top, 8)
                }
            }
        }
    }

    private struct Headers: View {
        var body: some View {
            VStack(spacing: 20) {
                ScreenHeader {
                    CircleButton(systemImage: "calendar", iconSize: 16, accessibilityLabel: Text(verbatim: "Calendar")) {}
                }
                ScreenHeader {
                    CircleButton(systemImage: "chevron.left", accessibilityLabel: Text(verbatim: "Previous night")) {}
                } center: {
                    VStack(spacing: 2) {
                        Text(verbatim: "Sleep").font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
                        Text(verbatim: "Last night · Sun, Nov 15").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                    }
                    .multilineTextAlignment(.center)
                } trailing: {
                    CircleButton(systemImage: "chevron.right", accessibilityLabel: Text(verbatim: "Next night")) {}
                        .disabled(true)
                }
                Card { HeroNumeralsRow(selection: .constant(.dots)) }
            }
        }
    }

    private func page(_ content: some View) -> some View {
        content
            .padding(20)
            .frame(width: 390, alignment: .topLeading)
            .background(Theme.background)
            .environment(\.colorScheme, .dark)
    }

    @Test func writeShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["PR4_SHOTS_DIR"] else { return }
        let views: [(String, AnyView)] = [
            ("glow-kinds", AnyView(page(Kinds()))),
            ("glow-kinds-flat", AnyView(page(Kinds(flat: true)))),
            ("glow-2up-fallback-350", AnyView(page(GlowTile(Theme.recovery, kind: .twoUp) {
                Text(verbatim: "Recovery").ryftGlowLabelStyle()
            }))),
            ("hypnogram", AnyView(page(HypnogramShot()))),
            ("headers", AnyView(page(Headers()))),
            ("sparkline", AnyView(page(VStack(alignment: .leading, spacing: 12) {
                Sparkline(values: [58, 51, 60, 55, 62, 57, 66])
                Sparkline(values: [58, 51, nil, 55, 62, 57, 66])
                Sparkline(values: [58, 51, 60, 55, 62, 57, nil])
                Sparkline(values: [nil, nil, nil, nil, nil, nil, 66])
            }))),
        ]
        for (name, view) in views {
            for (size, typeSize) in [("default", DynamicTypeSize.large), ("ax3", .accessibility3)] {
                let renderer = ImageRenderer(content: view.environment(\.dynamicTypeSize, typeSize))
                renderer.scale = 3
                let data = try #require(renderer.uiImage?.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
            }
        }
    }
}
