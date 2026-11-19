import SwiftUI

/// The session detail's numbers (PR 6 B §7.2, `b-14`), bottom of one element to the top of the next.
enum SessionDetailLayout {
    /// The header → the numeral (Strain's and the summary's 22).
    nonisolated static let heroGap = StrainLayout.numeralGap
    /// The ruler → the tiles: 26, of which the hero keeps 20 under the ruler (its labels hang into it).
    nonisolated static let tilesGap: CGFloat = 26 - StrainLayout.rulerFollowingGap
    /// Between the tiles, and between the blocks under them (notes, the exercise cards).
    nonisolated static let spacing: CGFloat = 12
    /// An exercise card: 16 at the sides, the name's row 40 high, a set's row 34, 6 under the last set.
    nonisolated static let cardInset: CGFloat = 16, cardHeadHeight: CGFloat = 40, setRowHeight: CGFloat = 34
    nonisolated static let cardBottomPadding: CGFloat = 6
    /// The set's position ("W", "2"): 14 pt numerals in a 28 pt column at the default size, both growing with the set's text.
    nonisolated static let positionSize: CGFloat = 14, positionWidth: CGFloat = 28
    /// From AX1 a set's RPE goes under its weight and reps, this far.
    nonisolated static let stackedRPEGap: CGFloat = 2
    /// The exercise cards' outlines while the session loads.
    nonisolated static let placeholderCards = 2, placeholderCardHeight: CGFloat = 160
    /// Under the last block.
    nonisolated static let bottomPadding: CGFloat = 32
}

/// What the session detail says (PR 6 B §7.2), from the whole session once it is here, and until then from History's
/// summary of it (title, day, duration, strain, volume, load), so the page paints at once. The phone computes no strain:
/// without the platform's the numeral is unlit. Pure, so previews show every state and tests decide them without a view.
struct SessionDetailContent: Equatable {
    enum State: Equatable {
        /// The whole session.
        case loaded
        /// Waiting for it: the exercises are outlines.
        case loading
        /// It couldn't be read (offline, not cached): the message and Try again in the exercises' place.
        case failed
    }

    /// One exercise's card: its name over its sets.
    struct ExerciseBlock: Identifiable, Equatable {
        /// The session's exercise (an exercise can be in a session twice).
        let id: UUID
        let exerciseID: UUID
        let name: String
        let sets: [SetLine]
    }

    /// One set: "W" or its position, "80 kg × 5", "RPE 8.5".
    struct SetLine: Identifiable, Equatable {
        let id: UUID
        let position: String
        let text: String
        let rpe: String?
        /// VoiceOver's label: "Set 2 of 5", "Set 1 of 5, warm-up" (the live workout's words).
        let spokenPosition: String
        /// VoiceOver's value: "5 reps at 80 kilograms, RPE 8.5".
        let spokenValue: String
    }

    let state: State
    let title: String
    /// "Fri, Nov 13 · 55 min · 17 sets"; nil before anything is known.
    let subtitle: String?
    /// "Friday, November 13, 55 minutes, 17 sets" (VoiceOver).
    let spokenSubtitle: String?
    /// The numeral, its caption ("Strain · of 21 · moderate") and the ruler (`StrainHeroView`).
    let hero: StrainHero
    /// Volume, Muscular load (strain is the hero).
    let tiles: [WorkoutStat]
    let notes: String?
    let exercises: [ExerciseBlock]

    /// - Parameters:
    ///   - summary: History's summary of the session (the list's, cached), for the first paint.
    ///   - session: the whole session, once read.
    ///   - loaded: the read is over (`session` nil then means it failed).
    ///   - name: the exercise's name in the library.
    init(summary: SessionSummary?, session: TrainSession?, loaded: Bool, locale: Locale = .autoupdatingCurrent,
         name: (UUID) -> String? = { _ in nil }) {
        state = session != nil ? .loaded : (loaded ? .failed : .loading)
        let rawTitle = (session?.title ?? summary?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        title = rawTitle.isEmpty ? String(localized: "Workout") : rawTitle

        let start = session?.startedAt ?? summary?.startedAt
        let minutes = session.flatMap { s in s.endedAt.map { StrainFormat.minutes($0.timeIntervalSince(s.startedAt)) } }
            ?? summary?.durationMin
        let sets = session.map { Self.completedWorkingSets($0) } ?? summary?.setCount
        if let start {
            var shown = [start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(locale))]
            var spoken = [start.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale))]
            if let minutes {
                shown.append(StrainFormat.durationText(minutes: minutes))
                spoken.append(Fmt.spokenDuration(minutes: minutes, locale: locale))
            }
            if let sets {
                shown.append(String(localized: "\(sets) sets"))
                spoken.append(String(localized: "\(sets) sets"))
            }
            subtitle = StrainRows.join(shown)
            spokenSubtitle = spoken.joined(separator: ", ")
        } else {
            subtitle = nil
            spokenSubtitle = nil
        }

        // The session's own numbers once it is here (its strain may be absent), the summary's until then; known to be
        // absent once either is here.
        let strain: Double? = if let session { session.strain } else { summary?.strain }
        let load: Double? = if let session { session.muscularTrimp } else { summary?.muscularTrimp }
        let known = session != nil || summary != nil
        hero = StrainHero(strain: strain, namesStrain: true, missingCaption: known ? Self.noStrainCaption : nil)

        let volumeKg = session.map { $0.volumeKg ?? Volume.of($0.exercises.flatMap(\.sets)) } ?? summary?.volumeKg
        let volume = SessionSummaryContent.volumeParts(volumeKg)
        tiles = [
            WorkoutStat(id: "volume", label: String(localized: "Volume"), value: volume.value, unit: volume.unit),
            WorkoutStat(id: "load", label: String(localized: "Muscular load"), value: Fmt.load(load)),
        ]

        let note = session?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        notes = note.isEmpty ? nil : note
        exercises = (session?.exercises ?? []).sorted { $0.position < $1.position }.map { e in
            ExerciseBlock(id: e.id, exerciseID: e.exerciseId, name: name(e.exerciseId) ?? String(localized: "Exercise"),
                          sets: Self.lines(e.sets))
        }
    }

    /// Under the unlit numeral: an imported session, or one the platform hasn't scored.
    static var noStrainCaption: String {
        String(localized: "No strain for this workout.",
               comment: "Session detail, under the unlit strain numeral: the session has no strain (imported, or not scored yet).")
    }

    /// Completed working sets, as History's summary counts them.
    static func completedWorkingSets(_ s: TrainSession) -> Int {
        s.exercises.flatMap(\.sets).filter { !$0.isWarmup && $0.completedAt != nil }.count
    }

    /// The sets in their order; the position counts the warm-ups too, as the live workout's list does ("W", "2", "3").
    static func lines(_ sets: [SessionSet]) -> [SetLine] {
        let ordered = sets.sorted { $0.setIndex < $1.setIndex }
        return ordered.enumerated().map { i, set in
            let rpe = set.rpe.map { String(localized: "RPE \(Fmt.kgNumber($0))") }
            var position = [String(localized: "Set \(i + 1) of \(ordered.count)")]
            if set.isWarmup { position.append(String(localized: "warm-up")) }
            return SetLine(id: set.id, position: set.isWarmup ? "W" : "\(i + 1)", text: text(set), rpe: rpe,
                           spokenPosition: position.joined(separator: ", "),
                           spokenValue: [spoken(set), rpe].compactMap(\.self).joined(separator: ", "))
        }
    }

    /// "5 reps at 80 kilograms", "8 reps", "80 kilograms"; a timed or distance set as drawn.
    static func spoken(_ s: SessionSet) -> String {
        switch (s.reps, s.weightKg) {
        case let (r?, kg?): return String(localized: "\(r) reps at \(Fmt.kgNumber(kg)) kilograms")
        case let (r?, nil): return String(localized: "\(r) reps")
        case let (nil, kg?): return String(localized: "\(Fmt.kgNumber(kg)) kilograms")
        default: return text(s)
        }
    }

    /// "80 kg × 5", "× 8"; a timed set "0:45", a distance "5.0 km" (with its time when there is one).
    static func text(_ s: SessionSet) -> String {
        guard s.reps == nil, s.weightKg == nil else { return SetText.short(s) }
        if let m = s.distanceM, m > 0 {
            return StrainRows.join([Fmt.distance(meters: m)] + (s.durationSec.map { [Fmt.clock(TimeInterval($0))] } ?? []))
        }
        if let d = s.durationSec { return Fmt.clock(TimeInterval(d)) }
        return SetText.short(s)
    }
}

/// Reads the whole session; History's cached summary of it paints the page meanwhile.
@MainActor
@Observable
final class SessionDetailViewModel {
    let sessionID: UUID
    private let library: TrainLibrary

    private(set) var session: TrainSession?
    private(set) var loaded = false

    init(sessionID: UUID, library: TrainLibrary) {
        self.sessionID = sessionID
        self.library = library
    }

    /// The list's summary of it (cached), for the first paint.
    var summary: SessionSummary? { library.cachedSessions().first { $0.id == sessionID } }

    func content(locale: Locale = .autoupdatingCurrent) -> SessionDetailContent {
        SessionDetailContent(summary: summary, session: session, loaded: loaded, locale: locale) { [library] in
            library.exercise(id: $0)?.name
        }
    }

    func load() async {
        loaded = false
        session = await library.session(id: sessionID)
        loaded = true
    }
}

/// A finished session (PR 6 B §7.2, `b-14`): Back, its title over "Fri, Nov 13 · 55 min · 17 sets"; the strain numeral and
/// ruler as the summary draws them; Volume and Muscular load; its notes; one card per exercise with its sets.
struct SessionDetailView: View {
    let sessionID: UUID
    @Environment(TrainLibrary.self) private var library

    var body: some View {
        SessionDetailScreen(model: SessionDetailViewModel(sessionID: sessionID, library: library))
    }
}

/// Wiring; the first model handed in is kept for the screen's lifetime.
private struct SessionDetailScreen: View {
    @State var model: SessionDetailViewModel
    @Environment(\.appEnvironment) private var env
    @Environment(\.locale) private var locale

    var body: some View {
        SessionDetailPage(content: model.content(locale: locale), key: model.sessionID.uuidString,
                          numeralStyle: env.settings.heroNumerals.style, retry: { await model.load() })
            .task { await model.load() }
    }
}

/// The page: header 40, the numeral 22 under it, its caption and the ruler, the two tiles 26 under the ruler, then the notes
/// and the exercise cards 12 apart. No navigation bar: Back is the header's, the edge swipe still pops. An exercise card opens
/// the exercise's page.
struct SessionDetailPage: View {
    let content: SessionDetailContent
    /// The session: a new one cross-fades the numeral.
    var key = ""
    var numeralStyle: DotNumeral.Style = .dots
    /// The failure's Try again: the session's read.
    var retry: () async -> Void = {}

    @State private var shownExercise: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PushedHeader(Text(verbatim: content.title), subtitle: content.subtitle.map { Text(verbatim: $0) },
                             spokenSubtitle: content.spokenSubtitle.map { Text(verbatim: $0) },
                             identifierPrefix: "sessionDetail")
                StrainHeroView(hero: content.hero, key: key, numeralStyle: numeralStyle, identifierPrefix: "sessionDetail")
                    .padding(.top, SessionDetailLayout.heroGap)
                SessionDetailTiles(tiles: content.tiles)
                    .padding(.top, SessionDetailLayout.tilesGap)
                VStack(alignment: .leading, spacing: SessionDetailLayout.spacing) {
                    if let notes = content.notes {
                        Card {
                            Text(verbatim: notes)
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("sessionDetail.notes")
                    }
                    switch content.state {
                    case .loaded:
                        ForEach(content.exercises) { block in
                            SessionExerciseCard(block: block) { shownExercise = block.exerciseID }
                        }
                    case .loading:
                        placeholders
                    case .failed:
                        InlineMessage(message: String(localized: "This workout couldn't be loaded. Try again when you're online."),
                                      retry: retry, identifier: "sessionDetail.failure")
                    }
                }
                .padding(.top, SessionDetailLayout.spacing)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, SessionDetailLayout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
        .navigationDestination(item: $shownExercise) { ExerciseDetailView(exerciseID: $0) }
    }

    /// While the session loads: the exercise cards' outlines; VoiceOver hears it once.
    private var placeholders: some View {
        VStack(spacing: SessionDetailLayout.spacing) {
            ForEach(0..<SessionDetailLayout.placeholderCards, id: \.self) { _ in
                PlaceholderRow(height: SessionDetailLayout.placeholderCardHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading the workout", comment: "VoiceOver: the session detail's outline cards while its sets load."))
        .accessibilityIdentifier("sessionDetail.loading")
    }
}

/// Volume and Muscular load side by side, 12 apart and as tall as the taller; one column from AX1.
private struct SessionDetailTiles: View {
    let tiles: [WorkoutStat]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: SessionDetailLayout.spacing))
            : AnyLayout(HStackLayout(spacing: SessionDetailLayout.spacing))
        layout {
            ForEach(tiles) { stat in
                NeutralTile(Text(verbatim: stat.label), value: Text(verbatim: stat.value),
                            unit: stat.unit.map { Text(verbatim: $0) }, accessibilityValue: stat.spoken.map { Text(verbatim: $0) })
                    .accessibilityIdentifier("sessionDetail.stat.\(stat.id)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One exercise (`b-14`): the name (`headline`) with a chevron, then its sets, 34 high: the position or "W" (14 pt numerals,
/// `textSecondary`), "80 kg × 5" (`callout`), "RPE 8.5" (`caption`, `textSecondary`) at the right, under the set from AX1.
/// The whole card opens the exercise's page. VoiceOver: a container; the name is its button ("Opens the exercise's history"),
/// each set one element ("Set 2", "80 kg × 5, RPE 8.5").
private struct SessionExerciseCard: View {
    let block: SessionDetailContent.ExerciseBlock
    let open: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .callout) private var positionSize = SessionDetailLayout.positionSize
    @ScaledMetric(relativeTo: .callout) private var positionWidth = SessionDetailLayout.positionWidth

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CardSpec.radius, style: .continuous)
        // A tap, not a Button: a button would fold the sets into one element, and VoiceOver reads them one by one.
        VStack(alignment: .leading, spacing: 0) {
            head
            ForEach(block.sets) { setRow($0) }
        }
        .padding(.horizontal, SessionDetailLayout.cardInset)
        .padding(.bottom, SessionDetailLayout.cardBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: shape)
        .contentShape(shape)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sessionDetail.exercise.\(block.exerciseID.uuidString)")
    }

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: SessionDetailLayout.cardInset) {
            Text(verbatim: block.name)
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: GroupedListSpec.chevronSize, weight: .semibold))
                .foregroundStyle(Theme.textPrimary.opacity(GroupedListSpec.accessoryOpacity))
        }
        .padding(.vertical, SessionDetailLayout.cardBottomPadding)
        .frame(maxWidth: .infinity, minHeight: SessionDetailLayout.cardHeadHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: block.name))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Opens the exercise's history"))
        .accessibilityAction(.default, open)
        .accessibilityIdentifier("sessionDetail.exercise.\(block.exerciseID.uuidString).open")
    }

    private func setRow(_ line: SessionDetailContent.SetLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: line.position)
                .font(.ryftNumber(size: positionSize))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: positionWidth, alignment: .leading)
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: SessionDetailLayout.stackedRPEGap) {
                    setText(line)
                    rpe(line)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                setText(line)
                Spacer(minLength: SessionDetailLayout.cardInset)
                rpe(line)
            }
        }
        .frame(maxWidth: .infinity, minHeight: SessionDetailLayout.setRowHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: line.spokenPosition))
        .accessibilityValue(Text(verbatim: line.spokenValue))
    }

    private func setText(_ line: SessionDetailContent.SetLine) -> some View {
        Text(verbatim: line.text)
            .font(.ryft(.callout))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func rpe(_ line: SessionDetailContent.SetLine) -> some View {
        if let rpe = line.rpe {
            Text(verbatim: rpe)
                .font(.ryft(.caption))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - previews (dark only)

@MainActor
enum SessionDetailPreview {
    /// The latest Upper A as the platform has it: strain 10-ish, its notes, Bench press first.
    static var scored: SessionDetailContent { content(MockTrain.completed) }

    /// Finished, not scored yet (or imported): the unlit numeral, "–" for the load.
    static var unscored: SessionDetailContent { content(MockTrain.completedUnscored) }

    /// History's summary is here, the session isn't yet.
    static var loading: SessionDetailContent {
        SessionDetailContent(summary: SessionSummary(MockTrain.completed), session: nil, loaded: false,
                             locale: Locale(identifier: "en_US"))
    }

    /// Offline, not cached, no summary either.
    static var failed: SessionDetailContent {
        SessionDetailContent(summary: nil, session: nil, loaded: true, locale: Locale(identifier: "en_US"))
    }

    static func content(_ s: TrainSession) -> SessionDetailContent {
        SessionDetailContent(summary: SessionSummary(s), session: s, loaded: true, locale: Locale(identifier: "en_US")) { id in
            MockTrain.exercises.first { $0.id == id }?.name
        }
    }
}

#Preview("Session detail") {
    NavigationStack { SessionDetailView(sessionID: MockTrain.history[MockTrain.history.count - 1].id).trainDestinations() }
        .previewEnvironment()
}

#Preview("Session detail · no strain") {
    NavigationStack { SessionDetailPage(content: SessionDetailPreview.unscored) }
        .previewEnvironment()
}

#Preview("Session detail · loading") {
    NavigationStack { SessionDetailPage(content: SessionDetailPreview.loading) }
        .previewEnvironment()
}

#Preview("Session detail · failed") {
    NavigationStack { SessionDetailPage(content: SessionDetailPreview.failed) }
        .previewEnvironment()
}

#Preview("Session detail · AX3") {
    NavigationStack { SessionDetailPage(content: SessionDetailPreview.scored) }
        .previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}
