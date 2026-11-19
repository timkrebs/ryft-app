// What Strain and the Workout detail show, as values (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-3, §P5-4,
// §P5-12 tests 24–27): the hero (numeral, caption, delta, split, ruler), the zones, the tiles, the state, and the activity
// rows. Pure, so previews show every state and tests decide them without a view.
import Foundation

// MARK: - the strain hero

/// The numeral, its caption, the ruler and what VoiceOver hears for them, for one strain on the 0–21 scale (a day's or a
/// workout's). The band is `TodayStrainBand`'s (10 / 14 / 18, never "a target": R-N1).
struct StrainHero: Equatable {
    /// The strain; nil: the unlit numeral and no needle.
    let strain: Double?
    /// "vs 7 d" (a day only): Today's rule, `MetricDelta.vsSevenDayMean` (`delta(_:day:prior:)`).
    var delta: MetricDelta?
    /// "Cardio 9.2 · Strength 4.1" (a day with a strength session).
    var split: String?
    /// The workout's caption starts "Strain · " (it has no title of its own above the numeral).
    var namesStrain = false
    /// What the caption says without a strain ("No strain recorded for this day."); `nil` keeps an empty line.
    var missingCaption: String?

    /// The scale: 0–21, the moderate band 10–14 marked on the ruler.
    nonisolated static let scale: ClosedRange<Double> = 0...21
    static var zone: ClosedRange<Double>? { TodayStrainBand.zone }
    /// The numeral's shape while there is no value ("00.0": two digits, the decimal point, one digit).
    nonisolated static let placeholder = "00.0"

    var band: TodayStrainBand? { strain.map(TodayStrainBand.init) }

    /// "12.4"; nil while there is none (the unlit placeholder).
    var numeral: String? { strain.map { Fmt.strain($0) } }

    /// "of 21 · moderate"; the workout's "Strain · of 21 · moderate"; without a strain the caller's sentence.
    var caption: String {
        guard let band else { return missingCaption ?? "" }
        return namesStrain ? Self.named(band.caption) : band.caption
    }

    /// "Strain · of 21 · moderate": a workout's caption names the number (it has no title above it).
    static func named(_ caption: String) -> String {
        // Its own key: "Strain · %@" is Today's tile label for another day.
        String(localized: "workout.strain.caption", defaultValue: "Strain · \(caption)",
               comment: "Under a workout's strain numeral: the word, then the scale and the band (\"of 21 · moderate\", \"of 21\").")
    }

    /// The numeral's VoiceOver label: "Strain 12.4 of 21".
    var numeralLabel: String? { strain.map { String(localized: "Strain \(Fmt.strain($0)) of 21") } }

    /// The numeral's VoiceOver value: the band, the change, the split ("Moderate strain, Up 1.2 versus 7 days, Cardio 9.2 · …").
    var numeralValue: String {
        guard let band else { return "" }
        var parts = [band.spoken]
        if let delta { parts.append(DeltaLabel.spoken(delta, spec: .strain, reference: Self.deltaReference)) }
        if let split { parts.append(split) }
        return parts.joined(separator: ", ")
    }

    /// "vs 7 d" after the delta (`DeltaLabel.sevenDayReference`, as Today, Sleep and Insights).
    static var deltaReference: String { DeltaLabel.sevenDayReference }

    /// The ruler's labels: "0", "moderate 10–14", "21".
    static var rulerLabels: [String] {
        ["0", String(localized: "moderate 10–14", comment: "Strain's ruler: the label of the marked band, strain 10 to 14 (never \"target\")."),
         "21"]
    }

    /// "12.4, Moderate strain, on a scale from 0 to 21. The moderate range is 10 to 14."; "No data" without a strain.
    var rulerValue: String {
        guard let strain, let band else { return String(localized: "No data") }
        // The catalog's key keeps its positional form (Today's tile says the same).
        let format = String(localized: "%1$@, %2$@, on a scale from 0 to 21. The moderate range is 10 to 14.",
                            comment: "VoiceOver on Today's strain tile: the value (12.4), its band (Moderate strain), the scale and the ruler's band.")
        return String(format: format, Fmt.strain(strain), band.spoken)
    }

    /// "vs 7 d" for the strain of `day` ("yyyy-MM-dd"): Today's rule (`MetricDelta.vsSevenDayMean`), so Strain and Insights'
    /// strain card agree. Against the mean of `prior`'s strains (the 6 days before it, those cached; one is enough); none
    /// without a strain of the day's own.
    static func delta(_ strain: Double?, day: String, prior: [TrendPoint]) -> MetricDelta? {
        guard let strain else { return nil }
        return .vsSevenDayMean(prior.filter { $0.day < day } + [TrendPoint(day: day, value: strain)])
    }
}

// MARK: - zones

/// The five heart-rate zones as the zones tile shows them (§P5-3.4): Z5 at the top, the minutes lighting 30 ticks on a
/// 40-minute scale, the head row's total, and the tile's one VoiceOver sentence.
struct StrainZones: Equatable {
    /// Minutes in Z1…Z5 (`zone_min`); nil without zone data (missing, or not five values).
    let minutes: [Double]?
    /// The day's TRIMP, in the head row after the minutes ("82 min · TRIMP 112"); nil on a workout, whose TRIMP is a tile.
    let trimp: Int?

    init(minutes: [Double]?, trimp: Int? = nil) {
        self.minutes = minutes.flatMap { $0.count == Self.count ? $0 : nil }
        self.trimp = trimp
    }

    nonisolated static let count = 5
    /// The minutes that light all 30 ticks (a zone of 40 minutes or more lights them all; its minutes are in its value).
    nonisolated static let scaleMax = ZoneBlock.defaultScaleMax
    /// The heart-rate-reserve bounds the app scores zones with (R-N3 would bring them from the platform): Z1 50–60 % … Z5 ≥ 90 %.
    nonisolated static let reserveBounds: [(lo: Int, hi: Int?)] = [(50, 60), (60, 70), (70, 80), (80, 90), (90, nil)]

    struct Row: Equatable, Identifiable {
        /// 1…5.
        let zone: Int
        /// "Z4 · Threshold".
        let label: String
        let minutes: Double?
        /// "14", "–".
        let value: String
        /// "Zone 4, threshold, 80 to 90 percent of heart-rate reserve, 14 minutes".
        let spoken: String
        var id: Int { zone }
    }

    /// Top to bottom, as the board: Z5 first.
    var rows: [Row] {
        (1...Self.count).reversed().map { zone in
            let m = minutes?[zone - 1]
            let label = Self.label(zone)
            let spoken: String
            if let m {
                let format = String(localized: "Zone %1$lld, %2$@, %3$@ of heart-rate reserve, %4$lld minutes",
                                    comment: "VoiceOver on one heart-rate zone row: its number, name, heart-rate-reserve range and minutes.")
                spoken = String(format: format, zone, Self.spokenName(zone), Self.spokenRange(zone), Int(m.rounded()))
            } else {
                spoken = label
            }
            return Row(zone: zone, label: label, minutes: m, value: m.map { String(Int($0.rounded())) } ?? Fmt.placeholder,
                       spoken: spoken)
        }
    }

    /// The minutes in all five zones, rounded.
    var totalMinutes: Int? { minutes.map { Int($0.reduce(0, +).rounded()) } }

    /// The head row's value: "82 min · TRIMP 112", "48 min", "–".
    var head: String {
        guard let total = totalMinutes else { return Fmt.placeholder }
        let minutes = String(localized: "\(total) min")
        // TRIMP is the training-impulse unit's name; it reads the same in every language.
        return trimp.map { "\(minutes) · TRIMP \($0)" } ?? minutes
    }

    /// The tile's VoiceOver value: "82 minutes. Zone 5, max, 6 minutes; …; Zone 1, easy, 11 minutes. TRIMP 112. Zones are in %
    /// of heart-rate reserve."; without zone data, `missing`.
    func spokenValue(missing: String) -> String {
        guard let minutes, let total = totalMinutes else { return missing }
        let zones = (1...Self.count).reversed().map { zone in
            let format = String(localized: "Zone %1$lld, %2$@, %3$@",
                                comment: "VoiceOver in the zones tile's sentence: a zone's number, its name and its minutes (\"6 minutes\").")
            return String(format: format, zone, Self.spokenName(zone), Fmt.spokenDuration(minutes: Int(minutes[zone - 1].rounded())))
        }
        var sentences = [Fmt.spokenDuration(minutes: total), zones.joined(separator: "; ")]
        if let trimp { sentences.append("TRIMP \(trimp)") }
        return sentences.joined(separator: ". ") + ". " + Self.footnote
    }

    /// Under the tile (the old `ZoneBar` line, reworded).
    static var footnote: String {
        String(localized: "Zones are in % of heart-rate reserve.", comment: "Under the heart-rate zones tile on Strain and a workout.")
    }

    /// "Z5 · Max" … "Z1 · Easy": generic training terms, not a brand's.
    static func label(_ zone: Int) -> String {
        switch zone {
        case 1: return String(localized: "Z1 · Easy", comment: "Heart-rate zone 1's row label (50–60 % of heart-rate reserve).")
        case 2: return String(localized: "Z2 · Aerobic", comment: "Heart-rate zone 2's row label (60–70 % of heart-rate reserve).")
        case 3: return String(localized: "Z3 · Tempo", comment: "Heart-rate zone 3's row label (70–80 % of heart-rate reserve).")
        case 4: return String(localized: "Z4 · Threshold", comment: "Heart-rate zone 4's row label (80–90 % of heart-rate reserve).")
        default: return String(localized: "Z5 · Max", comment: "Heart-rate zone 5's row label (90 % of heart-rate reserve and more).")
        }
    }

    /// The zone's name as VoiceOver says it after "Zone 3, ": "tempo".
    static func spokenName(_ zone: Int) -> String {
        switch zone {
        case 1: return String(localized: "easy", comment: "VoiceOver: heart-rate zone 1's name, after \"Zone 1, \".")
        case 2: return String(localized: "aerobic", comment: "VoiceOver: heart-rate zone 2's name, after \"Zone 2, \".")
        case 3: return String(localized: "tempo", comment: "VoiceOver: heart-rate zone 3's name, after \"Zone 3, \".")
        case 4: return String(localized: "threshold", comment: "VoiceOver: heart-rate zone 4's name, after \"Zone 4, \".")
        default: return String(localized: "max", comment: "VoiceOver: heart-rate zone 5's name, after \"Zone 5, \".")
        }
    }

    /// "70 to 80 percent", "90 percent or more".
    static func spokenRange(_ zone: Int) -> String {
        let bounds = reserveBounds[min(max(zone, 1), count) - 1]
        guard let hi = bounds.hi else {
            return String(localized: "\(bounds.lo)\u{00A0}percent or more", comment: "VoiceOver: zone 5's heart-rate-reserve range.")
        }
        return String(localized: "\(bounds.lo) to \(hi)\u{00A0}percent", comment: "VoiceOver: a zone's heart-rate-reserve range.")
    }
}

// MARK: - the day

/// Strain for one day (§P5-3.1, §P5-3.7): what the hero, the zones tile and the tiles show, in which state.
struct StrainBoard: Equatable {
    enum Look: Equatable {
        /// The day is cached: its values, with or without a strain and zones.
        case loaded
        /// Nothing cached yet, loading: outlines, no spinner.
        case loading
        /// Nothing cached and the load failed: the outlines, and the calm sentence in the zones tile's place.
        case failed(SleepLoadFailure)
    }

    /// How final the day's numbers are, which decides what a missing strain or missing zones say (§P5-3.7).
    enum DayScoring: Equatable {
        /// A past day the platform has scored: an absence is final ("No strain recorded for this day.").
        case final
        /// Today, not being scored: the day isn't over ("No strain yet today.").
        case today
        /// The platform is scoring newer data (`pending`): no absence sentence, the rows keep "–".
        case pending

        /// `state`: the day's scoring state (today's from `ScoringWord.state`, as Today and Sleep read it; another day's
        /// from its row).
        init(_ state: ScoringState?, isToday: Bool) {
            if state == .pending {
                self = .pending
            } else {
                self = isToday ? .today : .final
            }
        }
    }

    let look: Look
    let scoring: DayScoring
    let hero: StrainHero
    let zones: StrainZones
    let steps: Int?
    let activeKcal: Int?

    /// - Parameters:
    ///   - detail: the day as cached; nil while it loads or after a failure.
    ///   - score: the day's score (the detail's, else the cached history's: the numeral may show before the detail).
    ///   - prior: the strains of the 6 days before, by day ("vs 7 d"'s window, `StrainHero.delta`).
    ///   - isLoading: nothing cached and the day's load hasn't answered yet.
    ///   - scoring: how final the day's numbers are.
    init(detail: DayDetail?, score: DailyScore?, prior: [TrendPoint], split: String?, isLoading: Bool,
         failure: SleepLoadFailure?, scoring: DayScoring = .final) {
        self.scoring = scoring
        if detail != nil {
            look = .loaded
        } else if let failure {
            look = .failed(failure)
        } else if isLoading {
            look = .loading
        } else {
            look = .loaded
        }
        let strain = score?.strain
        hero = StrainHero(strain: strain, delta: StrainHero.delta(strain, day: score?.day ?? "", prior: prior),
                          split: strain == nil ? nil : split,
                          missingCaption: look == .loaded ? Self.noStrainCaption(scoring) : nil)
        zones = StrainZones(minutes: detail?.strain?.zoneMin.map(Double.init), trimp: detail?.strain?.trimp)
        steps = detail?.strain?.steps ?? score?.steps
        activeKcal = detail?.strain?.activeKcal ?? score?.activeKcal
    }

    /// Outlines instead of the zones, the tiles and the rows: loading, or a failed load with nothing to show.
    var isOutline: Bool { look != .loaded }

    var failure: SleepLoadFailure? {
        if case .failed(let failure) = look { return failure }
        return nil
    }

    /// The day loaded without zone data: the short tile and its sentence; while it is being scored, the rows with "–".
    var lacksZones: Bool { look == .loaded && zones.minutes == nil && scoring != .pending }

    /// What the zones tile says without zone data.
    var zonesMissing: StrainZonesTile.Missing {
        switch scoring {
        case .final: .sentence(Self.noZonesSentence)
        case .today: .sentence(Self.noZonesTodaySentence)
        case .pending: .pending(Self.pendingSentence)
        }
    }

    /// The caption under the unlit numeral, by how final the day is.
    static func noStrainCaption(_ scoring: DayScoring) -> String {
        switch scoring {
        case .final: noStrainSentence
        case .today: noStrainTodaySentence
        case .pending: pendingSentence
        }
    }

    var stepsText: String { Fmt.integer(steps.map(Double.init)) }
    var energyText: String { Fmt.integer(activeKcal.map(Double.init)) }

    static var noStrainSentence: String {
        String(localized: "No strain recorded for this day.", comment: "Strain's caption under the unlit numeral: the day loaded without a strain.")
    }
    static var noZonesSentence: String {
        String(localized: "Your watch didn't record heart-rate zones for this day.",
               comment: "Strain's zones tile without zone data for the day.")
    }
    static var noStrainTodaySentence: String {
        String(localized: "No strain yet today.",
               comment: "Strain's caption under the unlit numeral today: nothing has added strain so far (the day isn't over).")
    }
    static var noZonesTodaySentence: String {
        String(localized: "No heart-rate zones yet today.",
               comment: "Strain's zones tile today without zone data so far (the day isn't over).")
    }
    /// While the platform scores newer data: what is happening, not that something is missing.
    static var pendingSentence: String { String(localized: "Scoring your latest data") }
    static var loadingLabel: String {
        String(localized: "Loading this day", comment: "VoiceOver on Strain's numeral while the day loads (outlines, no spinner).")
    }
}

// MARK: - formatting

enum StrainFormat {
    /// "min" after a duration under an hour ("42 min").
    static var minuteUnit: String { String(localized: "min", comment: "Minutes, the unit after a duration under an hour on Strain and a workout: \"42 min\".") }
    /// "h" after a clock duration ("1:05 h").
    static var hourUnit: String {
        String(localized: "h", comment: "Hours, the unit after a clock duration on Today's Sleep tile and on Sleep's tiles: \"7:48 h\", \"0:30 h\".")
    }

    /// "kcal" after an energy ("612 kcal").
    static var kcalUnit: String {
        String(localized: "kcal", comment: "Kilocalories, the unit after an energy on Strain's and a workout's tiles: \"612 kcal\".")
    }
    /// "bpm" after a heart rate ("148 bpm").
    static var bpmUnit: String { String(localized: "bpm", comment: "Beats per minute, the unit after a heart rate on a workout's tiles: \"148 bpm\".") }

    /// A duration as the rows and tiles show it: under an hour "42" + "min", else "1:05" + "h".
    static func duration(minutes: Int) -> (value: String, unit: String) {
        minutes < 60 ? (String(minutes), minuteUnit) : (Fmt.clock(minutes: minutes), hourUnit)
    }

    /// "42 min", "1:05 h".
    static func durationText(minutes: Int) -> String {
        let d = duration(minutes: minutes)
        return "\(d.value) \(d.unit)"
    }

    static func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }

    /// "7.8 kilometres" (VoiceOver).
    static func spokenDistance(_ meters: Double, locale: Locale) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .wide, usage: .road, numberFormatStyle: .number.precision(.fractionLength(1)))
                .locale(locale))
    }
}

// MARK: - activity rows

/// Strain's rows (§P5-3.6), one `ActivityListRow.Content` for a workout, a logged session and a My Day item: "07:10 · 42 min
/// · 7.8 km" (start · duration · distance, else the average heart rate; a logged session's load after them), the strain on
/// the right ("–" without one), and one VoiceOver sentence.
enum StrainRows {
    static func workout(_ w: Workout, session: SessionSummary?, locale: Locale = .autoupdatingCurrent) -> ActivityListRow.Content {
        let title: String
        if let session, !session.title.isEmpty {
            title = session.title
        } else {
            title = ActivityStyle.name(for: w.activity)
        }
        let minutes = StrainFormat.minutes(w.duration)
        var meta = [Fmt.time(w.start, locale: locale), StrainFormat.durationText(minutes: minutes)]
        var spoken = [title, Fmt.time(w.start, locale: locale), Fmt.spokenDuration(minutes: minutes, locale: locale)]
        if let m = w.distanceM, m > 0 {
            meta.append(Fmt.distance(meters: m))
            spoken.append(StrainFormat.spokenDistance(m, locale: locale))
        } else if let hr = w.avgHr {
            meta.append(String(localized: "\(Int(hr.rounded())) bpm"))
            spoken.append(String(localized: "average heart rate \(Int(hr.rounded()))\u{00A0}bpm",
                                 comment: "VoiceOver in an activity row: the workout's average heart rate."))
        }
        // A logged session's load replaces the old load chip (a workout that carries one without its session, too).
        let hasLoad = session != nil || w.muscularLoad != nil
        let load = session?.muscularTrimp ?? w.muscularLoad
        if hasLoad { meta.append(loadText(load)) }
        spoken.append(spokenStrain(w.strain))
        if hasLoad, let load { spoken.append(String(localized: "Muscular load \(Fmt.load(load))")) }
        return ActivityListRow.Content(systemImage: session == nil ? ActivityStyle.icon(for: w.activity) : "dumbbell",
                                       title: title, meta: join(meta), value: w.strain.map { Fmt.strain($0) },
                                       spoken: spoken.joined(separator: ", "))
    }

    static func session(_ s: SessionSummary, locale: Locale = .autoupdatingCurrent) -> ActivityListRow.Content {
        let title = s.title.isEmpty ? String(localized: "Workout") : s.title
        var meta = [Fmt.time(s.startedAt, locale: locale)]
        var spoken = [title, Fmt.time(s.startedAt, locale: locale)]
        if let min = s.durationMin {
            meta.append(StrainFormat.durationText(minutes: min))
            spoken.append(Fmt.spokenDuration(minutes: min, locale: locale))
        }
        meta.append(loadText(s.muscularTrimp))
        spoken.append(spokenStrain(s.strain))
        if let load = s.muscularTrimp { spoken.append(String(localized: "Muscular load \(Fmt.load(load))")) }
        return ActivityListRow.Content(systemImage: "dumbbell", title: title, meta: join(meta),
                                       value: s.strain.map { Fmt.strain($0) }, spoken: spoken.joined(separator: ", "))
    }

    /// A My Day row (`today.my_day`): its symbol and title, start · duration · distance, the load, and a state that is not a
    /// number (pending, uploading, no heart rate) as its word at the end of the meta line, so it is never lost.
    static func myDay(_ item: MyDayItem, locale: Locale = .autoupdatingCurrent) -> ActivityListRow.Content {
        let minutes = StrainFormat.minutes(item.duration)
        var meta = [Fmt.time(item.start, locale: locale)]
        if item.duration >= 60 { meta.append(StrainFormat.durationText(minutes: minutes)) }
        if let m = item.distanceM, m > 0 { meta.append(Fmt.distance(meters: m)) }
        if let load = item.load { meta.append(loadText(load)) }
        let mark = ActivityStateMark.State(item)
        var value: String?
        if case .scored(let strain) = mark {
            value = Fmt.strain(strain)
        } else if let word = mark.word {
            meta.append(word)
        }
        return ActivityListRow.Content(systemImage: item.symbol, title: item.title, meta: join(meta), value: value,
                                       spoken: MyDayRow.spoken(item, showsLoad: true, locale: locale))
    }

    /// "Load 84.6", "Load –".
    static func loadText(_ load: Double?) -> String {
        String(localized: "Load \(Fmt.load(load))", comment: "An activity row's meta: a logged session's muscular load.")
    }

    /// "Strain 9.8", or "No strain" without one.
    static func spokenStrain(_ strain: Double?) -> String {
        strain.map { String(localized: "Strain \(Fmt.strain($0))") }
            ?? String(localized: "No strain", comment: "VoiceOver in an activity row without a strain.")
    }

    /// The parts with " · " between them; a part never breaks inside ("1:05 h", "7.8 km").
    static func join(_ parts: [String]) -> String { MyDayText.join(parts) }
}
