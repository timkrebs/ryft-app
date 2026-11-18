// RYFT palette ("Nocturne", docs/work/2026-11-16-nocturne/design.md, ADR 0016). Every colour is an asset-catalog
// colour set with ONE value: the app is dark-only, so nothing here adapts to an appearance. The neutrals are
// `#F2F1EC` at fixed opacities on the near-black screen, the three metric colours are the orbit's legend (one
// colour per metric, everywhere), and Volt is the signal, never text.
import SwiftUI

enum Theme {
    // MARK: brand palette (legacy names; each carries its Nocturne value)

    /// `#0A0C0B`, the screen. The same colour as `background`.
    static let graphite = Color("Graphite")
    /// `#121514`, the neutral tile. The same colour as `surface` (it was the cooler `#1A2226`).
    static let slate = Color("Slate")
    /// `#6EA89A`, the muted green of `accentSecondary`.
    static let sage = Color("Sage")
    /// `#F2F1EC`, text at full strength. The same colour as `textPrimary`.
    static let mist = Color("Mist")
    /// `#63D2B4`, the recovery teal. The same colour as `accent`.
    static let teal = Color("Teal")

    // MARK: semantic

    /// The screen: `#0A0C0B`.
    static let background = Color("Background")
    /// Neutral tiles, lists, the segment control: `#121514`.
    static let surface = Color("Surface")
    /// Ring tracks, unselected segments, empty bar backgrounds, raised chips and fields: the opaque `#2F312F`, the 16 %
    /// track (`#F2F1EC`) composited over `background`, so it is the same pixel on every ground. It carries `textPrimary`
    /// (11.6:1) and `textSecondary` (5.5:1) text, never `textTertiary` (3.9:1). Today every ring's track uses it; PR 3
    /// draws the middle and inner rings' 7 % and 13 % tracks from `textPrimary` and leaves it the outer ring's 16 %.
    static let surfaceRaised = Color("SurfaceRaised")
    /// Numbers and titles: `#F2F1EC`.
    static let textPrimary = Color("TextPrimary")
    /// Labels and units: `#F2F1EC` at 62 %.
    static let textSecondary = Color("TextSecondary")
    /// Scales and meta: `#F2F1EC` at 48 %. The style says 45 %, which is 4.1:1; 48 % is the lowest value that
    /// reaches 4.5:1 on both `background` and `surface`.
    static let textTertiary = Color("TextTertiary")
    /// List dividers and the tab bar's rule: `#F2F1EC` at 8 %.
    static let separator = Color("Separator")
    /// The recovery teal `#63D2B4`: rings, progress, highlights, primary fills.
    static let accent = Color("Accent")
    /// Recovery, the orbit's teal: the same colour as `accent` (one accent per screen, and it is the recovery
    /// metric's colour), so the legend reads `recovery`, `metricSleep`, `metricStrain`.
    static let recovery = Color("Accent")
    /// Text and icons on an `accent` fill (buttons, checks): `#0A0C0B`, 10.7:1.
    static let onAccent = Color("OnAccent")
    /// Volt `#D8FF4F`, the signal. Only for the ruler's needle, the readiness marker in the inner ring, the
    /// "today" dot in dot rows, the active tab's dot and the hint dot on Insights. Never text.
    static let signal = Color("Signal")
    /// What sits on a `signal` fill: `#0A0C0B`, 17.1:1.
    static let onSignal = Color("OnSignal")
    /// Sage `#6EA89A`: muted positives, info insights.
    static let accentSecondary = Color("AccentSecondary")
    /// Amber `#E3C25B`: moderate band, notices.
    static let warning = Color("Warning")
    /// Coral `#E36B5B`: low band, warnings.
    static let alert = Color("Alert")

    // MARK: metric colours (charts and gauges)

    /// Blue `#5E8BEA`: strain.
    static let metricStrain = Color("MetricStrain")
    /// Violet `#9B8AF0`: sleep performance and time asleep.
    static let metricSleep = Color("MetricSleep")

    // MARK: sleep stages

    static let stageDeep = Color("StageDeep")
    static let stageLight = Color("StageLight")
    static let stageREM = Color("StageREM")
    static let stageAwake = Color("StageAwake")

    static func color(for stage: SleepStageKind) -> Color {
        switch stage {
        case .deep: return stageDeep
        case .light: return stageLight
        case .rem: return stageREM
        case .awake: return stageAwake
        }
    }

    // MARK: bands

    /// Recovery / readiness: green (Teal) → yellow → red.
    static func band(forScore score: Int?) -> Color {
        guard let score else { return textTertiary }
        switch score {
        case 67...: return accent
        case 34...: return warning
        default: return alert
        }
    }

    static func color(for severity: InsightSeverity) -> Color {
        switch severity {
        case .info: return accentSecondary
        case .notice: return warning
        case .warn: return alert
        }
    }

    /// HRR zones 1–5 (50–60 … 90+ % heart-rate reserve).
    static let zones: [Color] = [stageAwake, accentSecondary, accent, warning, alert]

    // MARK: metrics

    enum Metrics {
        static let cardRadius: CGFloat = 18
        static let tileRadius: CGFloat = 16
        static let cardPadding: CGFloat = 18
        static let screenPadding: CGFloat = 20
        static let sectionSpacing: CGFloat = 24
        static let hairline: CGFloat = 1

        // Nocturne form (brief §2 "Form", design.md §P2-8). Additive: PRs 4–5 move the callers of the radii above.

        /// Neutral tiles and lists on `surface`.
        static let neutralTileRadius: CGFloat = 22
        /// Today's 2-up glow tiles (`GlowTileSpec.Radius.tile`).
        static let glowTileRadius: CGFloat = 24
        /// The Sleep and Strain hero glow tiles (`GlowTileSpec.Radius.hero`).
        static let heroTileRadius: CGFloat = 28
        /// The diameter of a circle button (`CircleButton`).
        static let circleButton: CGFloat = 40
        /// The smallest tap target (HIG, brief §6): a 40 pt circle sits in a 44 pt box.
        static let minHitTarget: CGFloat = 44
        /// The minimum height of a pill button (`PillButton`); its ends are round (radius 26).
        static let pillHeight: CGFloat = 52
        /// The gap between items in a row or a stack (§2 "Abstand 12").
        static let itemSpacing: CGFloat = 12

        // Nocturne controls (design.md §P5-1.4). Additive.

        /// An outline that carries a state, where a hairline would be too faint: the toggle's off track
        /// (`RyftToggleStyle`), a selected row's or chip's ring. Hue never carries the state; this line does.
        static let controlOutline: CGFloat = 1.5
    }

    // MARK: motion

    /// Gauges and charts settle in 250 ms; no springs, no count-ups.
    static let ringAnimation = Animation.easeOut(duration: 0.25)

    /// Every animation in the app: ease-out, 0.25–0.6 s, never a spring. Each explains a
    /// change (a value moving, a panel appearing); Reduce Motion turns them off.
    enum Motion {
        /// Selection, small state changes.
        static let quick = Animation.easeOut(duration: 0.25)
        /// Panels and banners appearing.
        static let standard = Animation.easeOut(duration: 0.4)
        /// A value arc filling, a coach mark moving.
        static let slow = Animation.easeOut(duration: 0.6)

        /// `nil` (no animation) under Reduce Motion.
        static func respecting(_ reduceMotion: Bool, _ animation: Animation = quick) -> Animation? {
            reduceMotion ? nil : animation
        }
    }
}
