// Read-permission status for the Profile screen. HealthKit never reveals
// whether *read* access was granted, only whether the prompt still needs to be
// shown — so "asked" is the best we can report.
import HealthKit

extension HealthKitManager {
    typealias AccessStatus = HealthAccess

    func accessStatus() async -> AccessStatus {
        guard Self.isAvailable else { return .unavailable }
        do {
            switch try await store.statusForAuthorizationRequest(toShare: [], read: readTypes) {
            case .shouldRequest: return .notAsked
            case .unnecessary: return .asked
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }
}

// MARK: - tracker catalog (design.md §2, ADR 0002)
//
// What each tracker writes to Apple Health and how its sources look there. In this file, not one of its
// own, because `Ryft/` is a classic group (ADR 0002 → follow-ups). The bundled copy is the generated
// region at the end (`make trackers` from `Content/trackers.json`).

/// trackers.json, validated (§2.3). Bundled (the generated literal), or the newest valid copy from ryftapp.de.
struct TrackerCatalog: Equatable, Sendable {
    let version: String
    /// Picker order.
    let trackers: [Tracker]
    /// How to let RYFT read: the Health app's route (no iOS path in code).
    let healthAccess: Localized<[String]>

    /// The most a copy may weigh (rule 1).
    static let maxBytes = 262_144

    func tracker(_ id: String) -> Tracker? { trackers.first { $0.id == id } }

    /// The tracker a HealthKit source belongs to (design.md §4.3), first in picker order. By bundle ID
    /// whenever the source has one (equal, or a prefix at a dot boundary), then by device for trackers
    /// that list models; by name only without a bundle ID, since names are user-editable. `nil`: unknown.
    func match(_ source: SourceRef) -> Tracker? {
        if let bundleID = source.bundleID, !bundleID.isEmpty {
            return trackers.first { $0.identity.matches(bundleID: bundleID, deviceModel: source.deviceModel) }
        }
        let name = SourceIdentity.folded(source.name)
        guard !name.isEmpty else { return nil }
        return trackers.first { $0.identity.sourceNames.contains { SourceIdentity.folded($0) == name } }
    }

    /// What RYFT calls a source (§5): a vendor app by its name ("Garmin Connect", not HealthKit's
    /// "Connect"); an Apple device by its own name ("Tim's Apple Watch"), which is more precise; anything
    /// else as HealthKit names it.
    func displayName(_ source: SourceRef) -> String {
        guard let tracker = match(source) else { return source.name }
        switch tracker.integration {
        case .vendorApp: return tracker.appName ?? tracker.name
        case .appleBuiltin: return source.name.isEmpty ? tracker.name : source.name
        case .none, .unknown: return source.name
        }
    }

    /// Parses and validates a copy (§2.3, §2.5): any structural error rejects the whole document, unknown
    /// keys are ignored, a help link off the allowlist is dropped. Pure and nonisolated: callers run it off
    /// the main actor. `now` bounds the dates ("not after tomorrow").
    static func decode(_ data: Data, now: Date) throws(CatalogError) -> TrackerCatalog {
        guard data.count <= maxBytes else { throw .tooLarge }
        guard String(data: data, encoding: .utf8) != nil,
              let json = try? JSONDecoder().decode(CatalogJSON.self, from: data),
              case .object(let root) = json else { throw .notJSON }
        return try CatalogValidator(now: now).catalog(root)
    }

    /// The generated literal, decoded once on first use. Its dates aren't held against the clock (a phone
    /// set to the wrong year mustn't lose it); `DecodingTests` proves it passes every other rule. Never
    /// invalid in a build that passed the tests; if it were, an empty catalog: HealthKit's names everywhere.
    static let bundled: TrackerCatalog = {
        let signpost = Signposts.launch.beginInterval("tracker-catalog", id: Signposts.launch.makeSignpostID())
        defer { Signposts.launch.endInterval("tracker-catalog", signpost) }
        return (try? decode(Data(bundledJSON.utf8), now: .distantFuture))
            ?? TrackerCatalog(version: "0", trackers: [], healthAccess: Localized(en: [], de: []))
    }()

    /// The bundled copy, its first parse off the main actor (Today names sources after HealthKit answered).
    @concurrent
    static func loadBundled() async -> TrackerCatalog { bundled }
}

struct Tracker: Equatable, Sendable, Identifiable {
    /// The tile's glyph (D2 §2.2): names carry the identity, the glyph only the form factor.
    enum Form: String, Sendable { case watch, ring, band, phone, other }
    enum Integration: String, Sendable { case appleBuiltin = "apple_builtin", vendorApp = "vendor_app", none, unknown }

    let id: String
    let name: String
    let form: Form
    /// "Garmin Connect", "Google Health"; nil for `none` and `unknown`.
    let appName: String?
    let integration: Integration
    let identity: SourceIdentity
    /// Digits only: the store link is built from it, never taken from content.
    let appStoreID: String?
    /// Every signal: a key the copy left out is `.unverified` (`.no` for integration `none`).
    let capabilities: [TrackerSignal: Capability]
    let notes: [TrackerSignal: Localized<String>]
    let setup: Localized<[String]>
    let habits: Localized<[String]>
    let limits: Localized<[String]>
    /// The vendor's guide; dropped when its host isn't on the compiled allowlist (§2.5).
    let help: URL?
    /// YYYY-MM-DD, when the facts were last checked against the vendor.
    let checked: String

    /// Storefront-neutral: the App Store shows "Open" when the app is installed.
    var appStoreURL: URL? { appStoreID.flatMap { URL(string: "https://apps.apple.com/app/id\($0)") } }
}

/// How a tracker's records look in HealthKit (`healthkit` in trackers.json).
struct SourceIdentity: Equatable, Sendable {
    let bundleIDs: [String]
    let bundlePrefixes: [String]
    let sourceNames: [String]
    /// `HKDevice.model` values ("Watch", "iPhone"): Apple devices share one bundle prefix.
    let deviceModels: [String]

    static let none = SourceIdentity(bundleIDs: [], bundlePrefixes: [], sourceNames: [], deviceModels: [])
    var isEmpty: Bool { bundleIDs.isEmpty && bundlePrefixes.isEmpty && sourceNames.isEmpty && deviceModels.isEmpty }

    /// Case-insensitive: the ID equals an entry of `bundleIDs` or continues a prefix at a dot boundary
    /// (`<bundle>.watchkitapp` yes, `com.garmin.connect.mobile2` no); then the device, when models are listed.
    func matches(bundleID: String, deviceModel: String?) -> Bool {
        let id = bundleID.lowercased()
        guard bundleIDs.contains(where: { $0.lowercased() == id }) || bundlePrefixes.contains(where: { Self.covers($0, id) })
        else { return false }
        guard !deviceModels.isEmpty else { return true }
        guard let deviceModel else { return false }
        return deviceModels.contains { $0.caseInsensitiveCompare(deviceModel) == .orderedSame }
    }

    /// `prefix` covers `id` at a dot boundary: equal, or `id` goes on after a dot (a prefix ending in "."
    /// already has it).
    static func covers(_ prefix: String, _ id: String) -> Bool {
        let p = prefix.lowercased(), i = id.lowercased()
        if p.hasSuffix(".") { return i.hasPrefix(p) }
        return i == p || i.hasPrefix(p + ".")
    }

    /// Source names compare without case and diacritics, trimmed.
    static func folded(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

enum TrackerSignal: String, CaseIterable, Sendable {
    case heartRate = "heart_rate", hrv, restingHR = "resting_hr", sleep, sleepStages = "sleep_stages"
    case respiratoryRate = "respiratory_rate", spo2, workouts, steps

    /// The stream it arrives in; nil for sleep stages (a property of `.sleep` samples).
    var stream: HealthStream? {
        switch self {
        case .heartRate: return .quantity(.heartRate)
        case .hrv: return .quantity(.hrvSDNN)
        case .restingHR: return .quantity(.restingHR)
        case .sleep: return .sleep
        case .sleepStages: return nil
        case .respiratoryRate: return .quantity(.respiratoryRate)
        case .spo2: return .quantity(.spo2)
        case .workouts: return .workouts
        case .steps: return .quantity(.steps)
        }
    }
}

/// What reaches Apple Health from a tracker. `unverified`: not confirmed either way (never shown as ✗).
enum Capability: String, Sendable { case yes, partial, no, unverified }

/// Catalog text in both languages; never through `Localizable.xcstrings` (it changes without a release).
struct Localized<T: Equatable & Sendable>: Equatable, Sendable {
    let en: T
    let de: T

    /// The app's UI language: German when the app runs in German, else English.
    var current: T { value(for: Bundle.main.preferredLocalizations.first) }

    func value(for language: String?) -> T {
        language?.lowercased().hasPrefix("de") == true ? de : en
    }
}

/// A HealthKit source as RYFT sees it.
struct SourceRef: Hashable, Sendable {
    let name: String
    let bundleID: String?
    /// HKDevice.model of the newest sample ("Watch", "iPhone"), else the letters of
    /// HKSourceRevision.productType ("Watch7,1" → "Watch"). Apple doesn't document either for this; verify on a device.
    let deviceModel: String?

    /// `deviceModel` from a sample: the device's model, else the product type's leading letters.
    static func deviceModel(model: String?, productType: String?) -> String? {
        if let model, !model.isEmpty { return model }
        guard let letters = productType.map({ String($0.prefix(while: \.isLetter)) }), letters.count >= 2 else { return nil }
        return letters
    }
}

enum CatalogError: Error, Equatable {
    case tooLarge, notJSON, schema(Int), invalid(rule: String, path: String)
}

extension AppEnvironment {
    /// The catalog every screen reads. T1: `.bundled`. T2 replaces the body with `catalogStore.current`.
    var trackerCatalog: TrackerCatalog { .bundled }
}

/// JSON as it came, its types kept (a bool is no number), so every rule can name the exact path.
private enum CatalogJSON: Decodable {
    case object([String: CatalogJSON]), array([CatalogJSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([CatalogJSON].self) {
            self = .array(a)
        } else {
            self = .object(try c.decode([String: CatalogJSON].self))
        }
    }
}

/// The rules of design.md §2.3 and the trust rules of §2.5, each failure named `rule` at `path`
/// ("text.markup" at "trackers[3].setup_steps.de[2]").
private struct CatalogValidator {
    let now: Date

    /// The denylisted brand, as `.claude/hooks/pre-edit-guard.sh` has it (`scripts/trackers.py --check`
    /// keeps the two equal).
    static let brandPattern = #"wh[o0]{2}p|w[-. ]h[-. ]o[-. ]o[-. ]p"#
    /// Help links: these hosts and their subdomains per tracker id, and RYFT's own for any. Compiled on
    /// purpose: a new vendor domain needs a release.
    static let helpHosts: [String: [String]] = [
        "garmin": ["garmin.com"], "oura": ["ouraring.com"], "polar": ["polar.com"], "suunto": ["suunto.com"],
        "coros": ["coros.com"], "withings": ["withings.com"], "amazfit": ["amazfit.com", "zepp.com"],
        "ultrahuman": ["ultrahuman.com"], "fitbit": ["google.com"], "samsung_galaxy_watch": ["samsung.com"],
        "apple_watch": ["apple.com"], "iphone": ["apple.com"], "other": ["apple.com"],
    ]
    static let anyHelpHost = "ryftapp.de"
    static let appleTrackers: Set<String> = ["apple_watch", "iphone"]

    func catalog(_ root: [String: CatalogJSON]) throws(CatalogError) -> TrackerCatalog {
        guard case .number(let schema)? = root["schema_version"] else { throw .schema(0) }
        guard schema == 1 else { throw .schema(Int(exactly: schema) ?? 0) }
        let version = try string(root, "version", "", required: true) ?? ""
        guard Self.matches(version, #"[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{1,3}"#), isDate(String(version.prefix(10)))
        else { throw .invalid(rule: "version", path: "version") }
        if let checked = try string(root, "checked", "", required: false) { try date(checked, "checked") }

        var healthAccess = Localized<[String]>(en: [], de: [])
        if let access = try object(root, "health_access", "") {
            healthAccess = try list(access, "steps", "health_access", max: 12)
            if let checked = try string(access, "checked", "health_access", required: false) {
                try date(checked, "health_access.checked")
            }
        }

        guard case .array(let items)? = root["trackers"] else { throw .invalid(rule: "missing", path: "trackers") }
        guard (2...40).contains(items.count) else { throw .invalid(rule: "trackers.count", path: "trackers") }
        var trackers: [Tracker] = []
        for (i, item) in items.enumerated() {
            guard case .object(let t) = item else { throw .invalid(rule: "type", path: "trackers[\(i)]") }
            let tracker = try self.tracker(t, "trackers[\(i)]")
            guard !trackers.contains(where: { $0.id == tracker.id }) else {
                throw .invalid(rule: "id.duplicate", path: "trackers[\(i)].id")
            }
            trackers.append(tracker)
        }
        guard trackers.contains(where: { $0.id == "iphone" }), trackers.contains(where: { $0.id == "other" }) else {
            throw .invalid(rule: "id.required", path: "trackers")
        }
        try Self.checkOwnership(trackers)
        return TrackerCatalog(version: version, trackers: trackers, healthAccess: healthAccess)
    }

    private func tracker(_ t: [String: CatalogJSON], _ path: String) throws(CatalogError) -> Tracker {
        let id = try string(t, "id", path, required: true) ?? ""
        guard Self.matches(id, "[a-z][a-z0-9_]{1,31}") else { throw .invalid(rule: "id.format", path: "\(path).id") }
        let name = try string(t, "name", path, required: true) ?? ""
        try text(name, max: 40, "\(path).name")
        let rawForm = try string(t, "form", path, required: true) ?? ""
        guard let form = Tracker.Form(rawValue: rawForm) else { throw .invalid(rule: "enum.form", path: "\(path).form") }
        let rawIntegration = try string(t, "integration", path, required: true) ?? ""
        guard let integration = Tracker.Integration(rawValue: rawIntegration) else {
            throw .invalid(rule: "enum.integration", path: "\(path).integration")
        }
        let appName = try string(t, "app_name", path, required: false)
        if let appName { try text(appName, max: 40, "\(path).app_name") }

        let identity = try self.identity(t, id: id, path)
        let capabilities = try self.capabilities(t, integration: integration, path)
        if integration == .none || integration == .unknown, !identity.isEmpty {
            throw .invalid(rule: "integration.identity", path: "\(path).healthkit")
        }

        let storeID = try string(t, "app_store_id", path, required: false)
        if let storeID, !Self.matches(storeID, "[0-9]{1,12}") {
            throw .invalid(rule: "store.format", path: "\(path).app_store_id")
        }
        let help = try string(t, "help_url", path, required: false).flatMap { Self.helpURL($0, trackerID: id) }
        let checked = try string(t, "checked", path, required: true) ?? ""
        try date(checked, "\(path).checked")

        var notes: [TrackerSignal: Localized<String>] = [:]
        if let raw = try object(t, "capability_notes", path) {
            for signal in TrackerSignal.allCases {
                guard let note = try object(raw, signal.rawValue, "\(path).capability_notes") else { continue }
                let at = "\(path).capability_notes.\(signal.rawValue)"
                guard let en = try string(note, "en", at, required: false), let de = try string(note, "de", at, required: false) else {
                    throw .invalid(rule: "text.pair", path: at)
                }
                try text(en, max: 240, "\(at).en")
                try text(de, max: 240, "\(at).de")
                notes[signal] = Localized(en: en, de: de)
            }
        }
        let setup = try list(t, "setup_steps", path, max: 12)
        let habits = try list(t, "habits", path, max: 8)
        let limits = try list(t, "limits", path, max: 8)
        return Tracker(id: id, name: name, form: form, appName: appName, integration: integration, identity: identity,
                       appStoreID: storeID, capabilities: capabilities, notes: notes, setup: setup, habits: habits,
                       limits: limits, help: help, checked: checked)
    }

    private func identity(_ t: [String: CatalogJSON], id: String, _ path: String) throws(CatalogError) -> SourceIdentity {
        guard let hk = try object(t, "healthkit", path) else { return .none }
        let at = "\(path).healthkit"
        let ids = try strings(hk, "bundle_ids", at), prefixes = try strings(hk, "bundle_id_prefixes", at)
        for (key, values) in [("bundle_ids", ids), ("bundle_id_prefixes", prefixes)] {
            for (j, value) in values.enumerated() {
                guard value.count <= 155, Self.matches(value, #"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.?"#) else {
                    throw .invalid(rule: "bundle.format", path: "\(at).\(key)[\(j)]")
                }
                guard !value.lowercased().hasPrefix("com.apple.") || Self.appleTrackers.contains(id) else {
                    throw .invalid(rule: "bundle.apple", path: "\(at).\(key)[\(j)]")
                }
            }
        }
        let names = try strings(hk, "source_names", at)
        for (j, name) in names.enumerated() { try text(name, max: 40, "\(at).source_names[\(j)]") }
        let models = try strings(hk, "device_models", at)
        for (j, model) in models.enumerated() where !Self.matches(model, "[A-Za-z]{2,16}") {
            throw .invalid(rule: "device.format", path: "\(at).device_models[\(j)]")
        }
        return SourceIdentity(bundleIDs: ids, bundlePrefixes: prefixes, sourceNames: names, deviceModels: models)
    }

    private func capabilities(_ t: [String: CatalogJSON], integration: Tracker.Integration,
                              _ path: String) throws(CatalogError) -> [TrackerSignal: Capability] {
        let raw = try object(t, "capabilities", path) ?? [:]
        var capabilities: [TrackerSignal: Capability] = [:]
        for signal in TrackerSignal.allCases {
            let at = "\(path).capabilities.\(signal.rawValue)"
            guard let value = try string(raw, signal.rawValue, "\(path).capabilities", required: false) else {
                capabilities[signal] = integration == .none ? .no : .unverified
                continue
            }
            guard let capability = Capability(rawValue: value) else { throw .invalid(rule: "enum.capability", path: at) }
            if integration == .none, capability != .no { throw .invalid(rule: "integration.none", path: at) }
            capabilities[signal] = capability
        }
        return capabilities
    }

    /// One bundle ID belongs to one tracker: no ID twice, no ID under another tracker's prefix, and
    /// prefixes overlap only between trackers told apart by device (Apple Watch and iPhone).
    private static func checkOwnership(_ trackers: [Tracker]) throws(CatalogError) {
        for (i, a) in trackers.enumerated() {
            for (k, b) in trackers.enumerated() where k != i {
                let path = "trackers[\(k)].healthkit"
                for (j, id) in b.identity.bundleIDs.enumerated()
                where a.identity.bundleIDs.contains(where: { $0.lowercased() == id.lowercased() })
                    || a.identity.bundlePrefixes.contains(where: { covers($0, id) }) {
                    throw .invalid(rule: "bundle.duplicate", path: "\(path).bundle_ids[\(j)]")
                }
                let byDevice = !a.identity.deviceModels.isEmpty && !b.identity.deviceModels.isEmpty
                for (j, prefix) in b.identity.bundlePrefixes.enumerated() where !byDevice
                    && a.identity.bundlePrefixes.contains(where: { covers($0, prefix) || covers(prefix, $0) }) {
                    throw .invalid(rule: "bundle.duplicate", path: "\(path).bundle_id_prefixes[\(j)]")
                }
            }
        }
    }

    /// Prefix overlap for content checks: also "com.a." against "com.a" (one may lack the trailing dot).
    private static func covers(_ prefix: String, _ id: String) -> Bool {
        let p = prefix.lowercased(), i = id.lowercased()
        let bare = p.hasSuffix(".") ? String(p.dropLast()) : p
        return i == bare || i.hasPrefix(bare + ".")
    }

    // MARK: fields

    private func string(_ o: [String: CatalogJSON], _ key: String, _ path: String,
                        required: Bool) throws(CatalogError) -> String? {
        let at = path.isEmpty ? key : "\(path).\(key)"
        switch o[key] {
        case .string(let s)?: return s
        case nil, .null?:
            if required { throw .invalid(rule: "missing", path: at) }
            return nil
        default: throw .invalid(rule: "type", path: at)
        }
    }

    private func object(_ o: [String: CatalogJSON], _ key: String,
                        _ path: String) throws(CatalogError) -> [String: CatalogJSON]? {
        switch o[key] {
        case .object(let value)?: return value
        case nil, .null?: return nil
        default: throw .invalid(rule: "type", path: path.isEmpty ? key : "\(path).\(key)")
        }
    }

    private func strings(_ o: [String: CatalogJSON], _ key: String, _ path: String) throws(CatalogError) -> [String] {
        let at = "\(path).\(key)"
        switch o[key] {
        case nil, .null?: return []
        case .array(let items)?:
            var values: [String] = []
            for (j, item) in items.enumerated() {
                guard case .string(let s) = item else { throw .invalid(rule: "type", path: "\(at)[\(j)]") }
                values.append(s)
            }
            return values
        default: throw .invalid(rule: "type", path: at)
        }
    }

    /// `{"en": [...], "de": [...]}`, the same count in both, at most `max`, each a step of ≤ 240
    /// characters. Absent: empty (nothing to show yet).
    private func list(_ o: [String: CatalogJSON], _ key: String, _ path: String,
                      max: Int) throws(CatalogError) -> Localized<[String]> {
        let at = path.isEmpty ? key : "\(path).\(key)"
        guard let pair = try object(o, key, path) else { return Localized(en: [], de: []) }
        guard pair["en"] != nil, pair["de"] != nil else { throw .invalid(rule: "text.pair", path: at) }
        let en = try strings(pair, "en", at), de = try strings(pair, "de", at)
        guard en.count == de.count else { throw .invalid(rule: "text.pair", path: at) }
        guard en.count <= max else { throw .invalid(rule: "text.count", path: at) }
        for (j, s) in en.enumerated() { try text(s, max: 240, "\(at).en[\(j)]") }
        for (j, s) in de.enumerated() { try text(s, max: 240, "\(at).de[\(j)]") }
        return Localized(en: en, de: de)
    }

    /// Plain text only (§2.5): shown with `Text(verbatim:)`, so no markup, no links, no control or format
    /// characters (bidi overrides, zero-width), never the denylisted brand.
    private func text(_ s: String, max: Int, _ path: String) throws(CatalogError) {
        guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { throw .invalid(rule: "text.empty", path: path) }
        guard s.count <= max else { throw .invalid(rule: "text.length", path: path) }
        guard !s.unicodeScalars.contains(where: { [.control, .format].contains($0.properties.generalCategory) }) else {
            throw .invalid(rule: "text.control", path: path)
        }
        let lower = s.lowercased()
        guard !["<", ">", "](", "://", "www."].contains(where: { lower.contains($0) }) else {
            throw .invalid(rule: "text.markup", path: path)
        }
        guard s.range(of: Self.brandPattern, options: [.regularExpression, .caseInsensitive]) == nil else {
            throw .invalid(rule: "text.brand", path: path)
        }
    }

    /// YYYY-MM-DD, a real day, not after tomorrow anywhere on Earth.
    private func date(_ s: String, _ path: String) throws(CatalogError) {
        guard isDate(s) else { throw .invalid(rule: "date", path: path) }
    }

    private func isDate(_ s: String) -> Bool {
        guard Self.matches(s, "[0-9]{4}-[0-9]{2}-[0-9]{2}") else { return false }
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        guard let day = f.date(from: s), f.string(from: day) == s else { return false }
        return s <= f.string(from: now.addingTimeInterval(38 * 3_600))
    }

    /// The whole string, never a part of it (`$` alone would allow a trailing newline).
    static func matches(_ s: String, _ pattern: String) -> Bool {
        s.range(of: #"\A(?:"# + pattern + #")\z"#, options: .regularExpression) != nil
    }

    /// `https`, no user, no port, a host on the tracker's allowlist (or RYFT's); else nil.
    static func helpURL(_ string: String, trackerID: String) -> URL? {
        guard let c = URLComponents(string: string), c.scheme?.lowercased() == "https",
              c.user == nil, c.password == nil, c.port == nil,
              let host = c.host?.lowercased(), !host.isEmpty, let url = c.url else { return nil }
        let allowed = (helpHosts[trackerID] ?? []) + [anyHelpHost]
        return allowed.contains { host == $0 || host.hasSuffix("." + $0) } ? url : nil
    }
}

// BEGIN GENERATED trackers.json (scripts/trackers.py --write from Content/trackers.json; do not edit)
extension TrackerCatalog {
    /// Content/trackers.json at build time: the copy that always works (offline, first launch, demo).
    static let bundledJSON = #"""
    {
      "schema_version": 1,
      "version": "2026-10-22.1",
      "checked": "2026-10-22",
      "status_values": [
        "yes",
        "partial",
        "no",
        "unverified"
      ],
      "health_access": {
        "steps": {
          "en": [],
          "de": []
        },
        "checked": "2026-10-22"
      },
      "trackers": [
        {
          "id": "apple_watch",
          "name": "Apple Watch",
          "form": "watch",
          "app_name": "Watch",
          "integration": "apple_builtin",
          "healthkit": {
            "bundle_ids": [],
            "bundle_id_prefixes": [
              "com.apple.health."
            ],
            "source_names": [],
            "device_models": [
              "Watch"
            ],
            "verified": {
              "bundle_ids": false,
              "source_names": false
            }
          },
          "app_store_id": "1069511734",
          "capabilities": {
            "heart_rate": "yes",
            "hrv": "yes",
            "resting_hr": "yes",
            "sleep": "yes",
            "sleep_stages": "yes",
            "respiratory_rate": "yes",
            "spo2": "partial",
            "workouts": "yes",
            "steps": "yes"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.apple.com/guide/iphone/intro-to-health-data-iphbb8259c61/ios",
          "sources": [
            {
              "url": "https://support.apple.com/guide/iphone/intro-to-health-data-iphbb8259c61/ios",
              "covers": "Heart rate and blood oxygen sent from Apple Watch to Health (iOS 27 guide)"
            },
            {
              "url": "https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn",
              "covers": "HRV: system records samples on Apple Watch"
            },
            {
              "url": "https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/restingheartrate",
              "covers": "Resting HR estimation and replacement"
            },
            {
              "url": "https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/respiratoryrate",
              "covers": "Respiratory rate recorded on Apple Watch"
            },
            {
              "url": "https://support.apple.com/en-us/108906",
              "covers": "Sleep stages, respiratory rate during sleep, charging reminders"
            },
            {
              "url": "https://support.apple.com/en-us/120358",
              "covers": "Blood Oxygen models and the US iPhone-analysis variant"
            },
            {
              "url": "https://support.apple.com/en-us/120277",
              "covers": "Resting and walking heart rate; Recovery HRV on Series 12 and Ultra 4"
            },
            {
              "url": "https://support.apple.com/en-us/108779",
              "covers": "Fitness Tracking toggle, data source priority"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "garmin",
          "name": "Garmin",
          "form": "watch",
          "app_name": "Garmin Connect",
          "integration": "vendor_app",
          "healthkit": {
            "bundle_ids": [
              "com.garmin.connect.mobile"
            ],
            "bundle_id_prefixes": [
              "com.garmin.connect.mobile"
            ],
            "source_names": [
              "Connect"
            ],
            "device_models": [],
            "verified": {
              "bundle_ids": true,
              "source_names": true
            }
          },
          "app_store_id": "583446403",
          "capabilities": {
            "heart_rate": "yes",
            "hrv": "no",
            "resting_hr": "no",
            "sleep": "yes",
            "sleep_stages": "unverified",
            "respiratory_rate": "no",
            "spo2": "no",
            "workouts": "yes",
            "steps": "yes"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA",
          "sources": [
            {
              "url": "https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA",
              "covers": "Data types sent, foreground requirement, setup in both apps, source name 'Connect'"
            },
            {
              "url": "https://itunes.apple.com/lookup?id=583446403",
              "covers": "Bundle ID"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "oura",
          "name": "Oura",
          "form": "ring",
          "app_name": "Oura",
          "integration": "vendor_app",
          "healthkit": {
            "bundle_ids": [
              "com.ouraring.oura"
            ],
            "bundle_id_prefixes": [
              "com.ouraring.oura"
            ],
            "source_names": [
              "Oura"
            ],
            "device_models": [],
            "verified": {
              "bundle_ids": true,
              "source_names": true
            }
          },
          "app_store_id": "1043837948",
          "capabilities": {
            "heart_rate": "yes",
            "hrv": "no",
            "resting_hr": "no",
            "sleep": "yes",
            "sleep_stages": "yes",
            "respiratory_rate": "yes",
            "spo2": "no",
            "workouts": "yes",
            "steps": "yes"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration",
          "sources": [
            {
              "url": "https://support.ouraring.com/hc/en-us/articles/360025438734-Apple-Health-Integration",
              "covers": "Export list, setup, membership requirement, Background App Refresh and Low Power Mode (last updated 2026-10-14)"
            },
            {
              "url": "https://ouraring.com/blog/apple-health/",
              "covers": "'Your Apple Health data syncs only after opening Oura.'"
            },
            {
              "url": "https://itunes.apple.com/lookup?id=1043837948",
              "covers": "Bundle ID"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "polar",
          "name": "Polar",
          "form": "watch",
          "app_name": "Polar Flow",
          "integration": "vendor_app",
          "healthkit": {
            "bundle_ids": [
              "fi.polar.polarflow"
            ],
            "bundle_id_prefixes": [
              "fi.polar.polarflow"
            ],
            "source_names": [
              "Polar Flow"
            ],
            "device_models": [],
            "verified": {
              "bundle_ids": true,
              "source_names": true
            }
          },
          "app_store_id": "717172678",
          "capabilities": {
            "heart_rate": "partial",
            "hrv": "no",
            "resting_hr": "no",
            "sleep": "yes",
            "sleep_stages": "no",
            "respiratory_rate": "no",
            "spo2": "no",
            "workouts": "yes",
            "steps": "yes"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.polar.com/us-en/support/connecting_polar_flow_with_apple_health",
          "sources": [
            {
              "url": "https://support.polar.com/us-en/support/connecting_polar_flow_with_apple_health",
              "covers": "Synced data list, setup, Sync now, priority"
            },
            {
              "url": "https://itunes.apple.com/lookup?id=717172678",
              "covers": "Bundle ID"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "suunto",
          "name": "Suunto",
          "form": "watch",
          "app_name": "Suunto",
          "integration": "vendor_app",
          "healthkit": {
            "bundle_ids": [
              "com.sports-tracker.suunto.iphone"
            ],
            "bundle_id_prefixes": [
              "com.sports-tracker.suunto.iphone"
            ],
            "source_names": [
              "Suunto"
            ],
            "device_models": [],
            "verified": {
              "bundle_ids": true,
              "source_names": false
            }
          },
          "app_store_id": "1230327951",
          "capabilities": {
            "heart_rate": "unverified",
            "hrv": "unverified",
            "resting_hr": "unverified",
            "sleep": "unverified",
            "sleep_stages": "unverified",
            "respiratory_rate": "unverified",
            "spo2": "unverified",
            "workouts": "unverified",
            "steps": "unverified"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": null,
          "sources": [
            {
              "url": "https://apps.apple.com/us/app/suunto/id1230327951",
              "covers": "'The Suunto app connects with Apple Health. Go to app settings to start sharing your data.'"
            },
            {
              "url": "https://forum.suunto.com/topic/739/apple-health",
              "covers": "User reports (not vendor documentation)"
            },
            {
              "url": "https://itunes.apple.com/lookup?id=1230327951",
              "covers": "Bundle ID"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "coros",
          "name": "COROS",
          "form": "watch",
          "app_name": "COROS",
          "integration": "vendor_app",
          "healthkit": {
            "bundle_ids": [
              "com.coros.coros"
            ],
            "bundle_id_prefixes": [
              "com.coros.coros"
            ],
            "source_names": [
              "COROS"
            ],
            "device_models": [],
            "verified": {
              "bundle_ids": true,
              "source_names": true
            }
          },
          "app_store_id": "1277625343",
          "capabilities": {
            "heart_rate": "yes",
            "hrv": "no",
            "resting_hr": "no",
            "sleep": "yes",
            "sleep_stages": "unverified",
            "respiratory_rate": "no",
            "spo2": "no",
            "workouts": "yes",
            "steps": "yes"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.coros.com/hc/en-us/articles/360041549551-Connecting-Apple-Health-with-COROS-App",
          "sources": [
            {
              "url": "https://support.coros.com/hc/en-us/articles/360041549551-Connecting-Apple-Health-with-COROS-App",
              "covers": "Setup and supported data types (updated 2026-10-19)"
            },
            {
              "url": "https://support.coros.com/hc/en-us/articles/360043975752-Exporting-Workout-Data-and-Uploading-to-3rd-Party-Apps",
              "covers": "Push on watch sync; 'Daily data is not supported for integration or export.'"
            },
            {
              "url": "https://support.coros.com/hc/en-us/articles/5146420791060-COROS-App-Release-Notes-iOS",
              "covers": "Workouts synced to Apple Health (V3.1.6)"
            },
            {
              "url": "https://itunes.apple.com/lookup?id=1277625343",
              "covers": "Bundle ID"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "withings",
          "name": "Withings",
          "form": "watch",
          "app_name": "Withings",
          "integration": "vendor_app",
          "healthkit": {
            "bundle_ids": [
              "com.withings.wiScaleNG"
            ],
            "bundle_id_prefixes": [
              "com.withings.wiScaleNG"
            ],
            "source_names": [
              "Withings",
              "Health Mate"
            ],
            "device_models": [],
            "verified": {
              "bundle_ids": true,
              "source_names": false
            }
          },
          "app_store_id": "542701020",
          "capabilities": {
            "heart_rate": "partial",
            "hrv": "unverified",
            "resting_hr": "unverified",
            "sleep": "unverified",
            "sleep_stages": "unverified",
            "respiratory_rate": "unverified",
            "spo2": "unverified",
            "workouts": "unverified",
            "steps": "unverified"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.withings.com/hc/en-us/articles/46746224229777-Partner-Apps-Apple-Health-Exporting-Withings-data-into-Apple-Health",
          "sources": [
            {
              "url": "https://support.withings.com/hc/en-us/articles/46746224229777-Partner-Apps-Apple-Health-Exporting-Withings-data-into-Apple-Health",
              "covers": "Setup, manual refresh, Withings+ rule (updated 2026-10-21)"
            },
            {
              "url": "https://support.withings.com/hc/en-us/articles/203934573-Partner-Apps-What-is-Apple-Health",
              "covers": "Combined list of shareable categories (updated 2026-10-22)"
            },
            {
              "url": "https://support.withings.com/hc/en-us/articles/203956733-Partner-Apps-Apple-Health-Data-Synchronization-Issues",
              "covers": "15-minute delay; iOS path Settings → Apps → Health → Data Access & Devices"
            },
            {
              "url": "https://support.withings.com/hc/en-us/articles/360000158447-Sleep-Analyzer-EU-ROW-Monitoring-my-sleep-heart-rate",
              "covers": "Sleep Analyzer heart rate doesn't sync to Apple Health"
            },
            {
              "url": "https://itunes.apple.com/lookup?id=542701020",
              "covers": "Bundle ID"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "amazfit",
          "name": "Amazfit (Zepp)",
          "form": "watch",
          "app_name": "Zepp",
          "integration": "vendor_app",
          "healthkit": {
            "bundle_ids": [
              "com.huami.watch"
            ],
            "bundle_id_prefixes": [
              "com.huami.watch"
            ],
            "source_names": [
              "Zepp"
            ],
            "device_models": [],
            "verified": {
              "bundle_ids": true,
              "source_names": false
            }
          },
          "app_store_id": "1127269366",
          "capabilities": {
            "heart_rate": "unverified",
            "hrv": "partial",
            "resting_hr": "unverified",
            "sleep": "unverified",
            "sleep_stages": "unverified",
            "respiratory_rate": "unverified",
            "spo2": "unverified",
            "workouts": "yes",
            "steps": "unverified"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.amazfit.com/en/amazfit_gts_2_mini/docs/N6cUdJxDRo6rbfxiLs1cJDBrnRd",
          "sources": [
            {
              "url": "https://support.amazfit.com/en/amazfit_gts_2_mini/docs/N6cUdJxDRo6rbfxiLs1cJDBrnRd",
              "covers": "'For Apple Health/Google Fit, please add Zepp app as the data source in them.' (published 2024-12-19)"
            },
            {
              "url": "https://us.amazfit.com/blogs/product-update/amazfit-balance-2-series-august-2026-update-a-smarter-training-experience-with-zepp-os-6",
              "covers": "HRV to Apple Health for Balance 2 series (2026-08-26)"
            },
            {
              "url": "https://us.amazfit.com/products/helio-strap",
              "covers": "Third-party workout data sync includes Apple Health"
            },
            {
              "url": "https://itunes.apple.com/lookup?id=1127269366",
              "covers": "Bundle ID"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "ultrahuman",
          "name": "Ultrahuman",
          "form": "ring",
          "app_name": "Ultrahuman",
          "integration": "vendor_app",
          "healthkit": {
            "bundle_ids": [
              "com.ultrahuman.ios"
            ],
            "bundle_id_prefixes": [
              "com.ultrahuman.ios"
            ],
            "source_names": [
              "Ultrahuman"
            ],
            "device_models": [],
            "verified": {
              "bundle_ids": true,
              "source_names": true
            }
          },
          "app_store_id": "1491286709",
          "capabilities": {
            "heart_rate": "yes",
            "hrv": "unverified",
            "resting_hr": "unverified",
            "sleep": "unverified",
            "sleep_stages": "unverified",
            "respiratory_rate": "unverified",
            "spo2": "unverified",
            "workouts": "yes",
            "steps": "unverified"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://www.ultrahuman.com/blog/how-to-access-your-hrv-data-on-apple-health/",
          "sources": [
            {
              "url": "https://www.ultrahuman.com/blog/how-to-access-your-hrv-data-on-apple-health/",
              "covers": "Setup, HRV claim and permission screenshots (published 2025-05-30; screenshots from 2024)"
            },
            {
              "url": "https://itunes.apple.com/lookup?id=1491286709",
              "covers": "Bundle ID"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "fitbit",
          "name": "Fitbit",
          "form": "watch",
          "app_name": "Google Health",
          "integration": "vendor_app",
          "healthkit": {
            "bundle_ids": [
              "com.fitbit.FitbitMobile"
            ],
            "bundle_id_prefixes": [
              "com.fitbit.FitbitMobile"
            ],
            "source_names": [
              "Google Health"
            ],
            "device_models": [],
            "verified": {
              "bundle_ids": true,
              "source_names": true
            }
          },
          "app_store_id": "462638897",
          "capabilities": {
            "heart_rate": "yes",
            "hrv": "no",
            "resting_hr": "yes",
            "sleep": "yes",
            "sleep_stages": "yes",
            "respiratory_rate": "yes",
            "spo2": "yes",
            "workouts": "yes",
            "steps": "yes"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.google.com/googlehealth/answer/17037331?hl=en",
          "sources": [
            {
              "url": "https://support.google.com/googlehealth/answer/17037331?hl=en",
              "covers": "Setup, requirements, read/write data-type table, source name in Apple Health"
            },
            {
              "url": "https://itunes.apple.com/lookup?id=462638897",
              "covers": "Bundle ID; App Store name 'Google Health (Fitbit)'"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "samsung_galaxy_watch",
          "name": "Samsung Galaxy Watch",
          "form": "watch",
          "app_name": null,
          "integration": "none",
          "healthkit": {
            "bundle_ids": [],
            "bundle_id_prefixes": [],
            "source_names": [],
            "device_models": [],
            "verified": {
              "bundle_ids": false,
              "source_names": false
            }
          },
          "app_store_id": null,
          "capabilities": {
            "heart_rate": "no",
            "hrv": "no",
            "resting_hr": "no",
            "sleep": "no",
            "sleep_stages": "no",
            "respiratory_rate": "no",
            "spo2": "no",
            "workouts": "no",
            "steps": "no"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://www.samsung.com/us/support/answer/ANS10004668/",
          "sources": [
            {
              "url": "https://www.samsung.com/us/support/answer/ANS10004668/",
              "covers": "iOS compatibility list"
            },
            {
              "url": "https://apps.apple.com/us/app/samsung-health/id1224541484",
              "covers": "Samsung Health for iOS: older models only; reads steps from Apple Health"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "other",
          "name": "Other",
          "form": "other",
          "app_name": null,
          "integration": "unknown",
          "healthkit": {
            "bundle_ids": [],
            "bundle_id_prefixes": [],
            "source_names": [],
            "device_models": [],
            "verified": {
              "bundle_ids": false,
              "source_names": false
            }
          },
          "app_store_id": null,
          "capabilities": {
            "heart_rate": "unverified",
            "hrv": "unverified",
            "resting_hr": "unverified",
            "sleep": "unverified",
            "sleep_stages": "unverified",
            "respiratory_rate": "unverified",
            "spo2": "unverified",
            "workouts": "unverified",
            "steps": "unverified"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.apple.com/en-us/108779",
          "sources": [
            {
              "url": "https://support.apple.com/en-us/108779",
              "covers": "Add data from other apps; data source priority"
            }
          ],
          "checked": "2026-10-22"
        },
        {
          "id": "iphone",
          "name": "Just my iPhone",
          "form": "phone",
          "app_name": "Health",
          "integration": "apple_builtin",
          "healthkit": {
            "bundle_ids": [],
            "bundle_id_prefixes": [
              "com.apple.health."
            ],
            "source_names": [],
            "device_models": [
              "iPhone"
            ],
            "verified": {
              "bundle_ids": false,
              "source_names": false
            }
          },
          "app_store_id": "1242545199",
          "capabilities": {
            "heart_rate": "partial",
            "hrv": "no",
            "resting_hr": "no",
            "sleep": "partial",
            "sleep_stages": "no",
            "respiratory_rate": "no",
            "spo2": "no",
            "workouts": "partial",
            "steps": "yes"
          },
          "capability_notes": {},
          "setup_steps": {
            "en": [],
            "de": []
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [],
            "de": []
          },
          "help_url": "https://support.apple.com/guide/iphone/intro-to-health-data-iphbb8259c61/ios",
          "sources": [
            {
              "url": "https://support.apple.com/guide/iphone/intro-to-health-data-iphbb8259c61/ios",
              "covers": "Health data from iPhone (iOS 27 guide)"
            },
            {
              "url": "https://support.apple.com/en-us/123184",
              "covers": "AirPods Pro 3 heart rate in Health; Fitness app Workout tab on iPhone"
            },
            {
              "url": "https://support.apple.com/guide/iphone/control-access-to-information-in-apps-iph251e92810/ios",
              "covers": "Settings → Privacy & Security → Motion & Fitness"
            }
          ],
          "checked": "2026-10-22"
        }
      ]
    }
    """#
}
// END GENERATED trackers.json
