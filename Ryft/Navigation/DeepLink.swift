import Foundation

/// A place in the app a URL can point at. Universal links come as
/// `https://ryftapp.de/<path>`, the same paths also as `ryft://<path>`
/// (notifications from older builds, the simulator without associated domains).
///
/// | Path | Opens |
/// | --- | --- |
/// | `/day/YYYY-MM-DD` | Today for today, otherwise Strain on that day |
/// | `/sleep/YYYY-MM-DD` | Sleep → Day on that night |
/// | `/insights/<metric>` | Insights, scrolled to the metric's trend (`TrendMetric` raw value) |
/// | `/train/session/<uuid>` | the logged session |
/// | `/train/plan/<uuid>` | the plan |
/// | `/auth/callback` | email confirmation and password reset (AuthService) |
enum DeepLink: Equatable {
    case day(Date)
    case sleep(Date)
    case insights(TrendMetric)
    case trainSession(UUID)
    case trainPlan(UUID)
    case authCallback(URL)

    static let host = "ryftapp.de"
    static let scheme = "ryft"

    /// `nil` for anything that isn't one of ours (another host, an unknown path, a bad date or ID).
    init?(url: URL) {
        let parts: [String]
        switch url.scheme?.lowercased() {
        case "https":
            guard let host = url.host?.lowercased(), host == Self.host || host == "www." + Self.host else { return nil }
            parts = url.pathComponents.filter { $0 != "/" }
        case Self.scheme:
            // ryft://day/2026-10-19: the first segment is the URL's host.
            parts = [url.host].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
        default:
            return nil
        }
        switch parts.count {
        case 2:
            switch parts[0] {
            case "day": guard let d = DayFormat.date(from: parts[1]) else { return nil }; self = .day(d)
            case "sleep": guard let d = DayFormat.date(from: parts[1]) else { return nil }; self = .sleep(d)
            case "insights": guard let m = TrendMetric(rawValue: parts[1]) else { return nil }; self = .insights(m)
            case "auth" where parts[1] == "callback": self = .authCallback(url)
            default: return nil
            }
        case 3 where parts[0] == "train":
            guard let id = UUID(uuidString: parts[2]) else { return nil }
            switch parts[1] {
            case "session": self = .trainSession(id)
            case "plan": self = .trainPlan(id)
            default: return nil
            }
        default:
            return nil
        }
    }

    /// The universal link for this place (what the platform puts in `ryft.url`).
    var url: URL? {
        let path: String
        switch self {
        case .day(let d): path = "day/\(DayFormat.string(from: d))"
        case .sleep(let d): path = "sleep/\(DayFormat.string(from: d))"
        case .insights(let m): path = "insights/\(m.rawValue)"
        case .trainSession(let id): path = "train/session/\(id.uuidString.lowercased())"
        case .trainPlan(let id): path = "train/plan/\(id.uuidString.lowercased())"
        case .authCallback(let url): return url
        }
        return URL(string: "https://\(Self.host)/\(path)")
    }

    /// Needs a signed-in account (everything but the auth callback).
    var needsSession: Bool {
        if case .authCallback = self { return false }
        return true
    }
}
