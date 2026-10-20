// The journal, behavior impact and the sleep planner for previews, tests and
// demo mode, shaped like API.md's examples (the built-in ids are the platform's).
import Foundation

enum MockJournal {
    static let alcohol = UUID(uuidString: "bad67883-7fb1-5f98-9761-feba0a813536") ?? UUID()
    static let drinks = UUID(uuidString: "8cf20bff-9124-5fba-95e5-fd2083b90318") ?? UUID()
    static let lastCaffeine = UUID(uuidString: "89a9dd86-4767-5eed-9718-24370f52078b") ?? UUID()
    static let sauna = UUID(uuidString: "ce48b6cf-43e3-5c6b-baf9-0a13e5d767d9") ?? UUID()
    static let lateMeal = UUID(uuidString: "4d1e6f2a-0b3c-5d4e-8f9a-1b2c3d4e5f60") ?? UUID()
    static let screens = UUID(uuidString: "5e2f7a3b-1c4d-5e6f-9a0b-2c3d4e5f6a71") ?? UUID()
    static let magnesium = UUID(uuidString: "6f3a8b4c-2d5e-5f7a-8b1c-3d4e5f6a7b82") ?? UUID()
    static let stretching = UUID(uuidString: "7a4b9c5d-3e6f-5a8b-9c2d-4e5f6a7b8c93") ?? UUID()
    static let sick = UUID(uuidString: "8b5c0d6e-4f7a-5b9c-8d3e-5f6a7b8c9da4") ?? UUID()
    static let meeting = UUID(uuidString: "3f1c2a9e-7b6d-4c5e-9a8f-0e1d2c3b4a55") ?? UUID()

    static let behaviors: [Behavior] = [
        b(alcohol, "alcohol", "Alcohol", "Alkohol", .substances, .yesNo, sort: 10),
        b(drinks, "drinks", "Drinks", "Getränke", .substances, .count, sort: 20),
        b(lastCaffeine, "last_caffeine", "Last caffeine", "Letztes Koffein", .substances, .time, sort: 40),
        b(screens, "screens_in_bed", "Screens in bed", "Bildschirm im Bett", .sleep, .yesNo, sort: 10),
        b(sauna, "sauna", "Sauna", "Sauna", .recovery, .yesNo, sort: 10),
        b(stretching, "stretching", "Stretching", "Dehnen", .recovery, .yesNo, sort: 20),
        b(magnesium, "magnesium", "Magnesium", "Magnesium", .supplements, .yesNo, sort: 10, enabled: false),
        b(sick, "feeling_sick", "Feeling sick", "Krank gefühlt", .health, .yesNo, sort: 10, enabled: false),
        b(lateMeal, "late_meal", "Late meal", "Spätes Essen", .lifestyle, .yesNo, sort: 10),
        b(meeting, "late-screen-meeting", "Late screen meeting", "Spätes Online-Meeting", .custom, .yesNo,
          sort: 0, custom: true),
    ]

    private static func b(_ id: UUID, _ slug: String, _ en: String, _ de: String, _ category: BehaviorCategory,
                          _ kind: BehaviorKind, sort: Int, enabled: Bool = true, custom: Bool = false) -> Behavior {
        let german = Locale.current.language.languageCode?.identifier == "de"
        return Behavior(id: id, slug: slug, name: german ? de : en, nameEn: en, nameDe: de, category: category,
                        kind: kind, defaultOn: enabled, enabled: enabled, isCustom: custom, sort: sort)
    }

    /// Yesterday as the API example answers it; other days unanswered.
    static func journal(day: String, today: Date = .now) -> JournalDay {
        let yesterday = DayFormat.string(from: DayFormat.shift(today, days: -1))
        let editable = isEditable(day, today: today)
        guard day == yesterday else {
            return JournalDay(day: day, answered: false, answeredAt: nil, editable: editable, entries: [])
        }
        return JournalDay(day: day, answered: true, answeredAt: today.addingTimeInterval(-3600), editable: editable,
                          entries: [
                              JournalEntry(behaviorId: alcohol, valueBool: true),
                              JournalEntry(behaviorId: drinks, valueBool: true, valueNum: 2),
                              JournalEntry(behaviorId: lastCaffeine, valueBool: true, valueTime: "16:30"),
                              JournalEntry(behaviorId: sauna, valueBool: true),
                              JournalEntry(behaviorId: screens, valueBool: false),
                              JournalEntry(behaviorId: stretching, valueBool: false),
                              JournalEntry(behaviorId: lateMeal, valueBool: false),
                              JournalEntry(behaviorId: meeting, valueBool: false),
                          ])
    }

    /// Within the last 14 days and not in the future (the platform's rule).
    static func isEditable(_ day: String, today: Date = .now) -> Bool {
        guard let date = DayFormat.date(from: day) else { return false }
        let start = Calendar.current.startOfDay(for: today)
        return date <= start && date >= DayFormat.shift(start, days: -14)
    }

    static let impacts = BehaviorImpacts(
        windowDays: 90, computedAt: Calendar.current.date(bySettingHour: 6, minute: 45, second: 0, of: .now) ?? .now,
        impacts: [
            BehaviorImpact(behaviorId: alcohol, slug: "alcohol", name: "Alcohol", kind: .yesNo, status: .unlocked,
                           nYes: 12, nNo: 31, needed: ImpactNeeded(yes: 0, no: 0),
                           recovery: BehaviorEffect(delta: -14.2, ciLo: -19.8, ciHi: -8.1, significant: true, nYes: 12, nNo: 31),
                           hrvPct: BehaviorEffect(delta: -11.5, ciLo: -17.0, ciHi: -5.9, significant: true, nYes: 12, nNo: 30),
                           sleepPerformance: BehaviorEffect(delta: -3.0, ciLo: -8.2, ciHi: 2.4, significant: false,
                                                            nYes: 12, nNo: 31)),
            BehaviorImpact(behaviorId: stretching, slug: "stretching", name: "Stretching", kind: .yesNo,
                           status: .unlocked, nYes: 18, nNo: 24, needed: ImpactNeeded(yes: 0, no: 0),
                           recovery: BehaviorEffect(delta: 4.6, ciLo: 0.8, ciHi: 8.3, significant: true, nYes: 18, nNo: 24),
                           hrvPct: nil,
                           sleepPerformance: BehaviorEffect(delta: 1.2, ciLo: -2.1, ciHi: 4.4, significant: false,
                                                            nYes: 18, nNo: 24)),
            BehaviorImpact(behaviorId: sauna, slug: "sauna", name: "Sauna", kind: .yesNo, status: .locked,
                           nYes: 2, nNo: 20, needed: ImpactNeeded(yes: 3, no: 0),
                           recovery: nil, hrvPct: nil, sleepPerformance: nil),
        ])

    /// `GET /v1/sleep/plan?wake=HH:MM` from the mock history, by the platform's formula.
    static func sleepPlan(wake hhmm: String, now: Date = .now) -> SleepPlan {
        let cal = Calendar.current
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        let today = MockData.todayScore
        var wake = cal.date(bySettingHour: parts.first ?? 7, minute: parts.last ?? 0, second: 0, of: now) ?? now
        if wake <= now { wake = cal.date(byAdding: .day, value: 1, to: wake) ?? wake }
        let basis = SleepPlanBasis(base: MockData.sleepBase,
                                   strainTopup: min(60, Int(((today.strain ?? 0) * 3).rounded())),
                                   debtTopup: min(60, Int((Double(today.sleepDebtMin ?? 0) * 0.3).rounded())),
                                   napCredit: min(90, today.napMin ?? 0), efficiency: 90)
        let need = basis.base + basis.strainTopup + basis.debtTopup - basis.napCredit
        let inBed = Int((Double(need) / Double(basis.efficiency) * 100).rounded())
        func bedtime(_ share: Double) -> Date { wake.addingTimeInterval(-share * Double(inBed) * 60) }
        return SleepPlan(wake: wake, needMin: need, inBedMin: inBed, efficiency: basis.efficiency,
                         bedtime100: bedtime(1), bedtime85: bedtime(0.85), bedtime70: bedtime(0.7), basis: basis)
    }
}
