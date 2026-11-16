import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes the Nocturne tokens' board (swatches with their contrast, the type scale, the wordmark lock-up), at the default
/// text size and at AX3, when `NOCTURNE_SHOTS_DIR` is set; otherwise does nothing. Run it with
/// `TEST_RUNNER_NOCTURNE_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/NocturneShotsTests test`. The images are for
/// the design note and ui-validator, not a golden-file test.
@MainActor
@Suite struct NocturneShotsTests {
    private struct Swatch: Identifiable {
        let name: String
        let colour: Color
        var id: String { name }
    }

    private static let swatches: [Swatch] = [
        Swatch(name: "recovery", colour: Theme.recovery), Swatch(name: "sleep", colour: Theme.metricSleep),
        Swatch(name: "strain", colour: Theme.metricStrain), Swatch(name: "signal", colour: Theme.signal),
        Swatch(name: "textPrimary", colour: Theme.textPrimary), Swatch(name: "textSecondary", colour: Theme.textSecondary),
        Swatch(name: "textTertiary", colour: Theme.textTertiary), Swatch(name: "track", colour: Theme.surfaceRaised),
        Swatch(name: "separator", colour: Theme.separator),
    ]

    private static let scale: [(String, RyftTextStyle)] = [
        ("title 26 Light", .title), ("numberLarge 34 Light", .numberLarge), ("metric 26 Light", .metric),
        ("headline 17 Medium", .headline), ("body 16 Regular", .body), ("callout 15 Regular", .callout),
        ("label 13 Regular", .label), ("caption 12 Regular", .caption), ("axis 11 Regular", .axis),
    ]

    private struct Board: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 20) {
                WordmarkLockup()
                HStack(spacing: 0) {
                    ForEach(NocturneShotsTests.swatches) { s in
                        s.colour.frame(height: 28)
                    }
                }
                .background(Theme.surface)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Good evening, Tim").font(.ryft(.title)).foregroundStyle(Theme.textPrimary)
                    Text("Tuesday, 16 November · scored at 06:42").font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(NocturneShotsTests.scale, id: \.0) { name, style in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "0123456789 h").font(.ryft(style)).foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 8)
                            Text(verbatim: name).font(.ryft(.axis)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .padding(14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Text("Readiness · High").ryftLabelStyle()
                HStack(spacing: 12) {
                    Text("Recovery").ryftLabelStyle(Theme.recovery)
                    Text("Sleep").ryftLabelStyle(Theme.metricSleep)
                    Text("Strain").ryftLabelStyle(Theme.metricStrain)
                    Circle().fill(Theme.signal).frame(width: 8, height: 8)
                }
            }
            .padding(20)
            .frame(width: 390, alignment: .leading)
            .background(Theme.background)
            .environment(\.colorScheme, .dark)
        }
    }

    @Test func writeShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["NOCTURNE_SHOTS_DIR"] else { return }
        for (name, size) in [("default", DynamicTypeSize.large), ("ax3", .accessibility3)] {
            let renderer = ImageRenderer(content: Board().environment(\.dynamicTypeSize, size))
            renderer.scale = 3
            let data = try #require(renderer.uiImage?.pngData())
            try data.write(to: URL(fileURLWithPath: "\(dir)/board-\(name).png"))
        }
    }
}
