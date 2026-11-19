import SwiftUI

/// History's numbers (PR 6 B §7.1, `b-13`), bottom of one element to the top of the next.
enum TrainHistoryLayout {
    /// The header → the first week's title (Plans' 20).
    nonisolated static let headerGap: CGFloat = 20
    /// A week's title → its first row, and between its rows.
    nonisolated static let weekTitleGap: CGFloat = 10, rowSpacing: CGFloat = 8
    /// Between two weeks (the grouped list's 18).
    nonisolated static let weekSpacing = GroupedListSpec.groupSpacing
    /// While the list loads the first time: this many outline rows.
    nonisolated static let placeholderRows = 3
    /// The empty card's glyph and the gap to its sentence.
    nonisolated static let emptyGlyphSize: CGFloat = 16, emptyGlyphGap: CGFloat = 12
    /// Under the last week.
    nonisolated static let bottomPadding: CGFloat = 32
}

/// What History's rows and week headers say (PR 6 B §7.1). Pure, so tests read them without a view.
enum TrainHistoryRows {
    /// A session as Strain's activity row draws it: `dumbbell.fill`, the title ("Workout" without one), "Fri, Nov 13 · 55m ·
    /// 7,500 kg", the muscular load at the right with "load" under it ("–" without one). VoiceOver: "Upper A, Friday, November
    /// 13, 55 minutes, 7,500 kilograms, Muscular load 85".
    static func row(_ s: SessionSummary, locale: Locale = .autoupdatingCurrent) -> ActivityListRow.Content {
        let title = s.title.isEmpty ? String(localized: "Workout") : s.title
        var meta = [s.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))]
        var spoken = [title, s.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))]
        if let min = s.durationMin {
            meta.append(Fmt.duration(minutes: min))
            spoken.append(Fmt.spokenDuration(minutes: min, locale: locale))
        }
        if let v = s.volumeKg {
            meta.append(Fmt.volume(v))
            spoken.append(HistorySpeech.kilograms(v, locale: locale))
        }
        spoken.append(s.muscularTrimp.map { String(localized: "Muscular load \(HistorySpeech.number($0, locale: locale))") }
            ?? String(localized: "No muscular load", comment: "VoiceOver: a History row whose session has no muscular load (yet)."))
        return ActivityListRow.Content(systemImage: "dumbbell.fill", title: title, meta: StrainRows.join(meta),
                                       value: s.muscularTrimp.map { Fmt.load($0) }, spoken: spoken.joined(separator: ", "),
                                       valueCaption: loadCaption)
    }

    /// A failed read with nothing cached.
    static var failureText: String {
        String(localized: "Your workouts couldn't be loaded. Try again when you're online.",
               comment: "History: the platform couldn't be reached and nothing is cached (as the session detail's message).")
    }

    /// The word under a row's load.
    static var loadCaption: String {
        String(localized: "load", comment: "History: under a session's muscular load at the right of its row (\"85.0\" over \"load\").")
    }
}

/// "Offline · as of 14:05" (History, the exercise page): the copy on this phone after a failed read, quiet (`caption`,
/// `textTertiary`, `wifi.slash`). The time is when the copy was fetched, never relative ("14:05", "Yesterday 14:05", "Tue 14:05").
struct TrainOfflineNote: View {
    let fetchedAt: Date?
    var identifier = "train.offline"
    var now: Date = .now

    static func text(fetchedAt: Date?, now: Date) -> String {
        guard let fetchedAt else { return String(localized: "Offline") }
        return String(localized: "Offline · as of \(SyncLine.dataTime(fetchedAt, now: now))",
                      comment: "Train's History and exercise page: offline, showing the copy fetched at this time (\"14:05\", \"Yesterday 14:05\").")
    }

    var body: some View {
        Label {
            Text(verbatim: Self.text(fetchedAt: fetchedAt, now: now))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "wifi.slash")
        }
        .font(.ryft(.caption))
        .monospacedDigit()
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Numbers as VoiceOver should hear them.
enum HistorySpeech {
    /// "7,500 kilograms", "93.3 kilograms".
    static func kilograms(_ kg: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: kg, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1)))
                .locale(locale))
    }

    /// "85", "84.6": no trailing ".0" to read out.
    static func number(_ v: Double, locale: Locale = .autoupdatingCurrent) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }
}

/// Finished sessions by week, with each week's count, volume and muscular load.
struct TrainHistoryView: View {
    @Environment(TrainLibrary.self) private var library

    var body: some View {
        TrainHistoryScreen(model: TrainHistoryViewModel(library: library))
    }
}

/// Wiring; the first model handed in is kept for the screen's lifetime.
private struct TrainHistoryScreen: View {
    @State var model: TrainHistoryViewModel

    var body: some View {
        TrainHistoryPage(model: model)
            .task { await model.load() }
    }
}

/// The pushed page (PR 6 B §7.1, `b-13`): Back, "History" over "25 workouts · last 90 days", then per week its title and
/// totals over the session rows. Loading the first time is three outline rows; none yet (the platform said so) is an outlined
/// card that says where they come from; a failed read with nothing cached is the message with Try again; the copy on this
/// phone after a failed read carries "Offline · as of 14:05". Layout only.
struct TrainHistoryPage: View {
    let model: TrainHistoryViewModel
    @Environment(\.locale) private var locale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PushedHeader(Text("History"), subtitle: model.subtitle.map { Text(verbatim: $0) }, identifierPrefix: "history")
                VStack(alignment: .leading, spacing: TrainHistoryLayout.weekSpacing) {
                    if model.isOffline {
                        TrainOfflineNote(fetchedAt: model.fetchedAt, identifier: "history.offline")
                    }
                    switch model.state {
                    case .loading: placeholders
                    case .empty: empty
                    case .failed: failure
                    case .list: EmptyView()
                    }
                    ForEach(model.weeks) { week($0) }
                }
                .padding(.top, TrainHistoryLayout.headerGap)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, TrainHistoryLayout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
        .refreshable { await model.refresh() }
    }

    private func week(_ week: TrainHistoryViewModel.Week) -> some View {
        VStack(alignment: .leading, spacing: TrainHistoryLayout.weekTitleGap) {
            HistoryWeekHeader(title: week.title(locale: locale), summary: week.summary,
                              spokenSummary: week.spokenSummary(locale: locale))
            VStack(spacing: TrainHistoryLayout.rowSpacing) {
                ForEach(week.sessions) { s in
                    NavigationLink(value: TrainRoute.session(s.id)) {
                        ActivityListRow(content: TrainHistoryRows.row(s, locale: locale), accessory: .chevron)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityHint(Text("Opens the session"))
                    .accessibilityIdentifier("history.row.\(s.id.uuidString)")
                }
            }
        }
    }

    /// The first load with nothing cached: three outline rows; VoiceOver hears it once.
    private var placeholders: some View {
        VStack(spacing: TrainHistoryLayout.rowSpacing) {
            ForEach(0..<TrainHistoryLayout.placeholderRows, id: \.self) { _ in ActivityListRowPlaceholder() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading workouts", comment: "VoiceOver: History's outline rows while the list loads the first time."))
        .accessibilityIdentifier("history.loading")
    }

    /// No session in 90 days, as the platform said: a calm outlined card, the dumbbell and the sentence.
    private var empty: some View {
        PlaceholderRow(height: ActivityListRowSpec.minHeight, radius: ActivityListRowSpec.radius) {
            HStack(alignment: .center, spacing: TrainHistoryLayout.emptyGlyphGap) {
                Image(systemName: "dumbbell")
                    .font(.system(size: TrainHistoryLayout.emptyGlyphSize, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
                Text("No workouts logged yet. Finished sessions appear here.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, ActivityListRowSpec.verticalPadding)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("history.empty")
    }

    /// The read failed and nothing is cached: say so, with Try again (the session detail's words).
    private var failure: some View {
        InlineMessage(message: TrainHistoryRows.failureText, retry: { await model.refresh() }, identifier: "history.failure")
    }
}

/// "Week of Nov 8" (`label`) and "2 sessions · 12.2 t · load 126" (`caption`) at the right, both `textTertiary`; the totals go
/// under the title from AX1. One header element: the title, with the totals as its value.
private struct HistoryWeekHeader: View {
    let title: String
    let summary: String
    let spokenSummary: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: GroupedListSpec.detailGap))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: GroupedListSpec.rowSpacing))
        layout {
            Text(verbatim: title)
                .font(.ryft(.label))
                .fixedSize(horizontal: false, vertical: true)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text(verbatim: summary)
                .font(.ryft(.caption))
                .monospacedDigit()
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityValue(Text(verbatim: spokenSummary))
        .accessibilityAddTraits(.isHeader)
    }
}

enum SetText {
    /// "100 kg × 5", "× 8", "45 s".
    static func short(_ s: SessionSet) -> String {
        if let d = s.durationSec, s.reps == nil { return String(localized: "\(d) s") }
        switch (s.weightKg, s.reps) {
        case let (kg?, r?): return "\(Fmt.kg(kg)) × \(r)"
        case let (nil, r?): return "× \(r)"
        case let (kg?, nil): return Fmt.kg(kg)
        default: return Fmt.placeholder
        }
    }
}

/// Where Train screens navigate inside a tab's NavigationStack.
enum TrainRoute: Hashable {
    case plans
    case plan(UUID)
    case history
    case session(UUID)
    case exercise(UUID)
}

extension View {
    /// Registers every Train destination on the enclosing NavigationStack.
    func trainDestinations() -> some View {
        navigationDestination(for: TrainRoute.self) { route in
            switch route {
            case .plans: PlansView()
            case .plan(let id): PlanDetailView(planID: id)
            case .history: TrainHistoryView()
            case .session(let id): SessionDetailView(sessionID: id)
            case .exercise(let id): ExerciseDetailView(exerciseID: id)
            }
        }
    }
}

// MARK: - previews (dark only)

@MainActor
enum TrainHistoryPreview {
    /// A new account's: the platform has no session, nothing is cached.
    static var emptyLibrary: TrainLibrary {
        TrainLibrary(store: TrainStore(inMemory: true), remote: { MockTrainSource(start: .empty) }, restore: false)
    }
}

#Preview("History") {
    NavigationStack { TrainHistoryView().trainDestinations() }
        .previewEnvironment()
}

#Preview("History · empty") {
    NavigationStack { TrainHistoryView().trainDestinations() }
        .environment(TrainHistoryPreview.emptyLibrary)
        .previewEnvironment()
}

#Preview("History · loading") {
    NavigationStack { TrainHistoryPage(model: TrainHistoryViewModel(library: TrainHistoryPreview.emptyLibrary)) }
        .previewEnvironment()
}

#Preview("History · offline") {
    NavigationStack {
        TrainHistoryPage(model: TrainHistoryViewModel(library: TrainHistoryPreview.emptyLibrary,
                                                      sessions: MockTrain.history.reversed().map(SessionSummary.init),
                                                      fresh: false, fetchedAt: .now.addingTimeInterval(-3 * 3600)))
    }
    .previewEnvironment()
}

#Preview("History · failed") {
    NavigationStack {
        TrainHistoryPage(model: TrainHistoryViewModel(library: TrainHistoryPreview.emptyLibrary, sessions: [], fresh: false))
    }
    .previewEnvironment()
}

#Preview("History · AX3") {
    NavigationStack { TrainHistoryView().trainDestinations() }
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}
