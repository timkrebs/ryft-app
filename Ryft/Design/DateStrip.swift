import SwiftUI

/// The week strip (Strain's, now shared with My Day): one chip per day, oldest first, with the weekday's
/// initial, the day's strain in a small ring and its scoring marker. Tapping a chip selects that day.
struct DateStrip: View {
    /// One day of the strip.
    struct Day: Identifiable, Equatable {
        let date: Date
        let strain: Double?
        let isSelected: Bool
        /// Scored, pending or no data (`DailyScore.scoringState`).
        var marker: DayMarker.Kind?
        var id: Date { date }
        var initial: String { date.formatted(.dateTime.weekday(.narrow)) }
        var name: String { date.formatted(.dateTime.weekday(.wide)) }
        var shortValue: String { strain.map { String(Int($0.rounded())) } ?? Fmt.placeholder }
        var spokenValue: String {
            let value = String(localized: "Strain \(Fmt.strain(strain))")
            return marker?.spoken.map { "\(value), \($0)" } ?? value
        }
        /// `datestrip.day.2026-10-22`: UI tests find a day by its date.
        var identifier: String { "datestrip.day.\(DayFormat.string(from: date))" }
    }

    /// The ring's full scale: strain runs 0–21 (`MetricSpec.strain`).
    static let maxStrain = 21.0
    /// Strain and My Day show a week: today and the six days before.
    static let length = 7

    let days: [Day]
    let select: (Date) -> Void

    /// `count` days ending on `today` (start of day), oldest first; `selected` is highlighted. `score` reads the
    /// cached score of a day.
    static func week(endingAt today: Date, selected: Date, count: Int = DateStrip.length,
                     calendar: Calendar = .current, score: (Date) -> DailyScore?) -> [Day] {
        (0..<count).reversed().map { offset in
            let day = DayFormat.shift(today, days: -offset)
            let s = score(day)
            return Day(date: day, strain: s?.strain, isSelected: calendar.isDate(day, inSameDayAs: selected),
                       marker: DayMarker.kind(for: s))
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                Button {
                    select(day.date)
                } label: {
                    VStack(spacing: 6) {
                        Text(day.initial)
                            .font(.ryft(.caption))
                            .foregroundStyle(day.isSelected ? Theme.textPrimary : Theme.textTertiary)
                        ScoreRing(progress: day.strain.map { $0 / Self.maxStrain }, size: 36, lineWidth: 3,
                                  color: Theme.metricStrain,
                                  accessibilityLabel: Text(day.name), accessibilityValue: Text(day.spokenValue)) {
                            Text(day.shortValue)
                                .font(.ryftNumber(size: 11))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        DayMarker(kind: day.marker)
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(day.isSelected ? Theme.surface : .clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(day.isSelected ? .isSelected : [])
                .accessibilityIdentifier(day.identifier)
            }
        }
    }
}

#Preview("Date strip", traits: .sizeThatFitsLayout) {
    let today = Calendar.current.startOfDay(for: .now)
    let scores = Dictionary(MockData.history.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    SchemePair {
        VStack(spacing: 16) {
            DateStrip(days: DateStrip.week(endingAt: today, selected: today) { scores[DayFormat.string(from: $0)] }) { _ in }
            // A past day selected; the oldest two without a score.
            DateStrip(days: DateStrip.week(endingAt: today, selected: DayFormat.shift(today, days: -2)) { day in
                day < DayFormat.shift(today, days: -4) ? nil : scores[DayFormat.string(from: day)]
            }) { _ in }
        }
    }
}

#Preview("Date strip · AX3", traits: .sizeThatFitsLayout) {
    let today = Calendar.current.startOfDay(for: .now)
    let scores = Dictionary(MockData.history.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
    SchemePair {
        DateStrip(days: DateStrip.week(endingAt: today, selected: today) { scores[DayFormat.string(from: $0)] }) { _ in }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
