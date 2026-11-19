import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Profile → Display → Hero numbers (docs/work/2026-11-16-nocturne/design.md §P4-6, L19; §P4-11 tests 46–47): the setting
/// on disk, what it gives the numerals, and the row in Profile. Today's and Sleep's use of it are T4.2's and T4.3's.
@Suite("Hero numbers, the setting")
struct HeroNumeralsTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard }

    @Test("Spec 46: the default is Dots")
    func defaultIsDots() {
        #expect(Settings(defaults: defaults()).heroNumerals == .dots)
    }

    @Test("Spec 46: a choice persists under ui.heroNumerals", arguments: HeroNumerals.allCases)
    func persists(_ choice: HeroNumerals) {
        let d = defaults()
        Settings(defaults: d).heroNumerals = choice
        #expect(d.string(forKey: "ui.heroNumerals") == choice.rawValue)
        #expect(Settings(defaults: d).heroNumerals == choice)
        #expect(HeroNumerals.defaultsKey == "ui.heroNumerals")
    }

    @Test("Spec 46: an unknown stored value reads as Dots")
    func unknownIsDots() {
        let d = defaults()
        d.set("serif", forKey: "ui.heroNumerals")
        #expect(Settings(defaults: d).heroNumerals == .dots)
    }

    @Test("Spec 46: a device preference: it survives log-out, on disk too")
    func survivesLogOut() {
        let d = defaults()
        let settings = Settings(defaults: d)
        settings.heroNumerals = .thin
        settings.clearPerUserState()
        #expect(settings.heroNumerals == .thin)
        #expect(Settings(defaults: d).heroNumerals == .thin)
    }

    @Test("Spec 46: Thin gives the numerals .light and Dots .dots; from AX1 both draw Light", arguments: DynamicTypeSize.allCases)
    func style(_ size: DynamicTypeSize) {
        #expect(HeroNumerals.dots.style == .dots && HeroNumerals.thin.style == .light)
        #expect(DotNumeral.rendersDots("84", style: HeroNumerals.thin.style, typeSize: size) == false)
        #expect(DotNumeral.rendersDots("84", style: HeroNumerals.dots.style, typeSize: size) == !size.isAccessibilitySize, "\(size)")
        #expect(DotNumeral.rendersDots("7:48", style: HeroNumerals.dots.style, typeSize: size) == !size.isAccessibilitySize)
    }

    @Test("The options' titles")
    func titles() {
        #expect(HeroNumerals.allCases.map(\.title) == ["Dots", "Thin"])
    }
}

/// The new shared views in a real window, read through the accessibility tree: Profile's row (47), the header row's
/// geometry, the launch's hand-off targets, the gauge without its caption.
@MainActor
@Suite("PR 4 shared views, hosted", .serialized)
struct NocturneSharedHostedTests {
    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool { abs(a - b) <= tolerance }

    /// `view` at the top-leading corner of a 390 × `height` window on the screen colour.
    private func host<V: View>(_ view: V, height: CGFloat = 700, typeSize: DynamicTypeSize = .large,
                               category: UIContentSizeCategory = .large,
                               _ body: (HostedWindow) async throws -> Void) async throws {
        let content = view.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Theme.background)
        try await HostedWindow.run(width: 390, height: height, typeSize: typeSize, category: category, content, body: body)
    }

    // MARK: 47. Profile

    private func settings() -> Settings {
        Settings(defaults: UserDefaults(suiteName: "ryft.test.\(UUID().uuidString)") ?? .standard)
    }

    /// The menu: UIKit draws a menu picker, so it is not one of `HostedWindow`'s SwiftUI nodes; found by its identifier.
    private func menu(_ w: HostedWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func find(_ object: NSObject, depth: Int) -> NSObject? {
            guard depth < 60, seen.insert(ObjectIdentifier(object)).inserted else { return nil }
            if (object.value(forKey: "accessibilityIdentifier") as? String) == "profile.heroNumerals" { return object }
            var children: [NSObject] = []
            if let elements = object.accessibilityElements { children += elements.compactMap { $0 as? NSObject } }
            if let view = object as? UIView { children += view.subviews }
            for child in children { if let hit = find(child, depth: depth + 1) { return hit } }
            return nil
        }
        return find(w.host.view, depth: 0)
    }

    /// What the menu says: its label and its value (the choice shows as one or the other).
    private func spoken(_ object: NSObject?) -> String {
        guard let object else { return "" }
        return "\(object.accessibilityLabel ?? "") \(object.accessibilityValue ?? "")"
    }

    @Test("Spec 47: Profile shows Hero numbers with the choice, and follows a change without a reload")
    func profileRow() async throws {
        let s = settings()
        try await HostedWindow.run(width: 390, height: 3200, ProfileView().environment(s)) { w in
            try await w.settle()
            // Nocturne (T5.4): the row is in Settings, a menu row (`HeroNumbersMenuRow`).
            #expect(w.node("Settings", exactly: true) != nil, "the group title")
            #expect(w.node("Hero numbers", exactly: true) != nil, "the row's title")
            #expect(w.node("Large numbers on Today, Sleep and Strain.", exactly: true) != nil, "the footer")
            let picker = try #require(menu(w), "the menu")
            #expect(spoken(picker).contains("Dots"), "\(spoken(picker))")
            s.heroNumerals = .thin
            try await w.wait("the menu shows Thin") { spoken(menu(w)).contains("Thin") }
        }
    }

    @Test("The row at AX3: the value under its title (a line of its own), inside the window")
    func profileRowAX3() async throws {
        // Profile's row (`HeroNumbersMenuRow`, one element: the title and the choice) in its card, over a one-line row of the
        // same type: beside the title the two are as high; under it the menu row has the value's line more.
        let rows = VStack(spacing: GroupedListSpec.groupSpacing) {
            GroupedCard(Text(verbatim: "Settings")) { HeroNumbersMenuRow(selection: .constant(.thin)) }
            GroupedCard(Text(verbatim: "Reference")) { GroupedRow.push(Text(verbatim: "One line")) {} }
        }
        .padding(.horizontal, 20)
        for (typeSize, category) in [(DynamicTypeSize.large, UIContentSizeCategory.large), (.accessibility3, .accessibilityExtraLarge)] {
            try await host(rows, typeSize: typeSize, category: category) { w in
                try await w.settle()
                let picker = try #require(menu(w), "the menu")
                #expect(spoken(picker).contains("Hero numbers") && spoken(picker).contains("Thin"), "\(spoken(picker))")
                let frame = picker.accessibilityFrame
                let line = try #require(w.node("One line", exactly: true)).frame
                if typeSize.isAccessibilitySize {
                    #expect(frame.height > line.height + 12, "the value under the title: \(frame) / \(line)")
                } else {
                    #expect(abs(frame.height - line.height) <= 1.5, "the value beside the title: \(frame) / \(line)")
                }
                #expect(frame.maxX <= 390 + 0.5 && frame.minX >= -0.5, "\(frame)")
            }
        }
    }

    // MARK: ScreenHeader

    @Test("Today's header: the lock-up on the inset, the button's circle edge on the trailing inset, the row 40 high")
    func todayHeader() async throws {
        let view = VStack(spacing: 0) {
            ScreenHeader {
                CircleButton(systemImage: "calendar", iconSize: 16, accessibilityLabel: Text(verbatim: "Calendar")) {}
            }
            Text(verbatim: "below")
        }
        .padding(.horizontal, 20)
        try await host(view) { w in
            try await w.settle()
            let lockUp = try #require(w.node("RYFT", exactly: true))
            let button = try #require(w.node("Calendar", exactly: true))
            let below = try #require(w.node("below", exactly: true))
            #expect(lockUp.traits.contains(.header))
            // The element's frame is the ink's: the mark's ring sits about 1 pt inside its 26 pt box.
            #expect(near(lockUp.frame.minX, 20, 1.5), "lock-up at \(lockUp.frame)")
            #expect(near(button.frame.width, 44) && near(button.frame.height, 44), "\(button.frame)")
            // The 40 pt circle ends on the inset (370), its 44 pt box 2 past it.
            #expect(near(button.frame.maxX, 372), "button at \(button.frame)")
            #expect(near(lockUp.frame.midY, button.frame.midY), "both centred in the row")
            #expect(near(below.frame.minY - button.frame.minY, 42), "row 40: the box reaches 2 above it")
        }
    }

    @Test("Without its button the row keeps its 40 pt and the lock-up its place")
    func todayHeaderWithoutButton() async throws {
        let view = VStack(spacing: 0) {
            ScreenHeader { EmptyView() }
            Text(verbatim: "below")
        }
        .padding(.horizontal, 20)
        try await host(view) { w in
            try await w.settle()
            let lockUp = try #require(w.node("RYFT", exactly: true))
            let below = try #require(w.node("below", exactly: true))
            #expect(near(lockUp.frame.minX, 20, 1.5))
            #expect(near(below.frame.minY - lockUp.frame.midY, 20), "half of 40 under the lock-up's middle")
        }
    }

    @Test("Three slots: a button's circle on each inset, the title centred between them, read left to right")
    func threeSlotHeader() async throws {
        let view = ScreenHeader {
            CircleButton(systemImage: "chevron.left", accessibilityLabel: Text(verbatim: "Previous night")) {}
        } center: {
            Text(verbatim: "Sleep").accessibilityAddTraits(.isHeader)
        } trailing: {
            CircleButton(systemImage: "chevron.right", accessibilityLabel: Text(verbatim: "Next night")) {}.disabled(true)
        }
        .padding(.horizontal, 20)
        try await host(view) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == ["Previous night", "Sleep", "Next night"])
            let previous = try #require(w.node("Previous night", exactly: true))
            let next = try #require(w.node("Next night", exactly: true))
            let title = try #require(w.node("Sleep", exactly: true))
            #expect(near(previous.frame.minX, 18) && near(next.frame.maxX, 372), "\(previous.frame) \(next.frame)")
            #expect(near(title.frame.midX, 195), "centred: \(title.frame)")
            #expect(!next.isEnabled)
        }
    }

    // MARK: The launch's hand-off targets (§P4-7 seam)

    @MainActor
    private final class Frames {
        var byRole: [LaunchHandOffRole: CGRect?] = [:]
        var reports = 0
    }

    private func lockUp(handOff: Bool, frames: Frames) -> some View {
        WordmarkLockup(handOff: handOff)
            .padding(.leading, 20)
            .padding(.top, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.launchHandOffRegistrar, LaunchHandOffRegistrar { role, frame in
                frames.byRole[role] = frame
                frames.reports += 1
            })
    }

    @Test("WordmarkLockup(handOff: true) registers the mark (26 × 26) and the wordmark in the window's space")
    func handOffRegisters() async throws {
        let frames = Frames()
        try await HostedWindow.run(width: 390, height: 300, lockUp(handOff: true, frames: frames)) { w in
            try await w.settle()
            try await w.wait("the mark registered") { frames.byRole[.mark] != nil }
            let mark = try #require(frames.byRole[.mark].flatMap { $0 })
            // The window's space (VB1): the 7 pt sit under the window's top inset.
            let top = w.window.safeAreaInsets.top
            #expect(near(mark.minX, 20) && near(mark.minY, top + 7) && near(mark.width, 26) && near(mark.height, 26),
                    "\(mark) under a \(top) pt inset")
            let wordmark = try #require(frames.byRole[.wordmark].flatMap { $0 })
            #expect(near(wordmark.minX, 56), "10 pt after the mark: \(wordmark)")
            #expect(near(wordmark.midY, mark.midY, 1))
        }
    }

    @Test("Without handOff nothing registers")
    func noHandOffNoRegistration() async throws {
        let frames = Frames()
        try await HostedWindow.run(width: 390, height: 300, lockUp(handOff: false, frames: frames)) { w in
            try await w.settle()
            #expect(frames.reports == 0 && frames.byRole.isEmpty)
        }
    }

    @Test("While the launch draws them the targets keep their place at opacity 0; a lock-up that is no target stays")
    func handOffHides() throws {
        func inked(_ view: some View) throws -> Int {
            let shot = try #require(KindShot.render(view.padding(4), scale: 2))
            var count = 0
            for iy in 0..<shot.height {
                for ix in 0..<shot.width where shot.px(ix, iy).a > 0.1 { count += 1 }
            }
            return count
        }
        #expect(try inked(WordmarkLockup(handOff: true)) > 100)
        #expect(try inked(WordmarkLockup(handOff: true).environment(\.launchHidesHandOffTargets, true)) == 0)
        #expect(try inked(WordmarkLockup().environment(\.launchHidesHandOffTargets, true)) > 100)
        let shown = try #require(KindShot.render(WordmarkLockup(handOff: true), scale: 2))
        let hidden = try #require(KindShot.render(WordmarkLockup(handOff: true).environment(\.launchHidesHandOffTargets, true),
                                                  scale: 2))
        #expect(shown.size == hidden.size, "the place is kept")
    }

    @Test("The hidden lock-up is still in the accessibility tree, the heading VoiceOver lands on")
    func hiddenLockUpIsInTheTree() async throws {
        let view = WordmarkLockup(handOff: true).environment(\.launchHidesHandOffTargets, true)
        try await host(view) { w in
            try await w.settle()
            #expect(w.node("RYFT", exactly: true)?.traits.contains(.header) == true)
        }
    }

    // MARK: OrbitGauge(showsCaption:)

    @Test("showsCaption: false draws the gauge without its caption; the caption is still spoken")
    func gaugeWithoutCaption() async throws {
        func gauge(_ shows: Bool) -> OrbitGauge {
            OrbitGauge(mode: .scored(.previewBoard), size: .large, caption: .previewBoard, showsCaption: shows,
                       animatesFill: false, breathes: false)
        }
        let with = try #require(KindShot.render(gauge(true), scale: 1))
        let without = try #require(KindShot.render(gauge(false), scale: 1))
        #expect(without.size.height < with.size.height - 10, "\(without.size) vs \(with.size)")
        try await host(gauge(false)) { w in
            try await w.settle()
            let node = try #require(w.nodes().first { $0.identifier == "orbitGauge" })
            // The caption's change (84 against 76) is still in the sentence.
            let spoken = DeltaLabel.spoken(MetricDelta(current: 84, reference: 76), spec: .readiness, reference: nil)
            #expect("\(node.label) \(node.value ?? "")".contains(spoken), "\(node.label) / \(node.value ?? "")")
        }
    }
}
