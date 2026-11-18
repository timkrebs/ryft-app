// Satoshi for headlines and UI, SF Pro Rounded as automatic fallback when the
// font files are not bundled (see scripts/fetch-fonts.sh). Text styles scale
// with Dynamic Type; `display` sizes are fixed because they live inside rings
// that have a fixed geometry.
//
// The Nocturne scale (docs/work/2026-11-16-nocturne/design.md): titles and numbers Light, text Regular, buttons
// and emphasised row titles Medium, sentence case everywhere, tabular digits on every style.
import SwiftUI
import UIKit

enum RyftTextStyle {
    /// Ring numbers (Today readiness) when they are set in type, not as a dot grid: 52 Light.
    case display
    /// Large numbers (total sleep, strain ring): 34 Light, the top of the tile-value range.
    case numberLarge
    /// Screen titles: 26 Light.
    case title
    /// Row titles and emphasis: 17 Medium.
    case headline
    /// Tile values: 26 Light, the low end of the 26-34 range.
    case metric
    /// Running text: 16 Regular.
    case body
    /// Secondary running text: 15 Regular.
    case callout
    /// Meta and notes: 12 Regular.
    case caption
    /// Section and tile labels, sentence case: 13 Regular. Use with `.ryftLabelStyle()` (colours it `textSecondary`).
    case label
    /// Chart axis ticks and scale annotations: 11 Regular.
    case axis
    /// Tab bar labels: 11 Regular.
    case tab
    /// Button labels: 16 Medium.
    case button
    /// The RYFT wordmark: 15 Light, tracked 0.32 em (see `Wordmark`).
    case wordmark

    var size: CGFloat {
        switch self {
        case .display: return 52
        case .numberLarge: return 34
        case .title, .metric: return 26
        case .headline: return 17
        case .body, .button: return 16
        case .callout, .wordmark: return 15
        case .label: return 13
        case .caption: return 12
        case .axis, .tab: return 11
        }
    }

    var weight: Font.Weight {
        switch self {
        case .display, .numberLarge, .metric, .title, .wordmark: return .light
        case .headline, .button: return .medium
        case .body, .callout, .caption, .label, .axis, .tab: return .regular
        }
    }

    fileprivate var textStyle: Font.TextStyle? {
        switch self {
        case .display, .numberLarge: return nil
        case .title: return .title
        case .headline: return .headline
        case .metric: return .title2
        case .body, .button: return .body
        case .callout: return .callout
        case .caption: return .caption
        case .label: return .footnote
        case .axis, .tab: return .caption2
        case .wordmark: return .headline
        }
    }
}

enum RyftFonts {
    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black, .semibold: return "Satoshi-Bold"
        case .medium: return "Satoshi-Medium"
        case .light, .thin, .ultraLight: return "Satoshi-Light"
        default: return "Satoshi-Regular"
        }
    }

    private static var availability: [String: Bool] = [:]

    /// True once the Satoshi files are registered via Info.plist `UIAppFonts`.
    static func isAvailable(_ name: String) -> Bool {
        if let known = availability[name] { return known }
        let ok = UIFont(name: name, size: 12) != nil
        availability[name] = ok
        return ok
    }

    /// Below this size a number is set Regular, not Light: a Light stroke under 20 pt is too thin to read on a dark
    /// screen (design.md, PR 1).
    static let lightFloor: CGFloat = 20

    /// The weight of a number set at `size` when the caller names none.
    static func numberWeight(forSize size: CGFloat) -> Font.Weight {
        size >= lightFloor ? .light : .regular
    }
}

extension Font {
    static func ryft(_ style: RyftTextStyle) -> Font {
        let name = RyftFonts.postScriptName(for: style.weight)
        if RyftFonts.isAvailable(name) {
            if let textStyle = style.textStyle {
                return .custom(name, size: style.size, relativeTo: textStyle).monospacedDigit()
            }
            return .custom(name, fixedSize: style.size).monospacedDigit()
        }
        if let textStyle = style.textStyle {
            return .system(textStyle, design: .rounded).weight(style.weight).monospacedDigit()
        }
        return .system(size: style.size, weight: style.weight, design: .rounded).monospacedDigit()
    }

    /// Fixed-size variant for numbers inside rings of arbitrary size, with tabular digits. Without a `weight` it is
    /// Light from 20 pt up and Regular below (`RyftFonts.lightFloor`).
    static func ryftNumber(size: CGFloat, weight: Font.Weight? = nil) -> Font {
        let weight = weight ?? RyftFonts.numberWeight(forSize: size)
        let name = RyftFonts.postScriptName(for: weight)
        if RyftFonts.isAvailable(name) { return .custom(name, fixedSize: size).monospacedDigit() }
        return .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension View {
    /// A section or tile label: 13 pt Regular, sentence case, no tracking, `textSecondary`.
    func ryftLabelStyle(_ color: Color = Theme.textSecondary) -> some View {
        font(.ryft(.label))
            .foregroundStyle(color)
    }
}
