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

    // MARK: the row's content (S6)

    private var gallery: [MyDayItem] { MockMyDay.gallery }

    @Test("The night: \"7:48\" with \"h\", the violet glyph, \"Apple Health\" as its badge, no mark")
    func nightContent() throws {
        let night = try #require(gallery.first { $0.kind.isSleep })
        let content = MyDayRow.content(night, locale: Self.english)
        // The demo night: 10:50 PM to 7:00 AM, 7 h 48 min asleep, from Apple Health (b-18).
        #expect(content.value == "7:48")
        #expect(content.valueUnit == "h")
        #expect(content.glyphInk == .sleep)
        #expect(content.badges == ["Apple Health"])
        #expect(content.mark == nil, "a night has no strain mark")
        #expect(content.showsValue)
        #expect(content.spoken.hasPrefix("Sleep, "), "\(content.spoken)")
        #expect(content.spoken.contains("7 hours, 48 minutes"), "\(content.spoken)")
        #expect(content.spoken.hasSuffix("Source: Apple Health"), "\(content.spoken)")
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
        // PR 6 ui-validator: Walking's bare "3.1" didn't say what it was; the pending row says "Strain pending".
        #expect(ActivityStateMark.State.scored(10.6).shownWord == "Strain", "scored: the number over what it is")
        #expect(ActivityStateMark.State.strainPending.shownWord == "Strain pending")
        #expect(ActivityStateMark.State.none.shownWord == nil)
        #expect(ActivityStateMark.State.uploading(lastStrain: nil).shownWord == ActivityStateMark.State.uploading(lastStrain: nil).word)
    }

    // MARK: drawing

    @Test("A state mark sits beside the text by default and goes under it from AX1")
    func markGoesUnderFromAX1() throws {
        let content = ActivityListRow.Content(systemImage: "figure.walk", title: "Walk", meta: "12:15", value: nil,
                                              spoken: "Walk, No heart rate", mark: .noHeartRate)
        func shot(_ typeSize: DynamicTypeSize) throws -> ControlRender {
            try #require(ControlRender(ActivityListRow(content: content).frame(width: 350).background(Theme.background)
                .environment(\.dynamicTypeSize, typeSize).environment(\.locale, Self.english), scale: 2))
        }
        let surface = Tokens.resolve(Theme.surface)
        func inkOnTheRight(_ shot: ControlRender) -> CGRect? {
            shot.bounds(xs: 230...330, ys: 4...Double(shot.size.height - 4)) {
                Tokens.luminance($0) > Tokens.luminance(surface) + 0.08
            }
        }
        let regular = try shot(.large), stacked = try shot(.accessibility1)
        #expect(inkOnTheRight(regular) != nil, "\"No heart rate\" at the trailing edge by default")
        #expect(inkOnTheRight(stacked) == nil, "nothing at the trailing edge from AX1: the word is under the text")
        let under = try #require(stacked.bounds(xs: 60...200, ys: 0...Double(stacked.size.height)) {
            Tokens.luminance($0) > Tokens.luminance(surface) + 0.08
        })
        #expect(under.maxY > stacked.size.height * 0.6, "ink in the lower part of the taller row: \(under), \(stacked.size)")
        #expect(stacked.size.height > regular.size.height)
    }

    @Test("A scored row draws \"Strain\" under its number: the trailing ink runs lower than the number alone's")
    func scoredRowSaysStrain() throws {
        let surface = Tokens.resolve(Theme.surface)
        func trailingInk(_ content: ActivityListRow.Content) throws -> CGRect {
            let shot = try #require(ControlRender(ActivityListRow(content: content).frame(width: 350).background(Theme.background)
                .environment(\.locale, Self.english), scale: 2))
            return try #require(shot.bounds(xs: 240...346, ys: 0...Double(shot.size.height)) {
                Tokens.luminance($0) > Tokens.luminance(surface) + 0.08
            })
        }
        let scored = try trailingInk(.init(systemImage: "figure.walk", title: "Walking", meta: "12:15–12:50", value: nil,
                                           spoken: "Walking, Strain 3.1", mark: .scored(3.1)))
        let bare = try trailingInk(.init(systemImage: "figure.walk", title: "Walking", meta: "12:15–12:50", value: "3.1",
                                         spoken: "Walking, Strain 3.1"))
        #expect(scored.height > bare.height + 8, "the number and \"Strain\" under it: \(scored) vs the number alone \(bare)")
    }

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

    @Test("The stale line's Try again is a 44 pt text button, beside the words by default and under them from AX1",
          arguments: [false, true])
    func cardStale(ax3: Bool) async throws {
        try await HostedWindow.run(width: Self.width, height: 1_800, typeSize: ax3 ? .accessibility3 : .large,
                                   category: ax3 ? .accessibilityExtraLarge : .large, card(MockMyDay.content(.stale))) { w in
            try await w.settle()
            let nodes = w.nodes()
            let retry = try #require(nodes.first { $0.identifier == "myday.stale.retry" })
            let words = try #require(nodes.first { $0.label.hasPrefix("Showing the list from") })
            #expect(retry.label == "Try again" && retry.traits.contains(.button))
            #expect(retry.frame.height >= 44, "\(retry.frame)")
            if ax3 {
                #expect(retry.frame.minY >= words.frame.maxY - 0.5, "under the words: \(words.frame) \(retry.frame)")
            } else {
                #expect(retry.frame.minX > words.frame.maxX, "beside the words: \(words.frame) \(retry.frame)")
            }
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
            // The rows are a LazyVStack: the height of those below the fold is an estimate until they're drawn, so scroll
            // to the end until the content's height holds.
            var height: CGFloat = -1
            for _ in 0..<5 where scroll.contentSize.height != height {
                height = scroll.contentSize.height
                let bottom = height - scroll.bounds.height + scroll.adjustedContentInset.bottom
                scroll.setContentOffset(CGPoint(x: 0, y: max(0, bottom)), animated: false)
                try await w.settle()
            }
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

    @Test("The 14-day rule: Add activity is pinned 13 days back, absent 20 days back (the live screen's own actions)")
    func addActivityOnlyInTheWindow() async throws {
        for (back, offered) in [(13, true), (20, false)] {
            let view = MyDayLiveHost(daysBack: back)
                .previewEnvironment(AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true]))
                .environment(\.locale, Self.english)
            let date = DayFormat.shift(MockMyDay.today, days: -back)
                .formatted(Date.FormatStyle(locale: Self.english).weekday(.wide).month(.wide).day())
            try await HostedWindow.run(width: Self.width, height: 844, view) { w in
                try await w.wait("the day \(back) back") {
                    w.nodes().first { $0.identifier == "myday.view.header" }?.value == date
                }
                try await w.settle()
                #expect(w.nodes().contains { $0.identifier == "myday.view.addActivity" } == offered, "\(back) days back")
            }
        }
    }

    // MARK: offline (the user's rule: never the outlines for good)

    private static var offlineContent: MyDayContent {
        MyDayContent(day: MockMyDay.today, isToday: true, phase: .offline, items: [])
    }

    @Test("Offline with nothing saved, the card and the screen say so with Try again, no outline rows")
    func offlineMessage() async throws {
        let views: [(String, AnyView)] = [("card", AnyView(card(Self.offlineContent))),
                                          ("screen", AnyView(page(Self.offlineContent)))]
        for (name, view) in views {
            try await HostedWindow.run(width: Self.width, height: 844, view) { w in
                try await w.settle()
                let nodes = w.nodes()
                #expect(nodes.contains { $0.label == "My Day appears once you're online." }, "\(name): \(nodes.map(\.label))")
                let retry = try #require(nodes.first { $0.identifier == "myday.offline.retry" }, "\(name)")
                #expect(retry.label == "Try again" && retry.frame.height >= 44)
                #expect(!nodes.contains { $0.identifier == "myday.loading" }, "\(name): no outline rows")
            }
        }
    }

    // MARK: Retry on a failed row (R4)

    @MainActor
    private final class Taps {
        var opened: [String] = []
        var retried: [String] = []
    }

    @Test("A failed row's Retry is a VoiceOver action on the row's button: it retries the upload and opens nothing",
          arguments: ["card", "screen"])
    func rowRetry(_ place: String) async throws {
        let content = MockMyDay.content(.full)
        let failed = try #require(content.cardRows.first(where: MockMyDay.failed))
        let other = try #require(content.cardRows.first { !MockMyDay.failed($0) && $0.opensDetail })
        let taps = Taps()
        let actions = MyDayActions(open: { taps.opened.append($0.id) }, retryRow: { taps.retried.append($0.id) })
        let prefix = place == "card" ? "myday.row." : "myday.view.row."
        let view = place == "card" ? AnyView(card(content, actions: actions)) : AnyView(page(content, actions: actions))
        try await HostedWindow.run(width: Self.width, height: 2_400, view) { w in
            try await w.settle()
            let nodes = w.nodes()
            let row = try #require(nodes.first { $0.identifier == prefix + failed.id }, "\(nodes.compactMap(\.identifier))")
            #expect(row.actionNames.filter { $0 == "Retry" }.count == 1, "\(row.actionNames)")
            #expect(row.traits.contains(.button))
            #expect(row.perform(action: "Retry"))
            #expect(taps.retried == [failed.id])
            #expect(taps.opened.isEmpty, "Retry doesn't open the detail")
            let plain = try #require(nodes.first { $0.identifier == prefix + other.id })
            #expect(!plain.actionNames.contains("Retry"), "only a failed row offers Retry")
        }
    }

    @Test("Without the uploader wired (previews) a failed row offers no Retry")
    func noRetryWithoutTheUploader() async throws {
        let content = MockMyDay.content(.full)
        let failed = try #require(content.cardRows.first(where: MockMyDay.failed))
        try await HostedWindow.run(width: Self.width, height: 2_400, card(content, actions: MyDayActions())) { w in
            try await w.settle()
            let row = try #require(w.nodes().first { $0.identifier == "myday.row." + failed.id })
            #expect(!row.actionNames.contains("Retry"))
        }
    }

    // MARK: the missing night on a narrow screen

    @Test("At 320 pt and xxxLarge \"No sleep recorded\" never breaks inside a word: Add sleep goes under it")
    func missingNightNarrow() async throws {
        let word = try #require(ControlRender(Text(verbatim: "recorded").font(.ryft(.callout)).fixedSize()
            .environment(\.dynamicTypeSize, .xxxLarge), scale: 2))
        let content = MyDayShotFixtures.missingNight(daysBack: 4)
        try await HostedWindow.run(width: 320, height: 1_400, typeSize: .xxxLarge, category: .extraExtraExtraLarge,
                                   page(content, daysBack: 4)) { w in
            try await w.settle()
            let nodes = w.nodes()
            let text = try #require(nodes.filter { $0.label == "No sleep recorded" }.min { $0.frame.width < $1.frame.width })
            let add = try #require(nodes.first { $0.identifier == "myday.addSleep" })
            #expect(text.frame.width >= word.size.width - 0.5, "wider than its longest word: \(text.frame) vs \(word.size)")
            #expect(add.frame.minY >= text.frame.maxY - 0.5, "Add sleep under the words: \(text.frame) \(add.frame)")
            #expect(add.frame.width > add.frame.height && add.frame.height >= 44, "one line, 44 high: \(add.frame)")
        }
    }
}

/// The live full screen on the preview environment's model, `daysBack` before today: the 14-day rule as the screen applies it.
private struct MyDayLiveHost: View {
    let daysBack: Int
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NavigationStack {
            MyDayView(model: screens.myDay)
                .onAppear { screens.myDay.select(DayFormat.shift(screens.myDay.today, days: -daysBack)) }
        }
    }
}
