import SwiftUI

/// One My Day row (ui.md §2.2; PR 6 B §9, S6): a thin adapter from a `MyDayItem` to `ActivityListRow`, shared by the card and
/// the full screen. The sport's disc (the night's glyph in `metricSleep`), the title, the facts, the sources as badges on a
/// second meta line, and in the value's place the night's time asleep ("7:48" "h") or the activity's state mark (the strain,
/// or the state's word). The missing night is the dashed row with "Add sleep". Layout only: the container makes it a button.
struct MyDayRow: View {
    enum Style {
        /// On the card: no surface of its own (the card doesn't nest surfaces), no chevron.
        case card
        /// The full screen: its own tile, a chevron when it opens something.
        case tile
    }

    let item: MyDayItem
    var style: Style = .card
    /// A chevron at the trailing edge (tile style, rows that open a detail).
    var showsChevron = false
    /// R4's Retry (A2's uploader); nil shows none.
    var retry: (() -> Void)?
    /// The missing night's "Add sleep" (`activities.manual`); nil shows none.
    var addSleep: (() -> Void)?

    @Environment(\.locale) private var locale

    var body: some View {
        ActivityListRow(content: MyDayRow.content(item, locale: locale), accessory: showsChevron ? .chevron : .none,
                        style: rowStyle, retry: retry, action: action)
    }

    private var rowStyle: ActivityListRow.Style {
        if item.kind.isMissingSleep { return .dashed }
        return style == .tile ? .tile : .card
    }

    /// "Add sleep" on the missing night, when it can be added.
    private var action: ActivityListRow.Action? {
        guard item.kind.isMissingSleep, let addSleep else { return nil }
        return ActivityListRow.Action(title: Text("Add sleep"), identifier: "myday.addSleep", perform: addSleep)
    }

    /// The row as `ActivityListRow` draws it. The night: its time asleep as the value with "h", its glyph in `metricSleep`, and
    /// its upload's word under the value while a night the user added uploads. An activity: its state mark. A recording in
    /// progress: no value. The missing night: the dashed row's glyph and title, nothing else.
    static func content(_ item: MyDayItem, locale: Locale = .autoupdatingCurrent) -> ActivityListRow.Content {
        if item.kind.isMissingSleep {
            return ActivityListRow.Content(systemImage: missingNightSymbol, title: item.title, meta: nil, value: nil,
                                           spoken: spoken(item, locale: locale), showsValue: false)
        }
        let mark = ActivityStateMark.State(item)
        let asleep = item.kind.isSleep && item.duration >= 60 ? Fmt.clock(minutes: Int((item.duration / 60).rounded())) : nil
        var content = ActivityListRow.Content(systemImage: item.symbol, title: item.title, meta: detail(item, locale: locale),
                                              value: asleep, spoken: spoken(item, locale: locale),
                                              showsValue: asleep != nil || mark != .none)
        content.badges = item.sources.map(\.title)
        content.mark = mark == .none ? nil : mark
        content.glyphInk = item.kind.isSleep ? .sleep : .primary
        if asleep != nil {
            content.valueUnit = String(localized: "h",
                                       comment: "Hours, the unit after a clock duration on Today's Sleep tile and on Sleep's tiles: \"7:48 h\", \"0:30 h\".")
        }
        return content
    }

    /// The missing night's glyph: the bed, filled, in `textTertiary` on the dashed disc (B §9.2).
    nonisolated static let missingNightSymbol = "bed.double.fill"

    // MARK: words

    /// "07:12–07:48 · 52m · 8.4 km": times, the duration, the distance; parts that don't exist are left out.
    static func detail(_ item: MyDayItem, locale: Locale = .autoupdatingCurrent) -> String {
        let start = Fmt.time(item.start, locale: locale)
        let range = item.isRecording
            ? String(localized: "\(start)–now", comment: "My Day row: a recording that is still running, from its start.")
            : "\(start)–\(Fmt.time(item.end, locale: locale))"
        var parts = [range]
        if item.duration >= 60 { parts.append(Fmt.duration(seconds: item.duration)) }
        if let m = item.distanceM, m > 0 { parts.append(Fmt.distance(meters: m)) }
        return MyDayText.join(parts)
    }

    /// One VoiceOver sentence, in the order the row shows it (ui.md §2.7): "Running, 6:40 AM to 7:32 AM,
    /// 48 minutes, 8.4 kilometres, Strain 10.6, Sources: Garmin Connect and RYFT, merged".
    static func spoken(_ item: MyDayItem, showsLoad: Bool = false, locale: Locale = .autoupdatingCurrent) -> String {
        if item.kind.isMissingSleep { return item.title }
        let start = Fmt.time(item.start, locale: locale)
        var parts = [item.title]
        parts.append(item.isRecording
            ? String(localized: "from \(start), still recording", comment: "VoiceOver: a recording in progress.")
            : String(localized: "\(start) to \(Fmt.time(item.end, locale: locale))", comment: "VoiceOver: a time range."))
        if item.duration >= 60 { parts.append(spokenDuration(item.duration)) }
        if let m = item.distanceM, m > 0 {
            parts.append(Measurement(value: m, unit: UnitLength.meters)
                .formatted(.measurement(width: .wide, usage: .road, numberFormatStyle: .number.precision(.fractionLength(1)))
                    .locale(locale)))
        }
        if let word = ActivityStateMark.State(item).spoken { parts.append(word) }
        if showsLoad, let load = item.load { parts.append(String(localized: "Muscular load \(Fmt.load(load))")) }
        let sources = SourceBadges.spoken(item.sources, merged: item.isMerged)
        if !sources.isEmpty { parts.append(sources) }
        return parts.joined(separator: ", ")
    }

    /// "48 minutes", "7 hours, 48 minutes".
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.unitsStyle = .full
        f.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        return f.string(from: (seconds / 60).rounded() * 60) ?? Fmt.duration(seconds: seconds)
    }
}

/// My Day's one-line facts ("07:12–07:48 · 52m · 8.4 km") break only between parts: never inside a duration
/// ("1h 08m") or a distance, and the bullet trails its line instead of starting the next.
enum MyDayText {
    static func join(_ parts: [String]) -> String {
        parts.map(keepTogether).joined(separator: "\u{00A0}· ")
    }

    /// Spaces become no-break spaces.
    static func keepTogether(_ part: String) -> String {
        part.replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}

extension MyDayItem.Kind {
    /// "No sleep recorded".
    var isMissingSleep: Bool {
        if case .missingSleep = self { return true }
        return false
    }

}

// MARK: - previews (dark only)

/// Every row of the gallery: sleep, merged, scored, a Train session, uploading, strain pending, not uploaded, no heart rate,
/// added by you, and the missing night.
private struct MyDayRowGallery: View {
    let style: MyDayRow.Style

    var body: some View {
        let rows = VStack(alignment: .leading, spacing: style == .tile ? 8 : 0) {
            ForEach(MockMyDay.gallery) { item in
                MyDayRow(item: item, style: style, showsChevron: style == .tile && item.opensDetail,
                         retry: MockMyDay.failed(item) ? {} : nil, addSleep: item.kind.isMissingSleep ? {} : nil)
            }
        }
        if style == .tile { rows } else { Card { rows } }
    }
}

#Preview("My Day rows · card", traits: .sizeThatFitsLayout) {
    DarkPreview { MyDayRowGallery(style: .card) }
}

#Preview("My Day rows · tiles", traits: .sizeThatFitsLayout) {
    DarkPreview { MyDayRowGallery(style: .tile) }
}

#Preview("My Day rows · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { MyDayRowGallery(style: .tile) }
        .environment(\.dynamicTypeSize, .accessibility3)
}
