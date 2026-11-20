// The week strip (Strain's, shared with My Day; Nocturne, docs/work/2026-11-16-nocturne/design-pr6-b-train.md S11 and §9.2, the
// `b-18` draft): one chip per day, oldest first, with the weekday's initial, the day's strain in a small strain-blue ring and a dot
// under it (Volt under today, an outline under a day whose score is pending). Tapping a chip selects that day.
import SwiftUI

struct DateStrip: View {
    /// One day of the strip.
    struct Day: Identifiable, Equatable {
        let date: Date
        let strain: Double?
        let isSelected: Bool
        /// Scored, pending or no data (`DailyScore.scoringState`).
        var marker: DayMarker.Kind?
        /// The strip's day that is today: the Volt dot, and "Today" for VoiceOver. `week(endingAt:…)` sets it on its last day.
        var isToday = false
        var id: Date { date }
        var initial: String { date.formatted(.dateTime.weekday(.narrow)) }
        var name: String { date.formatted(.dateTime.weekday(.wide)) }
        var shortValue: String { strain.map { String(Int($0.rounded())) } ?? Fmt.placeholder }
        /// "Strain 15", then "Today" and "not scored yet" when they apply; VoiceOver reads it after the weekday, and "selected"
        /// from the trait.
        var spokenValue: String {
            var parts = [String(localized: "Strain \(Fmt.strain(strain))")]
            if isToday { parts.append(String(localized: "Today")) }
            if let pending = marker?.spoken { parts.append(pending) }
            return parts.joined(separator: ", ")
        }
        /// `datestrip.day.2026-10-22`: UI tests find a day by its date.
        var identifier: String { "datestrip.day.\(DayFormat.string(from: date))" }
        /// The ring's arc, 0…1 of `DateStrip.maxStrain`; `nil` draws the empty ring.
        var arc: Double? { strain.map { min(max($0 / DateStrip.maxStrain, 0), 1) } }
    }

    /// The ring's full scale: strain runs 0–21 (`MetricSpec.strain`).
    static let maxStrain = 21.0
    /// Strain and My Day show a week: today and the six days before.
    static let length = 7

    // S11's numbers.
    /// The ring: 32 pt, a 2.5 pt stroke, its track ink at 7 %.
    nonisolated static let ringSize: CGFloat = 32, ringLine: CGFloat = 2.5, trackOpacity = 0.07
    /// The dot under the ring: 4 pt; a pending day's is a 1 pt outline at ink 35 %.
    nonisolated static let dotSize: CGFloat = 4, pendingDotLine: CGFloat = 1, pendingDotOpacity = 0.35
    /// Initial → ring → dot, and the chip's padding above and below (the content is 64 high, the chip 80).
    nonisolated static let chipSpacing: CGFloat = 6, chipPadding: CGFloat = 8
    /// The selected chip's `surface` fill.
    nonisolated static let selectionRadius: CGFloat = 16
    /// From AX1 the strip scrolls sideways, each chip this wide, the selected one centred.
    nonisolated static let scrollChipWidth: CGFloat = 64

    let days: [Day]
    let select: (Date) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// `count` days ending on `today` (start of day), oldest first; `selected` is highlighted, `today` gets the Volt dot.
    /// `score` reads the cached score of a day.
    static func week(endingAt today: Date, selected: Date, count: Int = DateStrip.length,
                     calendar: Calendar = .current, score: (Date) -> DailyScore?) -> [Day] {
        (0..<count).reversed().map { offset in
            let day = DayFormat.shift(today, days: -offset)
            let s = score(day)
            return Day(date: day, strain: s?.strain, isSelected: calendar.isDate(day, inSameDayAs: selected),
                       marker: DayMarker.kind(for: s), isToday: offset == 0)
        }
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                scrolling
            } else {
                HStack(spacing: 0) {
                    ForEach(days) { day in
                        chip(day).frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// AX1+: the chips at 64 pt in a sideways scroll, the selected one centred (and kept centred when the selection changes).
    private var scrolling: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(days) { day in
                        chip(day).frame(width: Self.scrollChipWidth).id(day.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onAppear { centre(proxy, animated: false) }
            .onChange(of: days.first(where: \.isSelected)?.id) { centre(proxy, animated: true) }
        }
    }

    private func centre(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let id = days.first(where: \.isSelected)?.id else { return }
        withAnimation(animated ? Theme.Motion.respecting(reduceMotion) : nil) {
            proxy.scrollTo(id, anchor: .center)
        }
    }

    private func chip(_ day: Day) -> some View {
        Button {
            select(day.date)
        } label: {
            VStack(spacing: Self.chipSpacing) {
                Text(day.initial)
                    .font(.ryft(.caption))
                    .foregroundStyle(day.isSelected ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                DateStripRing(arc: day.arc, value: day.shortValue)
                DateStripDot(isToday: day.isToday, marker: day.marker)
            }
            .padding(.vertical, Self.chipPadding)
            .frame(maxWidth: .infinity)
            .background {
                if day.isSelected {
                    RoundedRectangle(cornerRadius: Self.selectionRadius, style: .continuous).fill(Theme.surface)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day.name))
        .accessibilityValue(Text(day.spokenValue))
        .accessibilityAddTraits(day.isSelected ? .isSelected : [])
        .accessibilityIdentifier(day.identifier)
    }
}

/// The 32 pt ring: the 7 % track, the strain arc in `metricStrain` from 12 o'clock with round caps, the whole-number strain in
/// ink inside (an unscored day: the empty ring and "–" in `textTertiary`). Decoration: the chip speaks for it.
private struct DateStripRing: View {
    let arc: Double?
    let value: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.textPrimary.opacity(DateStrip.trackOpacity), lineWidth: DateStrip.ringLine)
            if let arc, arc > 0 {
                Circle()
                    .trim(from: 0, to: arc)
                    .stroke(Theme.metricStrain, style: StrokeStyle(lineWidth: DateStrip.ringLine, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(verbatim: value)
                .font(.ryftNumber(size: 11))
                .foregroundStyle(arc == nil ? Theme.textTertiary : Theme.textPrimary)
                .lineLimit(1)
        }
        .frame(width: DateStrip.ringSize, height: DateStrip.ringSize)
        .accessibilityHidden(true)
    }
}

/// The 4 pt dot under a chip's ring: Volt under today (the one signal in the strip), a 1 pt outline at ink 35 % under another day
/// whose score is pending, nothing otherwise. Today's dot wins over pending; VoiceOver says both.
private struct DateStripDot: View {
    let isToday: Bool
    let marker: DayMarker.Kind?

    var body: some View {
        ZStack {
            if isToday {
                Circle().fill(Theme.signal)
            } else if marker == .pending {
                Circle().strokeBorder(Theme.textPrimary.opacity(DateStrip.pendingDotOpacity), lineWidth: DateStrip.pendingDotLine)
            }
        }
        .frame(width: DateStrip.dotSize, height: DateStrip.dotSize)
        .accessibilityHidden(true)
    }
}

// MARK: previews

/// The preview's week: the board's strains ending today; `selected` days back is selected, `pending` days back is pending, the
/// days from `unscoredFrom` back have no score.
@MainActor
private func previewWeek(selected: Int = 0, pending: Int? = nil, unscoredFrom: Int = 99) -> [DateStrip.Day] {
    let today = Calendar.current.startOfDay(for: .now)
    let strains: [Double] = [12.4, 11, 12, 16, 6, 15, 15]
    return (0..<DateStrip.length).reversed().map { back in
        DateStrip.Day(date: DayFormat.shift(today, days: -back), strain: back >= unscoredFrom ? nil : strains[back],
                      isSelected: back == selected, marker: back == pending ? .pending : (back >= unscoredFrom ? nil : .scored),
                      isToday: back == 0)
    }
}

#Preview("Date strip", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 16) {
            DateStrip(days: previewWeek()) { _ in }
            // A past day selected, yesterday pending, the oldest two without a score.
            DateStrip(days: previewWeek(selected: 2, pending: 1, unscoredFrom: 5)) { _ in }
            // Today pending: the Volt dot wins; VoiceOver says both.
            DateStrip(days: previewWeek(selected: 3, pending: 0)) { _ in }
        }
    }
}

#Preview("Date strip · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 16) {
            DateStrip(days: previewWeek()) { _ in }
            DateStrip(days: previewWeek(selected: 3, pending: 1, unscoredFrom: 5)) { _ in }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
