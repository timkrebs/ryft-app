// Satoshi for headlines and UI, SF Pro Rounded as automatic fallback when the
// font files are not bundled (see scripts/fetch-fonts.sh). Text styles scale
// with Dynamic Type; `display` sizes are fixed because they live inside rings
// that have a fixed geometry.
import SwiftUI
import UIKit

enum RyftTextStyle {
    /// Ring numbers (Today readiness).
    case display
    /// Large numbers (total sleep, strain ring).
    case numberLarge
    case title
    case headline
    case metric
    case body
    case callout
    case caption
    /// Small uppercase tracked section label. Use with `.ryftLabelStyle()`.
    case label
    /// The RYFT wordmark.
    case wordmark

    fileprivate var size: CGFloat {
        switch self {
        case .display: return 56
        case .numberLarge: return 40
        case .title: return 26
        case .headline: return 18
        case .metric: return 22
        case .body: return 16
        case .callout: return 14
        case .caption: return 12
        case .label: return 11
        case .wordmark: return 17
        }
    }

    fileprivate var weight: Font.Weight {
        switch self {
        case .display, .numberLarge, .metric: return .medium
        case .title, .headline, .wordmark: return .medium
        case .body, .callout, .caption: return .regular
        case .label: return .medium
        }
    }

    fileprivate var textStyle: Font.TextStyle? {
        switch self {
        case .display, .numberLarge: return nil
        case .title: return .title
        case .headline: return .headline
        case .metric: return .title2
        case .body: return .body
        case .callout: return .callout
        case .caption: return .caption
        case .label: return .caption2
        case .wordmark: return .headline
        }
    }
}

enum RyftFonts {
    static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black, .semibold: return "Satoshi-Bold"
        case .medium: return "Satoshi-Medium"
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
}

extension Font {
    static func ryft(_ style: RyftTextStyle) -> Font {
        let name = RyftFonts.postScriptName(for: style.weight)
        if RyftFonts.isAvailable(name) {
            if let textStyle = style.textStyle {
                return .custom(name, size: style.size, relativeTo: textStyle)
            }
            return .custom(name, fixedSize: style.size)
        }
        if let textStyle = style.textStyle {
            return .system(textStyle, design: .rounded).weight(style.weight)
        }
        return .system(size: style.size, weight: style.weight, design: .rounded)
    }

    /// Fixed-size variant for numbers inside rings of arbitrary size.
    static func ryftNumber(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let name = RyftFonts.postScriptName(for: weight)
        if RyftFonts.isAvailable(name) { return .custom(name, fixedSize: size) }
        return .system(size: size, weight: weight, design: .rounded)
    }
}

extension View {
    /// Small, uppercase, tracked (+2 pt) section label.
    func ryftLabelStyle(_ color: Color = Theme.textSecondary) -> some View {
        font(.ryft(.label))
            .textCase(.uppercase)
            .tracking(2)
            .foregroundStyle(color)
    }
}
