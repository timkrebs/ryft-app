import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T6B.0's primitives for PR 6 B (docs/work/2026-11-16-nocturne/design-pr6-b-train.md §2): the pushed header of B's pages,
/// the search field of its sheets, the icon disc's filled style and the activity row's two options. Numbers first, then the
/// accessibility tree in a real window (`HostedWindow`).
@MainActor
@Suite("Nocturne train primitives: specs and decisions")
struct NocturneTrainPrimitivesTests {
    @Test("The pushed header's subtitle sits 2 under the title; its empty slot is a circle button's 44 pt box")
    func pushedHeaderNumbers() {
        #expect(PushedHeaderSpec.subtitleGap == 2)
        #expect(CircleButton.hitSize == 44 && ScreenHeaderSpec.buttonOverhang == 2)
    }

    @Test("The search field is a capsule at least 46 high, 16 in, a 15 pt glyph 10 before the text")
    func searchFieldNumbers() {
        #expect(SearchFieldSpec.minHeight == 46 && SearchFieldSpec.leadingPadding == 16)
        #expect(SearchFieldSpec.spacing == 10 && SearchFieldSpec.glyphSize == 15)
    }

    @Test("A filled disc draws its glyph in background on ink; the outline disc in ink")
    func discInks() {
        #expect(IconDisc.glyphInk(.filled) == Theme.background)
        #expect(IconDisc.glyphInk(.outline) == Theme.textPrimary)
    }

    @Test("The row's new options are off for every existing caller")
    func rowDefaults() {
        let row = ActivityListRow.Content(systemImage: "figure.run", title: "Run", meta: nil, value: "9.8", spoken: "Run")
        #expect(!row.filledDisc && row.valueCaption == nil && row.showsValue)
    }
}

@MainActor
@Suite("Nocturne train primitives: VoiceOver and layout", .serialized)
struct NocturneTrainPrimitivesHostedTests {
    private func host<V: View>(_ view: V, typeSize: DynamicTypeSize = .large, category: UIContentSizeCategory = .large,
                               _ body: (HostedWindow) async throws -> Void) async throws {
        let content = view.padding(.horizontal, Theme.Metrics.screenPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Theme.background)
        try await HostedWindow.run(width: 390, height: 600, bottomInset: 0, typeSize: typeSize, category: category, content,
                                   body: body)
    }

    private func node(_ w: HostedWindow, _ label: String) throws -> HostedWindow.Node {
        try #require(w.node(label, exactly: true), "'\(label)' in \(w.nodes().map(\.label))")
    }

    @Test("Pushed header: Back, then the title as a header with the subtitle as its value, then the trailing circle")
    func pushedHeaderOrder() async throws {
        let header = PushedHeader(Text(verbatim: "My Day"), subtitle: Text(verbatim: "Today · Wed, Nov 18")) {
            CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add")) {}
        }
        try await host(header.padding(.top, 20)) { w in
            try await w.settle()
            let back = try node(w, "Back"), title = try node(w, "My Day"), add = try node(w, "Add")
            #expect(title.traits.contains(.header) && title.value == "Today · Wed, Nov 18")
            #expect(back.frame.width >= 44 && back.frame.height >= 44 && add.frame.width >= 44)
            #expect(abs(title.frame.midX - 195) < 1, "centred between the edges: \(title.frame)")
            #expect(abs(back.frame.minX - (20 - ScreenHeaderSpec.buttonOverhang)) < 1, "the circle's edge on the inset")
            let order = w.nodes().map(\.label)
            let b = try #require(order.firstIndex(of: "Back")), t = try #require(order.firstIndex(of: "My Day"))
            let a = try #require(order.firstIndex(of: "Add"))
            #expect(b < t && t < a, "\(order)")
        }
    }

    @Test("Pushed header: without a trailing circle the title stays centred; a spoken subtitle replaces the drawn one")
    func pushedHeaderEmptySlot() async throws {
        let header = PushedHeader(Text(verbatim: "Upper A"), subtitle: Text(verbatim: "Fri, Nov 13 · 55 min"),
                                  spokenSubtitle: Text(verbatim: "Friday 13 November, 55 minutes"))
        try await host(header.padding(.top, 20)) { w in
            try await w.settle()
            let title = try node(w, "Upper A")
            #expect(abs(title.frame.midX - 195) < 1, "\(title.frame)")
            #expect(title.value == "Friday 13 November, 55 minutes")
            #expect(w.nodes().map(\.label) == ["Back", "Upper A"], "the empty slot is hidden")
        }
    }

    @Test("Pushed header at AX3: a long title wraps between the buttons, whole")
    func pushedHeaderAX3() async throws {
        let header = PushedHeader(Text(verbatim: "Upper/Lower 4× (copy)"), subtitle: Text(verbatim: "Hypertrophy · 4 days/week"))
        try await host(header.padding(.top, 20), typeSize: .accessibility3, category: .accessibilityExtraLarge) { w in
            try await w.settle()
            let title = try node(w, "Upper/Lower 4× (copy)"), back = try node(w, "Back")
            #expect(title.frame.minX >= back.frame.maxX - 0.5 && title.frame.maxX <= 370 + 0.5, "\(title.frame)")
            #expect(title.frame.height > back.frame.height, "it wrapped instead of being cut: \(title.frame)")
        }
    }

    private struct SearchHost: View {
        @State var text: String

        var body: some View {
            SearchField(text: $text, prompt: Text(verbatim: "Search exercises"), identifier: "search.field")
        }
    }

    /// The window's text fields: UIKit's, outside SwiftUI's accessibility nodes.
    private func textFields(_ w: HostedWindow) -> [UITextField] {
        func walk(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(walk)
        }
        return walk(w.window)
    }

    @Test("Search field: the text field named by its prompt; with text, a 44 pt Clear search that empties it")
    func searchField() async throws {
        try await host(SearchHost(text: "bench").padding(.top, 20)) { w in
            try await w.settle()
            let field = try #require(textFields(w).first, "one text field")
            #expect(field.accessibilityLabel == "Search exercises", "\(field.accessibilityLabel ?? "nil")")
            #expect(field.text == "bench" && field.returnKeyType == .search && field.autocorrectionType == .no)
            let clear = try node(w, "Clear search")
            #expect(clear.frame.width >= 44 && clear.frame.height >= 44)
            clear.activate()
            try await w.settle()
            #expect(w.node("Clear search", exactly: true) == nil, "gone once the field is empty")
            #expect(field.text?.isEmpty ?? true)
        }
    }

    @Test("Activity row: the caption and the filled disc are drawing only; the row is one element with its sentence")
    func rowOptions() async throws {
        let rows = VStack(spacing: 8) {
            ActivityListRow(content: .init(systemImage: "dumbbell.fill", title: "Upper A", meta: "Fri, Nov 13 · 55m",
                                           value: "85.0", spoken: "Upper A, muscular load 85", valueCaption: "load"),
                            accessory: .chevron)
            ActivityListRow(content: .init(systemImage: "checkmark", title: "Upper/Lower 4×", meta: nil, value: nil,
                                           spoken: "Upper/Lower 4×, active", showsValue: false, filledDisc: true))
        }
        try await host(rows.padding(.top, 20)) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == ["Upper A, muscular load 85", "Upper/Lower 4×, active"])
            let row = try node(w, "Upper A, muscular load 85")
            #expect(row.frame.height >= ActivityListRowSpec.minHeight - 0.5)
        }
    }
}
