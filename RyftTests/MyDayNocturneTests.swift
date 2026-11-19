import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T6B.6, My Day in Nocturne (docs/work/2026-11-16-nocturne/design-pr6-b-train.md §9, S6, S11, §14.2): the row's mapping from a
/// `MyDayItem`, the S6 extensions of `ActivityListRow` (badges, the state mark, the dashed variant, the card style), the card and
/// the full screen as VoiceOver and the eye find them. Hosted reads go through the accessibility tree (`HostedWindow`); colours
/// through `ControlRender`.
@MainActor
@Suite("T6B.6: My Day in Nocturne", .serialized)
struct MyDayNocturneTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA

    private static let width: CGFloat = 390
    private static let english = Locale(identifier: "en_US")

    // MARK: numbers

    @Test("The card's and the screen's numbers are the spec's (§9.1, §9.2)")
    func layoutNumbers() {
        #expect(MyDayLayout.headerHeight == 40)
        #expect(MyDayLayout.showAllHeight == GroupedListSpec.rowMinHeight)
        #expect(MyDayLayout.placeholderRows == 3)
        #expect(MyDayLayout.stripGap == 8 && MyDayLayout.summaryGap == 18 && MyDayLayout.rowsGap == 12)
        #expect(MyDayLayout.rowSpacing == 8)
        #expect(MyDayLayout.pinnedFade == 24 && MyDayLayout.pinnedBottom == 16 && MyDayLayout.pinnedSides == 20)
        #expect(ActivityListRowSpec.cardVerticalPadding == 12 && ActivityListRowSpec.badgedVerticalPadding == 12)
        #expect(ActivityListRowSpec.dashedOutlineOpacity == 0.12 && ActivityListRowSpec.outlineDash == 4)
        #expect(SourceBadgeSpec.minHeight == 22 && SourceBadgeSpec.horizontalPadding == 8 && SourceBadgeSpec.outlineOpacity == 0.12)
    }

    // MARK: the row's content (S6)

    private var gallery: [MyDayItem] { MockMyDay.gallery }

    @Test("The night: its time asleep with \"h\", the violet glyph, its source as a badge, no mark")
    func nightContent() throws {
        let night = try #require(gallery.first { $0.kind.isSleep })
        let content = MyDayRow.content(night, locale: Self.english)
        #expect(content.value == Fmt.clock(minutes: Int((night.duration / 60).rounded())))
        #expect(content.valueUnit == "h")
        #expect(content.glyphInk == .sleep)
        #expect(content.badges == night.sources.map(\.title))
        #expect(content.mark == nil, "a night has no strain mark")
        #expect(content.showsValue)
        #expect(content.spoken == MyDayRow.spoken(night, locale: Self.english), "the pinned sentence")
    }

    @Test("A merged, scored run: both sources as badges and the strain as its mark, no value of its own")
    func mergedRunContent() throws {
        let run = try #require(gallery.first { $0.isMerged })
        let content = MyDayRow.content(run, locale: Self.english)
        #expect(content.badges.count == 2, "\(content.badges)")
        #expect(content.badges.contains("RYFT"))
        guard case .scored = content.mark else {
            Issue.record("a scored run's mark: \(String(describing: content.mark))")
            return
        }
        #expect(content.value == nil)
        #expect(content.glyphInk == .primary)
        #expect(content.spoken.contains("Sources: ") && content.spoken.hasSuffix("merged"), "\(content.spoken)")
    }

    @Test("Uploading and not uploaded rows carry their state marks; the failed one speaks \"Not uploaded\"")
    func uploadMarks() throws {
        let pending = try #require(gallery.first { if case .pending? = $0.upload { return true } else { return false } })
        guard case .uploading = MyDayRow.content(pending).mark else {
            Issue.record("uploading: \(String(describing: MyDayRow.content(pending).mark))")
            return
        }
        let failed = try #require(gallery.first(where: MockMyDay.failed))
        let content = MyDayRow.content(failed, locale: Self.english)
        #expect(content.mark?.isFailed == true)
        #expect(content.spoken.contains("Not uploaded"), "\(content.spoken)")
    }

    @Test("The missing night is the dashed row's content: the filled bed, no meta, no value, no badges")
    func missingNightContent() throws {
        let missing = try #require(gallery.first { $0.kind.isMissingSleep })
        let content = MyDayRow.content(missing)
        #expect(content.systemImage == "bed.double.fill")
        #expect(content.meta == nil && content.value == nil && content.badges.isEmpty && content.mark == nil)
        #expect(!content.showsValue)
        #expect(content.spoken == missing.title)
    }

    @Test("A state mark draws the strain, the pending dash, or no number at all")
    func markNumbers() {
        #expect(ActivityStateMark.State.scored(10.6).number == .strain(10.6))
        #expect(ActivityStateMark.State.strainPending.number == .dash)
        #expect(ActivityStateMark.State.uploading(lastStrain: nil).number == nil)
        #expect(ActivityStateMark.State.failed(lastStrain: 7.2).number == .strain(7.2))
        #expect(ActivityStateMark.State.noHeartRate.number == nil)
        #expect(ActivityStateMark.State.scored(10.6).shownWord == nil, "scored is the number alone")
        #expect(ActivityStateMark.State.uploading(lastStrain: nil).shownWord == ActivityStateMark.State.uploading(lastStrain: nil).word)
    }

    // MARK: drawing

    @Test("StrainPill is the bare numeral in ink, never teal, and \"–\" in textTertiary without a strain")
    func strainPillInk() throws {
        let shot = try #require(ControlRender(StrainPill(strain: 10.6).padding(4).background(Theme.background), scale: 4))
        let ground = Tokens.resolve(Theme.background), ink = Tokens.resolve(Theme.textPrimary)
        let teal = Tokens.resolve(Theme.recovery)
        var inked = 0, tealish = 0
        for iy in 0..<shot.height {
            for ix in 0..<shot.width {
                let p = shot.px(ix, iy)
                if p.near(ink, 6) { inked += 1 }
                if p.near(teal, 24) { tealish += 1 }
            }
        }
        #expect(inked > 20, "the numeral's ink")
        #expect(tealish == 0, "no teal: numbers stay ink (L27)")
        // No capsule: the corners are the ground.
        #expect(shot.at(1, 1).near(ground, 2))
        #expect(StrainPill.ink(nil) == Theme.textTertiary && StrainPill.ink(1) == Theme.textPrimary)
    }

    @Test("The dashed row's outline is dashes: ink at 12 % and the ground, many times along its top edge")
    func dashedOutline() throws {
        let row = ActivityListRow(content: .init(systemImage: "bed.double.fill", title: "No sleep recorded", meta: nil, value: nil,
                                                 spoken: "No sleep recorded", showsValue: false), style: .dashed)
        let shot = try #require(ControlRender(row.frame(width: 350).background(Theme.background), scale: 4))
        let ground = Tokens.resolve(Theme.background)
        let edge = shot.row(0.4, xs: 40...310)
        var changes = 0
        var last = edge.first.map { $0.near(ground, 2) } ?? true
        for p in edge.dropFirst() {
            let isGround = p.near(ground, 2)
            if isGround != last { changes += 1 }
            last = isGround
        }
        #expect(changes > 20, "a 4-on-4 dash over 270 pt: \(changes) changes")
        #expect(shot.at(320, 30).near(ground, 2), "no fill: \(Tokens.describe(shot.at(320, 30)))")
    }

    @Test("A source badge is an outline: ink at 12 % at its edge, no fill inside")
    func badgeOutline() throws {
        let badge = SourceBadge(title: "RYFT").padding(10).background(Theme.surface)
        let shot = try #require(ControlRender(badge, scale: 4))
        let surface = Tokens.resolve(Theme.surface)
        let midY = Double(shot.size.height) / 2
        var ink = Tokens.resolve(Theme.textPrimary)
        ink.a = SourceBadgeSpec.outlineOpacity
        let outline = Tokens.over(ink, surface)
        // The capsule's leading edge at mid-height, then inside it before the text: the surface.
        let edge = shot.row(midY, xs: 9...12).contains { $0.near(outline, 4) }
        #expect(edge, "the outline: \(shot.row(midY, xs: 9...12).map(Tokens.describe))")
        #expect(shot.at(13.5, midY).near(surface, 2), "no fill: \(Tokens.describe(shot.at(13.5, midY)))")
        #expect(shot.size.height >= SourceBadgeSpec.minHeight + 20 - 0.5, "at least 22 high: \(shot.size)")
    }

    // MARK: the card (§9.1)

    private func card(_ content: MyDayContent, actions: MyDayActions = .preview) -> some View {
        ScrollView {
            MyDayCardBody(content: content, actions: actions)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 24)
        }
        .background(Theme.background)
        .environment(\.locale, Self.english)
    }

    @Test("The card's title is one header button with the date and the summary; the plus menu is \"Add\"")
    func cardHeader() async throws {
        try await HostedWindow.run(width: Self.width, height: 844, card(MockMyDay.content(.populated))) { w in
            try await w.settle()
            let nodes = w.nodes()
            let title = try #require(nodes.first { $0.identifier == "myday.title" })
            #expect(title.label.hasPrefix("My Day, "), "\(title.label)")
            #expect(title.traits.contains(.header) && title.traits.contains(.button))
            #expect(title.value?.hasPrefix("4 activities") == true, "\(title.value ?? "nil")")
            #expect(title.frame.height >= MyDayLayout.headerHeight - 0.5)
            let add = try #require(nodes.first { $0.identifier == "myday.add" })
            #expect(add.label == "Add")
            #expect(add.frame.width >= 44 && add.frame.height >= 44, "\(add.frame)")
            #expect(nodes.contains { $0.identifier == "myday.showAll" && $0.label == "Show all" })
            #expect(nodes.contains { $0.identifier == "myday.addActivity" && $0.label == "Add activity" })
            // One element per row, the pinned sentence.
            let rows = nodes.filter { $0.identifier?.hasPrefix("myday.row.") == true }
            #expect(rows.count == MockMyDay.content(.populated).cardRows.count, "\(rows.map(\.label))")
        }
    }

    @Test("Nothing today says so; loading is one element over three outline rows")
    func cardEmptyAndLoading() async throws {
        try await HostedWindow.run(width: Self.width, height: 844, card(MockMyDay.content(.nothing))) { w in
            try await w.settle()
            #expect(w.nodes().contains { $0.identifier == "myday.empty" && $0.label == "Nothing logged yet today." })
            #expect(!w.nodes().contains { $0.identifier == "myday.showAll" }, "no Show all without activities")
        }
        try await HostedWindow.run(width: Self.width, height: 844, card(MockMyDay.content(.loading))) { w in
            try await w.settle()
            let loading = try #require(w.nodes().first { $0.identifier == "myday.loading" })
            #expect(loading.label == "Loading My Day")
            #expect(loading.frame.height >= 3 * ActivityListRowSpec.minHeight + 2 * MyDayLayout.placeholderSpacing - 0.5)
        }
    }

    @Test("The stale line's Try again is a 44 pt text button")
    func cardStale() async throws {
        try await HostedWindow.run(width: Self.width, height: 1_000, card(MockMyDay.content(.stale))) { w in
            try await w.settle()
            let retry = try #require(w.nodes().first { $0.identifier == "myday.stale.retry" })
            #expect(retry.label == "Try again" && retry.traits.contains(.button))
            #expect(retry.frame.height >= 44, "\(retry.frame)")
        }
    }

    // MARK: the full screen (§9.2, §14.2)

    private func page(_ content: MyDayContent, daysBack: Int = 0, actions: MyDayActions? = nil) -> some View {
        NavigationStack {
            MyDayPage(content: content, week: MockMyDay.week(daysBack: daysBack), actions: actions ?? MyDayShotFixtures.actions(content))
        }
        .environment(\.locale, Self.english)
    }

    @Test("The missing-night row is a container: \"No sleep recorded\", then the \"Add sleep\" button (44 high, one line)",
          arguments: [false, true])
    func missingNightRow(ax3: Bool) async throws {
        let content = MyDayShotFixtures.missingNight(daysBack: 4)
        try await HostedWindow.run(width: Self.width, height: 1_400, typeSize: ax3 ? .accessibility3 : .large,
                                   category: ax3 ? .accessibilityExtraLarge : .large, page(content, daysBack: 4)) { w in
            try await w.settle()
            let nodes = w.nodes()
            // The words' own element (the smallest one saying them).
            let text = try #require(nodes.filter { $0.label == "No sleep recorded" }.min { $0.frame.width < $1.frame.width })
            let add = try #require(nodes.first { $0.identifier == "myday.addSleep" })
            #expect(add.label == "Add sleep" && add.traits.contains(.button))
            #expect(add.frame.height >= 44, "\(add.frame)")
            #expect(add.frame.width > add.frame.height, "one line, never broken: \(add.frame)")
            if ax3 {
                #expect(add.frame.minY >= text.frame.maxY - 0.5, "under the words at AX3: \(text.frame) \(add.frame)")
            } else {
                #expect(add.frame.minX > text.frame.maxX, "beside the words: \(text.frame) \(add.frame)")
            }
            let index = try #require(nodes.firstIndex { $0.identifier == "myday.addSleep" })
            let textIndex = try #require(nodes.firstIndex { $0.label == "No sleep recorded" && $0.frame == text.frame })
            #expect(textIndex < index, "the words, then the button")
        }
    }

    @Test("The pinned Add activity clears the last row at AX3 (the page scrolls above the fade)")
    func pinnedAddClearsTheLastRow() async throws {
        let content = MockMyDay.content(.full)
        try await HostedWindow.run(width: Self.width, height: 844, typeSize: .accessibility3, category: .accessibilityExtraLarge,
                                   page(content)) { w in
            try await w.settle()
            let scroll = try #require(w.pageScrollView())
            let bottom = scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom
            scroll.setContentOffset(CGPoint(x: 0, y: max(0, bottom)), animated: false)
            try await w.settle()
            let nodes = w.nodes()
            let add = try #require(nodes.first { $0.identifier == "myday.view.addActivity" })
            let rows = nodes.filter { $0.identifier?.hasPrefix("myday.view.row.") == true }
            let last = try #require(rows.max { $0.frame.maxY < $1.frame.maxY })
            #expect(last.frame.maxY <= add.frame.minY - MyDayLayout.pinnedFade + 0.5,
                    "last row \(last.frame), Add activity \(add.frame)")
            #expect(add.frame.height >= 44)
        }
    }

    @Test("The header says the day; the strip's seven days are their own elements; the summary is one")
    func pageReading() async throws {
        let content = MyDayShotFixtures.today
        try await HostedWindow.run(width: Self.width, height: 1_200, page(content)) { w in
            try await w.settle()
            let nodes = w.nodes()
            let header = try #require(nodes.first { $0.identifier == "myday.view.header" })
            #expect(header.label == "My Day" && header.traits.contains(.header))
            #expect(header.value?.hasPrefix("Today, ") == true, "\(header.value ?? "nil")")
            #expect(nodes.filter { $0.identifier?.hasPrefix("datestrip.day.") == true }.count == 7)
            let summary = try #require(nodes.first { $0.identifier == "myday.view.summary" })
            #expect(summary.label.hasPrefix("4 activities") && summary.label.contains("Strain "), "\(summary.label)")
            #expect(nodes.contains { $0.identifier == "myday.add" && $0.label == "Add" })
            #expect(nodes.contains { $0.identifier == "myday.view.back" })
        }
    }

    @Test("A past day's header says its date in full; yesterday's says \"Yesterday\" first")
    func pastDayHeader() async throws {
        for back in [1, 3] {
            let content = MyDayShotFixtures.past(daysBack: back)
            let date = content.day.formatted(Date.FormatStyle(locale: Self.english).weekday(.wide).month(.wide).day())
            try await HostedWindow.run(width: Self.width, height: 1_200, page(content, daysBack: back)) { w in
                try await w.settle()
                let header = try #require(w.nodes().first { $0.identifier == "myday.view.header" })
                #expect(header.value == (back == 1 ? "Yesterday, \(date)" : date), "\(header.value ?? "nil")")
            }
        }
    }

    @Test("Without the 14-day window there is no pinned Add activity")
    func noAddOutsideTheWindow() async throws {
        let content = MockMyDay.content(.pastEmpty)
        try await HostedWindow.run(width: Self.width, height: 844, page(content, daysBack: 3, actions: MyDayActions())) { w in
            try await w.settle()
            #expect(!w.nodes().contains { $0.identifier == "myday.view.addActivity" })
            #expect(w.nodes().contains { $0.identifier == "myday.view.empty" })
        }
    }
}
