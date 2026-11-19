// What Plans and a plan's page say (Nocturne PR 6 B §6.1, §6.2; build plan F18): the active or paused plan's tile, the plan
// rows, and what VoiceOver hears for a plan, a day and an exercise. Pure, so the tests read every state without a view.
import Foundation

/// The plan the user is on, as Plans' tile shows it: the active plan is the screen's one glow tile (strain blue, a training
/// object); a paused plan is an outline ("not now", F18).
struct PlanTileContent: Equatable {
    enum State: Equatable {
        case active
        case paused
    }

    let planID: UUID
    let state: State
    let name: String
    /// "Active" / "Paused" at the head's left.
    let stateText: String
    /// "Week 6" at the head's right, while active. A paused plan's right ("since Nov 3") needs a paused date the API
    /// does not report.
    let weekText: String?
    /// "Next: Upper A"; paused "Next: Upper A · week 6 waits", or "Resume continues where you stopped." when the next day
    /// is not known.
    let nextText: String?
    /// "Upper/Lower 4×, Active, Week 6, Next: Upper A".
    let spoken: String

    /// - Parameters:
    ///   - week: the enrolment's week, when the platform reported it.
    ///   - nextDay: the day the plan continues with, when known.
    init(planID: UUID, paused: Bool, name: String, week: Int?, nextDay: String?) {
        self.planID = planID
        self.name = name
        state = paused ? .paused : .active
        stateText = paused ? String(localized: "Paused") : String(localized: "Active")
        let next = nextDay.map { String(localized: "Next: \($0)") }
        var spokenParts = [name, stateText]
        if paused {
            weekText = nil
            if let next {
                let waits = week.map {
                    String(localized: "week \($0) waits",
                           comment: "Plans, a paused plan's tile, after \"Next: Upper A · \": the week the plan continues with.")
                }
                nextText = [next, waits].compactMap { $0 }.joined(separator: " · ")
                spokenParts += [next, waits].compactMap { $0 }
            } else {
                nextText = String(localized: "Resume continues where you stopped.")
                spokenParts.append(nextText ?? "")
            }
        } else {
            weekText = week.map { String(localized: "Week \($0)") }
            nextText = next
            spokenParts += [weekText, next].compactMap { $0 }
        }
        spoken = spokenParts.joined(separator: ", ")
    }

    /// The day an enrolment continues with, from the plan's detail: the day at `currentDayIndex` in its week (a plan
    /// without weeks has one set of days).
    static func nextDayName(plan: Plan?, enrollment: Enrollment?) -> String? {
        guard let plan, let enrollment else { return nil }
        return plan.days.first {
            $0.dayIndex == enrollment.currentDayIndex && ($0.week == nil || $0.week == enrollment.currentWeek)
        }?.name
    }
}

/// A plan in Plans' "Built-in" or "My plans": the activity row with the plan's summary as its meta. The active plan has the
/// filled disc with a check (the one filled icon on the screen, "this one"); a paused plan keeps the outline disc and says
/// "Paused".
struct PlanRowContent: Equatable, Identifiable {
    let id: UUID
    let row: ActivityListRow.Content

    /// `status`: the plan the user is on, active or paused; nil for the others.
    init(_ plan: PlanSummary, status: PlanTileContent.State?) {
        id = plan.id
        let active = status == .active
        let state: String? = switch status {
        case .active: String(localized: "Active")
        case .paused: String(localized: "Paused")
        case nil: nil
        }
        let summary = PlanSpeech.summary(goal: plan.goal, daysPerWeek: plan.daysPerWeek, weeks: plan.weeks)
        row = ActivityListRow.Content(
            systemImage: active ? "checkmark" : "list.bullet.rectangle", title: plan.name, meta: plan.summaryText,
            value: nil, spoken: [plan.name, state, summary].compactMap { $0 }.joined(separator: ", "),
            showsValue: false, filledDisc: active)
    }
}

/// What VoiceOver hears where the screen abbreviates ("4 days/week", "5 × 5 @ 100 kg · rest 3:00").
enum PlanSpeech {
    /// "Strength, 3 days a week, 12 weeks".
    static func summary(goal: PlanGoal, daysPerWeek: Int, weeks: Int?) -> String {
        let length = weeks.map { String(localized: "\($0) weeks") } ?? String(localized: "repeating")
        let days = String(localized: "\(daysPerWeek) days a week",
                          comment: "VoiceOver, a plan's summary: how many days a week it trains (\"4 days/week\" on screen).")
        return [goal.title, days, length].joined(separator: ", ")
    }

    /// "Day A, about 55 minutes": a day card's container label.
    static func day(_ name: String, minutes: Int) -> String {
        String(localized: "\(name), about \(Fmt.spokenDuration(minutes: minutes))",
               comment: "VoiceOver, a plan day's card: the day's name and its estimated length (\"Day A, about 55 minutes\").")
    }

    /// "Back squat, 5 sets of 5 at 100 kilograms, rest 3 minutes"; "Superset" first for a superset member.
    static func exercise(_ e: PlanExercise, locale: Locale = .autoupdatingCurrent) -> String {
        let reps = e.repsMin == e.repsMax
            ? "\(e.repsMin)"
            : String(localized: "\(e.repsMin) to \(e.repsMax)",
                     comment: "VoiceOver, a plan exercise's rep range (\"10 to 12\"; \"10–12\" on screen).")
        var prescription = String(localized: "\(e.sets) sets of \(reps)",
                                  comment: "VoiceOver, a plan exercise: sets and reps (\"5 sets of 5\"; \"5 × 5\" on screen).")
        if let target = target(e, locale: locale) { prescription += " " + target }
        let rest = String(localized: "rest \(restDuration(e.restSec, locale: locale))",
                          comment: "VoiceOver, a plan exercise's rest between sets (\"rest 3 minutes\").")
        var parts = [e.exercise.name, prescription, rest]
        if e.supersetGroup != nil { parts.insert(String(localized: "Superset"), at: 0) }
        return parts.joined(separator: ", ")
    }

    /// "at 100 kilograms", "at RPE 8", "at 75 percent of one-rep max", "bodyweight plus 10 kilograms".
    static func target(_ e: PlanExercise, locale: Locale = .autoupdatingCurrent) -> String? {
        guard let v = e.targetValue else { return e.targetKind == .bodyweight ? TargetKind.bodyweight.title : nil }
        let kg = Measurement(value: v, unit: UnitMass.kilograms)
            .formatted(.measurement(width: .wide, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...1))).locale(locale))
        switch e.targetKind {
        case .kg:
            return String(localized: "at \(kg)", comment: "VoiceOver, a plan exercise's target weight (\"at 100 kilograms\").")
        case .rpe:
            return String(localized: "at RPE \(Fmt.kgNumber(v))", comment: "VoiceOver, a plan exercise's target effort (\"at RPE 8\").")
        case .pct1rm:
            return String(localized: "at \(Fmt.kgNumber(v)) percent of one-rep max",
                          comment: "VoiceOver, a plan exercise's target as a share of the one-rep max (\"75 % 1RM\" on screen).")
        case .bodyweight:
            return String(localized: "bodyweight plus \(kg)",
                          comment: "VoiceOver, a plan exercise's added weight on bodyweight (\"BW + 10 kg\" on screen).")
        }
    }

    /// "3 minutes", "1 minute, 30 seconds".
    static func restDuration(_ seconds: Int, locale: Locale = .autoupdatingCurrent) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.minutes, .seconds], width: .wide).locale(locale))
    }
}
