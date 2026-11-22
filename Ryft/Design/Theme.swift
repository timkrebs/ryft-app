// RYFT palette ("Nocturne", docs/work/2026-11-16-nocturne/design.md, ADR 0016). Every colour is an asset-catalog
// colour set with ONE value: the app is dark-only, so nothing here adapts to an appearance. The neutrals are
// `#F2F1EC` at fixed opacities on the near-black screen, the three metric colours are the orbit's legend (one
// colour per metric, everywhere), and Volt is the signal, never text.
import SwiftUI

enum Theme {
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
    /// Recovery, the orbit's teal `#63D2B4`, and nothing else (L27): the legend reads `recovery`, `metricSleep`,
    /// `metricStrain`. The pre-Nocturne `accent` was this colour; the gate (T5.9) deleted it.
    static let recovery = Color("Recovery")
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

    // MARK: bands

    /// Recovery / readiness: recovery's teal → amber → coral.
    static func band(forScore score: Int?) -> Color {
        guard let score else { return textTertiary }
        switch score {
        case 67...: return recovery
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

    // MARK: metrics

    enum Metrics {
        static let screenPadding: CGFloat = 20
        static let sectionSpacing: CGFloat = 24
        static let hairline: CGFloat = 1

        // Nocturne form (brief §2 "Form", design.md §P2-8).

        /// Neutral tiles, lists and cards on `surface`: the one card radius (the gate's D8).
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

        // MARK: T5.0-B

        /// The least height of a row in a grouped card (`GroupedRow`, design.md §P5-6.1, PR 6 A's `listRowHeight`): 46. A row
        /// with a second line or a leading icon disc grows with them.
        static let listRowHeight: CGFloat = 46
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
