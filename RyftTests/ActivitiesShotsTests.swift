import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes T6B.7's screens (Add activity, the sport picker, Add sleep, the activity detail) as 3x PNGs, whole pages
/// (`PagedWindowShot`), at the default size and at AX3 when `ACTIVITIES_SHOTS_DIR` is set; otherwise does nothing. For
/// comparing with the approved drafts (`b-19`, `b-20`, `b-21`) before and after a change:
/// `TEST_RUNNER_ACTIVITIES_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/ActivitiesShotsTests test-without-building`
/// (`TEST_RUNNER_ACTIVITIES_SHOTS_ONLY=add-empty,detail-run` draws a subset). Drawn from a real window (`drawHierarchy`);
/// not a golden-file test.
@MainActor
@Suite("T6B.7: Add activity, Add sleep and the activity detail, shots", .serialized)
struct ActivitiesShotsTests {
    /// The screens, each its own test (a test has a minute).
    nonisolated static let screens = ["add-empty", "add-filled", "add-strength", "add-saving", "add-error", "add-recorded",
                                      "sport-picker", "sleep-new", "sleep-edit", "detail-manual", "detail-effort", "detail-run",
                                      "detail-pending", "detail-offline"]

    private static func view(_ name: String) -> AnyView {
        switch name {
        case "add-empty": return AnyView(ActivitiesShotFixtures.add { _ in })
        case "add-filled": return AnyView(ActivitiesShotFixtures.add(ActivitiesShotFixtures.fill))
        case "add-strength": return AnyView(ActivitiesShotFixtures.add { $0.sport = .strength })
        case "add-saving": return AnyView(ActivitiesShotFixtures.saving())
        case "add-error": return AnyView(ActivitiesShotFixtures.failed())
        case "add-recorded": return AnyView(ActivitiesShotFixtures.editRecorded())
        case "sport-picker": return AnyView(ActivitiesShotFixtures.sportPicker())
        case "sleep-new": return AnyView(ActivitiesShotFixtures.sleep(editing: false))
        case "sleep-edit": return AnyView(ActivitiesShotFixtures.sleep(editing: true))
        case "detail-manual": return AnyView(ActivitiesShotFixtures.detail { $0.sport == .mobility })
        case "detail-effort": return AnyView(ActivitiesShotFixtures.detail { $0.sport == .padel })
        case "detail-run": return AnyView(ActivitiesShotFixtures.detail { $0.splits?.isEmpty == false })
        case "detail-pending": return AnyView(ActivitiesShotFixtures.detail { $0.sport == .yoga })
        default: return AnyView(ActivitiesShotFixtures.offlineDetail())
        }
    }

    /// `ACTIVITIES_SHOTS_ONLY`: a comma-separated subset of `screens`.
    @Test(arguments: screens)
    func writeScreen(_ name: String) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["ACTIVITIES_SHOTS_DIR"] else { return }
        if let only = env["ACTIVITIES_SHOTS_ONLY"], !only.split(separator: ",").contains(Substring(name)) { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            let view = Self.view(name)
            try await HostedWindow.run(width: 390, height: 844, typeSize: typeSize, category: category,
                                       view.toggleStyle(.ryft).activitiesShotsWithoutEdgeEffect()
                                           .environment(\.locale, Locale(identifier: "en_US"))) { w in
                try await w.settle()
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
            }
        }
    }
}

private extension View {
    /// iOS 26 blurs what scrolls under a scroll view's top edge: in a paged shot that is the top of every later part.
    @ViewBuilder func activitiesShotsWithoutEdgeEffect() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectHidden(true, for: .all)
        } else {
            self
        }
    }
}

/// The states the shots draw, each on its own preview state (flags on: `today.my_day`, `activities.manual`).
@MainActor
enum ActivitiesShotFixtures {
    static func state(online: Bool = true) -> AppState {
        AppState.preview(online: online, flags: [.todayMyDay: true, .activitiesManual: true])
    }

    /// Add activity on today, `setup` applied to its model.
    static func add(_ setup: (AddActivityModel) -> Void) -> some View {
        let state = state()
        let model = AddActivityModel(env: state.env, day: .now)
        setup(model)
        return AddActivitySheet(model: model).previewEnvironment(state)
    }

    /// The draft's form: Running, 5.2 (the locale's unit), effort 7.
    static func fill(_ model: AddActivityModel) {
        model.sport = .running
        model.distanceText = "5.2"
        model.effort = 7
    }

    /// The form as Save writes it (the busy commit).
    static func saving() -> some View {
        add { model in
            fill(model)
            model.previewSaving()
        }
    }

    /// Save couldn't write: the banner on top with Try again.
    static func failed() -> some View {
        let state = state()
        let model = AddActivityModel(env: state.env, day: .now)
        fill(model)
        return AddActivitySheet(model: model, saveFailed: true).previewEnvironment(state)
    }

    /// Editing the demo's merged run: the sport row locked, the measured times.
    static func editRecorded() -> some View {
        let state = state()
        let run = MockActivitiesSource.demo().first { $0.origin == .recorded } ?? MockActivitiesSource.demo()[0]
        return AddActivitySheet(model: AddActivityModel(env: state.env, editing: run, merged: run.mergedWith != nil))
            .previewEnvironment(state)
    }

    static func sportPicker() -> some View {
        SportPickerHost().previewEnvironment(state())
    }

    /// Add sleep for last night, or editing a night added on this iPhone.
    static func sleep(editing: Bool) -> some View {
        let state = state()
        let model: AddSleepModel
        if editing, let night = Self.addedNight(state) {
            model = AddSleepModel(env: state.env, editing: night)
        } else {
            model = AddSleepModel(env: state.env, day: .now)
        }
        return AddSleepSheet(model: model).previewEnvironment(state)
    }

    /// A night added for yesterday's wake day: 23:10 to 06:50.
    private static func addedNight(_ state: AppState) -> ManualSleepSnapshot? {
        let calendar = Calendar.current
        let wakeDay = DayFormat.shift(calendar.startOfDay(for: .now), days: -1)
        let evening = DayFormat.shift(wakeDay, days: -1)
        guard let bed = calendar.date(bySettingHour: 23, minute: 10, second: 0, of: evening),
              let wake = calendar.date(bySettingHour: 6, minute: 50, second: 0, of: wakeDay) else { return nil }
        return state.env.activities.saveSleep(day: DayFormat.string(from: wakeDay), bed: bed, wake: wake)
    }

    /// The demo platform's activities cached for their days, the one `pick` names opened.
    static func detail(_ pick: (SportActivity) -> Bool) -> some View {
        let state = state()
        let all = MockActivitiesSource.demo()
        for day in Set(all.map { DayFormat.string(from: $0.start) }) {
            state.repository.seed(.activities(all.filter { DayFormat.string(from: $0.start) == day }, day: day))
        }
        let chosen = all.first(where: pick) ?? all[0]
        return NavigationStack { ActivityDetailView(route: ActivityRoute(id: chosen.id, day: chosen.start)) }
            .previewEnvironment(state)
    }

    /// A HIIT session typed in offline: saved on this iPhone, waiting to upload.
    static func offlineDetail() -> some View {
        let state = state(online: false)
        let saved = state.env.activities.save(manual: ActivityDraft(
            sport: .hiit, start: .now.addingTimeInterval(-3_600), end: .now.addingTimeInterval(-1_800), perceivedEffort: 8,
            notes: "Intervals, 8 × 1 min"))
        return NavigationStack {
            ActivityDetailView(route: ActivityRoute(id: saved?.id ?? UUID(), day: saved?.start ?? .now))
        }
        .previewEnvironment(state)
    }
}

/// The sport picker as Add activity pushes it: Cycling chosen, three recent sports.
private struct SportPickerHost: View {
    @State private var sport = Sport.cycling

    var body: some View {
        NavigationStack { SportPicker(selection: $sport, recents: [.cycling, .running, .yoga]) }
    }
}
