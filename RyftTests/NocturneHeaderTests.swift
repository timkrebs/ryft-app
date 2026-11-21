import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The Nocturne gate's one header (G2, docs/work/2026-11-20-nocturne-gate/design.md §2.4 D4, DG-6): a sheet's root draws
/// `SheetHeader` (Close leading, the title centred, pinned), a pushed page `PushedHeader`'s row (Back leading, the title
/// centred; stacked from AX1), the import's steps 2 to 5 Back, the title and Close trailing (steps 1 and 6 its sheet header,
/// pinned). Only the tab roots keep the 26 pt leading title (`ScreenHeader`), and the onboarding and gate pages theirs (D4
/// rule 7). Synthetic data only.
@MainActor
@Suite("Nocturne gate G2: one header", .serialized)
struct NocturneHeaderTests {
    // MARK: the source scan

    /// The 26 pt leading title (`ScreenHeaderTitle`) is drawn by `ScreenHeader` and, outside it, only by the onboarding steps
    /// and the gate sheets, which are flows, not pages (D4 rule 7).
    nonisolated static let bigTitleFiles: Set = [
        "Ryft/Design/ScreenHeader.swift", "Ryft/Features/Onboarding/OnboardingSteps.swift",
        "Ryft/Features/Onboarding/HealthPermissionView.swift", "Ryft/Features/Auth/AccountHintSheet.swift",
    ]

    /// `ScreenHeader(title:)`, the titled header, belongs to the tab roots (and its own previews and the Debug catalog that
    /// show them).
    nonisolated static let titledHeaderFiles: Set = [
        "Ryft/Design/ScreenHeader.swift", "Ryft/Features/Strain/StrainView.swift", "Ryft/Features/Insights/InsightsView.swift",
        "Ryft/Features/Profile/ProfileView.swift", "Ryft/Features/Profile/NocturneStructuresCatalog.swift",
    ]

    /// The repository, symlinks resolved (the enumerator hands back resolved paths).
    private static var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
    }

    /// Every Swift file of the app, the widget and the shared folder, as repository paths, with its text.
    private static func sources() throws -> [(path: String, text: String)] {
        var found: [(String, String)] = []
        for folder in ["Ryft", "RyftWidgets", "Shared"] {
            guard let walker = FileManager.default.enumerator(at: root.appendingPathComponent(folder),
                                                              includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension == "swift" {
                let path = file.resolvingSymlinksInPath().path
                guard path.hasPrefix(root.path + "/") else { continue }
                found.append((String(path.dropFirst(root.path.count + 1)), try String(contentsOf: file, encoding: .utf8)))
            }
        }
        return found.sorted { $0.0 < $1.0 }
    }

    /// The lines of `text` whose code matches `pattern`, as "path:line: text": `//` comments don't count
    /// (`NocturneGateComponentsTests.code`, line for line), so a note on what a header was may stay.
    private static func hits(_ path: String, _ text: String, _ pattern: Regex<AnyRegexOutput>) -> [String] {
        NocturneGateComponentsTests.code(text).split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            .compactMap { index, line in
                line.firstMatch(of: pattern) == nil ? nil : "\(path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces))"
            }
    }

    @Test("The scan reads code: SubpageHeader in a `//` or `///` comment passes, in code it fails")
    func theScanSkipsComments() throws {
        let retired = try Regex(#"\bSubpageHeader\b"#)
        let text = "/// Was `SubpageHeader` (deleted by the gate).\nlet a = 1 // SubpageHeader\nSubpageHeader(title: t)\n"
        #expect(Self.hits("X.swift", text, retired) == ["X.swift:3: SubpageHeader(title: t)"])
    }

    /// SubpageHeader is gone; `ScreenHeaderTitle` and `ScreenHeader(title:)` stay where they belong.
    @Test("No page outside the tab roots draws the 26 pt leading title")
    func noLeadingTitleOutsideTheTabRoots() throws {
        let files = try Self.sources()
        #expect(files.count > 100, "the scan reads the sources: \(files.count) files")
        let retired = try Regex(#"\bSubpageHeader\b"#)
        let named = files.flatMap { Self.hits($0.path, $0.text, retired) }
        #expect(named.isEmpty, "SubpageHeader (the 26 pt leading title) is named again:\n\(named.joined(separator: "\n"))")
        let bigTitle = try Regex(#"\bScreenHeaderTitle\("#)
        let titles = files.filter { !Self.bigTitleFiles.contains($0.path) }.flatMap { Self.hits($0.path, $0.text, bigTitle) }
        #expect(titles.isEmpty, "a 26 pt leading title outside ScreenHeader and the flows:\n\(titles.joined(separator: "\n"))")
        let titled = try Regex(#"\bScreenHeader\(title:"#)
        let headers = files.filter { !Self.titledHeaderFiles.contains($0.path) }.flatMap { Self.hits($0.path, $0.text, titled) }
        #expect(headers.isEmpty, "a titled tab header outside the tab roots:\n\(headers.joined(separator: "\n"))")
        // The lists can't outlive their files: each still exists and still draws what it is allowed to.
        for (path, pattern) in Self.bigTitleFiles.map({ ($0, bigTitle) }) + Self.titledHeaderFiles.map({ ($0, titled) }) {
            let text = files.first { $0.path == path }?.text
            #expect(text.map { !Self.hits(path, $0, pattern).isEmpty } == true, "\(path): gone or no longer needs its entry")
        }
    }

    // MARK: in a window

    /// A page's header elements by identifier, or its title by label.
    private func node(_ w: HostedWindow, id: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == id }, "'\(id)' in \(w.nodes().map { $0.identifier ?? $0.label })")
    }

    private func node(_ w: HostedWindow, _ label: String) throws -> HostedWindow.Node {
        try #require(w.node(label, exactly: true), "'\(label)' in \(w.nodes().map(\.label))")
    }

    /// The type sizes the checks run at: the default and AX3.
    nonisolated static let sizes = [false, true]

    private func run(_ ax: Bool, height: CGFloat = 844, _ view: some View, body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: 390, height: height, bottomInset: 34, typeSize: ax ? .accessibility3 : .large,
                                   category: ax ? .accessibilityExtraLarge : .large, view, body: body)
    }

    /// The circle's edge on the inset: its 44 pt box reaches 2 past it.
    private static let leadingBox: CGFloat = SubpageSpec.sidePadding - ScreenHeaderSpec.buttonOverhang
    private static let trailingBox: CGFloat = 390 - leadingBox

    @Test("A C sheet (Sleep need): Close leading, the title centred and read first, the header pinned while the page scrolls",
          arguments: Self.sizes)
    func sheetRoot(_ ax: Bool) async throws {
        let screen = SleepNeedShotScreen("sleep-need")
        // Short enough that the page scrolls at the default size too.
        try await run(ax, height: 560, screen.view) { w in
            try await w.wait("the sheet's page") { w.nodes().contains { $0.identifier == "sleepNeed.changeBaseline" } }
            try await w.settle()
            let close = try node(w, id: "subpage.close"), title = try node(w, "Sleep need")
            #expect(close.label == "Close" && close.traits.contains(.button) && close.frame.width >= 44, "\(close.frame)")
            #expect(abs(close.frame.minX - Self.leadingBox) < 1, "Close leads: \(close.frame)")
            // The page's top edge: the sheet's, here the window's safe area.
            let top = w.host.view.safeAreaInsets.top
            #expect(abs(close.frame.minY - top - (SubpageSpec.sheetTopInset - ScreenHeaderSpec.buttonOverhang)) < 1,
                    "26 below the sheet's top edge: \(close.frame), top \(top)")
            #expect(title.traits.contains(.header))
            #expect(abs(title.frame.midX - 195) < 1 && abs(title.frame.midY - close.frame.midY) < 1.5,
                    "the title centred on Close's row: \(title.frame) \(close.frame)")
            #expect(!w.nodes().contains { $0.identifier == "subpage.back" }, "a sheet's root has no Back")
            let order = w.nodes().map(\.label)
            #expect((order.firstIndex(of: "Sleep need") ?? .max) < (order.firstIndex(of: "Close") ?? -1), "\(order)")

            let scroll = try #require(w.pageScrollView(), "the page's scroll view")
            let end = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            #expect(end > 60, "the page scrolls: \(end)")
            let link = try node(w, id: "sleepNeed.changeBaseline")
            let by = min(120, end)
            scroll.setContentOffset(CGPoint(x: 0, y: scroll.contentOffset.y + by), animated: false)
            try await w.settle()
            let moved = try node(w, id: "sleepNeed.changeBaseline"), stays = try node(w, id: "subpage.close")
            #expect(abs((link.frame.minY - moved.frame.minY) - by) < 1, "the content scrolled: \(link.frame) \(moved.frame)")
            let titleNow = try node(w, "Sleep need")
            #expect(abs(stays.frame.minY - close.frame.minY) < 0.5 && abs(titleNow.frame.minY - title.frame.minY) < 0.5,
                    "the header stays put (D4 rule 5): \(stays.frame) \(close.frame)")
            #expect(scroll.convert(scroll.bounds, to: w.window).minY >= close.frame.maxY - ScreenHeaderSpec.buttonOverhang - 0.5,
                    "the page scrolls under the header, not over it")
        }
        await screen.finish()
    }

    @Test("A pushed C page (Devices & sync): Back leading, the title centred; from AX1 under the buttons' row, from the inset",
          arguments: Self.sizes)
    func pushedPage(_ ax: Bool) async throws {
        let g = MockDevicesStates.graph(later: ["oura"])
        let page = NavigationStack { DevicesAndSyncView(model: g.devices) }
            .previewEnvironment(g.state).environment(\.locale, Locale(identifier: "en_US"))
        try await run(ax, page) { w in
            try await w.wait("the page") { w.nodes().contains { $0.identifier == "subpage.header" } }
            try await w.settle()
            let back = try node(w, id: "subpage.back"), title = try node(w, id: "subpage.header")
            #expect(back.label == "Back" && back.traits.contains(.button) && back.frame.width >= 44, "\(back.frame)")
            #expect(title.label == "Devices & sync" && title.traits.contains(.header))
            #expect(abs(back.frame.minX - Self.leadingBox) < 1, "Back leads: \(back.frame)")
            #expect(!w.nodes().contains { $0.identifier == "subpage.close" }, "a pushed page has no Close")
            if ax {
                #expect(title.frame.minY >= back.frame.maxY - ScreenHeaderSpec.buttonOverhang - 0.5,
                        "the title under the buttons' row: \(title.frame) \(back.frame)")
                #expect(abs(title.frame.minX - SubpageSpec.sidePadding) < 1 && title.frame.maxX <= 390 - SubpageSpec.sidePadding + 0.5,
                        "from the inset, inside it: \(title.frame)")
            } else {
                #expect(abs(title.frame.midX - 195) < 1 && abs(title.frame.midY - back.frame.midY) < 1.5,
                        "the title centred on Back's row: \(title.frame) \(back.frame)")
            }
            let order = w.nodes().map(\.label)
            #expect((order.firstIndex(of: "Back") ?? .max) < (order.firstIndex(of: "Devices & sync") ?? -1), "\(order)")
        }
        g.tearDown()
    }

    /// Steps 1 and 6 are the cover's sheet roots (D4): Close leads, and the header stays put while the step scrolls under it,
    /// as `SubpageScaffold`'s sheets do (the part 1 review's nit 3).
    @Test("The import's steps 1 and 6: Close leading, the header pinned while the step scrolls under it",
          arguments: ["1-pick", "6-done"])
    func importSheetRootPinsItsHeader(_ name: String) async throws {
        let id = name.hasPrefix("6") ? "import.close" : "import.cancel"
        // Short enough that both steps scroll at the default size.
        try await run(false, height: 480, ImportNocturneShotsTests.screen(name)) { w in
            try await w.wait("the step") { w.nodes().contains { $0.identifier == id } }
            try await w.settle()
            let close = try node(w, id: id)
            #expect(close.label == "Close" && abs(close.frame.minX - Self.leadingBox) < 1, "Close leads: \(close.frame)")
            #expect(!w.nodes().contains { $0.identifier == "subpage.back" }, "a sheet root has no Back")
            let scroll = try #require(w.pageScrollView(), "the step's scroll view")
            #expect(scroll.convert(scroll.bounds, to: w.window).minY >= close.frame.maxY - ScreenHeaderSpec.buttonOverhang - 0.5,
                    "the step scrolls under the header, not with it: \(scroll.convert(scroll.bounds, to: w.window)) \(close.frame)")
            let end = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            #expect(end > 40, "the step scrolls: \(end)")
            let start = scroll.contentOffset.y, by = min(120, end)
            scroll.setContentOffset(CGPoint(x: 0, y: start + by), animated: false)
            try await w.settle()
            #expect(abs(scroll.contentOffset.y - start - by) < 1, "the step scrolled: \(scroll.contentOffset.y)")
            let stays = try node(w, id: id)
            #expect(abs(stays.frame.minY - close.frame.minY) < 0.5, "the header stays put (D4 rule 5): \(stays.frame) \(close.frame)")
        }
    }

    /// From AX1 Back and Close share the first row and the title goes under it.
    @Test("The import's step 2: Back leading, the title centred, Close trailing", arguments: Self.sizes)
    func importStep(_ ax: Bool) async throws {
        try await run(ax, ImportNocturneShotsTests.screen("2-detected")) { w in
            try await w.wait("step 2") { w.nodes().contains { $0.identifier == "import.cancel" } }
            try await w.settle()
            let back = try node(w, id: "subpage.back"), close = try node(w, id: "import.cancel")
            let title = try node(w, id: "subpage.header")
            #expect(title.label == "Detected" && title.traits.contains(.header))
            #expect(back.label == "Back" && close.label == "Close" && close.frame.width >= 44, "\(close.frame)")
            #expect(abs(back.frame.minX - Self.leadingBox) < 1, "Back leads: \(back.frame)")
            #expect(abs(close.frame.maxX - Self.trailingBox) < 1, "Close trails: \(close.frame)")
            #expect(abs(back.frame.midY - close.frame.midY) < 1, "one row: \(back.frame) \(close.frame)")
            if ax {
                #expect(title.frame.minY >= back.frame.maxY - ScreenHeaderSpec.buttonOverhang - 0.5,
                        "the title under the buttons' row: \(title.frame) \(back.frame)")
                #expect(abs(title.frame.minX - SubpageSpec.sidePadding) < 1, "from the inset: \(title.frame)")
            } else {
                #expect(abs(title.frame.midX - 195) < 1 && abs(title.frame.midY - back.frame.midY) < 1.5,
                        "the title centred between Back and Close: \(title.frame)")
            }
            let order = w.nodes().map(\.label)
            let at = { (label: String) in order.firstIndex(of: label) ?? .max }
            #expect(at("Back") < at("Close"), "\(order)")
            #expect(ax ? at("Close") < at("Detected") : at("Detected") < at("Close"), "\(order)")
        }
    }
}
