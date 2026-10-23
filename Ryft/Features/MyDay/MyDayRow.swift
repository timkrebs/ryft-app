import SwiftUI

/// One My Day row (ui.md §2.2), shared by the card, the full screen and Strain's list:
/// `[icon 44] 14 [name · times · badges] Spacer [state mark]`. Layout only: the container makes it a button.
struct MyDayRow: View {
    enum Style {
        /// On the card: no surface of its own (the card doesn't nest surfaces), no chevron.
        case card
        /// The full screen and Strain: its own tile, a chevron when it opens something.
        case tile
    }

    let item: MyDayItem
    var style: Style = .card
    /// A chevron at the trailing edge (tile style, rows that open a detail).
    var showsChevron = false
    /// Train's muscular load beside the strain (Strain's list).
    var showsLoad = false
    /// R4's Retry (A2's uploader); nil shows none.
    var retry: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    private var isLarge: Bool { typeSize.isAccessibilitySize }
    private var iconSize: CGFloat { isLarge ? 36 : 44 }
    private var mark: ActivityStateMark.State { ActivityStateMark.State(item) }
    private var isMissingSleep: Bool { item.kind.isMissingSleep }

    var body: some View {
        // The missing night is one line: centred on its icon.
        HStack(alignment: isMissingSleep ? .center : .top, spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: item.title)
                    .font(.ryft(.body))
                    .foregroundStyle(isMissingSleep ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(isLarge ? 3 : 1)
                    .truncationMode(.tail)
                if !isMissingSleep {
                    Text(verbatim: MyDayRow.detail(item, locale: locale))
                        .font(.ryft(.caption))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.sources.isEmpty {
                    SourceBadges(sources: item.sources, merged: item.isMerged)
                        .padding(.top, 2)
                }
                // At the large sizes the mark goes under the text, with its word.
                if isLarge, mark != .none || showsLoad && item.load != nil {
                    trailing.padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isLarge { trailing.frame(minWidth: 44, alignment: .trailing) }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(minHeight: 28)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, style == .card ? 6 : 0)
        .padding(style == .tile ? 14 : 0)
        .frame(minHeight: 60, alignment: .topLeading)
        .background {
            if style == .tile {
                RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous).fill(Theme.surface)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: MyDayRow.spoken(item, showsLoad: showsLoad, locale: locale)))
        .accessibilityActions {
            if let retry { Button(String(localized: "Retry", comment: "My Day: send a failed upload again."), action: retry) }
        }
    }

    private var icon: some View {
        let sleep = item.kind.isSleep
        let tint = isMissingSleep ? Theme.textTertiary : sleep ? Theme.metricSleep : Theme.accent
        let fill = isMissingSleep ? Theme.surfaceRaised : sleep ? Theme.metricSleep.opacity(0.14) : Theme.accent.opacity(0.12)
        return Image(systemName: item.symbol)
            .font(.system(size: isLarge ? 15 : 18, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: iconSize, height: iconSize)
            .background(fill, in: Circle())
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(alignment: .center, spacing: 8) {
            if showsLoad, let load = item.load { LoadChip(load: load) }
            ActivityStateMark(state: mark, retry: retry)
        }
    }

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
        return parts.joined(separator: " · ")
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
        if let word = ActivityStateMark.State(item).word { parts.append(word) }
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

extension MyDayItem.Kind {
    /// "No sleep recorded".
    var isMissingSleep: Bool {
        if case .missingSleep = self { return true }
        return false
    }

    /// The row opens something: sleep (Sleep), a workout, a session. Activities open once A2's detail exists;
    /// a missing night has nothing to open yet (Add sleep is A2's).
    var opensDetail: Bool {
        switch self {
        case .sleep, .workout, .session: return true
        case .missingSleep, .activity: return false
        }
    }
}

#Preview("My Day rows", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MockMyDay.gallery) { item in MyDayRow(item: item, retry: MockMyDay.failed(item) ? {} : nil) }
        }
    }
}

#Preview("My Day rows · tiles", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MockMyDay.gallery) { MyDayRow(item: $0, style: .tile, showsChevron: $0.kind.opensDetail, showsLoad: true) }
        }
    }
}

#Preview("My Day rows · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MockMyDay.gallery.prefix(5)) { MyDayRow(item: $0) }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("My Day rows · AX5", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(MockMyDay.gallery.suffix(4)) { MyDayRow(item: $0, style: .tile, showsChevron: true) }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
