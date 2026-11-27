import SwiftUI

/// The summary's numbers (PR 6 B §5.1, `b-09`).
enum SessionSummaryLayout {
    /// The header → the numeral.
    nonisolated static let heroGap: CGFloat = 22
    /// The ruler → the tiles: 26, of which the hero keeps 20 under the ruler (its labels hang into it, `StrainLayout`).
    nonisolated static let tilesGap: CGFloat = 26 - StrainLayout.rulerFollowingGap
    /// Between the tiles, and between the blocks under them (records, the heart-rate line, Apple Health, notes).
    nonisolated static let spacing: CGFloat = 12
    /// The header's height (no buttons) and the title → the subtitle.
    nonisolated static let headerHeight: CGFloat = 40, subtitleGap: CGFloat = 2
    /// The records card: the label → the first record; between the records once they stack (AX sizes).
    nonisolated static let recordsTitleGap: CGFloat = 8, stackedRecordsGap: CGFloat = 12
    /// Under the last block, above the pinned Done.
    nonisolated static let bottomPadding: CGFloat = 24
}

/// What the summary says (PR 6 B §5.1), from the session as `…/complete` answered it, or as it was logged here while that
/// answer is pending. The phone computes no strain: without the platform's answer the numeral is unlit and the ruler has no
/// needle. `…/complete` always returns a strain (the muscular load on the strain scale, heart rate or not), so a session
/// without one is one the platform hasn't scored yet. Pure, so the tests read its states.
struct SessionSummaryContent: Equatable {
    enum StrainState: Equatable {
        /// The platform's strain.
        case scored
        /// No answer yet (offline, queued), or not scored yet.
        case pending
    }

    let title: String
    /// "Workout done · Wed, Nov 18".
    let subtitle: String
    /// "Workout done, Wednesday 18 November" (VoiceOver).
    let spokenSubtitle: String
    let strainState: StrainState
    /// The numeral, its caption and the ruler (`StrainHeroView`): "Strain · of 21 · moderate" when scored.
    let hero: StrainHero
    /// Duration, Volume, Muscular load, Sets.
    let tiles: [WorkoutStat]
    /// "Saved on this phone. Will sync when you're back online."
    let showsWillSync: Bool

    /// - Parameters:
    ///   - session: the platform's answer, else the local document.
    ///   - answered: `…/complete` answered (the session's scores are the platform's).
    ///   - pendingCompletion: the local session waits for `…/complete` (offline).
    init(session: TrainSession?, answered: Bool, pendingCompletion: Bool, locale: Locale = .autoupdatingCurrent) {
        let title = session?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.title = title.isEmpty ? String(localized: "Workout") : title
        let date = session.map { $0.endedAt ?? $0.startedAt }
        let done = String(localized: "Workout done")
        if let date {
            let shown = date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(locale))
            subtitle = String(localized: "Workout done · \(shown)",
                              comment: "The workout summary's subtitle under the session's title: the day it ended (\"Wed, Nov 18\").")
            spokenSubtitle = "\(done), \(date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale)))"
        } else {
            subtitle = done
            spokenSubtitle = done
        }

        let strain = session?.strain
        strainState = strain != nil ? .scored : .pending
        hero = StrainHero(strain: strain, namesStrain: true, missingCaption: Self.missingCaption(strainState), locale: locale)
        tiles = Self.tiles(session, locale: locale)
        showsWillSync = !answered && pendingCompletion
    }

    /// The caption under an unlit numeral.
    static func missingCaption(_ state: StrainState) -> String? {
        switch state {
        case .scored:
            return nil
        case .pending:
            return String(localized: "Strain · arrives once your workout is scored",
                          comment: "Workout summary, under the unlit strain numeral: the platform hasn't scored the session yet.")
        }
    }

    /// Duration, Volume, Muscular load, Sets (strain is the hero). Without the platform's answer the volume is the logged
    /// sets' and the load "–".
    static func tiles(_ session: TrainSession?, locale: Locale = .autoupdatingCurrent) -> [WorkoutStat] {
        let sets = session?.exercises.flatMap(\.sets) ?? []
        var duration = WorkoutStat(id: "duration", label: String(localized: "Duration"), value: Fmt.placeholder)
        if let session, let end = session.endedAt {
            let minutes = StrainFormat.minutes(end.timeIntervalSince(session.startedAt))
            let shown = StrainFormat.duration(minutes: minutes)
            duration = WorkoutStat(id: "duration", label: String(localized: "Duration"), value: shown.value, unit: shown.unit,
                                   spoken: Fmt.spokenDuration(minutes: minutes, locale: locale))
        }
        let volume = volumeParts(session.map { $0.volumeKg ?? Volume.of(sets) }, locale: locale)
        let completed = sets.filter { $0.completedAt != nil }.count
        return [
            duration,
            WorkoutStat(id: "volume", label: String(localized: "Volume"), value: volume.value, unit: volume.unit,
                        spoken: volume.spoken),
            WorkoutStat(id: "load", label: String(localized: "Muscular load"), value: Fmt.load(session?.muscularTrimp, locale: locale)),
            WorkoutStat(id: "sets", label: String(localized: "Sets"), value: session == nil ? Fmt.placeholder : "\(completed)"),
        ]
    }

    /// "7,500" + "kg" ("7,500 kilograms"); "12.4" + "t" from 10 t ("12.4 tonnes"): `Fmt.volume`'s rule, split for the
    /// tile's unit.
    static func volumeParts(_ kg: Double?, locale: Locale = .autoupdatingCurrent) -> (value: String, unit: String?, spoken: String?) {
        guard let kg else { return (Fmt.placeholder, nil, nil) }
        if kg >= 10_000 {
            let tonnes = (kg / 1000).formatted(.number.precision(.fractionLength(1)).locale(locale))
            return (tonnes,
                    String(localized: "summary.volume.tonnes", defaultValue: "t",
                           comment: "Workout summary, the Volume tile: the unit after a volume of 10 tonnes or more (\"12.4 t\")."),
                    String(localized: "summary.volume.tonnesSpoken", defaultValue: "\(tonnes) tonnes",
                           comment: "VoiceOver, the workout summary's Volume tile from 10 tonnes: \"12.4 tonnes\"."))
        }
        let spoken = Measurement(value: kg, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale))
        return (kg.formatted(.number.precision(.fractionLength(0)).locale(locale)), String(localized: "kg"), spoken)
    }
}

/// After Finish (PR 6 B §5.1, `b-09`): the title over "Workout done · Wed, Nov 18", the strain numeral and its ruler, the
/// four tiles, the records, where the heart rate came from, Apple Health's one-time ask, notes, and Done pinned at the
/// bottom. No celebration: one success haptic, nothing moves. VoiceOver starts on the header.
struct SessionSummarySheet: View {
    let summary: FinishSummary

    @Environment(TrainSyncService.self) private var sync
    @Environment(TrainLibrary.self) private var library
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @State private var notes = ""
    @State private var appeared = false
    /// Where the strain's heart rate came from (the platform's workout for the session).
    @State private var heartRate: SummaryHeartRate?
    @State private var sessionRPE: SessionRPEModel?
    @State private var summaryWorkout: Workout?
    @State private var savingToHealth = false
    @AccessibilityFocusState private var headerFocused: Bool
    private var export: WorkoutHealthExport { .shared }

    /// `heartRate`: previews only (the line is looked up once the platform has answered).
    init(summary: FinishSummary, heartRate: SummaryHeartRate? = nil) {
        self.summary = summary
        _heartRate = State(initialValue: heartRate)
    }

    private var session: LocalSession? { sync.store.session(id: summary.sessionID) }

    /// The server's answer: at finish, or later from the queue.
    private var completed: TrainSession? {
        summary.completed ?? sync.lastCompletion.flatMap { $0.id == summary.sessionID ? $0 : nil }
    }

    private var ratingWorkoutID: UUID? {
        guard state.env.recoveryCheckinEnabled else { return nil }
        return completed?.workoutId ?? session?.workoutId
    }

    var body: some View {
        let content = SessionSummaryContent(session: completed ?? session?.wire, answered: completed != nil,
                                            pendingCompletion: session?.pendingCompletion == true, locale: locale)
        let prs = completed?.prs ?? session?.prs ?? []
        ScrollView {
            VStack(spacing: 0) {
                header(content)
                StrainHeroView(hero: content.hero, key: summary.sessionID.uuidString,
                               numeralStyle: state.env.settings.heroNumerals.style, identifierPrefix: "summary")
                    .padding(.top, SessionSummaryLayout.heroGap)
                SummaryTiles(tiles: content.tiles)
                    .padding(.top, SessionSummaryLayout.tilesGap)
                VStack(alignment: .leading, spacing: SessionSummaryLayout.spacing) {
                    if content.showsWillSync {
                        WillSyncNote()
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !prs.isEmpty { records(prs) }
                    if let heartRate {
                        Label(heartRate.text, systemImage: "heart")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("summary.heartRate")
                    }
                    if let sessionRPE, sessionRPE.workoutID == ratingWorkoutID {
                        SessionRPERow(model: sessionRPE)
                    }
                    if export.shouldAsk { saveToHealth }
                    notesCard
                }
                .padding(.top, SessionSummaryLayout.spacing)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.top, SheetHeaderSpec.topInset)
            .padding(.bottom, SessionSummaryLayout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .pinnedBar {
            PillButton(Text("Done"), systemImage: PillButton.Icon.confirm) { done() }
                .accessibilityIdentifier("summary.done")
        }
        .presentationBackground(Theme.background)
        // It can't be swiped away (Done saves the notes), so no grabber promises it.
        .presentationDragIndicator(.hidden)
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            notes = session?.notes ?? ""
            appeared = true
            headerFocused = true
        }
        .task(id: completed?.workoutId) { await loadHeartRate() }
        .onChange(of: ratingWorkoutID, initial: true) { _, id in
            sessionRPE = id.map { SessionRPEModel(env: state.env, workoutID: $0,
                                                  workout: summaryWorkout?.id == $0 ? summaryWorkout : nil,
                                                  repository: state.repository) }
        }
        .interactiveDismissDisabled()
    }

    /// No buttons: the title over "Workout done · Wed, Nov 18", one header element.
    private func header(_ content: SessionSummaryContent) -> some View {
        VStack(spacing: SessionSummaryLayout.subtitleGap) {
            Text(verbatim: content.title)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
            Text(verbatim: content.subtitle)
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: SessionSummaryLayout.headerHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: content.title))
        .accessibilityValue(Text(verbatim: content.spokenSubtitle))
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($headerFocused)
        .accessibilityIdentifier("summary.header")
    }

    private func records(_ prs: [PersonalRecord]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: SessionSummaryLayout.recordsTitleGap) {
                Text("Personal records")
                    .ryftLabelStyle()
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading,
                       spacing: typeSize.isAccessibilitySize ? SessionSummaryLayout.stackedRecordsGap : 0) {
                    ForEach(prs, id: \.self) { pr in
                        PRBadge(record: pr, exerciseName: library.exercise(id: pr.exerciseId)?.name)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary.records")
    }

    /// Once, after the first completed workout: RYFT writes nothing to Apple Health unless asked.
    private var saveToHealth: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save workouts to Apple Health?")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Your strength workouts then appear in Fitness and Health. RYFT writes only the workout, no heart rate. You can change this in Profile.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    PillButton(Text("Save"), size: .compact, busy: savingToHealth) {
                        savingToHealth = true
                        defer { savingToHealth = false }
                        guard await export.turnOn(), let s = session, let end = s.endedAt else { return }
                        await export.save(sessionID: s.id, start: s.startedAt, end: end)
                    }
                    PillButton(Text("Not now"), style: .secondary, size: .compact) { export.turnOff() }
                        .disabled(savingToHealth)
                }
                if export.needsAccess { HealthWriteAccessHint() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("summary.saveToHealth")
    }

    private var notesCard: some View {
        Card {
            TextField(text: $notes, prompt: Text("How did it feel?").foregroundStyle(Theme.textTertiary), axis: .vertical) {
                Text("Notes")
            }
            .font(.ryft(.body))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.textPrimary)
            .lineLimit(1...6)
            .accessibilityLabel(Text("Notes"))
        }
    }

    /// "Heart rate from Garmin Connect" when the platform matched a watch's workout; otherwise how to get heart-rate strain
    /// next time.
    private func loadHeartRate() async {
        guard let id = completed?.workoutId else { return }
        let owner = AccountBinding(state.env)
        guard let detail = try? await state.source.workout(id: id), owner.isCurrent(in: state.env), !Task.isCancelled else { return }
        heartRate = SummaryHeartRate(detail.workout)
        summaryWorkout = detail.workout
        sessionRPE?.seed(from: detail.workout)
    }

    static func heartRateLine(_ workout: Workout) -> String {
        if hasHeartRate(workout) {
            return String(localized: "Heart rate from \(workout.source)")
        }
        // A watch workout may still be on its way (it's matched once it syncs).
        return String(localized: "No heart rate yet. With a strength workout on your watch too, it arrives once the watch syncs.")
    }

    /// A watch's (or another app's) workout with heart rate; RYFT's own session has none.
    private static func hasHeartRate(_ workout: Workout) -> Bool {
        workout.avgHr != nil && workout.source != "ryft-session"
    }

    private func done() {
        if let s = session, s.notes != notes {
            s.notes = notes
            sync.sessionChanged(s)
        }
        dismiss()
    }
}

/// The heart-rate line under the records.
struct SummaryHeartRate: Equatable {
    let text: String

    init(text: String) {
        self.text = text
    }

    init(_ workout: Workout) {
        self.init(text: SessionSummarySheet.heartRateLine(workout))
    }
}

/// The four tiles, two by two and 12 apart, each pair as tall as the taller; one column from AX1.
private struct SummaryTiles: View {
    let tiles: [WorkoutStat]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: SessionSummaryLayout.spacing) {
            if typeSize.isAccessibilitySize {
                ForEach(tiles) { tile($0) }
            } else {
                ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { i in
                    HStack(spacing: SessionSummaryLayout.spacing) {
                        tile(tiles[i])
                        if i + 1 < tiles.count { tile(tiles[i + 1]) } else { Color.clear.frame(maxWidth: .infinity) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func tile(_ stat: WorkoutStat) -> some View {
        NeutralTile(Text(verbatim: stat.label), value: Text(verbatim: stat.value), unit: stat.unit.map { Text(verbatim: $0) },
                    accessibilityValue: stat.spoken.map { Text(verbatim: $0) })
            .accessibilityIdentifier("summary.stat.\(stat.id)")
    }
}

// MARK: - previews (dark only)

@MainActor
private enum SummaryPreview {
    /// A session finished offline, waiting for `…/complete`.
    static func pending() -> FinishSummary {
        let s = MockTrain.liveSession(in: TrainPreview.store, started: -52 * 60, checked: 17)
        s.status = .completed
        s.endedAt = .now
        s.pendingCompletion = true
        return FinishSummary(sessionID: s.id, completed: nil)
    }

    static let garmin = SummaryHeartRate(text: "Heart rate from Garmin Connect")
}

#Preview("Summary · scored, records") {
    SessionSummarySheet(summary: FinishSummary(sessionID: MockTrain.completed.id, completed: MockTrain.completed),
                        heartRate: SummaryPreview.garmin)
        .previewEnvironment()
}

#Preview("Summary · no records") {
    SessionSummarySheet(summary: FinishSummary(sessionID: MockTrain.completedWithoutRecords.id,
                                               completed: MockTrain.completedWithoutRecords))
        .previewEnvironment()
}

#Preview("Summary · pending strain, will sync") {
    SessionSummarySheet(summary: SummaryPreview.pending())
        .previewEnvironment()
}

#Preview("Summary · AX3") {
    SessionSummarySheet(summary: FinishSummary(sessionID: MockTrain.completed.id, completed: MockTrain.completed),
                        heartRate: SummaryPreview.garmin)
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Summary · workout effort") {
    let state = AppState.preview(flags: [.recoveryCheckin: true])
    SessionSummarySheet(summary: FinishSummary(sessionID: MockTrain.completed.id, completed: MockTrain.completed))
        .previewEnvironment(state)
}
