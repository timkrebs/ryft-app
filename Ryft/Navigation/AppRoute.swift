import Foundation

/// A place in the app, from a URL, a notification's `ryft.url` or an insight.
/// One parser for all of them. Universal links come as
/// `https://ryftapp.de/<path>`; until an AASA is hosted (Associated Domains
/// is empty), the same paths work as `ryft://<path>` and from notifications.
///
/// | Path | Opens |
/// | --- | --- |
/// | `/day/YYYY-MM-DD` | Today for today; an earlier day on Strain |
/// | `/sleep/YYYY-MM-DD` | Sleep → Day on that night |
/// | `/sleep/plan` | Sleep → Planner |
/// | `/insights/behaviors` | Insights → Behaviors |
/// | `/insights/<metric>` | Insights, scrolled to the metric's trend |
/// | `/train/session(s)/<uuid>` | the session summary (API.md's push table says `session`) |
/// | `/train/exercises/<uuid>` | the exercise's history |
/// | `/train/plan/<uuid>` | the plan |
/// | `/train/history` | past sessions (the `pr` insight) |
/// | `/auth/callback` | email confirmation and password reset (Supabase) |
/// | `/invite/<code>` | the invite step, with the code filled in |
/// | anything else on our host | Today |
enum AppRoute: Equatable {
    case today
    case day(Date)
    case sleep(Date)
    case sleepPlan
    case insights(TrendMetric)
    case insightsBehaviors
    case trainSession(UUID)
    case trainExercise(UUID)
    case trainPlan(UUID)
    case trainHistory
    case authCallback(URL)
    /// A beta invite: the code fills in the invite step.
    case invite(code: String)

    static let host = "ryftapp.de"
    static let scheme = "ryft"

    /// `nil` only for URLs that aren't ours (another host or scheme). Ours with a
    /// path the app doesn't know open Today.
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
        self = Self.route(parts, url: url) ?? .today
    }

    private static func route(_ parts: [String], url: URL) -> AppRoute? {
        switch parts.count {
        case 2:
            switch (parts[0], parts[1]) {
            case ("day", let d): return DayFormat.date(from: d).map(AppRoute.day)
            case ("sleep", "plan"): return .sleepPlan
            case ("sleep", let d): return DayFormat.date(from: d).map(AppRoute.sleep)
            case ("insights", "behaviors"): return .insightsBehaviors
            case ("insights", let m): return TrendMetric(rawValue: m).map(AppRoute.insights)
            case ("auth", _): return .authCallback(url)
            case ("invite", let code) where !code.isEmpty: return .invite(code: code)
            case ("train", "history"): return .trainHistory
            default: return nil
            }
        case 3 where parts[0] == "train":
            guard let id = UUID(uuidString: parts[2]) else { return nil }
            switch parts[1] {
            case "session", "sessions": return .trainSession(id)
            case "exercise", "exercises": return .trainExercise(id)
            case "plan", "plans": return .trainPlan(id)
            default: return nil
            }
        default:
            return parts.first == "auth" ? .authCallback(url) : nil
        }
    }

    /// The universal link for this place.
    var url: URL? {
        let path: String
        switch self {
        case .today: path = ""
        case .day(let d): path = "day/\(DayFormat.string(from: d))"
        case .sleep(let d): path = "sleep/\(DayFormat.string(from: d))"
        case .sleepPlan: path = "sleep/plan"
        case .insights(let m): path = "insights/\(m.rawValue)"
        case .insightsBehaviors: path = "insights/behaviors"
        case .trainSession(let id): path = "train/sessions/\(id.uuidString.lowercased())"
        case .trainExercise(let id): path = "train/exercises/\(id.uuidString.lowercased())"
        case .trainPlan(let id): path = "train/plan/\(id.uuidString.lowercased())"
        case .trainHistory: path = "train/history"
        case .invite(let code): path = "invite/\(code)"
        case .authCallback(let url): return url
        }
        return URL(string: "https://\(Self.host)/\(path)")
    }

    /// Needs a signed-in account (everything but the auth callback).
    var needsSession: Bool {
        if case .authCallback = self { return false }
        return true
    }

    /// Where an insight card leads: its trend; `behavior-impact` the Behaviors
    /// section; `pr` the session history. `nil` when there's nothing to show.
    static func forInsight(_ insight: Insight) -> AppRoute? {
        switch insight.kind {
        case .behaviorImpact: return .insightsBehaviors
        case .pr: return .trainHistory
        default: return insight.trendMetric.map(AppRoute.insights)
        }
    }
}
