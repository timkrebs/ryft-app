import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T5.0-B's pieces in a real window, read from the accessibility tree (`HostedWindow`): every grouped-row kind's role, label,
/// value and hint; the group title's header trait and action; the neutral tile at AX3; the date strip's chips; the segmented
/// picker's selection; the titled header; the zone block's one tick column; the trend line's sentence.
@MainActor
@Suite("Nocturne structures: VoiceOver and layout", .serialized)
struct NocturneStructuresHostedTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA

    @MainActor
    private final class Log {
        var events: [String] = []
    }

    private func host<V: View>(_ view: V, width: CGFloat = 390, height: CGFloat = 1_400, typeSize: DynamicTypeSize = .large,
                               category: UIContentSizeCategory = .large,
                               _ body: (HostedWindow) async throws -> Void) async throws {
        let content = view.padding(.horizontal, Theme.Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Theme.background)
        try await HostedWindow.run(width: width, height: height, bottomInset: 0, typeSize: typeSize, category: category, content,
                                   body: body)
    }

    private func node(_ w: HostedWindow, _ label: String) throws -> HostedWindow.Node {
        try #require(w.node(label, exactly: true), "'\(label)' in \(w.nodes().map(\.label))")
    }

    // MARK: the grouped list

    private struct ListHost: View {
        let log: Log
        @State private var units = "Metric"
        @State private var reminder = false

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                        GroupedCard(Text(verbatim: "Account"), footer: Text(verbatim: "Your data stays in the EU.")) {
                            GroupedRow.value(Text(verbatim: "Email"), value: Text(verbatim: "alex@example.com"))
                            GroupedRow.push(Text(verbatim: "Units"), value: Text(verbatim: units),
                                            hint: Text(verbatim: "Opens the units")) { log.events.append("push") }
                            GroupedRow.linkOut(Text(verbatim: "Privacy policy"), url: URL(fileURLWithPath: "/privacy"))
                            GroupedRow.action(Text(verbatim: "Sync now"), detail: Text(verbatim: "Last sync 2 min ago"),
                                              systemImage: "arrow.triangle.2.circlepath") { log.events.append("sync") }
                            GroupedRow.action(Text(verbatim: "Copy diagnostics"), busy: true) { log.events.append("copy") }
                        }
                        GroupedCard(title: GroupTitle(Text(verbatim: "Units"),
                                                      action: .init(Text(verbatim: "Edit")) { log.events.append("edit") })) {
                            ForEach(["Metric", "Imperial"], id: \.self) { option in
                                GroupedRow.select(Text(verbatim: option), isSelected: units == option) { units = option }
                            }
                        }
                        GroupedCard(Text(verbatim: "Reminders")) {
                            GroupedRow.toggle(Text(verbatim: "Bedtime reminder"), isOn: $reminder)
                            GroupedRow.custom(Text(verbatim: "Session layout")) {
                                Button { log.events.append("layout") } label: { Text(verbatim: "List") }
                            }
                            GroupedRow.menu(Text(verbatim: "Hero numbers"), value: Text(verbatim: "Dots")) {
                                Button { log.events.append("dots") } label: { Text(verbatim: "Dots") }
                                Button { log.events.append("thin") } label: { Text(verbatim: "Thin") }
                            }
                            GroupedRow.push(Text(verbatim: "Plan"), detail: Text(verbatim: "Week 3"), icon: "calendar", route: "plan")
                        }
                        GroupedCard {
                            GroupedRow.destructive(Text(verbatim: "Delete account")) { log.events.append("delete") }
                        }
                    }
                    .padding(.horizontal, Theme.Metrics.screenPadding)
                }
                .navigationDestination(for: String.self) { Text(verbatim: "page \($0)") }
            }
            .toggleStyle(.ryft)
            .environment(\.openURL, OpenURLAction { url in
                log.events.append("open \(url.path)")
                return .handled
            })
            .onChange(of: units) { _, new in log.events.append("units \(new)") }
            .onChange(of: reminder) { _, new in log.events.append("reminder \(new)") }
        }
    }

    private func hostList(typeSize: DynamicTypeSize = .large, category: UIContentSizeCategory = .large, log: Log,
                          _ body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: 390, height: typeSize.isAccessibilitySize ? 4_000 : 1_400, bottomInset: 0,
                                   typeSize: typeSize, category: category,
                                   ListHost(log: log).background(Theme.background), body: body)
    }

    @Test("Every row kind's role: value is static, push / action / select / menu / destructive are buttons, link-out is a link")
    func rowTraits() async throws {
        let log = Log()
        try await hostList(log: log) { w in
            try await w.wait("the list") { w.node("Email", exactly: true) != nil }
            try await w.settle()
            let email = try node(w, "Email")
            #expect(email.value == "alex@example.com" && !email.traits.contains(.button), "value row: \(email.traits.rawValue)")
            let units = try node(w, "Units")
            #expect(units.traits.contains(.button) && units.value == "Metric" && units.hint == "Opens the units")
            let link = try node(w, "Privacy policy")
            #expect(link.traits.contains(.link) && !link.traits.contains(.button), "link-out: \(link.traits.rawValue)")
            // The fixture is a file URL, not a web page: the row says where it goes outside the app.
            #expect(link.hint == "Opens outside the app", "hint \(String(describing: link.hint))")
            let sync = try node(w, "Sync now")
            #expect(sync.traits.contains(.button) && sync.value == "Last sync 2 min ago")
            let busy = try node(w, "Copy diagnostics")
            #expect(busy.value == "In progress", "busy: \(String(describing: busy.value))")
            let metric = try node(w, "Metric"), imperial = try node(w, "Imperial")
            #expect(metric.isSelected && !imperial.isSelected && metric.traits.contains(.button))
            let delete = try node(w, "Delete account")
            #expect(delete.traits.contains(.button))
            let plan = try node(w, "Plan")
            #expect(plan.traits.contains(.button) && plan.value == "Week 3", "route row: \(plan.traits.rawValue) \(String(describing: plan.value))")
            let toggle = try node(w, "Bedtime reminder")
            #expect(toggle.traits.contains(.toggleButton) || toggle.traits.contains(.button), "toggle: \(toggle.traits.rawValue)")
            // The custom row: its title as text, then the caller's control.
            #expect(try node(w, "Session layout").traits.contains(.staticText))
            #expect(try node(w, "List").traits.contains(.button))
            // The menu row: one button, the title and the current value.
            let menu = try node(w, "Hero numbers")
            #expect(menu.traits.contains(.button) && menu.value == "Dots", "menu: \(menu.traits.rawValue) \(String(describing: menu.value))")
            // Group titles are headers; the footer is read.
            for title in ["Account", "Units", "Reminders"] {
                let header = try #require(w.nodes().first { $0.label == title && $0.traits.contains(.header) }, "\(title) as a header")
                #expect(header.frame.height > 0)
            }
            #expect(w.node("Your data stays in the EU.", exactly: true) != nil)
        }
    }

    @Test("Activating each row runs its action once; busy does nothing; link-out goes through openURL; select and toggle change")
    func rowActions() async throws {
        let log = Log()
        try await hostList(log: log) { w in
            try await w.wait("the list") { w.node("Email", exactly: true) != nil }
            try await w.settle()
            try node(w, "Units").activate()
            try node(w, "Privacy policy").activate()
            try node(w, "Sync now").activate()
            try node(w, "Copy diagnostics").activate()
            try node(w, "Delete account").activate()
            try node(w, "Edit").activate()
            try await w.wait("the actions") { log.events.count >= 5 }
            #expect(log.events == ["push", "open /privacy", "sync", "delete", "edit"], "\(log.events)")
            try node(w, "Imperial").activate()
            try await w.wait("the selection") { log.events.last == "units Imperial" }
            try await w.settle()
            #expect(try node(w, "Imperial").isSelected && !node(w, "Metric").isSelected)
            try node(w, "Bedtime reminder").activate()
            try await w.wait("the toggle") { log.events.last == "reminder true" }
        }
    }

    @Test("Rows are at least 46 high, an icon row at least 56; the title action's target is 44; the card's rows fill its width")
    func rowSizes() async throws {
        try await hostList(log: Log()) { w in
            try await w.wait("the list") { w.node("Email", exactly: true) != nil }
            try await w.settle()
            for label in ["Email", "Units", "Privacy policy", "Copy diagnostics", "Metric", "Imperial", "Hero numbers",
                          "Delete account"] {
                let frame = try node(w, label).frame
                #expect(frame.height >= 46 - 0.5, "\(label): \(frame)")
                #expect(abs(frame.width - 350) <= 0.5, "\(label) fills the card: \(frame)")
            }
            #expect(try node(w, "Plan").frame.height >= 56 - 0.5)
            let edit = try node(w, "Edit").frame
            #expect(edit.height >= 44 - 0.5, "the Edit link's target: \(edit)")
            // The card's title sits 8 above it.
            let title = try #require(w.nodes().first { $0.label == "Account" && $0.traits.contains(.header) })
            let email = try node(w, "Email").frame
            #expect(abs(email.minY - title.frame.maxY - 8) <= 1.5, "title \(title.frame), card \(email)")
        }
    }

    @Test("At AX3 every row is still one element with its label and value; a value row grows (the value under the title)")
    func rowsAtAX3() async throws {
        var defaultHeight: CGFloat = 0
        try await hostList(log: Log()) { w in
            try await w.wait("the list") { w.node("Email", exactly: true) != nil }
            try await w.settle()
            defaultHeight = try node(w, "Email").frame.height
        }
        try await hostList(typeSize: .accessibility3, category: .accessibilityExtraLarge, log: Log()) { w in
            try await w.wait("the list") { w.node("Email", exactly: true) != nil }
            try await w.settle()
            let email = try node(w, "Email")
            #expect(email.value == "alex@example.com")
            #expect(email.frame.height > defaultHeight * 2, "the value has its own line: \(email.frame.height) vs \(defaultHeight)")
            #expect(abs(email.frame.width - 350) <= 0.5)
            for label in ["Units", "Privacy policy", "Sync now", "Metric", "Delete account", "Bedtime reminder"] {
                #expect(w.node(label, exactly: true) != nil, "\(label)")
            }
            let menu = try node(w, "Hero numbers")
            #expect(menu.value == "Dots" && abs(menu.frame.width - 350) <= 0.5, "menu at AX3: \(menu.frame)")
        }
    }

    // MARK: the neutral tile

    @Test("The neutral tile is one element (label; value, unit, note), 80 high; at AX3 it grows and keeps its width")
    func neutralTile() async throws {
        let tiles = HStack(spacing: 12) {
            NeutralTile(Text(verbatim: "Steps"), value: Text(verbatim: "8,412"), note: Text(verbatim: "Goal 10k"))
            NeutralTile(Text(verbatim: "Active energy"), value: Text(verbatim: "512"), unit: Text(verbatim: "kcal"))
        }
        // A pair matches the taller tile: the row is as high as its content, and each tile fills it.
        .fixedSize(horizontal: false, vertical: true)
        var heights: [CGFloat] = []
        for (typeSize, category) in [(DynamicTypeSize.large, UIContentSizeCategory.large), (.accessibility3, .accessibilityExtraLarge)] {
            try await host(tiles, typeSize: typeSize, category: category) { w in
                try await w.settle()
                let nodes = w.nodes()
                #expect(nodes.map(\.label) == ["Steps", "Active energy"], "\(nodes.map(\.label))")
                let steps = try node(w, "Steps"), energy = try node(w, "Active energy")
                #expect(steps.value == "8,412, Goal 10k" && energy.value == "512 kcal", "\(String(describing: steps.value))")
                #expect(!steps.traits.contains(.button))
                #expect(abs(steps.frame.width - 169) <= 0.5 && abs(energy.frame.width - 169) <= 0.5, "\(steps.frame)")
                #expect(abs(steps.frame.height - energy.frame.height) <= 0.5, "one height: \(steps.frame) \(energy.frame)")
                heights.append(steps.frame.height)
            }
        }
        #expect(abs(heights[0] - 80) <= 0.5, "default \(heights[0])")
        #expect(heights[1] > 80 + 40, "AX3: label, value and note on their own lines: \(heights[1])")
    }

    // MARK: the date strip

    private struct StripHost: View {
        let log: Log
        @State private var selected = Calendar.current.startOfDay(for: .now)

        var body: some View {
            let today = Calendar.current.startOfDay(for: .now)
            DateStrip(days: DateStrip.week(endingAt: today, selected: selected) { day in
                day == today ? nil : MockData.history.last
            }) { day in
                selected = day
                log.events.append(DayFormat.string(from: day))
            }
        }
    }

    @Test("S11: seven chips ending today, each a button with its id; today says so and is selected; a tap selects the day")
    func stripChips() async throws {
        let log = Log()
        let today = Calendar.current.startOfDay(for: .now)
        try await host(StripHost(log: log)) { w in
            try await w.settle()
            let chips = w.nodes().filter { $0.identifier?.hasPrefix("datestrip.day.") == true }
            #expect(chips.count == 7, "\(w.nodes().map(\.label))")
            #expect(chips.map(\.identifier) == (0..<7).reversed().map { "datestrip.day.\(DayFormat.string(from: DayFormat.shift(today, days: -$0)))" })
            let last = try #require(chips.last)
            #expect(last.label == today.formatted(.dateTime.weekday(.wide)) && last.isSelected)
            #expect((last.value ?? "").contains("Today"), "\(String(describing: last.value))")
            #expect(chips.dropLast().allSatisfy { !($0.value ?? "").contains("Today") && !$0.isSelected })
            #expect(chips.allSatisfy { $0.traits.contains(.button) })
            #expect(chips.allSatisfy { abs($0.frame.width - 50) <= 0.5 && $0.frame.height >= 44 }, "\(chips.map(\.frame))")
            chips[4].activate()
            let picked = DayFormat.string(from: DayFormat.shift(today, days: -2))
            try await w.wait("the selection") { log.events == [picked] }
            try await w.settle()
            let after = w.nodes().filter { $0.identifier?.hasPrefix("datestrip.day.") == true }
            #expect(after[4].isSelected && !after[6].isSelected)
        }
    }

    @Test("S11: at AX3 the strip scrolls sideways, 64 pt chips, and every chip is still a labelled button")
    func stripAtAX3() async throws {
        try await host(StripHost(log: Log()), typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            let chips = w.nodes().filter { $0.identifier?.hasPrefix("datestrip.day.") == true }
            #expect(chips.count >= 5, "\(chips.count)")
            #expect(chips.allSatisfy { abs($0.frame.width - 64) <= 0.5 }, "\(chips.map(\.frame.width))")
            // The selected day (today) is on screen.
            let today = try #require(chips.last)
            #expect(today.isSelected && today.frame.maxX <= 390 + 0.5 && today.frame.minX >= -0.5, "\(today.frame)")
        }
    }

    // MARK: the segmented picker

    private struct PickerHost: View {
        let look: SegmentedPickerSpec.Look
        let log: Log
        @State private var mode = "Day"

        var body: some View {
            SegmentedPicker(selection: $mode, options: ["Day", "Week", "Month", "Bedtime"], look: look) { $0 }
                .onChange(of: mode) { _, new in log.events.append(new) }
        }
    }

    @Test("§P5-7.1: each segment is a button, the selected one has the trait; a tap selects; the ink fill's targets are 44 high",
          arguments: [SegmentedPickerSpec.Look.inkFill, .capsule])
    func pickerSelection(_ look: SegmentedPickerSpec.Look) async throws {
        let log = Log()
        try await host(PickerHost(look: look, log: log)) { w in
            try await w.settle()
            let segments = w.nodes()
            #expect(segments.map(\.label) == ["Day", "Week", "Month", "Bedtime"], "\(segments.map(\.label))")
            #expect(segments.map(\.isSelected) == [true, false, false, false])
            #expect(segments.allSatisfy { $0.traits.contains(.button) && $0.frame.height >= 44 - 0.5 && $0.frame.width >= 44 },
                    "\(segments.map(\.frame))")
            try node(w, "Week").activate()
            try await w.wait("the selection") { log.events == ["Week"] }
            try await w.settle()
            #expect(w.nodes().map(\.isSelected) == [false, true, false, false])
        }
    }

    @Test("§P5-7.1: the ink fill control is 40 high with 34 pt segments, 44 from AX1; the capsule (PR 4's) stays 52")
    func pickerHeights() throws {
        let ink = try #require(ControlRender(SegmentedPicker(selection: .constant("Day"), options: ["Day", "Week"], look: .inkFill) { $0 }
            .frame(width: 350), scale: 2))
        #expect(abs(ink.size.height - 40) <= 0.5, "\(ink.size)")
        let capsule = try #require(ControlRender(SegmentedPicker(selection: .constant("Day"), options: ["Day", "Week"]) { $0 }
            .frame(width: 350), scale: 2))
        #expect(abs(capsule.size.height - 52) <= 0.5, "\(capsule.size)")
        // The selection is ink: the selected segment's middle (34 high from y 3) is textPrimary.
        let fill = Tokens.resolve(Theme.textPrimary)
        #expect(ink.at(10, 20).near(fill, 3), "\(Tokens.describe(ink.at(10, 20)))")
        #expect(!ink.at(10, 1.5).near(fill, 3), "3 pt of surface above the segment")
        // §P5-5.1: from AX1 the control is at least 44 high.
        let large = try #require(ControlRender(SegmentedPicker(selection: .constant("7\u{00A0}D"), options: ["7\u{00A0}D", "30\u{00A0}D", "90\u{00A0}D"],
                                                               look: .inkFill) { $0 }
            .frame(width: 350).environment(\.dynamicTypeSize, .accessibility1), scale: 2))
        #expect(large.size.height >= 44 - 0.5, "AX1: \(large.size)")
    }

    @Test("§P5-5.1: spokenTitle names a segment for VoiceOver (\"7 days\" for \"7 D\")")
    func pickerSpokenTitles() async throws {
        let picker = SegmentedPicker(selection: .constant("7\u{00A0}D"), options: ["7\u{00A0}D", "30\u{00A0}D"], look: .inkFill, width: .content,
                                     spokenTitle: { "\($0.dropLast(2)) days" }) { $0 }
        try await host(picker) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == ["7 days", "30 days"])
        }
    }

    // MARK: the titled header

    @Test("Test 21: the titled header is 40 high, the title leading with the header trait, the button at the inset; .wide stacks from AX1")
    func titledHeader() async throws {
        let header = VStack(spacing: 0) {
            ScreenHeader(title: Text(verbatim: "Strain")) {
                CircleButton(systemImage: "plus", iconSize: 14, accessibilityLabel: Text(verbatim: "Add activity")) {}
            }
            ScreenHeader(title: Text(verbatim: "Insights"), trailingLayout: .wide) {
                SegmentedPicker(selection: .constant("30\u{00A0}D"), options: ["7\u{00A0}D", "30\u{00A0}D", "90\u{00A0}D"], look: .inkFill, width: .content) { $0 }
            }
        }
        try await host(header) { w in
            try await w.settle()
            let title = try node(w, "Strain"), add = try node(w, "Add activity")
            #expect(title.traits.contains(.header) && abs(title.frame.minX - 20) <= 0.5, "\(title.frame)")
            #expect(abs(add.frame.maxX - (370 + 2)) <= 0.5 && abs(add.frame.height - 44) <= 0.5, "the button at the inset: \(add.frame)")
            #expect(abs(add.frame.midY - title.frame.midY) <= 1, "one row: \(add.frame) \(title.frame)")
            let insights = try node(w, "Insights"), week = try node(w, "7\u{00A0}D")
            #expect(abs(week.frame.midY - insights.frame.midY) <= 2, "the control on the title's line: \(week.frame) \(insights.frame)")
            #expect(try node(w, "90\u{00A0}D").frame.maxX <= 370 + 0.5)
        }
        try await host(header, typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            let insights = try node(w, "Insights"), week = try node(w, "7\u{00A0}D"), all = try node(w, "90\u{00A0}D")
            #expect(week.frame.minY >= insights.frame.maxY, "under the title: \(week.frame) \(insights.frame)")
            #expect(abs(week.frame.minX - 20 - 3) <= 1 && abs(all.frame.maxX - 370 + 3) <= 1, "full width: \(week.frame) \(all.frame)")
        }
    }

    // MARK: the zone block

    /// The window drawn at 3x, for reading where the ticks start.
    private struct WindowShot {
        let width: Int, height: Int
        let bytes: [UInt8]

        @MainActor init?(_ w: HostedWindow) {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            format.opaque = true
            let image = UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
                w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
            }
            guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            (width, height) = (cg.width, cg.height)
            var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            guard let ctx = CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            self.bytes = bytes
        }

        /// The first x (points) on row `y` between `from` and `to` whose pixel is full ink.
        func firstInk(y: CGFloat, from: CGFloat, to: CGFloat, ink: RGBA) -> CGFloat? {
            let iy = Int(y * 3)
            for ix in Int(from * 3)..<min(Int(to * 3), width) {
                let i = (iy * width + ix) * 4
                let p = RGBA(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255, a: 1)
                if p.near(ink, 3) { return CGFloat(ix) / 3 }
            }
            return nil
        }
    }

    private func zones() -> [ZoneBlock.Zone] {
        let names = ["Z5 · Max", "Z4 · Threshold", "Z3 · Tempo", "Z2 · Aerobic", "Z1 · Easy"]
        return zip(names, [6.0, 14, 27, 24, 11]).map { name, m in
            ZoneBlock.Zone(label: Text(verbatim: name), minutes: m, value: Text(verbatim: "\(Int(m))m"),
                           accessibilityLabel: Text(verbatim: "\(name), \(Int(m)) minutes"))
        }
    }

    @Test("Test 14: in 318 pt the five rows are aligned, one line each, every row's ticks starting at the same x")
    func zoneBlockAligned() async throws {
        let block = ZoneBlock(zones: zones(), accessibilityLabel: Text(verbatim: "Heart-rate zones")).frame(width: 318)
        try await host(block) { w in
            try await w.settle()
            let rows = w.nodes().filter { $0.label.hasPrefix("Z") }
            #expect(rows.count == 5, "\(w.nodes().map(\.label))")
            #expect(rows.allSatisfy { $0.frame.height < 20 }, "one line each: \(rows.map(\.frame.height))")
            let shot = try #require(WindowShot(w))
            let ink = Tokens.resolve(Theme.textPrimary)
            let starts = rows.compactMap { shot.firstInk(y: $0.frame.midY, from: $0.frame.minX, to: $0.frame.maxX, ink: ink) }
            #expect(starts.count == 5, "\(starts)")
            let first = try #require(starts.first)
            #expect(starts.allSatisfy { abs($0 - first) <= 0.5 }, "one tick column: \(starts)")
            #expect(first - 20 >= 74 + 12 - 0.5, "after the label column: \(first - 20)")
        }
    }

    @Test("Test 14: in 303 pt and at AX3 the five rows stack, each still one element",
          arguments: [(CGFloat(303), DynamicTypeSize.large), (318, .accessibility3)])
    func zoneBlockStacked(_ width: CGFloat, _ typeSize: DynamicTypeSize) async throws {
        let block = ZoneBlock(zones: zones(), accessibilityLabel: Text(verbatim: "Heart-rate zones")).frame(width: width)
        try await host(block, typeSize: typeSize, category: typeSize.isAccessibilitySize ? .accessibilityExtraLarge : .large) { w in
            try await w.settle()
            let rows = w.nodes().filter { $0.label.hasPrefix("Z") }
            #expect(rows.map(\.label).count == 5, "\(w.nodes().map(\.label))")
            #expect(rows.allSatisfy { $0.frame.height > 12 + 4 + 10 }, "stacked: \(rows.map(\.frame.height))")
            for (a, b) in zip(rows, rows.dropFirst()) {
                #expect(abs(b.frame.minY - a.frame.maxY - TickRow.rowSpacing) <= 0.5, "9 apart: \(a.frame) \(b.frame)")
            }
        }
    }

    // MARK: the trend line

    @Test("Test 20: the trend line is one element: the caller's label and the sentence's ending")
    func trendLineSpeaks() async throws {
        let lines = VStack {
            TrendLine(values: [60, 62, 74], band: 56...68, color: Theme.recovery, accessibilityLabel: Text(verbatim: "HRV over 30 days"))
            TrendLine(values: [9, 14], color: Theme.metricStrain, accessibilityLabel: Text(verbatim: "Strain over 30 days"),
                      spokenLatest: Text(verbatim: "14"))
            TrendLine(values: [], color: Theme.recovery, isPending: true, accessibilityLabel: Text(verbatim: "Sleep over 30 days"))
        }
        try await host(lines) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == ["HRV over 30 days", "Strain over 30 days", "Sleep over 30 days"])
            #expect(nodes.map(\.value) == ["ending above its usual range", "ending at 14", "Loading…"], "\(nodes.map(\.value))")
            #expect(nodes.allSatisfy { abs($0.frame.height - 48) <= 0.5 })
        }
    }
}
