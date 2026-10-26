import SwiftUI

/// An activity the user added or RYFT recorded (ui.md §8; A2: without the map and charts, which A4 adds). Header
/// with its sources and, while it isn't at RYFT, what's happening to the upload; the numbers; where its strain comes
/// from; splits; the merge; notes; Edit and Delete for manual and recorded activities on any day.
struct ActivityDetailView: View {
    let route: ActivityRoute
    @Environment(AppState.self) private var state

    var body: some View {
        ActivityDetailScreen(model: ActivityDetailViewModel(route: route, state: state))
    }
}

/// Layout only; the first model handed in is kept for the screen's lifetime.
struct ActivityDetailScreen: View {
    @State var model: ActivityDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(TrainCoordinator.self) private var coordinator
    @State private var editing: AddActivityModel?
    @State private var confirmsDelete = false
    @State private var workout: Workout?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Metrics.sectionSpacing) {
                if model.activity != nil {
                    header
                    if model.suggestsTrain { trainCard }
                    stats
                    strainCard
                    if let splits = model.activity?.splits, !splits.isEmpty {
                        SplitsTable(splits: splits, paceStyle: model.activity?.sport.paceStyle ?? .pace)
                    }
                    if model.isMerged { mergeNote }
                    notes
                    if model.isEditable { footer }
                } else {
                    InlineMessage(message: String(localized: "This activity isn't on this iPhone any more.",
                                                  comment: "Activity detail: deleted meanwhile."),
                                  systemImage: "trash", identifier: "activityDetail.gone")
                        .padding(.top, 24)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(Text(verbatim: model.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if model.isEditable {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { editing = model.editModel() } label: { Label("Edit", systemImage: "pencil") }
                            .accessibilityIdentifier("activityDetail.menu.edit")
                        Button(role: .destructive) { confirmsDelete = true } label: { Label("Delete", systemImage: "trash") }
                            .accessibilityIdentifier("activityDetail.menu.delete")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .accessibilityLabel(Text("More", comment: "VoiceOver: the activity detail's menu (Edit, Delete)."))
                    }
                    .accessibilityIdentifier("activityDetail.menu")
                }
            }
        }
        .sheet(item: $editing) { AddActivitySheet(model: $0) }
        .navigationDestination(item: $workout) { WorkoutDetailView(workout: $0) }
        .confirmationDialog(Text("Delete this activity?"), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(role: .destructive) {
                if model.delete() { dismiss() }
            } label: {
                Text("Delete", comment: "Confirms deleting an activity or a night the user added.")
            }
            .accessibilityIdentifier("activityDetail.confirmDelete")
            Button(role: .cancel) {} label: { Text("Keep", comment: "Cancels deleting an activity or a night.") }
        } message: {
            Text(model.isRecorded
                 ? String(localized: "It's removed from RYFT, including its route, and your strain for the day is recalculated.")
                 : String(localized: "It's removed from RYFT and your strain for the day is recalculated."))
        }
        .accessibilityIdentifier("activityDetail")
    }

    // MARK: header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: model.symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 64, height: 64)
                .background(Theme.accent.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(verbatim: model.title)
                .font(.ryft(.title))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(verbatim: model.when(locale: locale))
                .font(.ryft(.callout))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if let sources = model.item?.sources, !sources.isEmpty {
                SourceBadges(sources: sources, merged: model.isMerged)
                    .fixedSize(horizontal: typeSize.isAccessibilitySize ? false : true, vertical: true)
            }
            if model.isOffline {
                Text("Showing what's saved on this iPhone.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let note = model.uploadNote { uploadMessage(note) }
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activityDetail.header")
    }

    @ViewBuilder
    private func uploadMessage(_ note: ActivityDetailViewModel.UploadNote) -> some View {
        switch note {
        case .uploading:
            InlineMessage(message: String(localized: "Saved on this iPhone. Uploading to RYFT.", comment: "Activity detail: queued or being sent."),
                          systemImage: "icloud.and.arrow.up", identifier: "activityDetail.upload")
        case .offline:
            InlineMessage(message: String(localized: "Saved on this iPhone. It will upload when you're online."),
                          systemImage: "icloud.and.arrow.up", identifier: "activityDetail.upload")
        case .notAvailableYet:
            InlineMessage(message: String(localized: "Saved on this iPhone. Uploading activities to RYFT isn't available yet.",
                                          comment: "Activity detail: the platform doesn't take activities yet; nothing is sent."),
                          systemImage: "icloud.and.arrow.up", identifier: "activityDetail.upload")
        case .gated:
            InlineMessage(message: String(localized: "Saved on this iPhone. It uploads once your account is ready.",
                                          comment: "Activity detail: the invite or consent step isn't done; the upload waits."),
                          systemImage: "icloud.and.arrow.up", identifier: "activityDetail.upload")
        case .retrying:
            InlineMessage(message: String(localized: "Saved on this iPhone. RYFT will try again, or tap Retry.",
                                          comment: "Activity detail: an upload failed and waits to be retried."),
                          systemImage: "icloud.and.arrow.up", retryTitle: "Retry", retry: { await model.retry() },
                          identifier: "activityDetail.upload")
        case .refused(let attempt):
            InlineMessage(message: String(localized: "RYFT couldn't accept this activity. It is still saved on this iPhone."),
                          systemImage: "exclamationmark.circle", retryTitle: "Try again", details: attempt.details,
                          retry: { await model.retry() }, identifier: "activityDetail.upload",
                          action: model.isEditable ? (title: String(localized: "Edit"), perform: { editing = model.editModel() }) : nil)
        case .failed(let attempt):
            InlineMessage(message: String(localized: "Couldn't upload. It is still saved on this iPhone.",
                                          comment: "Activity detail: retries ran out; the activity is still on the phone."),
                          systemImage: "exclamationmark.circle", retryTitle: "Retry", details: attempt.details,
                          retry: { await model.retry() }, identifier: "activityDetail.upload")
        }
    }

    // MARK: numbers

    private var stats: some View {
        let count = typeSize.isAccessibilitySize ? 1 : 3
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(model.stats(locale: locale)) { stat in
                VStack(spacing: 6) {
                    Text(verbatim: stat.title).ryftLabelStyle().lineLimit(1).minimumScaleFactor(0.8)
                    Text(verbatim: stat.value)
                        .font(.ryft(.headline))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("activityDetail.stats")
    }

    /// Where the strain comes from (ui.md §8.1.3, D5–D7).
    private var strainCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Strain").ryftLabelStyle()
                switch model.strainLine {
                case .heartRate(let value, let source):
                    strainValue(value)
                    if let source {
                        line(Text("Heart rate from \(source)"), systemImage: "heart.fill")
                    }
                case .effort(let value, let rating):
                    strainValue(value)
                    line(rating.map {
                        Text("From your effort rating (\($0) of 10). Strain becomes more precise when heart rate arrives.")
                    } ?? Text("From your effort rating. Strain becomes more precise when heart rate arrives.",
                              comment: "Activity detail: strain from perceived effort, the rating unknown."),
                         systemImage: "pencil")
                case .value(let value):
                    strainValue(value)
                case .noHeartRate:
                    line(Text("No heart rate for this time."), systemImage: "minus.circle")
                case .waiting:
                    HStack(spacing: 10) {
                        Circle()
                            .strokeBorder(Theme.textTertiary, lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                        Text("Waiting for heart rate")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("activityDetail.strain")
    }

    private func strainValue(_ value: Double) -> some View {
        Text(verbatim: Fmt.strain(value))
            .font(.ryft(.numberLarge))
            .monospacedDigit()
            .foregroundStyle(Theme.metricStrain)
    }

    private func line(_ text: Text, systemImage: String) -> some View {
        Label {
            text.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.ryft(.callout))
        .foregroundStyle(Theme.textSecondary)
    }

    // MARK: more

    /// D8: a manual Strength activity has no sets; Train logs them.
    private var trainCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label {
                    Text("Strength is best logged in Train. Your sets, reps and load count toward muscular load.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "dumbbell")
                }
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                PrimaryButton(title: "Log this in Train", style: .secondary) { await coordinator.quickStart(.auto) }
                    .accessibilityIdentifier("activityDetail.logInTrain")
            }
        }
    }

    /// D4: merged with a tracker's workout; its heart rate and zones are in that workout's detail.
    private var mergeNote: some View {
        let source = model.mergeSource ?? MyDayAssembler.appleHealth
        return VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Merged from two sources: heart rate from \(source), route and distance from RYFT. RYFT counts this activity once.")
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.ryft(.callout))
            .foregroundStyle(Theme.textSecondary)
            if let w = model.mergedWorkout {
                Button { workout = w } label: {
                    HStack {
                        Label("Heart rate and zones", systemImage: "heart.fill")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(14)
                    .frame(minHeight: 44)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(Text("Opens the workout", comment: "VoiceOver hint: the row opens the workout's detail."))
                .accessibilityIdentifier("activityDetail.mergedWorkout")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activityDetail.merge")
    }

    @ViewBuilder
    private var notes: some View {
        if let text = model.activity?.notes, !text.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes").ryftLabelStyle()
                    Text(verbatim: text)
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("activityDetail.notes")
        } else if model.isEditable {
            Button { editing = model.editModel() } label: {
                Label("Add a note", systemImage: "square.and.pencil")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activityDetail.addNote")
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            PrimaryButton(title: "Edit", style: .secondary) { editing = model.editModel() }
                .accessibilityIdentifier("activityDetail.edit")
            Button(role: .destructive) { confirmsDelete = true } label: {
                Text("Delete")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.alert)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("activityDetail.delete")
        }
    }
}

// MARK: - previews

@MainActor
private enum DetailPreview {
    static let state = AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true])
    static var demo: [SportActivity] { MockActivitiesSource.demo() }

    /// The demo platform's activities cached, plus a manual HIIT on this iPhone (not uploaded yet).
    static func host(_ pick: (([SportActivity]) -> SportActivity?)?, local: Bool = false) -> some View {
        let all = demo
        for day in Set(all.map { DayFormat.string(from: $0.start) }) {
            state.repository.store(activities: all.filter { DayFormat.string(from: $0.start) == day }, day: day)
        }
        var id = pick?(all)?.id ?? UUID()
        var day = pick?(all)?.start ?? .now
        if local, let saved = state.env.activities.save(manual: ActivityDraft(
            sport: .hiit, start: .now.addingTimeInterval(-3_600), end: .now.addingTimeInterval(-1_800), perceivedEffort: 8,
            notes: "Intervals, 8 × 1 min")) {
            id = saved.id
            day = saved.start
        }
        return NavigationStack { ActivityDetailView(route: ActivityRoute(id: id, day: day)) }
    }
}

#Preview("Detail · merged run · dark") {
    DetailPreview.host { $0.first { $0.mergedWith != nil } }.previewEnvironment(DetailPreview.state)
}

#Preview("Detail · merged run · light") {
    DetailPreview.host { $0.first { $0.mergedWith != nil } }.previewEnvironment(DetailPreview.state, scheme: .light)
}

#Preview("Detail · strain pending (yoga)") {
    DetailPreview.host { $0.first { $0.sport == .yoga } }.previewEnvironment(DetailPreview.state)
}

#Preview("Detail · effort strain (padel) · de") {
    DetailPreview.host { $0.first { $0.sport == .padel } }.previewEnvironment(DetailPreview.state)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Detail · on this iPhone (HIIT)") {
    DetailPreview.host(nil, local: true).previewEnvironment(DetailPreview.state)
}

#Preview("Detail · ride · AX3") {
    DetailPreview.host { $0.first { $0.sport == .cycling } }.previewEnvironment(DetailPreview.state)
        .environment(\.dynamicTypeSize, .accessibility3)
}
