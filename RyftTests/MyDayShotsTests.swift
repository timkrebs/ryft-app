import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes T6B.6's screens (My Day's card on Today and its states, the full screen on today, a past day and a day without a
/// night, every row's state mark) as 3x PNGs, whole pages (`PagedWindowShot`), at the default size and at AX3 when
/// `MYDAY_SHOTS_DIR` is set; otherwise does nothing. For comparing with the approved drafts (`b-17`, `b-18`, `b-26`) before and
/// after a change: `TEST_RUNNER_MYDAY_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/MyDayShotsTests test-without-building`
/// (`TEST_RUNNER_MYDAY_SHOTS_ONLY=card-rows,day-today` draws a subset). Drawn from a real window; not a golden-file test.
@MainActor
@Suite("T6B.6: My Day, shots", .serialized)
struct MyDayShotsTests {
    /// The screens, each its own test (a test has a minute).
    nonisolated static let screens = ["today", "card-rows", "card-full", "card-empty", "card-loading", "card-stale",
                                      "card-missing-night", "card-missing-nothing", "card-failed", "day-today", "day-past",
                                      "day-missing-night", "day-empty", "day-loading", "rows-tile", "rows-card",
                                      "card-offline", "day-offline", "day-missing-night-narrow"]

    /// The screen and its window's height at the default size and at AX3.
    private static func view(_ name: String) -> (AnyView, CGFloat, CGFloat) {
        switch name {
        case "today":
            return (AnyView(TodayView().previewEnvironment(AppState.preview(flags: [.todayMyDay: true], scenario: .watch))),
                    1_900, 2_600)
        case "card-rows": return (card(.populated), 844, 844)
        case "card-full": return (card(.full), 844, 844)
        case "card-empty": return (card(.nothing), 600, 844)
        case "card-loading": return (card(.loading), 600, 844)
        case "card-stale": return (card(.stale), 844, 844)
        case "card-missing-night": return (card(.noSleepRows), 844, 844)
        case "card-missing-nothing": return (card(.noSleepNothing), 600, 844)
        case "card-failed": return (card(.failed), 600, 844)
        case "day-today": return (page(MyDayShotFixtures.today, daysBack: 0), 844, 844)
        case "day-past": return (page(MyDayShotFixtures.past(daysBack: 2), daysBack: 2), 844, 844)
        case "day-missing-night": return (page(MyDayShotFixtures.missingNight(daysBack: 4), daysBack: 4), 844, 844)
        case "day-empty": return (page(MockMyDay.content(.pastEmpty), daysBack: 3), 844, 844)
        case "day-loading": return (page(MockMyDay.content(.loading), daysBack: 0), 844, 844)
        case "rows-tile": return (rows(tile: true), 844, 844)
        case "card-offline": return (card(MyDayShotFixtures.offline), 600, 844)
        case "day-offline": return (page(MyDayShotFixtures.offline, daysBack: 0), 844, 844)
        case "day-missing-night-narrow": return (page(MyDayShotFixtures.missingNight(daysBack: 4), daysBack: 4), 844, 844)
        default: return (rows(tile: false), 844, 844)
        }
    }

    private static func card(_ c: MockMyDay.Case) -> AnyView { card(MockMyDay.content(c)) }

    private static func card(_ content: MyDayContent) -> AnyView {
        AnyView(ScrollView {
            MyDayCardBody(content: content, actions: .preview)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 24)
        }
        .background(Theme.background.ignoresSafeArea()))
    }

    private static func page(_ content: MyDayContent, daysBack: Int) -> AnyView {
        AnyView(NavigationStack {
            MyDayPage(content: content, week: MockMyDay.week(daysBack: daysBack), actions: MyDayShotFixtures.actions(content))
        })
    }

    /// Every row of `MockMyDay.gallery`, on tiles (the full screen) or in a card (Today).
    private static func rows(tile: Bool) -> AnyView {
        let items = MockMyDay.gallery
        let list = VStack(alignment: .leading, spacing: tile ? 8 : 0) {
            ForEach(items) { item in
                MyDayRow(item: item, style: tile ? .tile : .card, showsChevron: tile && item.opensDetail,
                         retry: MockMyDay.failed(item) ? {} : nil, addSleep: item.kind.isMissingSleep ? {} : nil)
            }
        }
        return AnyView(ScrollView {
            Group {
                if tile { list } else { Card { list } }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 24)
        }
        .background(Theme.background.ignoresSafeArea()))
    }

    /// `MYDAY_SHOTS_ONLY`: a comma-separated subset of `screens`.
    @Test(arguments: screens)
    func writeScreen(_ name: String) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["MYDAY_SHOTS_DIR"] else { return }
        if let only = env["MYDAY_SHOTS_ONLY"], !only.split(separator: ",").contains(Substring(name)) { return }
        let (view, height, ax3Height) = Self.view(name)
        // The narrow one: 320 pt at xxxLarge (the review's "No sleep recorded" case) and at AX3.
        let narrow = name.hasSuffix("-narrow")
        let sizes: [(String, DynamicTypeSize, UIContentSizeCategory, CGFloat)] = [
            narrow ? ("default", .xxxLarge, .extraExtraExtraLarge, height) : ("default", .large, .large, height),
            ("ax3", .accessibility3, .accessibilityExtraLarge, ax3Height),
        ]
        for (size, typeSize, category, h) in sizes {
            try await HostedWindow.run(width: narrow ? 320 : 390, height: h, typeSize: typeSize, category: category,
                                       view.toggleStyle(.ryft).myDayShotsWithoutEdgeEffect()
                                           .environment(\.locale, Locale(identifier: "en_US"))) { w in
                if name == "today" {
                    try? await w.wait("My Day's rows", timeout: .seconds(20)) {
                        w.nodes().contains { $0.identifier?.hasPrefix("myday.row.") == true }
                    }
                }
                try await w.settle()
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
            }
        }
    }
}

/// The full screen's days for the shots: today as drawn on `b-18`, a past day, a past day without a night (`b-26`).
@MainActor
enum MyDayShotFixtures {
    static var today: MyDayContent {
        var content = MockMyDay.content(.populated)
        content.dayStrain = MockData.todayScore.strain
        content.title = String(localized: "Today")
        return content
    }

    /// Offline with nothing saved for today.
    static var offline: MyDayContent { MyDayContent(day: MockMyDay.today, isToday: true, phase: .offline, items: []) }

    static func past(daysBack: Int) -> MyDayContent {
        let day = DayFormat.shift(MockMyDay.today, days: -daysBack)
        return MyDayContent(day: day, isToday: false, phase: .ready, items: MockMyDay.items(daysBack: daysBack),
                            dayStrain: strain(day), title: Fmt.dayTitle(day), isYesterday: daysBack == 1)
    }

    static func missingNight(daysBack: Int) -> MyDayContent {
        let day = DayFormat.shift(MockMyDay.today, days: -daysBack)
        return MyDayContent(day: day, isToday: false, phase: .ready, items: MockMyDay.items(daysBack: daysBack, sleep: false),
                            dayStrain: strain(day), title: Fmt.dayTitle(day), isYesterday: daysBack == 1)
    }

    private static func strain(_ day: Date) -> Double? {
        MockData.history.last { $0.day == DayFormat.string(from: day) }?.strain
    }

    /// What the live screen offers on that day: Add activity in the 14-day window, Add sleep where the night is missing.
    static func actions(_ content: MyDayContent) -> MyDayActions {
        MyDayActions(addActivity: {}, addSleep: content.items.contains(where: \.kind.isMissingSleep) ? {} : nil,
                     startStrength: content.isToday ? {} : nil, edit: { _ in }, delete: { _ in })
    }
}

private extension View {
    /// As the app's root sets it; without the scroll edge effect, a paged shot's later parts stay sharp at the top.
    @ViewBuilder func myDayShotsWithoutEdgeEffect() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}
