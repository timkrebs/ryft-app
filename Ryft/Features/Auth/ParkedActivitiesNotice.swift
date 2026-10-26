import SwiftUI

/// Welcome, signed out: what a session expiry parked on this iPhone (design.md §8.4), activities and nights the
/// platform hasn't confirmed, kept up to 30 days for the same account. One calm line with their count, nothing of
/// their content, and "Delete from this iPhone" with a confirmation (GDPR Art. 17, transparency).
struct ParkedActivitiesNotice: View {
    /// What Welcome mentions: how many (`ActivityStore.parkedCount()`, more than 0), and the day the first of them
    /// goes (`parkedUntil()`; nil: "within 30 days").
    struct Parked: Equatable {
        let count: Int
        let until: Date?
    }

    let parked: Parked
    /// `ActivityStore.purgeParked()`.
    let delete: () -> Void

    @State private var confirms = false

    /// What to mention on Welcome; nil when nothing is parked. Not behind `activities.manual`: only an enabled feature
    /// parks rows, and signed out the flag reads its compiled default.
    static func parkedToMention(in env: AppEnvironment) -> Parked? {
        let count = env.activities.parkedCount()
        guard count > 0 else { return nil }
        // The limit runs from parking, not from now.
        return Parked(count: count, until: env.activities.parkedUntil())
    }

    /// "… Log in by 24 November to send them." (or "within 30 days" without a date).
    static func message(_ parked: Parked) -> String {
        guard let until = parked.until else {
            return String(localized: "\(parked.count) activities or nights you added haven't reached RYFT yet. Log in within 30 days to send them.",
                          comment: "Welcome after a session expiry: how many unsent activities and nights wait on the phone.")
        }
        let date = until.formatted(.dateTime.day().month(.wide))
        return String(localized: "\(parked.count) activities or nights you added haven't reached RYFT yet. Log in by \(date) to send them.",
                      comment: "Welcome after a session expiry: how many unsent activities and nights wait on the phone; the day they're deleted after.")
    }

    var body: some View {
        InlineMessage(message: Self.message(parked), systemImage: "icloud.and.arrow.up", identifier: "welcome.parked",
                      action: (title: String(localized: "Delete from this iPhone",
                                             comment: "Welcome: delete the unsent activities and nights without logging in."),
                               perform: { confirms = true }))
            .confirmationDialog(Text("Delete them from this iPhone?", comment: "Welcome: confirm deleting parked activities and nights."),
                                isPresented: $confirms, titleVisibility: .visible) {
                Button(role: .destructive, action: delete) {
                    Text("Delete", comment: "Confirms deleting an activity or a night the user added.")
                }
                .accessibilityIdentifier("welcome.parked.confirmDelete")
                Button(role: .cancel) {} label: { Text("Keep", comment: "Cancels deleting an activity or a night.") }
            } message: {
                Text("They haven't reached RYFT, so they're gone for good. This can't be undone.",
                     comment: "Welcome: deleting parked activities and nights is final.")
            }
    }
}

extension AppEnvironment {
    /// A preview graph whose store holds a parked run and a parked night of an expired session, `activities.manual`
    /// at its default (off), as Welcome sees it signed out. Previews and the Debug `welcome-parked` screen.
    static func previewWithParkedRows() -> AppEnvironment {
        let env = AppEnvironment.preview()
        let context = env.persistence.context
        let run = LocalActivity(account: "expired", sport: .running, origin: .recorded, start: .now.addingTimeInterval(-7_200),
                                end: .now.addingTimeInterval(-5_400), movingSec: 1_700, localRevision: 1, createdAt: .now)
        run.parkedAt = .now
        context.insert(run)
        let night = LocalManualSleep(day: DayFormat.string(from: .now), account: "expired", bed: .now.addingTimeInterval(-36_000),
                                     wake: .now.addingTimeInterval(-7_800))
        night.parkedAt = .now
        context.insert(night)
        env.persistence.save()
        return env
    }
}

#Preview("Parked notice", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 16) {
            ParkedActivitiesNotice(parked: .init(count: 3, until: nil)) {}
            ParkedActivitiesNotice(parked: .init(count: 1, until: .now.addingTimeInterval(29 * 86_400))) {}
        }
        .padding()
    }
}
