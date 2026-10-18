import SwiftUI
import BackgroundTasks

@main
struct RyftApp: App {
    @StateObject private var settings = Settings.shared
    @StateObject private var sync = SyncService.shared
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Opportunistic refresh when iOS gives us background time (in addition
        // to HealthKit background delivery). Identifier must match Info.plist →
        // BGTaskSchedulerPermittedIdentifiers.
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: nil) { task in
            Self.handleRefresh(task as! BGAppRefreshTask)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(sync)
                .environmentObject(state)
                .task { await bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await sync.syncNow(); await state.refresh() }
            } else if phase == .background {
                Self.scheduleRefresh()
            }
        }
    }

    private func bootstrap() async {
        guard HealthKitManager.isAvailable else { return }
        try? await HealthKitManager.shared.requestAuthorization()
        await HealthKitManager.shared.enableBackgroundDelivery()
        HealthKitManager.shared.startObserving {
            await SyncService.shared.syncNow()
        }
        await sync.syncNow()
        await state.refresh()
    }

    // MARK: background refresh

    static let refreshTaskID = "dev.timkrebs.ryft.refresh"

    static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }

    static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleRefresh()
        let work = Task { await SyncService.shared.syncNow() }
        task.expirationHandler = { work.cancel() }
        Task { await work.value; task.setTaskCompleted(success: true) }
    }
}

struct RootView: View {
    @EnvironmentObject private var settings: Settings

    var body: some View {
        TabView {
            TodayView().tabItem { Label("Today", systemImage: "circle.circle") }
            TrendsView().tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            SettingsView().tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
