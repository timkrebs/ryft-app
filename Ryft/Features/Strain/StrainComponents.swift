import SwiftUI

/// Icon and display name per `Workout.activity` (names from HealthKitManager.activityName). The sport
/// catalogue (`Sport`) comes first; this keeps only what has no sport.
enum ActivityStyle {
    static func icon(for activity: String) -> String {
        if let sport = Sport(healthKitActivity: activity) { return sport.symbol }
        switch activity {
        case "elliptical": return "figure.elliptical"
        case "stairs": return "figure.stair.stepper"
        case "core": return "figure.core.training"
        case "xc_skiing": return "figure.skiing.crosscountry"
        case "snowboarding": return "figure.snowboarding"
        case "cooldown": return "figure.cooldown"
        default: return "figure.mixed.cardio"
        }
    }

    /// My Day's name for a workout (and Strain's list behind `today.my_day`): the catalogue's, so a tracker's run
    /// and a RYFT run read the same; "Workout" for a tracker's unspecified one. `name(for:)` keeps the shipped
    /// names until the flag goes.
    static func title(for activity: String) -> String {
        if activity != "other", let sport = Sport(healthKitActivity: activity) { return sport.name }
        return name(for: activity)
    }

    static func name(for activity: String) -> String {
        switch activity {
        case "running": return String(localized: "Run")
        case "walking": return String(localized: "Walk")
        case "hiking": return String(localized: "Hike")
        case "cycling": return String(localized: "Ride")
        case "swimming": return String(localized: "Swim")
        case "strength": return String(localized: "Strength")
        case "functional_strength": return String(localized: "Functional strength")
        case "hiit": return String(localized: "HIIT")
        case "xc_skiing": return String(localized: "Cross-country ski")
        case "other": return String(localized: "Workout")
        default: return activity.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// A row in Strain's activity list.
enum ActivityItem: Identifiable {
    /// A workout, with its logged Train session when `session_id` matches.
    case workout(Workout, SessionSummary?)
    /// A logged session no workout points at (yet).
    case session(SessionSummary)

    var id: UUID {
        switch self {
        case .workout(let w, _): return w.id
        case .session(let s): return s.id
        }
    }

    var start: Date {
        switch self {
        case .workout(let w, _): return w.start
        case .session(let s): return s.startedAt
        }
    }
}

/// A strain as a row's value (PR 6 B §9.1, T6B.6): the bare numeral, 20 Light in ink, as `ActivityListRow`'s value, growing
/// with Dynamic Type like it (`.title3`); without one "–" in `textTertiary`. No capsule and no tint: numbers stay ink (L27). My
/// Day's state marks (a scored activity, the last strain beside an upload) and its screen's day strain use it.
struct StrainPill: View {
    let strain: Double?

    @ScaledMetric(relativeTo: .title3) private var size: CGFloat = ActivityListRowSpec.valueSize

    init(strain: Double?) {
        self.strain = strain
    }

    var body: some View {
        Text(Fmt.strain(strain))
            .font(.ryftNumber(size: size, weight: .light))
            .foregroundStyle(Self.ink(strain))
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(Text("Strain \(Fmt.strain(strain))"))
    }

    /// Ink for a strain, `textTertiary` for the dash.
    static func ink(_ strain: Double?) -> Color { strain == nil ? Theme.textTertiary : Theme.textPrimary }
}

// MARK: - the hero

/// The numeral, its caption (with the 7-day change), the split and the ruler (§P5-3.1 rows 3–6; §P5-4 row 2). A new day or
/// workout cross-fades the numeral (250 ms, none under Reduce Motion). The ruler leaves `rulerFollowingGap` to the zones
/// tile under it, so the tile's top is the ruler's top + 56.
struct StrainHeroView: View {
    let hero: StrainHero
    /// The day or the workout: a new one cross-fades the numeral.
    let key: String
    var numeralStyle: DotNumeral.Style = .dots
    /// The numeral's VoiceOver label while there is no strain ("Loading this day", a workout's "No strain"); nil: the
    /// caption's sentence ("No strain recorded for this day."), or hidden without one (the failure's message speaks).
    var pendingLabel: String?
    /// `strain` (the screen) or `workout`: the identifiers' prefix.
    var identifierPrefix = "strain"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            numeral
            caption
                .padding(.top, StrainLayout.captionGap)
            if let split = hero.split {
                Text(verbatim: split)
                    .font(.ryft(.caption))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.top, StrainLayout.splitGap)
                    // In the numeral's value.
                    .accessibilityHidden(true)
            }
            RulerScale(range: StrainHero.scale, value: hero.strain, zone: StrainHero.zone, zoneStyle: .strain,
                       tickCount: RulerScale.Ticks.strain, labels: StrainHero.rulerLabels, size: .regular,
                       accessibilityLabel: Text("Strain scale", comment: "VoiceOver label of a strain ruler (0 to 21)."),
                       accessibilityValue: Text(verbatim: hero.rulerValue), followingGap: StrainLayout.rulerFollowingGap)
                .accessibilityIdentifier("\(identifierPrefix).ruler")
                .padding(.top, StrainLayout.rulerGap)
                // The gap the ruler was told about: its labels hang into it, and the next block starts under it.
                .padding(.bottom, StrainLayout.rulerFollowingGap)
        }
    }

    private var numeral: some View {
        let label = hero.numeralLabel ?? pendingLabel ?? hero.missingCaption ?? ""
        let fadeKey = "\(key)|\(hero.numeral ?? "")"
        return ZStack {
            DotNumeral(hero.numeral, style: numeralStyle, glyphGap: DotNumeral.glyphGapDetail,
                       placeholder: StrainHero.placeholder, accessibilityLabel: Text(verbatim: label))
                .accessibilityValue(Text(verbatim: hero.numeralValue))
                .accessibilityHint(hero.split == nil ? Text(verbatim: "")
                                                      : Text("Split by heart-rate and strength load"))
                .accessibilityHidden(label.isEmpty)
                .accessibilityIdentifier("\(identifierPrefix).numeral")
                .id(fadeKey)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .animation(Theme.Motion.respecting(reduceMotion), value: fadeKey)
    }

    /// "of 21 · moderate" and, on its line, "▲ +1.2 vs 7 d"; under it when the line is too narrow. Hidden from VoiceOver: with
    /// a strain both are in the numeral's value, without one its sentence is the numeral's label.
    private var caption: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                captionText.fixedSize()
                delta
            }
            VStack(spacing: 2) {
                captionText
                delta
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var captionText: some View {
        // An empty caption keeps its line, so nothing below moves.
        Text(verbatim: hero.caption.isEmpty ? " " : hero.caption)
            .font(.ryft(.label))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var delta: some View {
        if let d = hero.delta {
            DeltaLabel(spec: .strain, delta: d, reference: StrainHero.deltaReference, font: .ryft(.label))
        }
    }
}

// MARK: - the zones tile

/// The heart-rate zones in the strain glow tile (§P5-3.3, §P5-3.4): the head row ("Heart-rate zones" · "82 min · TRIMP 112")
/// and the five-row `ZoneBlock`, with the footnote 8 under the tile. Without zone data the short tile says why; while the page
/// loads it is a flat outline with five unlit rows. One VoiceOver element: "Heart-rate zones", then the minutes, each zone,
/// TRIMP and the footnote.
struct StrainZonesTile: View {
    /// What the tile says without zone data.
    enum Missing: Equatable {
        /// The short tile with this sentence ("Your watch didn't record heart-rate zones for this day.").
        case sentence(String)
        /// Being scored: the five rows with "–", no sentence; VoiceOver hears this ("Scoring your latest data").
        case pending(String)

        var spoken: String {
            switch self {
            case .sentence(let s), .pending(let s): s
            }
        }

        var isPending: Bool {
            if case .pending = self { return true }
            return false
        }
    }

    let zones: StrainZones
    let missing: Missing
    var isOutline = false
    /// Previews and tests; nil follows the system.
    var reduceTransparency: Bool?
    var identifierPrefix = "strain"

    var body: some View {
        VStack(alignment: .leading, spacing: StrainLayout.footnoteGap) {
            tile
            if !isOutline, zones.minutes != nil {
                Text(verbatim: StrainZones.footnote)
                    .font(.ryft(.axis))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    // In the tile's value.
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder private var tile: some View {
        if isOutline {
            content(rows: true)
                .padding(GlowTileSpec.padding(for: .zones))
                .frame(maxWidth: .infinity, minHeight: GlowTileSpec.zonesMinHeight, alignment: .topLeading)
                .background { PlaceholderOutline(RoundedRectangle(cornerRadius: GlowTileSpec.shape(for: .zones).radius,
                                                                  style: .continuous)) }
                .accessibilityHidden(true)
        } else {
            let rows = zones.minutes != nil || missing.isPending
            GlowTile(Theme.metricStrain, kind: .zones, minHeight: rows ? nil : StrainLayout.zonesShortHeight,
                     reduceTransparency: reduceTransparency) {
                content(rows: rows)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Heart-rate zones"))
            .accessibilityValue(Text(verbatim: zones.spokenValue(missing: missing.spoken)))
            .accessibilityIdentifier("\(identifierPrefix).zones")
        }
    }

    private func content(rows: Bool) -> some View {
        VStack(alignment: .leading, spacing: StrainLayout.zonesHeadGap) {
            StrainZonesHead(value: isOutline ? Fmt.placeholder : zones.head)
            if rows {
                ZoneBlock(zones: (isOutline ? StrainZones(minutes: nil) : zones).rows.map(Self.zone),
                          scaleMax: StrainZones.scaleMax, accessibilityLabel: Text("Heart-rate zones"))
            } else if case .sentence(let sentence) = missing {
                Text(verbatim: sentence)
                    .ryftGlowLabelStyle()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func zone(_ row: StrainZones.Row) -> ZoneBlock.Zone {
        ZoneBlock.Zone(label: Text(verbatim: row.label), minutes: row.minutes, value: Text(verbatim: row.value),
                       accessibilityLabel: Text(verbatim: row.spoken))
    }
}

/// The zones tile's head: "Heart-rate zones" and the minutes at the right on its baseline, both in the tile's label ink. From
/// AX1 the minutes go under the title, so the title keeps its line ("Heart-rate zones", never "Heart-/rate zones").
private struct StrainZonesHead: View {
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                title
                valueText
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                title
                Spacer(minLength: 0)
                valueText
            }
        }
    }

    private var title: some View {
        Text("Heart-rate zones")
            .ryftGlowLabelStyle()
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The minutes in the tile's label ink (the board's 55 % fails in the tile's corners, §P5-3.3).
    private var valueText: some View {
        Text(verbatim: value)
            .ryftGlowLabelStyle(.caption)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - the tiles

/// Steps and Active energy (§P5-3.1 row 8): two neutral tiles side by side, one column from AX1; outlines while loading.
struct StrainTiles: View {
    let board: StrainBoard
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: StrainLayout.tileSpacing))
            : AnyLayout(HStackLayout(spacing: StrainLayout.tileSpacing))
        layout {
            if board.isOutline {
                PlaceholderRow(height: NeutralTile.height)
                PlaceholderRow(height: NeutralTile.height)
            } else {
                NeutralTile(Text("Steps"), value: Text(verbatim: board.stepsText))
                    .accessibilityIdentifier("strain.tile.steps")
                NeutralTile(Text("Active energy"), value: Text(verbatim: board.energyText),
                            unit: board.activeKcal == nil ? nil : Text(verbatim: StrainFormat.kcalUnit))
                    .accessibilityIdentifier("strain.tile.energy")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
