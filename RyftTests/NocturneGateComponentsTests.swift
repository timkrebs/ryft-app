import Foundation
import SwiftUI
import Testing
@testable import Ryft

/// The Nocturne gate's components (G2, docs/work/2026-11-20-nocturne-gate/design.md §5.2): one circle menu, the live workout's
/// offline line once, one card radius, `ValueChipRow`'s role, and the old components gone. By reading the sources; the hosted
/// half is `NocturneGateComponentsHostedTests`.
@MainActor
@Suite("Nocturne gate: the components, by source")
struct NocturneGateComponentsTests {
    private typealias Tokens = NocturneTokenTests

    // MARK: the sources

    /// `RyftTests/`'s parent.
    nonisolated static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Every Swift file under `folder` (`Ryft`, `Shared`, …): its path from there and its code, `//` comments removed.
    static func sources(_ folder: String) throws -> [(path: String, code: String)] {
        let root = repo.appendingPathComponent(folder)
        return try FileManager.default.subpathsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".swift") }.sorted().map {
            ($0, code(try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8)))
        }
    }

    /// The code without `//` comments (one after a colon is a URL's), line for line.
    static func code(_ source: String) -> String {
        source.components(separatedBy: "\n").map { $0.replacing(#/(^|[^:])//.*/#) { String($0.output.1) } }
            .joined(separator: "\n")
    }

    /// From the opening `{` or `(` at `start` to its closer, both included; nil when it doesn't close.
    static func block(_ code: String, at start: String.Index) -> Range<String.Index>? {
        let open = code[start], close: Character = open == "{" ? "}" : ")"
        var depth = 0
        var index = start
        while index < code.endIndex {
            if code[index] == open { depth += 1 }
            if code[index] == close {
                depth -= 1
                if depth == 0 { return start..<code.index(after: index) }
            }
            index = code.index(after: index)
        }
        return nil
    }

    /// The `label:` closure of every `Menu { … } label: { … }` in `code` (a `Menu("Title") { … }` has none).
    static func menuLabels(in code: String) -> [String] {
        var labels: [String] = []
        for match in code.matches(of: #/\bMenu\s*(\{|\()/#) {
            var at = code.index(before: match.range.upperBound)
            if code[at] == "(" {
                guard let args = block(code, at: at),
                      let brace = code[args.upperBound...].firstIndex(where: { !$0.isWhitespace }), code[brace] == "{" else { continue }
                at = brace
            }
            guard let items = block(code, at: at) else { continue }
            let rest = code[items.upperBound...]
            guard let label = rest.prefixMatch(of: #/\s*label:\s*\{/#),
                  let closure = block(code, at: code.index(before: label.range.upperBound)) else { continue }
            labels.append(String(code[closure]))
        }
        return labels
    }

    /// A menu label that draws the circle button itself: its numbers or a circle.
    static func drawsACircle(_ label: String) -> Bool {
        ["CircleButton.diameter", "CircleButton.borderOpacity", "Circle()"].contains { label.contains($0) }
    }

    // MARK: one circle menu (D3)

    @Test("The scan's own control: a hand-drawn circle menu is caught; CircleMenu and a bare … menu are not")
    func theMenuScanCatchesAHandDrawnCircle() {
        let handDrawn = """
            Menu {
                Button("Add activity") {}
            } label: {
                Image(systemName: "plus")
                    .frame(width: CircleButton.diameter, height: CircleButton.diameter)
                    .overlay { Circle().strokeBorder(Theme.textPrimary.opacity(CircleButton.borderOpacity), lineWidth: 1) }
            }
            .accessibilityLabel(Text("Add"))
            """
        let labels = Self.menuLabels(in: handDrawn)
        #expect(labels.count == 1 && labels.allSatisfy(Self.drawsACircle), "\(labels)")
        let circleMenu = "CircleMenu(systemImage: \"plus\", accessibilityLabel: Text(\"Add\")) { Button(\"Add activity\") {} }"
        #expect(Self.menuLabels(in: circleMenu).isEmpty)
        let bare = """
            Menu { Button("Remove") {} } label: {
                Image(systemName: "ellipsis").frame(width: CircleButton.hitSize, height: CircleButton.hitSize)
            }
            """
        #expect(Self.menuLabels(in: bare).count == 1 && !Self.menuLabels(in: bare).contains(where: Self.drawsACircle))
        let titled = "Menu(\"Sort\") { Button(\"A\") {} }\nMenu(\"More\") { Button(\"B\") {} } label: { Circle() }"
        #expect(Self.menuLabels(in: titled) == ["{ Circle() }"])
    }

    @Test("No menu in Ryft/ draws the circle button itself; the button's ring is drawn once, in CircleButton.swift")
    func oneCircleMenu() throws {
        let files = try Self.sources("Ryft")
        var menus = 0
        var handDrawn: [String] = []
        for (path, code) in files {
            let labels = Self.menuLabels(in: code)
            menus += labels.count
            if labels.contains(where: Self.drawsACircle) { handDrawn.append(path) }
        }
        #expect(menus >= 10, "menus with a label found: \(menus)")
        #expect(handDrawn.isEmpty, "a menu drawing the circle itself, not CircleMenu: \(handDrawn)")

        // The ring: the button's (and so the menu's) one source, and two graphics that are not buttons.
        let ring = #/Circle\(\)\s*\.strokeBorder\(\s*Theme\.textPrimary\.opacity\(\s*CircleButton\.borderOpacity/#
        let rings = files.filter { $0.code.contains(ring) }.map(\.path)
        #expect(Set(rings) == ["Design/CircleButton.swift", "Features/Auth/CheckInboxView.swift",
                               "Features/Onboarding/HealthIllustration.swift"], "\(rings)")
        let button = try #require(files.first { $0.path == "Design/CircleButton.swift" }).code
        #expect(button.matches(of: ring).count == 1)
        #expect(button.contains("CircleButtonLook(isPressed: configuration.isPressed)"), "the button's style draws the look")
        let menu = try #require(files.first { $0.path == "Design/CircleMenu.swift" }).code
        #expect(menu.contains(".modifier(CircleButtonLook())"), "the menu draws the same look")
    }

    // MARK: the offline line, once

    @Test("The live workout's offline sentence is in Ryft/ once, in SessionOfflineLine")
    func offlineSentenceOnce() throws {
        let sentence = "\"Offline — every set is saved on this phone and syncs later.\""
        let hits = try Self.sources("Ryft").flatMap { file in
            Array(repeating: file.path, count: file.code.components(separatedBy: sentence).count - 1)
        }
        #expect(hits == ["Features/Train/Session/SessionOfflineLine.swift"], "\(hits)")
    }

    // MARK: one card radius (D8)

    @Test("Every card's radius is the one token, 22")
    func oneCardRadius() {
        #expect(Theme.Metrics.neutralTileRadius == 22)
        let radii: [(String, CGFloat)] = [
            ("CardSpec.radius", CardSpec.radius), ("GroupedListSpec.cardRadius", GroupedListSpec.cardRadius),
            ("ProfileLayout.cardRadius", ProfileLayout.cardRadius),
            ("JournalSettingsLayout.cardRadius", JournalSettingsLayout.cardRadius),
            ("StrainLayout.chartRadius", StrainLayout.chartRadius), ("SleepModesLayout.stageCardRadius", SleepModesLayout.stageCardRadius),
        ]
        for (name, radius) in radii {
            #expect(radius == Theme.Metrics.neutralTileRadius, "\(name) is \(radius)")
        }
    }

    @Test("The card radii name the token, not a number of their own")
    func cardRadiiNameTheToken() throws {
        let declarations = [
            ("Design/Card.swift", "radius"), ("Design/GroupedList.swift", "cardRadius"),
            ("Features/Profile/ProfileLayout.swift", "cardRadius"), ("Features/Journal/JournalSettingsView.swift", "cardRadius"),
            ("Features/Strain/StrainLayout.swift", "chartRadius"), ("Features/Sleep/SleepModesLayout.swift", "stageCardRadius"),
        ]
        let files = try Self.sources("Ryft")
        for (path, name) in declarations {
            let code = try #require(files.first { $0.path == path }, "\(path)").code
            let declared = try Regex("static let \(name)\\s*(:\\s*CGFloat\\s*)?=\\s*([^,\\n]+)")
            let values = code.matches(of: declared).compactMap { $0.output[2].substring.map(String.init) }
            #expect(!values.isEmpty, "\(path): \(name) declared")
            #expect(values.allSatisfy { $0.trimmingCharacters(in: .whitespaces) == "Theme.Metrics.neutralTileRadius" },
                    "\(path): \(name) = \(values)")
        }
    }

    // MARK: ValueChipRow's role (D9 row 1)

    @Test("ValueChipRow's label: a field's caption in textSecondary by default, a row's title in textPrimary")
    func valueChipRowRoles() {
        #expect(ValueChipRole.field.ink == Theme.textSecondary)
        #expect(ValueChipRole.row.ink == Theme.textPrimary)
        let surface = Tokens.resolve(Theme.surface)
        #expect(Tokens.ratio(Tokens.resolve(ValueChipRole.row.ink), on: surface) >= 16)
        #expect(Tokens.ratio(Tokens.resolve(ValueChipRole.field.ink), on: surface) >= 4.5)
    }

    @Test("Notifications and Bedtime & wake pass .row; every other caller keeps the default")
    func valueChipRowCallers() throws {
        var rows: [String] = [], fields: [String] = []
        for (path, code) in try Self.sources("Ryft") where path != "Design/FormField.swift" {
            for match in code.matches(of: #/\bValueChipRow\(/#) {
                let open = code.index(before: match.range.upperBound)
                let call = try #require(Self.block(code, at: open), "\(path): the call closes")
                if code[call].contains("role: .row") { rows.append(path) } else { fields.append(path) }
                #expect(!code[call].contains("role: .field"), "\(path): the default is not spelled out")
            }
        }
        #expect(rows.sorted() == ["Features/Profile/NotificationSettingsView.swift", "Features/Profile/NotificationSettingsView.swift",
                                  "Features/Sleep/SleepPlannerView.swift"], "\(rows)")
        #expect(Set(fields) == ["Features/Activities/AddActivitySheet.swift", "Features/Activities/AddSleepSheet.swift",
                                "Features/Journal/JournalViews.swift", "Features/Profile/NocturneFoundationCatalog.swift"],
                "\(fields)")
    }

    // MARK: the deleted components

    @Test("MetricGauge, MetricTile, ZoneBar, ScoreRing and AppState.workoutDetail(_:) are gone; no motion allowlist entry names a missing file")
    func retiredComponentsAreGone() throws {
        let manager = FileManager.default
        for file in ["MetricGauge", "MetricTile", "ZoneBar", "ScoreRing"] {
            #expect(!manager.fileExists(atPath: Self.repo.appendingPathComponent("Ryft/Design/\(file).swift").path), "\(file).swift")
        }
        let use = #/\b(MetricGauge|MetricTile|ZoneBar|ScoreRing)\b\s*[(<{:.]|\b(struct|enum|class|extension)\s+(MetricGauge|MetricTile|ZoneBar|ScoreRing)\b/#
        var found: [String] = []
        for folder in ["Ryft", "RyftWidgets", "Shared"] {
            for (path, code) in try Self.sources(folder) where code.contains(use) { found.append("\(folder)/\(path)") }
        }
        #expect(found.isEmpty, "\(found)")
        let appState = try #require(try Self.sources("Ryft").first { $0.path == "App/AppState.swift" }).code
        #expect(!appState.contains("func workoutDetail("), "AppState.workoutDetail(_:) had no caller")
        for entry in ReduceMotionScanTests.guarded {
            #expect(manager.fileExists(atPath: Self.repo.appendingPathComponent("Ryft/\(entry.file)").path), "\(entry.file)")
        }
    }
}

/// The same in real windows: the circle menu is the circle button's pixels, at each of its three places, and the offline line
/// shows once in either layout. Synthetic values only.
@MainActor
@Suite("Nocturne gate: the components, hosted", .serialized)
struct NocturneGateComponentsHostedTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA

    private static func distance(_ a: RGBA, _ b: RGBA) -> Double { max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b)) }
    private static func luminance(_ c: RGBA) -> Double { Tokens.luminance(c) }

    /// The largest channel difference between two equal-sized boxes of the window, pixel for pixel; `keep` picks the points
    /// (from the box's centre) that count.
    private static func difference(_ pixels: WindowPixels, _ a: CGRect, _ b: CGRect,
                                   keep: (CGFloat, CGFloat) -> Bool = { _, _ in true }) -> Double {
        let step = 1 / pixels.scale
        var worst = 0.0
        var y = step / 2
        while y < a.height {
            var x = step / 2
            while x < a.width {
                if keep(x - a.width / 2, y - a.height / 2) {
                    worst = max(worst, distance(pixels.at(a.minX + x, a.minY + y), pixels.at(b.minX + x, b.minY + y)))
                }
                x += step
            }
            y += step
        }
        return worst
    }

    /// The brightest pixel in `rect`.
    private static func brightest(_ pixels: WindowPixels, in rect: CGRect) -> RGBA {
        let step = 1 / pixels.scale
        var best = pixels.at(rect.minX, rect.minY)
        var y = rect.minY + step / 2
        while y < rect.maxY {
            var x = rect.minX + step / 2
            while x < rect.maxX {
                let p = pixels.at(x, y)
                if luminance(p) > luminance(best) { best = p }
                x += step
            }
            y += step
        }
        return best
    }

    /// The circle's ring: 1 pt inside the 40 pt circle, with half a point either side for the antialiasing.
    private static func onTheRing(_ x: CGFloat, _ y: CGFloat) -> Bool {
        let r = (x * x + y * y).squareRoot(), outer = CircleButton.diameter / 2
        return r >= outer - Theme.Metrics.hairline - 0.5 && r <= outer + 0.5
    }

    // MARK: the component

    private struct Lineup: View {
        var body: some View {
            HStack(spacing: 8) {
                CircleMenu(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "Menu idle")) {
                    Button {} label: { Text(verbatim: "Edit") }
                }
                CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "Button idle")) {}
                CircleMenu(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "Menu disabled")) {
                    Button {} label: { Text(verbatim: "Edit") }
                }
                .disabled(true)
                CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "Button disabled")) {}
                    .disabled(true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
        }
    }

    /// The ring pixel for pixel. The glyph by its box and its ink: a menu's label may land a pixel (⅓ pt) beside the button's
    /// (iOS 27.2 rounds the centred ellipsis at 15.33 in the menu and 15.67 in the button), which no eye sees and a pixel diff
    /// would.
    @Test("CircleMenu is CircleButton's pixels, idle and disabled: a 44 pt box, the same ring, the glyph at 35 % when disabled")
    func circleMenuIsTheCircleButton() async throws {
        try await HostedWindow.run(width: 390, height: 200, Lineup()) { w in
            try await w.settle()
            let frames = try ["Menu idle", "Button idle", "Menu disabled", "Button disabled"].map { label in
                try #require(w.node(label, exactly: true), "\(label)").frame
            }
            for frame in frames {
                #expect(abs(frame.width - CircleButton.hitSize) < 0.5 && abs(frame.height - CircleButton.hitSize) < 0.5, "\(frame)")
            }
            #expect(try #require(w.node("Menu disabled", exactly: true)).isEnabled == false)
            let pixels = try WindowPixels(w)
            for (menu, button, state) in [(frames[0], frames[1], "idle"), (frames[2], frames[3], "disabled")] {
                let ring = Self.difference(pixels, menu, button, keep: Self.onTheRing)
                #expect(ring < 0.02, "the \(state) menu's ring differs from the button's by \(ring)")
            }

            // The glyph: ink when idle, ink at 35 % over the screen when disabled (the ring stays at 16 %); the same box.
            let screen = Tokens.resolve(Theme.background)
            var ink = Tokens.resolve(Theme.textPrimary)
            let idle = ink
            ink.a = CircleButton.disabledIconOpacity
            let dimmed = Tokens.over(ink, screen)
            let inner = { (frame: CGRect) in frame.insetBy(dx: 6, dy: 6) }
            for (frame, want, name) in [(frames[0], idle, "Menu idle"), (frames[1], idle, "Button idle"),
                                        (frames[2], dimmed, "Menu disabled"), (frames[3], dimmed, "Button disabled")] {
                let p = Self.brightest(pixels, in: inner(frame))
                #expect(Self.distance(p, want) < 0.04, "\(name): \(Tokens.describe(p)), want \(Tokens.describe(want))")
            }
            for (menu, button, level) in [(frames[0], frames[1], idle), (frames[2], frames[3], dimmed)] {
                let half = (level.r + screen.r) / 2
                let a = try #require(pixels.box(in: inner(menu)) { $0.r > half }?.offsetBy(dx: -menu.midX, dy: -menu.midY))
                let b = try #require(pixels.box(in: inner(button)) { $0.r > half }?.offsetBy(dx: -button.midX, dy: -button.midY))
                #expect(abs(a.width - b.width) <= 0.34 && abs(a.height - b.height) <= 0.34, "glyph \(a) vs \(b)")
                #expect(abs(a.midX - b.midX) <= 0.34 && abs(a.midY - b.midY) <= 0.34, "glyph \(a) vs \(b)")
            }
        }
    }

    // MARK: the three places

    enum Site: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case liveWorkout, activityDetail, myDay
        var testDescription: String { rawValue }

        var identifier: String {
            switch self {
            case .liveWorkout: "session.more"
            case .activityDetail: "activityDetail.menu"
            case .myDay: "myday.add"
            }
        }

        var label: String { self == .myDay ? "Add" : "More" }
        /// The `CircleButton` beside it in the same header.
        var neighbour: String {
            switch self {
            case .liveWorkout: "Minimise"
            case .activityDetail: "activityDetail.back"
            case .myDay: "myday.view.back"
            }
        }

        /// Its first item.
        var item: String {
            switch self {
            case .liveWorkout: "Reorder exercises"
            case .activityDetail: "Edit"
            case .myDay: "Add activity"
            }
        }
    }

    @Test("Each of the three menus is CircleMenu: its label and identifier, a 44 pt box, the button's ring, and it opens",
          arguments: Site.allCases)
    func theThreeMenus(_ site: Site) async throws {
        let session = FocusedPreview.controller(.draft)
        defer { session.stop() }
        let content: AnyView = switch site {
        case .liveWorkout:
            AnyView(SessionView(controller: session))
        case .activityDetail:
            AnyView(ActivitiesShotFixtures.detail { $0.sport == .mobility })
        case .myDay:
            AnyView(NavigationStack {
                MyDayPage(content: MyDayShotFixtures.today, week: MockMyDay.week(daysBack: 0),
                          actions: MyDayShotFixtures.actions(MyDayShotFixtures.today))
            }
            .environment(\.locale, Locale(identifier: "en_US")))
        }
        try await HostedWindow.run(width: 390, height: 844, content) { w in
            try await w.wait(site.identifier) { w.nodes().contains { $0.identifier == site.identifier } }
            try await w.settle()
            let nodes = w.nodes()
            let menu = try #require(nodes.first { $0.identifier == site.identifier })
            #expect(menu.label == site.label)
            #expect(abs(menu.frame.width - CircleButton.hitSize) < 0.5 && abs(menu.frame.height - CircleButton.hitSize) < 0.5,
                    "\(menu.frame)")
            let neighbour = try #require(nodes.first { $0.identifier == site.neighbour || $0.label == site.neighbour },
                                         "\(site.neighbour)")
            #expect(abs(neighbour.frame.width - menu.frame.width) < 0.5 && abs(neighbour.frame.height - menu.frame.height) < 0.5)
            let ring = Self.difference(try WindowPixels(w), menu.frame, neighbour.frame, keep: Self.onTheRing)
            #expect(ring < 0.02, "the menu's ring differs from \(site.neighbour)'s by \(ring)")
            #expect(menu.activate())
            try await w.wait("the menu lists \(site.item)") { w.menuItem(site.item) != nil }
        }
    }

    // MARK: the offline line

    enum Layout: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case list, focused
        var testDescription: String { rawValue }
    }

    @Test("Offline, each layout shows the one line, its words from the 16 pt side; online, none", arguments: Layout.allCases)
    func offlineLineInBothLayouts(_ layout: Layout) async throws {
        let monitor = ConnectivityMonitor.preview(online: false)
        let c = FocusedPreview.controller(layout == .list ? .draftList : .draft, connectivity: monitor)
        defer { c.stop() }
        #expect(c.layout == (layout == .list ? .list : .focused))
        // The list reads the environment's sync service: the controller's, as in the app.
        try await HostedWindow.run(width: 390, height: 844, SessionView(controller: c).environment(c.sync)) { w in
            try await w.wait("the line") { w.nodes().contains { $0.identifier == "session.offlineLine" } }
            try await w.settle()
            let lines = w.nodes().filter { $0.identifier == "session.offlineLine" }
            #expect(lines.count == 1, "\(lines.map(\.label))")
            let line = try #require(lines.first)
            #expect(line.label == "Offline — every set is saved on this phone and syncs later.")
            // The element is the glyph and the words (the 28 pt row is `SessionOfflineLine.minHeight`): the glyph's ink starts
            // a point or two inside the side, and the words end before the other.
            #expect(SessionOfflineLine.minHeight == 28)
            #expect(line.frame.minX >= LiveSessionSpec.sidePadding - 0.5 && line.frame.minX < LiveSessionSpec.sidePadding + 4,
                    "\(line.frame)")
            #expect(line.frame.maxX <= 390 - LiveSessionSpec.sidePadding + 0.5, "\(line.frame)")
            monitor.update(true)
            try await w.wait("the line goes") { !w.nodes().contains { $0.identifier == "session.offlineLine" } }
        }
    }

    // MARK: ValueChipRow's ink

    @Test("A field row's label is drawn in textSecondary, a row's title in textPrimary")
    func valueChipRowInks() async throws {
        let card = GroupedCard {
            ValueChipRow(Text(verbatim: "Field")) { ValueChip(Text(verbatim: "9:41")) }
            ValueChipRow(Text(verbatim: "Title"), role: .row) { ValueChip(Text(verbatim: "9:41")) }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.background)
        try await HostedWindow.run(width: 390, height: 300, card) { w in
            try await w.settle()
            let pixels = try WindowPixels(w)
            let surface = Tokens.resolve(Theme.surface)
            for (label, ink) in [("Field", Theme.textSecondary), ("Title", Theme.textPrimary)] {
                let frame = try #require(w.node(label, exactly: true), "\(label)").frame
                let p = Self.brightest(pixels, in: frame)
                let want = Tokens.over(Tokens.resolve(ink), surface)
                #expect(Self.distance(p, want) < 0.04, "\(label): \(Tokens.describe(p)), want \(Tokens.describe(want))")
            }
        }
    }
}
