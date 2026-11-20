import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes T6.0's parts (`NocturneFoundationCatalog.Part`) and two whole pages (a pushed subpage with its pinned bar, a sheet
/// with its header and a field) as 3x PNGs, dark, at the default size and at AX3, when `FOUNDATION_SHOTS_DIR` is set;
/// otherwise does nothing. Run it with `TEST_RUNNER_FOUNDATION_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/
/// NocturneFoundationShotsTests test-without-building`. For comparing with the drafts, not a golden-file test.
@MainActor
@Suite("Nocturne foundation: shots", .serialized)
struct NocturneFoundationShotsTests {
    private static let sizes: [(String, DynamicTypeSize, UIContentSizeCategory)] = [
        ("default", .large, .large), ("ax3", .accessibility3, .accessibilityExtraLarge),
    ]

    @Test func writeParts() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDATION_SHOTS_DIR"] else { return }
        for part in NocturneFoundationCatalog.Part.allCases {
            for (name, typeSize, category) in Self.sizes {
                let content = NavigationStack {
                    ScrollView {
                        NocturneFoundationCatalog(parts: [part])
                            .padding(Theme.Metrics.screenPadding)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(Theme.background)
                    .toolbar(.hidden, for: .navigationBar)
                }
                try await HostedWindow.run(width: 390, height: 2_600, bottomInset: 0, typeSize: typeSize, category: category,
                                           content) { w in
                    try await w.settle()
                    let image = try await PagedWindowShot.image(w)
                    let data = try #require(Self.cropped(image))
                    try data.write(to: URL(fileURLWithPath: "\(dir)/\(part.rawValue)-\(name).png"))
                }
            }
        }
    }

    @Test func writePages() async throws {
        guard let dir = ProcessInfo.processInfo.environment["FOUNDATION_SHOTS_DIR"] else { return }
        for (name, typeSize, category) in Self.sizes {
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       SubpagePage()) { w in
                try await w.wait("the pushed page") { w.node("Report a problem", exactly: true) != nil }
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                try #require(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/page-subpage-\(name).png"))
            }
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       SheetPage()) { w in
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                try #require(image.pngData()).write(to: URL(fileURLWithPath: "\(dir)/page-sheet-\(name).png"))
            }
        }
    }

    /// c-03's frame: a pushed page, three groups, a message field, the pinned Send with its reason.
    private struct SubpagePage: View {
        @State private var path: [Int] = []
        @State private var message = ""
        @State private var category = "Something's wrong"

        var body: some View {
            NavigationStack(path: $path) {
                Color.clear.navigationDestination(for: Int.self) { _ in page }
            }
            .onAppear { path = [1] }
        }

        private var page: some View {
            SubpageScaffold(Text(verbatim: "Report a problem")) {
                VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                    GroupedCard(Text(verbatim: "What happened")) {
                        ForEach(["Something's wrong", "An idea", "A question"], id: \.self) { option in
                            GroupedRow.select(Text(verbatim: option), isSelected: category == option) { category = option }
                        }
                    }
                    GroupedCard(Text(verbatim: "Message"), footer: Text(verbatim: "Don't include health details.")) {
                        FormField(Text(verbatim: "Message"), isFocused: true, minHeight: 120) {
                            TextField(text: $message, prompt: Text(verbatim: "What did you see?").fieldPrompt(), axis: .vertical) {
                                Text(verbatim: "Message")
                            }
                            .lineLimit(3...)
                        }
                    }
                    GroupedCard(Text(verbatim: "Included")) {
                        GroupedRow.toggle(Text(verbatim: "Diagnostics"), isOn: .constant(true))
                        GroupedRow.push(Text(verbatim: "What's included")) {}
                    }
                    InlineMessage(message: "2 reports are waiting to send. They go when you're online.",
                                  systemImage: "tray.and.arrow.up", announces: false)
                }
            }
            .toggleStyle(.ryft)
            .pinnedBar(caption: Text(verbatim: "Write a message first.")) {
                PillButton(Text(verbatim: "Send"), systemImage: PillButton.Icon.send) {}
                    .disabled(true)
            }
        }
    }

    /// b-19's frame: a sheet's header with Save, a field, chips and a stepper row.
    private struct SheetPage: View {
        @State private var name = "Evening walk"
        @State private var start = Date(timeIntervalSince1970: 1_795_500_720)
        @State private var count = 2

        var body: some View {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(Text(verbatim: "Add activity"), closeLabel: Text(verbatim: "Cancel")) {
                    PillButton(Text(verbatim: "Save"), size: .compact) {}
                        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                }
                GroupedCard {
                    FormField(Text(verbatim: "Name"), valueSize: .large) {
                        TextField(text: $name) { Text(verbatim: "Name") }
                    }
                }
                GroupedCard {
                    ValueChipRow(Text(verbatim: "Start")) {
                        ValueChip(Text(verbatim: "Start date"), date: $start, displayedComponents: .date)
                        ValueChip(Text(verbatim: "Start time"), date: $start, displayedComponents: .hourAndMinute)
                    }
                    RyftStepperRow(Text(verbatim: "Rounds"), value: $count, in: 1...20)
                }
                HStack(spacing: 14) {
                    LegendMark(Theme.metricStrain)
                    Text(verbatim: "Counts toward today's strain").font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SheetHeaderSpec.sidePadding)
            .padding(.top, SheetHeaderSpec.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
            .environment(\.locale, Locale(identifier: "en_US"))
        }
    }

    /// The page cut 60 px below the last row that isn't the screen colour.
    private static func cropped(_ image: UIImage) -> Data? {
        guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (width, height) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ground = (bytes[0], bytes[1], bytes[2])
        var last = 0
        for y in stride(from: height - 1, through: 0, by: -1) {
            let row = y * width * 4
            if (0..<width).contains(where: { x in
                let i = row + x * 4
                return abs(Int(bytes[i]) - Int(ground.0)) > 2 || abs(Int(bytes[i + 1]) - Int(ground.1)) > 2
                    || abs(Int(bytes[i + 2]) - Int(ground.2)) > 2
            }) {
                last = y
                break
            }
        }
        guard let cut = cg.cropping(to: CGRect(x: 0, y: 0, width: width, height: min(height, last + 60))) else { return nil }
        return UIImage(cgImage: cut).pngData()
    }
}
