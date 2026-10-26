import SwiftData
import SwiftUI

/// What a session expiry parked on this iPhone (design.md §8.4): activities and nights the platform hasn't
/// confirmed, kept up to 30 days for the same account. Counted and deleted without an account, so Welcome can say
/// they're there and offer to delete them (GDPR Art. 17, transparency).
@MainActor
protocol ParkedActivities: AnyObject {
    /// Activities and nights parked on this iPhone, whoever's.
    func parkedCount() -> Int
    /// Deletes them with their track data. Returns how many went.
    @discardableResult
    func purgeParked() -> Int
}

/// Stand-in until `ActivityStore.parkedCount()` and `purgeParked()` land (sync-engineer, in parallel): the same on
/// the account's store, in the order `deleteExpiredParked()` uses (chunks, then rows; keys first once A3b seals
/// routes). At the merge, `extension ActivityStore: ParkedActivities {}` and `parkedActivities` returning
/// `activities` replace it.
@MainActor
final class ParkedActivityRows: ParkedActivities {
    private let env: AppEnvironment

    init(env: AppEnvironment) {
        self.env = env
    }

    private var context: ModelContext { env.persistence.context }

    func parkedCount() -> Int {
        let rows = (try? context.fetchCount(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.parkedAt != nil }))) ?? 0
        let nights = (try? context.fetchCount(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.parkedAt != nil }))) ?? 0
        return rows + nights
    }

    @discardableResult
    func purgeParked() -> Int {
        let rows = (try? context.fetch(FetchDescriptor<LocalActivity>(predicate: #Predicate { $0.parkedAt != nil }))) ?? []
        let nights = (try? context.fetch(FetchDescriptor<LocalManualSleep>(predicate: #Predicate { $0.parkedAt != nil }))) ?? []
        guard !rows.isEmpty || !nights.isEmpty else { return 0 }
        for row in rows {
            let id = row.id, owner = row.account
            try? context.delete(model: ActivityTrackChunk.self, where: #Predicate { $0.activityID == id && $0.account == owner })
            context.delete(row)
        }
        for night in nights { context.delete(night) }
        env.persistence.save()
        // Readers read again (nobody reads while signed out, but a sign-in right after must see nothing).
        env.activities.accountChanged()
        return rows.count + nights.count
    }
}

extension AppEnvironment {
    /// What a session expiry parked, for Welcome (`ParkedActivities`).
    var parkedActivities: ParkedActivities { ParkedActivityRows(env: self) }
}

/// Welcome, signed out (behind `activities.manual`): one calm line with the count of parked activities and nights,
/// nothing of their content, and "Delete from this iPhone" with a confirmation.
struct ParkedActivitiesNotice: View {
    let source: ParkedActivities

    @State private var parked: Int
    @State private var confirms = false

    init(source: ParkedActivities) {
        self.source = source
        // Read here, not in `onAppear`: with nothing to show yet the view is empty and never appears.
        _parked = State(initialValue: source.parkedCount())
    }

    private var message: String {
        String(localized: "\(parked) activities or nights you added haven't reached RYFT yet. Log in within 30 days to send them.",
               comment: "Welcome after a session expiry: how many unsent activities and nights wait on the phone.")
    }

    var body: some View {
        Group {
            if parked != 0 {
                InlineMessage(message: message, systemImage: "icloud.and.arrow.up", identifier: "welcome.parked",
                              action: (title: String(localized: "Delete from this iPhone",
                                                     comment: "Welcome: delete the unsent activities and nights without logging in."),
                                       perform: { confirms = true }))
                    .confirmationDialog(Text("Delete them from this iPhone?", comment: "Welcome: confirm deleting parked activities and nights."),
                                        isPresented: $confirms, titleVisibility: .visible) {
                        Button(role: .destructive) {
                            source.purgeParked()
                            parked = source.parkedCount()
                        } label: {
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
    }
}
