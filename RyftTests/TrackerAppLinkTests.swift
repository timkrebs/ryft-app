import Foundation
import Testing
@testable import Ryft

/// The tracker's app from Today's hint (design.md §D3, plan.md T1 and decision 3): the compiled scheme table, its URL
/// builder, the Info.plist it needs, and which action the card offers.
@Suite("Tracker app link")
struct TrackerAppLinkTests {
    // MARK: the table and the URL builder (ADR 0012 rules 1, 2, 4)

    @Test func aKnownTrackerGetsItsAppsBareURL() {
        let c = TrackerCatalog.bundled
        #expect(c.tracker("garmin")?.appURL?.absoluteString == "garminconnect://")
        #expect(c.tracker("oura")?.appURL?.absoluteString == "oura://")
        #expect(TrackerAppLink.url(forScheme: "garminconnect")?.absoluteString == "garminconnect://")
    }

    @Test func noSchemeGetsNothingAndAppleSamsungAndOtherNeverDo() {
        let c = TrackerCatalog.bundled
        #expect(c.tracker("polar")?.appURL == nil) // a vendor app without a candidate: the App Store action
        for id in ["apple_watch", "iphone", "samsung_galaxy_watch", "other"] {
            #expect(TrackerCatalog.appSchemes[id] == nil && c.tracker(id)?.appScheme == nil, "\(id)")
        }
        #expect(TrackerAppLink.url(forScheme: nil) == nil)
    }

    @Test func aMalformedSchemeIsRefused() {
        let malformed = ["Garmin Connect", "garmin://", "garmin:", "garmin://x", "1garmin", "", "g", "GarminConnect",
                         "garmin connect", "garmin/connect", "garmin?x", String(repeating: "a", count: 33), "gärmin"]
        for scheme in malformed {
            #expect(TrackerAppLink.url(forScheme: scheme) == nil, "\(scheme)")
        }
        // The web, RYFT's own and the system's handlers open something other than the tracker's app.
        for scheme in ["http", "https", "ryft", "tel", "sms", "mailto", "facetime", "file", "javascript", "itms-apps",
                       "x-apple-health", "x-apple-reminderkit"] {
            #expect(TrackerAppLink.url(forScheme: scheme) == nil, "\(scheme)")
        }
        // The plain form RFC 3986 allows, 2 to 32 characters.
        #expect(TrackerAppLink.url(forScheme: "a1+b-c.d")?.absoluteString == "a1+b-c.d://")
        #expect(TrackerAppLink.url(forScheme: "ab") != nil && TrackerAppLink.url(forScheme: String(repeating: "a", count: 32)) != nil)
    }

    @Test func everyCompiledEntryIsAPlainSchemeOfAVendorApp() throws {
        for (id, scheme) in TrackerCatalog.appSchemes {
            #expect(TrackerAppLink.isPlainScheme(scheme), "\(id): \(scheme)")
            let tracker = try #require(TrackerCatalog.bundled.tracker(id), "\(id) isn't in the catalog")
            #expect(tracker.integration == .vendorApp && tracker.appScheme == scheme, "\(id)")
            // The fallback when the app doesn't open: every tracker with a scheme has a pinned store page (`storeIDs`).
            #expect(tracker.appStoreID != nil && tracker.appStoreURL != nil, "\(id) has a scheme but no storeIDs entry")
        }
    }

    /// `canOpenURL` answers only for schemes in `LSApplicationQueriesSchemes`: a missing one would leave the card on the
    /// App Store page forever, an extra one is an unexplained query. Reads the built app's Info.plist (the test host).
    @Test func lsApplicationQueriesSchemesIsTheTablePlusRYFTsOwn() throws {
        let listed = try #require(Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String])
        let table = Set(TrackerCatalog.appSchemes.values)
        #expect(Set(listed) == table.union(TrackerAppLink.ownQueriedSchemes),
                "Ryft/Info.plist lists \(listed.sorted()); the table has \(table.sorted())")
        #expect(listed.count == Set(listed).count, "a duplicate entry")
        #expect(listed.count <= TrackerAppLink.maxQueriedSchemes, "iOS ignores entries past 50")
        #expect(TrackerAppLink.ownQueriedSchemes.isDisjoint(with: table))
        for scheme in table {
            #expect(TrackerAppLink.isPlainScheme(scheme), "\(scheme)")
        }
    }

    // MARK: the hint's action (design.md §D3.3)

    private static let since = Date(timeIntervalSince1970: 1_790_000_000)
    private static let store = URL(string: "https://apps.apple.com/app/id583446403")
    private static let app = TrackerAppLink.url(forScheme: "garminconnect")

    private func hint(isApp: Bool = true, storeURL: URL? = TrackerAppLinkTests.store, appURL: URL? = TrackerAppLinkTests.app,
                      night: Bool = false) -> WatchSyncHint {
        guard night else {
            return WatchSyncHint(source: "Garmin Connect", since: Self.since, isApp: isApp, storeURL: storeURL, appURL: appURL)
        }
        return WatchSyncHint(night: NightGap(name: "Garmin Connect", kind: isApp ? .app : .appleDevice, storeURL: storeURL,
                                             newest: Self.since, appURL: appURL))
    }

    @Test func anInstalledAppOpensWithTheStorePageAsFallback() throws {
        let app = try #require(Self.app)
        for night in [false, true] {
            let h = hint(night: night)
            let action = try #require(h.action { $0 == app })
            #expect(action == .openApp(app, fallback: Self.store))
            #expect(h.title(action) == String(localized: "Open \("Garmin Connect")"))
        }
    }

    /// `open` reports whether the app opened: the store page only when it didn't, never after the store page itself.
    @Test func theStorePageIsTheFallbackOnlyWhenTheAppDidNotOpen() throws {
        let app = try #require(Self.app), store = try #require(Self.store)
        let open = WatchSyncHint.Action.openApp(app, fallback: store)
        #expect(open.fallback(accepted: false) == store)
        #expect(open.fallback(accepted: true) == nil)
        // No store page known: nothing to fall back to, and no error.
        #expect(WatchSyncHint.Action.openApp(app, fallback: nil).fallback(accepted: false) == nil)
        // The store page itself has no fallback, whatever `open` says.
        #expect(WatchSyncHint.Action.store(store).fallback(accepted: false) == nil)
        #expect(WatchSyncHint.Action.store(store).fallback(accepted: true) == nil)
        #expect(open.opensApp && !WatchSyncHint.Action.store(store).opensApp)
    }

    @Test func notInstalledOrNoSchemeKeepsTheStorePage() throws {
        let store = try #require(Self.store)
        #expect(hint().action { _ in false } == .store(store))
        // No scheme in the table (Polar): never asks, the store page.
        var asked = false
        #expect(hint(appURL: nil).action { _ in asked = true; return true } == .store(store))
        #expect(!asked)
        #expect(hint().title(.store(store)) == String(localized: "\("Garmin Connect") in the App Store"))
    }

    @Test func anAppleDeviceOrAnAppWithNeitherGetsNoButton() {
        #expect(hint(isApp: false, storeURL: nil, appURL: nil).action { _ in true } == nil)
        // Even with URLs the content couldn't have given it: an Apple device has nothing to open.
        #expect(hint(isApp: false).action { _ in true } == nil)
        #expect(hint(isApp: false, night: true).action { _ in true } == nil)
        #expect(hint(storeURL: nil, appURL: nil).action { _ in true } == nil)
        // Installed-check fails and no store page: information only.
        #expect(hint(storeURL: nil).action { _ in false } == nil)
    }

    @Test func theSyncSentenceFollowsTheScreensLanguage() throws {
        let sync = try #require(TrackerCatalog.bundled.tracker("garmin")?.sync)
        var h = hint()
        h.sync = sync
        let de = Locale(identifier: "de_DE")
        #expect(h.text(now: Self.since, locale: de).hasSuffix("\n" + sync.de))
        #expect(h.text(now: Self.since, locale: Locale(identifier: "en_US")).hasSuffix("\n" + sync.en))
        // An Apple device keeps its own sentence, whatever it carries.
        var watch = hint(isApp: false)
        watch.sync = sync
        #expect(!watch.text(now: Self.since, locale: Locale(identifier: "en_US")).contains(sync.en))
    }
}
