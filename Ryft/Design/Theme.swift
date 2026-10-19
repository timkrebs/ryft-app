// RYFT palette. Every colour is an asset-catalog colour set so it adapts to
// light/dark automatically. Brand colours are fixed; semantic colours flip
// (dark: Graphite background / Mist text, light: Mist background / Graphite text).
import SwiftUI

enum Theme {
    // MARK: brand palette (identical in both appearances)

    static let graphite = Color("Graphite")
    static let slate = Color("Slate")
    static let sage = Color("Sage")
    static let mist = Color("Mist")
    static let teal = Color("Teal")

    // MARK: semantic

    static let background = Color("Background")
    static let surface = Color("Surface")
    /// Ring tracks, unselected segments, empty bar backgrounds.
    static let surfaceRaised = Color("SurfaceRaised")
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")
    static let separator = Color("Separator")
    /// Teal: rings, progress, active tab, highlights.
    static let accent = Color("Accent")
    /// Text and icons on an Accent fill (buttons, checks): Graphite in dark mode,
    /// white on the darker light-mode teal, so both reach 4.5:1.
    static let onAccent = Color("OnAccent")
    /// Sage: muted positives, info insights.
    static let accentSecondary = Color("AccentSecondary")
    static let warning = Color("Warning")
    static let alert = Color("Alert")

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
    }

    // MARK: motion

    static let ringAnimation = Animation.easeOut(duration: 0.8)
}
