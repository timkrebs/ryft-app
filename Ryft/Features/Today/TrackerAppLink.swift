import SwiftUI
import UIKit

/// The tracker's own app, opened by its bare URL scheme ("Open Garmin Connect" on Today's quiet-source hint).
///
/// ADR 0012 (amending ADR 0002 rule 4; plan.md decision 3 (data quality)): the schemes are a compiled table,
/// `CatalogValidator.appSchemes`, never read from `trackers.json`. Every entry is in `LSApplicationQueriesSchemes`
/// (`TrackerAppLinkTests` pins the two lists); an app opens only when `canOpenURL` accepts its URL, else the hint keeps
/// the App Store page. A wrong scheme costs nothing.
enum TrackerAppLink {
    /// Entries of `LSApplicationQueriesSchemes` that are RYFT's own, not a tracker's: `x-apple-health` (`HealthLinks`,
    /// onboarding and Profile open the Health app).
    static let ownQueriedSchemes: Set<String> = ["x-apple-health"]

    /// iOS reads at most 50 `LSApplicationQueriesSchemes` entries for apps linked on iOS 15 or later.
    static let maxQueriedSchemes = 50

    /// Schemes no tracker may use: the web, files, RYFT's own and the system's handlers open something other than the
    /// tracker's app. Every `x-apple-` scheme is refused too (`isPlainScheme`).
    static let refused: Set<String> = [
        "http", "https", "file", "data", "javascript", "about", "ryft", "mailto", "tel", "telprompt", "sms", "facetime",
        "facetime-audio", "itms", "itms-apps", "itms-appss", "app-settings", "prefs", "shortcuts",
    ]

    /// Exactly `<scheme>://`, no host, path, query or user data; nil for nil or anything that isn't a plain scheme.
    static func url(forScheme scheme: String?) -> URL? {
        guard let scheme, isPlainScheme(scheme) else { return nil }
        return URL(string: "\(scheme)://")
    }

    /// ADR 0012 rule 2: a lowercase letter, then 1 to 31 letters, digits, `+`, `-` or `.`; not refused, not `x-apple-`.
    static func isPlainScheme(_ scheme: String) -> Bool {
        scheme.range(of: #"\A[a-z][a-z0-9+.-]{1,31}\z"#, options: .regularExpression) != nil
            && !refused.contains(scheme) && !scheme.hasPrefix("x-apple-")
    }
}

/// Whether an app is installed that handles a URL (`UIApplication.canOpenURL`, which answers only for schemes in
/// `LSApplicationQueriesSchemes`). A seam: previews and tests say yes or no without UIKit. It wraps the `(URL) -> Bool`
/// because `@Entry` refuses a bare closure. Asked on each render, never cached (the user may install or remove the app
/// between foregrounds), and its answer is never logged, stored or sent (ADR 0012, Privacy).
struct AppInstalledCheck: Sendable {
    let check: @MainActor @Sendable (URL) -> Bool

    @MainActor func callAsFunction(_ url: URL) -> Bool { check(url) }

    static let live = AppInstalledCheck { UIApplication.shared.canOpenURL($0) }
    static let installed = AppInstalledCheck { _ in true }
    static let notInstalled = AppInstalledCheck { _ in false }
}

extension EnvironmentValues {
    @Entry var appInstalled: AppInstalledCheck = .live
}
