// Today's header in Nocturne (docs/work/2026-11-16-nocturne/design.md §P4-1 row 1, §P4-8 rows 1–2): the lock-up leading,
// the launch's hand-off target (§P4-7), and the calendar trailing, which opens My Day on today. 40 pt high; without My
// Day (`today.my_day` off) the button is absent, not disabled, and the row keeps its height.
import SwiftUI

struct TodayHeader: View {
    @Environment(ScreenModels.self) private var screens
    /// My Day, pushed on Today's stack (as its card does).
    @State private var showsMyDay = false

    var body: some View {
        let myDay = screens.myDay
        ScreenHeader(handOff: true) {
            if myDay.isEnabled {
                CircleButton(systemImage: "calendar", iconSize: Self.calendarIconSize,
                             accessibilityLabel: Text("Calendar", comment: "Today's header button that opens My Day (VoiceOver label).")) {
                    myDay.select(myDay.today)
                    showsMyDay = true
                }
                .accessibilityHint(Text("Opens My Day", comment: "VoiceOver hint of Today's Calendar button."))
                .accessibilityIdentifier("today.header.calendar")
            }
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
