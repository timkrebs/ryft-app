// Today's header in Nocturne (docs/work/2026-11-16-nocturne/design.md §P4-1 row 1, §P4-8 rows 1–2): the lock-up leading,
// the launch's hand-off target (§P4-7), and the sync and optional My Day calendar trailing.
import SwiftUI

struct TodayHeader: View {
    @Environment(ScreenModels.self) private var screens
    /// My Day, pushed on Today's stack (as its card does).
    @State private var showsMyDay = false

    var body: some View {
        let myDay = screens.myDay
        let sync = screens.homeSync
        let nextChange = sync.nextStateChange
        ScreenHeader(handOff: true) {
            HStack(spacing: ScreenHeaderSpec.minGap) {
                if myDay.isEnabled {
                    CircleButton(systemImage: "calendar", iconSize: Self.calendarIconSize,
                                 accessibilityLabel: Text("Calendar", comment: "Today's header button that opens My Day (VoiceOver label).")) {
                        myDay.select(myDay.today)
                        showsMyDay = true
                    }
                    .accessibilityHint(Text("Opens My Day", comment: "VoiceOver hint of Today's Calendar button."))
                    .accessibilityIdentifier("today.header.calendar")
                }
                SyncStatusButton(state: sync.state, sources: sync.sources, now: sync.now,
                                 scoresTakingLonger: sync.scoresTakingLonger, enabled: sync.canSync) {
                    await sync.sync(trigger: .homescreenTopRight) == .success
                }
            }
            .task(id: nextChange) { await sync.updateState(at: nextChange) }
        }
        .navigationDestination(isPresented: $showsMyDay) { MyDayView(model: myDay) }
    }

    /// The board's 16 pt glyph (D4-8: the component's stroke).
    nonisolated static let calendarIconSize: CGFloat = 16
}

#Preview("Today header · with My Day, without") {
    DarkPreview {
        NavigationStack {
            VStack(spacing: 24) {
                TodayHeader()
                    .previewEnvironment(.preview(flags: [.todayMyDay: true]))
                TodayHeader()
                    .previewEnvironment()
                Spacer()
            }
            .background(Theme.background)
        }
    }
}
