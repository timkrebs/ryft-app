import Foundation

/// A "new" row's custom exercise (ui.md 7.3, design §4): name and equipment from the file, the muscle from the user.
/// Created when Import is tapped (step 6), under its derived id.
struct ImportCustomDraft: Equatable, Sendable {
    var name: String
    var kind: ExerciseKind
    var loadType: LoadType
    /// Left empty until the user chooses one: a "new" row blocks Continue until then.
    var muscle: Muscle?
    var unilateral = false

    init(_ source: ImportedExerciseSource, aliases: ExerciseAliases) {
        name = ImportCustomExercise.name(source.name, key: source.key)
        kind = ImportCustomExercise.kind(for: source.key, aliases: aliases)
        loadType = ImportCustomExercise.loadType(for: source.key, hasPlusSets: source.plusLoads != nil, aliases: aliases)
    }

    init(name: String, kind: ExerciseKind, loadType: LoadType, muscle: Muscle?, unilateral: Bool = false) {
        self.name = name
        self.kind = kind
        self.loadType = loadType
        self.muscle = muscle
        self.unilateral = unilateral
    }
}

/// One distinct imported exercise in step 4 (ui.md 7.2): what the file calls it, what the matcher found, and what the
/// user decided. The file's name is shown in the flow only, never stored or logged.
struct ImportMappingRow: Identifiable, Equatable, Sendable {
    let source: ImportedExerciseSource
    let match: ExerciseMatch
    var decision: Decision
    /// The user's tap on the bodyweight question (any option, the pre-selected one too).
    var bodyweight: BodyweightAnswer?
    /// Remembered with an earlier import's match.
    let rememberedBodyweight: BodyweightAnswer?

    var id: SourceExerciseKey { source.key }

    enum Decision: Equatable, Sendable {
        /// A fuzzy suggestion waiting for a tap: never accepted on its own, at any score.
        case check(UUID)
        /// Remembered, exact or alias; or a suggestion the user accepted.
        case matched(UUID)
        /// Another library exercise the user picked.
        case chosen(UUID)
        /// A new custom exercise, created when Import is tapped.
        case create(ImportCustomDraft)
        /// Not imported: its sets are left out and it's removed from the plan.
        case skip
    }

    /// The library exercise the row maps to now (a check row's suggestion too); nil for new and skipped rows.
    var exerciseID: UUID? {
        switch decision {
        case let .check(id), let .matched(id), let .chosen(id): id
        case .create, .skip: nil
        }
    }

    var draft: ImportCustomDraft? {
        if case let .create(draft) = decision { return draft }
        return nil
    }
}

/// The trailing status of a row (ui.md 7.2): a glyph and a word each, never colour alone.
enum ImportRowStatus: Equatable, Sendable {
    case matched(remembered: Bool)
    case check(likely: Bool)
    /// `ready`: the muscle group is chosen.
    case new(ready: Bool)
    case yourChoice
    case skipped

    var symbol: String {
        switch self {
        case .matched, .yourChoice: "checkmark.circle"
        case .check: "questionmark.circle"
        case .new: "plus.circle"
        case .skipped: "minus.circle"
        }
    }

    var word: String {
        switch self {
        case .matched: String(localized: "Matched", comment: "Training import, step 4: a row's status.")
        case .check: String(localized: "Check", comment: "Training import, step 4: a row's status, a suggestion to confirm.")
        case .new: String(localized: "New", comment: "Training import, step 4: a row's status, a new custom exercise.")
        case .yourChoice: String(localized: "Your choice", comment: "Training import, step 4: a row's status.")
        case .skipped: String(localized: "Skipped", comment: "Training import, step 4: a row's status.")
        }
    }

    /// The detail under the match: confidence in words (never a number), where the match came from.
    var detail: String? {
        switch self {
        case .matched(remembered: true):
            String(localized: "Matched · from your earlier choice", comment: "Training import, step 4: a remembered match.")
        case .check(likely: true): String(localized: "Likely match", comment: "Training import, step 4: a fuzzy match's confidence.")
        case .check(likely: false): String(localized: "Possible match", comment: "Training import, step 4: a fuzzy match's confidence.")
        case .new(ready: true):
            String(localized: "New · created when you import", comment: "Training import, step 4: a new exercise with its muscle group.")
        case .matched(remembered: false), .new(ready: false), .yourChoice, .skipped: nil
        }
    }
}

/// Step 4's state (ui.md §7): every distinct exercise once, matched once. Pure; the decisions the view model tests.
struct ImportMappingState: Equatable, Sendable {
    var rows: [ImportMappingRow]
    /// The library exercises the rows can name (the matched library and later picks).
    var exercises: [UUID: Exercise]

    /// `previous`: decisions from an earlier visit (the user went back to step 3), kept by key.
    init(sources: [ImportedExerciseSource], matches: [ExerciseMatch], library: [Exercise],
         remembered: [SourceExerciseKey: RememberedMatch], aliases: ExerciseAliases,
         previous: [ImportMappingRow] = []) {
        let earlier = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [ImportMappingRow] = []
        for (source, match) in zip(sources, matches) {
            if let kept = earlier[source.key] {
                rows.append(kept)
                continue
            }
            let decision: ImportMappingRow.Decision
            switch (match.exerciseID, match.tier) {
            case let (id?, .fuzzy): decision = .check(id)
            case let (id?, _): decision = .matched(id)
            case (nil, _): decision = .create(ImportCustomDraft(source, aliases: aliases))
            }
            let remembered = match.tier == .remembered ? remembered[source.key]?.bodyweight : nil
            rows.append(ImportMappingRow(source: source, match: match, decision: decision, bodyweight: nil,
                                         rememberedBodyweight: remembered))
        }
        self.rows = rows
        exercises = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    init(rows: [ImportMappingRow], exercises: [UUID: Exercise]) {
        self.rows = rows
        self.exercises = exercises
    }

    // MARK: Per row

    func row(_ key: SourceExerciseKey) -> ImportMappingRow? { rows.first { $0.id == key } }

    func exercise(for row: ImportMappingRow) -> Exercise? { row.exerciseID.flatMap { exercises[$0] } }

    func status(of row: ImportMappingRow) -> ImportRowStatus {
        switch row.decision {
        case let .matched(id): .matched(remembered: row.match.tier == .remembered && row.match.exerciseID == id)
        case .check: .check(likely: row.match.isLikely)
        case let .create(draft): .new(ready: draft.muscle != nil)
        case .chosen: .yourChoice
        case .skip: .skipped
        }
    }

    /// The `load_type` the bodyweight question is asked against: the mapped exercise's, a new one's, none if skipped.
    func loadType(of row: ImportMappingRow) -> LoadType? {
        switch row.decision {
        case .check, .matched, .chosen: exercise(for: row)?.loadType
        case let .create(draft): draft.loadType
        case .skip: nil
        }
    }

    /// The answers offered for a row's `+N` sets (ui.md 7.4); empty when not asked.
    func bodyweightOptions(_ row: ImportMappingRow) -> [BodyweightAnswer] {
        guard let plus = row.source.plusLoads, let loadType = loadType(of: row) else { return [] }
        return BodyweightAnswer.options(for: loadType, plus: plus)
    }

    /// The tapped answer, else the remembered one while it's still offered, else the default.
    func bodyweightAnswer(_ row: ImportMappingRow) -> BodyweightAnswer? {
        guard let plus = row.source.plusLoads, let loadType = loadType(of: row) else { return nil }
        return BodyweightAnswer.resolved(row.bodyweight ?? row.rememberedBodyweight, for: loadType, plus: plus)
    }

    /// The question waits for a tap (it never blocks Continue: a default is pre-selected).
    func isQuestionOpen(_ row: ImportMappingRow) -> Bool {
        let options = bodyweightOptions(row)
        guard !options.isEmpty, row.bodyweight == nil else { return false }
        return row.rememberedBodyweight.map { !options.contains($0) } ?? true
    }

    /// A `+N` row matched to a `time` or `distance` exercise: the weight is left out, and the row says so.
    func dropsPlusLoad(_ row: ImportMappingRow) -> Bool {
        guard row.source.plusLoads != nil, let loadType = loadType(of: row) else { return false }
        return loadType == .time || loadType == .distance
    }

    /// Blocks Continue: a check not yet accepted, a new exercise without its muscle group.
    func blocks(_ row: ImportMappingRow) -> Bool {
        switch row.decision {
        case .check: true
        case let .create(draft): draft.muscle == nil
        case .matched, .chosen, .skip: false
        }
    }

    /// In "Needs your attention": what blocks, and an open question.
    func needsAttention(_ row: ImportMappingRow) -> Bool { blocks(row) || isQuestionOpen(row) }

    // MARK: Counts

    var leftToCheck: Int { rows.filter(blocks).count }
    var matchedCount: Int {
        rows.filter { if case .matched = $0.decision { true } else if case .chosen = $0.decision { true } else { false } }.count
    }
    var checkCount: Int { rows.filter { if case .check = $0.decision { true } else { false } }.count }
    var newCount: Int { rows.filter { $0.draft != nil }.count }
    var skippedCount: Int { rows.filter { $0.decision == .skip }.count }
    /// M2: every row matched and no question open.
    var allMatched: Bool { checkCount == 0 && newCount == 0 && skippedCount == 0 && !rows.contains(where: isQuestionOpen) }
    var likelyChecks: [SourceExerciseKey] {
        rows.filter { if case .check = $0.decision { $0.match.isLikely } else { false } }.map(\.id)
    }

    var attention: [ImportMappingRow] { rows.filter(needsAttention) }
    var resolved: [ImportMappingRow] { rows.filter { !needsAttention($0) } }

    // MARK: Decisions

    mutating func accept(_ key: SourceExerciseKey) {
        update(key) { row in
            if case let .check(id) = row.decision { row.decision = .matched(id) }
        }
    }

    /// "Accept N likely matches": every likely check row, each undoable on its own. Returns how many.
    @discardableResult
    mutating func acceptLikely() -> Int {
        let keys = likelyChecks
        for key in keys { accept(key) }
        return keys.count
    }

    /// "Choose another exercise…": a library exercise (the same as the suggestion counts as accepting it).
    mutating func choose(_ key: SourceExerciseKey, _ exercise: Exercise) {
        exercises[exercise.id] = exercise
        update(key) { row in
            row.decision = exercise.id == row.match.exerciseID ? .matched(exercise.id) : .chosen(exercise.id)
            row.bodyweight = nil
        }
    }

    /// "Create a custom exercise…" or the inline muscle menu.
    mutating func create(_ key: SourceExerciseKey, _ draft: ImportCustomDraft) {
        update(key) { row in
            row.decision = .create(draft)
            row.bodyweight = nil
        }
    }

    mutating func setMuscle(_ key: SourceExerciseKey, _ muscle: Muscle, aliases: ExerciseAliases) {
        update(key) { row in
            var draft = row.draft ?? ImportCustomDraft(row.source, aliases: aliases)
            draft.muscle = muscle
            row.decision = .create(draft)
        }
    }

    mutating func skip(_ key: SourceExerciseKey) {
        update(key) { $0.decision = .skip }
    }

    mutating func answer(_ key: SourceExerciseKey, _ answer: BodyweightAnswer) {
        update(key) { $0.bodyweight = answer }
    }

    private mutating func update(_ key: SourceExerciseKey, _ change: (inout ImportMappingRow) -> Void) {
        guard let index = rows.firstIndex(where: { $0.id == key }) else { return }
        change(&rows[index])
    }

    // MARK: For the import

    /// What each source exercise became: a library id or the new exercise's derived id. Skipped rows are absent.
    func resolvedIDs(account: String, source: ImportFormatID) -> [SourceExerciseKey: UUID] {
        var out: [SourceExerciseKey: UUID] = [:]
        for row in rows {
            switch row.decision {
            case let .check(id), let .matched(id), let .chosen(id): out[row.id] = id
            case .create: out[row.id] = ImportCustomExercise.id(account: account, source: source, key: row.id)
            case .skip: break
            }
        }
        return out
    }

    /// The choices remembered when Import is tapped (never per tap): new rows as their derived ids, so the next
    /// import matches them as `.remembered` once they're in the library. Skipped rows aren't remembered.
    func rememberedChoices(account: String, source: ImportFormatID) -> [SourceExerciseKey: RememberedMatch] {
        let ids = resolvedIDs(account: account, source: source)
        var out: [SourceExerciseKey: RememberedMatch] = [:]
        for row in rows {
            guard let id = ids[row.id] else { continue }
            out[row.id] = RememberedMatch(exerciseID: id, bodyweight: bodyweightAnswer(row))
        }
        return out
    }

    /// The custom exercises to create first (step 6), under their derived ids.
    func newExercises(account: String, source: ImportFormatID, aliases: ExerciseAliases) -> [Exercise] {
        rows.compactMap { row in
            guard let draft = row.draft, let muscle = draft.muscle else { return nil }
            var exercise = ImportCustomExercise.make(row.source, name: draft.name, account: account, source: source,
                                                     primaryMuscles: [muscle], aliases: aliases)
            exercise.kind = draft.kind
            exercise.equipment = [draft.kind.rawValue]
            exercise.loadType = draft.loadType
            exercise.bodyweightFactor = draft.loadType == .bodyweight ? 1 : 0
            exercise.isUnilateral = draft.unilateral
            return exercise
        }
    }

    /// What each source exercise became, for the builder (`ImportDecisions.exercises`): the library exercise, the new
    /// custom one under its derived id, or skip. A "new" row without its muscle group can't reach the builder.
    func choices(account: String, source: ImportFormatID, aliases: ExerciseAliases) -> [SourceExerciseKey: ImportExerciseChoice] {
        let customs = Dictionary(newExercises(account: account, source: source, aliases: aliases).map { ($0.id, $0) },
                                 uniquingKeysWith: { a, _ in a })
        var out: [SourceExerciseKey: ImportExerciseChoice] = [:]
        for row in rows {
            let answer = bodyweightAnswer(row)
            switch row.decision {
            case let .check(id), let .matched(id), let .chosen(id):
                guard let exercise = exercises[id] else { continue }
                out[row.id] = ImportExerciseChoice(.library(exercise), bodyweight: answer)
            case .create:
                let id = ImportCustomExercise.id(account: account, source: source, key: row.id)
                out[row.id] = customs[id].map { ImportExerciseChoice(.custom($0), bodyweight: answer) }
                    ?? ImportExerciseChoice(.skip)
            case .skip:
                out[row.id] = ImportExerciseChoice(.skip)
            }
        }
        return out
    }

    /// The bodyweight answers by source exercise (only rows that were asked).
    func bodyweightAnswers() -> [SourceExerciseKey: BodyweightAnswer] {
        var out: [SourceExerciseKey: BodyweightAnswer] = [:]
        for row in rows {
            if let answer = bodyweightAnswer(row) { out[row.id] = answer }
        }
        return out
    }
}

/// Matching off the main actor (design §4: the matcher is pure; mapping never runs on the main actor).
enum ImportMatching {
    @concurrent
    static func run(_ bundle: ImportBundle, library: [Exercise], aliases: ExerciseAliases,
                    remembered: [SourceExerciseKey: UUID]) async -> (sources: [ImportedExerciseSource], matches: [ExerciseMatch]) {
        MainThread.assertOff("Matching imported exercises")
        let sources = aliases.normalizer.sources(in: bundle)
        let matcher = ExerciseMatcher(library: library, aliases: aliases, remembered: remembered)
        return (sources, matcher.match(sources.map(\.key)))
    }
}
