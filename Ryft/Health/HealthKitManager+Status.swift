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
    /// the main actor. `now` bounds the dates ("not after tomorrow"). Hostile input costs little: the size
    /// and the nesting are checked on the bytes before anything is parsed.
    static func decode(_ data: Data, now: Date) throws(CatalogError) -> TrackerCatalog {
        guard data.count <= maxBytes else { throw .tooLarge }
        guard nesting(data) <= maxDepth else { throw .invalid(rule: "depth", path: "") }
        guard String(data: data, encoding: .utf8) != nil,
              let parsed = try? JSONSerialization.jsonObject(with: data),
              let json = CatalogJSON(parsed), case .object(let root) = json else { throw .notJSON }
        try CatalogValidator.checkBrand(json)
        return try CatalogValidator(now: now).catalog(root)
    }

    /// The denylisted brand's pattern (the hook's), and the app's check for it on folded text: for tests.
    static var brandPattern: String { CatalogValidator.brandPattern }
    static func containsBrand(_ s: String) -> Bool { CatalogValidator.hasBrand(s) }

    /// trackers.json needs 5 levels; deeper is refused unparsed (the parser recurses).
    static let maxDepth = 8

    /// The deepest nesting of objects and arrays, counted on the bytes outside strings; it stops counting
    /// once past `maxDepth`.
    static func nesting(_ data: Data) -> Int {
        data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Int in
            var depth = 0, deepest = 0, inString = false, escaped = false
            for byte in bytes {
                if inString {
                    if escaped {
                        escaped = false
                    } else if byte == 0x5C {
                        escaped = true
                    } else if byte == 0x22 {
                        inString = false
                    }
                    continue
                }
                switch byte {
                case 0x22: inString = true
                case 0x5B, 0x7B:
                    depth += 1
                    deepest = max(deepest, depth)
                    if deepest > maxDepth { return deepest }
                case 0x5D, 0x7D: depth -= 1
                default: break
                }
            }
            return deepest
        }
    }

    /// `YYYY-MM-DD.N` as (date, N), for "the newest version wins" (T2): by date, then N as a number, so
    /// ".10" comes after ".9". `nil` for anything else.
    static func versionOrder(_ version: String) -> (date: String, n: Int)? {
        guard CatalogValidator.matches(version, CatalogValidator.versionPattern),
              let dot = version.firstIndex(of: "."), let n = Int(version[version.index(after: dot)...]) else { return nil }
        return (String(version[..<dot]), n)
    }

    /// `version` is newer than `other`; an unreadable version is never newer, and anything readable beats one.
    static func isNewer(_ version: String, than other: String) -> Bool {
        guard let a = versionOrder(version) else { return false }
        guard let b = versionOrder(other) else { return true }
        return a > b
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
    /// The build's App Store id for this tracker id (`CatalogValidator.storeIDs`): content can't change it.
    let appStoreID: String?
    /// Every signal: a key the copy left out is `.unverified` (`.no` for integration `none`).
    let capabilities: [TrackerSignal: Capability]
    let notes: [TrackerSignal: Localized<String>]
    let setup: Localized<[String]>
    let habits: Localized<[String]>
    let limits: Localized<[String]>
    /// The vendor's guide; dropped unless its host is exactly one the build lists for this tracker (§2.5).
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
    /// The catalog every screen reads: the bundled copy, or the newest valid one from ryftapp.de.
    var trackerCatalog: TrackerCatalog { catalogStore.current }
}

/// JSON as it came, its types kept (a bool is no number), so every rule can name the exact path.
private enum CatalogJSON {
    case object([String: CatalogJSON]), array([CatalogJSON]), string(String), number(Double), bool(Bool), null

    /// From `JSONSerialization`'s objects (the nesting is bounded before parsing, `TrackerCatalog.nesting`).
    init?(_ value: Any) {
        switch value {
        case let s as String: self = .string(s)
        case let n as NSNumber:
            self = CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let items as [Any]:
            var array: [CatalogJSON] = []
            array.reserveCapacity(items.count)
            for item in items {
                guard let json = CatalogJSON(item) else { return nil }
                array.append(json)
            }
            self = .array(array)
        case let fields as [String: Any]:
            var object: [String: CatalogJSON] = [:]
            for (key, item) in fields {
                guard let json = CatalogJSON(item) else { return nil }
                object[key] = json
            }
            self = .object(object)
        case is NSNull: self = .null
        default: return nil
        }
    }

    /// Every string, keys included; with its path only when asked (`path(where:)`, on a hit).
    func strings(into result: inout [String]) {
        switch self {
        case .string(let s):
            result.append(s)
        case .array(let items):
            for item in items { item.strings(into: &result) }
        case .object(let fields):
            for (key, value) in fields {
                result.append(key)
                value.strings(into: &result)
            }
        case .number, .bool, .null:
            break
        }
    }

    /// The path of the first string (or key) that `test` accepts. Paths reach `lastFailure` and Copy
    /// diagnostics, so a key appears only when the schema knows it, any other as "?", and the path at most
    /// 80 characters (`CatalogValidator.safePath`).
    func path(at path: String = "", where test: (String) -> Bool) -> String? {
        switch self {
        case .string(let s):
            return test(s) ? CatalogValidator.safePath(path) : nil
        case .array(let items):
            for (i, item) in items.enumerated() {
                if let hit = item.path(at: "\(path)[\(i)]", where: test) { return hit }
            }
            return nil
        case .object(let fields):
            for (key, value) in fields {
                let name = CatalogValidator.safeKey(key)
                let at = path.isEmpty ? name : "\(path).\(name)"
                if test(key) { return CatalogValidator.safePath(at) }
                if let hit = value.path(at: at, where: test) { return hit }
            }
            return nil
        case .number, .bool, .null:
            return nil
        }
    }
}

/// The rules of design.md §2.3 and the trust rules of §2.5, each failure named `rule` at `path`
/// ("text.markup" at "trackers[3].setup_steps.de[2]"). Written for a hostile remote copy: every list is
/// capped, the brand check sees every string, and nothing a copy says can claim an Apple device, a store
/// page or a link host the build doesn't list.
private struct CatalogValidator {
    let now: Date

    /// The denylisted brand, as `.claude/hooks/pre-edit-guard.sh` has it (`scripts/trackers.py --check`
    /// keeps the two equal). Matched on folded text (`folded`).
    static let brandPattern = #"wh[o0]{2}p|w[-. ]h[-. ]o[-. ]o[-. ]p"#
    static let versionPattern = #"[0-9]{4}-[0-9]{2}-[0-9]{2}\.[0-9]{1,3}"#
    /// Help links: exactly these hosts per tracker id, and RYFT's own for any. Compiled on purpose: a new
    /// vendor page host needs a release.
    static let helpHosts: [String: Set<String>] = [
        "garmin": ["support.garmin.com"], "oura": ["support.ouraring.com"], "polar": ["support.polar.com"],
        "coros": ["support.coros.com"], "withings": ["support.withings.com"], "amazfit": ["support.amazfit.com"],
        "ultrahuman": ["www.ultrahuman.com"], "fitbit": ["support.google.com"], "samsung_galaxy_watch": ["www.samsung.com"],
        "apple_watch": ["support.apple.com"], "iphone": ["support.apple.com"], "other": ["support.apple.com"],
    ]
    /// On a shared host, the vendor's own part of it.
    static let helpPaths: [String: [String]] = ["fitbit": ["/googlehealth/answer/"]] // not /googlehealth/thread/: user posts
    static let anyHelpHost = "ryftapp.de"
    /// On RYFT's own host, content pages only: never the universal-link routes (`/auth/…`, `/invite/…`).
    static let anyHelpPaths = ["/setup/", "/help/"]

    /// The keys schema v1 knows: the only ones a path may name.
    static let knownKeys: Set<String> = Set([
        "schema_version", "version", "checked", "status_values", "health_access", "steps", "en", "de", "trackers", "id", "name",
        "form", "app_name", "integration", "healthkit", "bundle_ids", "bundle_id_prefixes", "source_names", "device_models",
        "verified", "app_store_id", "app_store_url", "capabilities", "capability_notes", "setup_steps", "habits", "limits",
        "help_url", "sources", "url", "covers",
    ] + TrackerSignal.allCases.map(\.rawValue))

    /// A document key as a path may show it: a key of the schema, else "?" (never the document's own text).
    static func safeKey(_ key: String) -> String { knownKeys.contains(key) ? key : "?" }

    /// At most 80 characters of a path.
    static func safePath(_ path: String) -> String { path.count <= 80 ? path : String(path.prefix(79)) + "…" }
    /// App Store ids per tracker id: content can't point a store button anywhere else.
    static let storeIDs: [String: String] = [
        "apple_watch": "1069511734", "garmin": "583446403", "oura": "1043837948", "polar": "717172678",
        "suunto": "1230327951", "coros": "1277625343", "withings": "542701020", "amazfit": "1127269366",
        "ultrahuman": "1491286709", "fitbit": "462638897", "iphone": "1242545199",
    ]
    /// The integration per tracker id: content may repeat it, never change it (the Watch stays Apple's).
    static let integrations: [String: Tracker.Integration] = [
        "apple_watch": .appleBuiltin, "iphone": .appleBuiltin, "garmin": .vendorApp, "oura": .vendorApp, "polar": .vendorApp,
        "suunto": .vendorApp, "coros": .vendorApp, "withings": .vendorApp, "amazfit": .vendorApp, "ultrahuman": .vendorApp,
        "fitbit": .vendorApp, "samsung_galaxy_watch": .none, "other": .unknown,
    ]
    /// The bundle IDs this build knows per tracker id (lowercased): no other tracker may claim, cover or sit
    /// under them, so Garmin's app can't move under another name. New IDs for the same tracker stay possible.
    static let knownBundles: [String: [String]] = [
        "garmin": ["com.garmin.connect.mobile"], "oura": ["com.ouraring.oura"], "polar": ["fi.polar.polarflow"],
        "suunto": ["com.sports-tracker.suunto.iphone"], "coros": ["com.coros.coros"], "withings": ["com.withings.wiscaleng"],
        "amazfit": ["com.huami.watch"], "ultrahuman": ["com.ultrahuman.ios"], "fitbit": ["com.fitbit.fitbitmobile"],
    ]
    /// The only trackers that may claim Apple's bundle IDs and device models.
    static let appleTrackers: Set<String> = ["apple_watch", "iphone"]
    /// Each identity list (bundle IDs, prefixes, source names, device models).
    static let maxIdentities = 8
    /// The text rules in one regular expression, compiled once, one native scan per string. Its groups, in
    /// order: control, format (bidi overrides, zero-width), private-use, unassigned and separator characters;
    /// letters of another script than Latin (look-alikes); markup, links and addresses.
    static let refusedText = try? NSRegularExpression(
        pattern: #"([\p{Cc}\p{Cf}\p{Co}\p{Cn}\p{Zl}\p{Zp}\x{E000}-\x{F8FF}\x{F0000}-\x{FFFFD}\x{100000}-\x{10FFFD}])|"#
            + #"([^\p{Script=Latin}\p{Script=Common}\p{Script=Inherited}])|(<|>|\]\(|://|www\.|@|mailto:|tel:)"#,
        options: [.caseInsensitive])
    /// Combining marks one character may stack.
    static let maxMarks = 3
    static let marks: Set<Unicode.GeneralCategory> = [.nonspacingMark, .spacingMark, .enclosingMark]
    static let refusedTextRules = ["text.control", "text.script", "text.markup"]

    /// The rule `s` breaks, if any; a pattern that didn't compile refuses everything (fail closed).
    static func refusal(_ s: String) -> String? {
        guard let regex = refusedText else { return "text.control" }
        guard let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1...3).first { match.range(at: $0).location != NSNotFound }.map { refusedTextRules[$0 - 1] } ?? "text.control"
    }

    /// Compatibility forms, case, diacritics and width folded away: "ＷＨ…", "w\u{301}h…" read as plain letters.
    static func folded(_ s: String) -> String {
        s.precomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// The brand in any string of the copy, keys included (ids, bundle IDs, URLs, keys the app ignores):
    /// one search over all of it, folded (a line break can't be part of the pattern); the path only on a hit.
    static func checkBrand(_ json: CatalogJSON) throws(CatalogError) {
        var strings: [String] = []
        json.strings(into: &strings)
        guard hasBrand(strings.joined(separator: "\n")) else { return }
        throw .invalid(rule: "text.brand", path: json.path(where: hasBrand) ?? "")
    }

    /// `brandPattern` on folded text, as a scan of its bytes: the same two forms ("wh", two of "o0", "p"; or
    /// its letters each followed by one of "-. "), without a regular expression's cost on 256 KiB
    /// (`DecodingTests` holds the two to the same answers).
    static func hasBrand(_ s: String) -> Bool {
        var text = folded(s)
        return text.withUTF8 { (b: UnsafeBufferPointer<UInt8>) -> Bool in
            let n = b.count
            func any(_ i: Int, _ set: (UInt8, UInt8, UInt8)) -> Bool {
                i < n && (b[i] == set.0 || b[i] == set.1 || b[i] == set.2)
            }
            let o0: (UInt8, UInt8, UInt8) = (0x6F, 0x30, 0x6F), sep: (UInt8, UInt8, UInt8) = (0x2D, 0x2E, 0x20)
            let h: (UInt8, UInt8, UInt8) = (0x68, 0x68, 0x68), o: (UInt8, UInt8, UInt8) = (0x6F, 0x6F, 0x6F)
            let p: (UInt8, UInt8, UInt8) = (0x70, 0x70, 0x70)
            var i = 0
            while i < n {
                if b[i] == 0x77 {
                    if any(i + 1, h), any(i + 2, o0), any(i + 3, o0), any(i + 4, p) { return true }
                    if any(i + 1, sep), any(i + 2, h), any(i + 3, sep), any(i + 4, o), any(i + 5, sep), any(i + 6, o),
                       any(i + 7, sep), any(i + 8, p) { return true }
                }
                i += 1
            }
            return false
        }
    }

    func catalog(_ root: [String: CatalogJSON]) throws(CatalogError) -> TrackerCatalog {
        guard case .number(let schema)? = root["schema_version"] else { throw .schema(0) }
        guard schema == 1 else { throw .schema(Int(exactly: schema) ?? 0) }
        let version = try string(root, "version", "", required: true) ?? ""
        guard Self.matches(version, Self.versionPattern), isDate(String(version.prefix(10))) else {
            throw .invalid(rule: "version", path: "version")
        }
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
        var ids: Set<String> = []
        for (i, item) in items.enumerated() {
            guard case .object(let t) = item else { throw .invalid(rule: "type", path: "trackers[\(i)]") }
            let tracker = try self.tracker(t, "trackers[\(i)]")
            guard ids.insert(tracker.id).inserted else { throw .invalid(rule: "id.duplicate", path: "trackers[\(i)].id") }
            trackers.append(tracker)
        }
        guard ids.contains("iphone"), ids.contains("other") else { throw .invalid(rule: "id.required", path: "trackers") }
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
        // The phone's glyph and behaviour are the iPhone's only.
        guard form != .phone || id == "iphone" else { throw .invalid(rule: "form.phone", path: "\(path).form") }
        let rawIntegration = try string(t, "integration", path, required: true) ?? ""
        guard let integration = Tracker.Integration(rawValue: rawIntegration) else {
            throw .invalid(rule: "enum.integration", path: "\(path).integration")
        }
        if let pinned = Self.integrations[id], pinned != integration {
            throw .invalid(rule: "integration.pinned", path: "\(path).integration")
        }
        let appName = try string(t, "app_name", path, required: false)
        if let appName { try text(appName, max: 40, "\(path).app_name") }

        let identity = try self.identity(t, id: id, path)
        let capabilities = try self.capabilities(t, integration: integration, path)
        if integration == .none || integration == .unknown, !identity.isEmpty {
            throw .invalid(rule: "integration.identity", path: "\(path).healthkit")
        }

        // The store page is the build's: content may repeat the pinned id, never change or add one.
        if let storeID = try string(t, "app_store_id", path, required: false) {
            guard Self.matches(storeID, "[0-9]{1,12}") else { throw .invalid(rule: "store.format", path: "\(path).app_store_id") }
            guard storeID == Self.storeIDs[id] else { throw .invalid(rule: "store.pinned", path: "\(path).app_store_id") }
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
                       appStoreID: Self.storeIDs[id], capabilities: capabilities, notes: notes, setup: setup, habits: habits,
                       limits: limits, help: help, checked: checked)
    }

    /// Bundle IDs and prefixes lowercased once here. Outside Apple's own trackers nothing may name or cover
    /// Apple's IDs, a prefix needs three labels, and device models (how Apple's trackers tell each other
    /// apart) are Apple's only.
    private func identity(_ t: [String: CatalogJSON], id: String, _ path: String) throws(CatalogError) -> SourceIdentity {
        guard let hk = try object(t, "healthkit", path) else { return .none }
        let at = "\(path).healthkit"
        let apple = Self.appleTrackers.contains(id)
        var lists: [String: [String]] = [:]
        for key in ["bundle_ids", "bundle_id_prefixes"] {
            var values: [String] = []
            for (j, raw) in try strings(hk, key, at).enumerated() {
                guard raw.utf8.count <= 155, Self.matches(raw, #"[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.?"#) else {
                    throw .invalid(rule: "bundle.format", path: "\(at).\(key)[\(j)]")
                }
                let value = raw.lowercased()
                let bare = Self.bare(value)
                if !apple, bare == "com" || bare.hasPrefix("com.apple") || SourceIdentity.covers(value, "com.apple.x") {
                    throw .invalid(rule: "bundle.apple", path: "\(at).\(key)[\(j)]")
                }
                if key == "bundle_id_prefixes", bare.split(separator: ".").count < 3 {
                    throw .invalid(rule: "bundle.prefix", path: "\(at).\(key)[\(j)]")
                }
                // Another tracker's known app: not this one's, nor under or over it.
                let others = Self.knownBundles.lazy.filter { $0.key != id }.flatMap(\.value)
                if others.contains(where: { $0 == bare || SourceIdentity.covers(value, $0) || SourceIdentity.covers($0, bare) }) {
                    throw .invalid(rule: "bundle.known", path: "\(at).\(key)[\(j)]")
                }
                values.append(value)
            }
            lists[key] = values
        }
        let names = try strings(hk, "source_names", at)
        for (j, name) in names.enumerated() { try text(name, max: 40, "\(at).source_names[\(j)]") }
        let models = try strings(hk, "device_models", at)
        if !models.isEmpty, !apple { throw .invalid(rule: "device.apple", path: "\(at).device_models") }
        for (j, model) in models.enumerated() where !Self.matches(model, "[A-Za-z]{2,16}") {
            throw .invalid(rule: "device.format", path: "\(at).device_models[\(j)]")
        }
        return SourceIdentity(bundleIDs: lists["bundle_ids"] ?? [], bundlePrefixes: lists["bundle_id_prefixes"] ?? [],
                              sourceNames: names, deviceModels: models)
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
    /// prefixes overlap only between the trackers told apart by device (Apple Watch and iPhone). Lookups by
    /// each ID's dot-boundary ancestors in a table of prefixes: linear in the copy's size.
    private static func checkOwnership(_ trackers: [Tracker]) throws(CatalogError) {
        var prefixOwners: [String: Set<Int>] = [:]
        for (k, t) in trackers.enumerated() {
            for prefix in t.identity.bundlePrefixes { prefixOwners[bare(prefix), default: []].insert(k) }
        }
        var idOwners: [String: Int] = [:]
        for (k, t) in trackers.enumerated() {
            let path = "trackers[\(k)].healthkit"
            func others(_ key: String) -> Set<Int> {
                (prefixOwners[key] ?? []).filter { $0 != k && !(byDevice(trackers[$0]) && byDevice(t)) }
            }
            for (j, id) in t.identity.bundleIDs.enumerated() {
                let owner = idOwners[id, default: k]
                idOwners[id] = owner
                if owner != k || ancestors(id).contains(where: { !others($0).isEmpty }) {
                    throw .invalid(rule: "bundle.duplicate", path: "\(path).bundle_ids[\(j)]")
                }
            }
            for (j, prefix) in t.identity.bundlePrefixes.enumerated() where ancestors(bare(prefix)).contains(where: { !others($0).isEmpty }) {
                throw .invalid(rule: "bundle.duplicate", path: "\(path).bundle_id_prefixes[\(j)]")
            }
        }
    }

    private static func byDevice(_ t: Tracker) -> Bool { !t.identity.deviceModels.isEmpty }

    /// Without a trailing dot: "com.apple.health." and "com.apple.health" claim the same IDs here.
    private static func bare(_ value: String) -> String { value.hasSuffix(".") ? String(value.dropLast()) : value }

    /// "a.b.c", "a.b", "a": every prefix that covers the ID at a dot boundary.
    private static func ancestors(_ id: String) -> [String] {
        var result = [id]
        var current = Substring(id)
        while let dot = current.lastIndex(of: ".") {
            current = current[..<dot]
            result.append(String(current))
        }
        return result
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

    /// An identity list: strings only, at most `maxIdentities`.
    private func strings(_ o: [String: CatalogJSON], _ key: String, _ path: String,
                         max: Int = maxIdentities) throws(CatalogError) -> [String] {
        let at = "\(path).\(key)"
        switch o[key] {
        case nil, .null?: return []
        case .array(let items)?:
            guard items.count <= max else { throw .invalid(rule: "identity.count", path: at) }
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
        // Counted before the cap so an oversized list says so; the cap itself bounds the work.
        for language in ["en", "de"] {
            if case .array(let items)? = pair[language], items.count > max { throw .invalid(rule: "text.count", path: at) }
        }
        let en = try strings(pair, "en", at, max: max), de = try strings(pair, "de", at, max: max)
        guard en.count == de.count else { throw .invalid(rule: "text.pair", path: at) }
        for (j, s) in en.enumerated() { try text(s, max: 240, "\(at).en[\(j)]") }
        for (j, s) in de.enumerated() { try text(s, max: 240, "\(at).de[\(j)]") }
        return Localized(en: en, de: de)
    }

    /// Plain text only (§2.5): shown with `Text(verbatim:)`, so no markup, no links or addresses, no
    /// control, format, private-use, unassigned or separator characters, Latin letters only (with common
    /// punctuation and combining marks), and no stacks of combining marks: at most twice `max` scalars.
    /// (The brand check runs over every string before this, `checkBrand`.)
    private func text(_ s: String, max: Int, _ path: @autoclosure () -> String) throws(CatalogError) {
        guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { throw .invalid(rule: "text.empty", path: path()) }
        let scalars = s.unicodeScalars.count
        // ASCII: one character per scalar, nothing to compose. Else graphemes, and scalars after composing.
        let ascii = scalars == s.utf8.count
        guard ascii ? scalars <= max
                : scalars <= 4 * max && s.count <= max && s.precomposedStringWithCanonicalMapping.unicodeScalars.count <= 2 * max
        else { throw .invalid(rule: "text.length", path: path()) }
        if !ascii {
            // One pass: private-use characters (U+F8FF draws Apple's logo; ICU's \p{Co} doesn't catch it), and
            // no more than `maxMarks` combining marks in a row (stacks render as noise over the line).
            var run = 0
            for scalar in s.unicodeScalars {
                let category = scalar.properties.generalCategory
                if category == .privateUse { throw .invalid(rule: "text.control", path: path()) }
                run = Self.marks.contains(category) ? run + 1 : 0
                if run > Self.maxMarks { throw .invalid(rule: "text.marks", path: path()) }
            }
        }
        if let rule = Self.refusal(s) { throw .invalid(rule: rule, path: path()) }
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

    /// `https`, no user, no port, a plain-ASCII host that is exactly one of the tracker's (on a shared host,
    /// under the vendor's path) or RYFT's; else nil.
    static func helpURL(_ string: String, trackerID: String) -> URL? {
        guard let c = URLComponents(string: string), c.scheme?.lowercased() == "https",
              c.user == nil, c.password == nil, c.port == nil,
              let raw = c.percentEncodedHost, matches(raw, "[A-Za-z0-9.-]+"), let url = c.url else { return nil }
        let host = raw.lowercased(), path = c.percentEncodedPath
        guard plainPath(path) else { return nil }
        if host == anyHelpHost { return anyHelpPaths.contains { path.hasPrefix($0) } ? url : nil }
        guard helpHosts[trackerID]?.contains(host) == true else { return nil }
        guard let paths = helpPaths[trackerID] else { return url }
        return paths.contains { path.hasPrefix($0) } ? url : nil
    }

    /// A path a prefix can be checked on: no "." or ".." segment, raw or percent-encoded, and no encoded
    /// slash or backslash, which a server might resolve past the prefix.
    static func plainPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard !lower.contains("\\"), !lower.contains("%2f"), !lower.contains("%5c") else { return false }
        return !lower.split(separator: "/", omittingEmptySubsequences: false).contains { segment in
            let decoded = String(segment).removingPercentEncoding ?? "."
            return decoded == "." || decoded == ".."
        }
    }
}

// BEGIN GENERATED trackers.json (scripts/trackers.py --write from Content/trackers.json; do not edit)
// swiftlint:disable line_length
extension TrackerCatalog {
    /// Content/trackers.json at build time: the copy that always works (offline, first launch, demo).
    static let bundledJSON = #"""
    {
      "schema_version": 1,
      "version": "2026-10-22.3",
      "checked": "2026-10-22",
      "status_values": [
        "yes",
        "partial",
        "no",
        "unverified"
      ],
      "health_access": {
        "steps": {
          "en": [
            "Open Health → Summary → your picture → Apps → RYFT.",
            "Tap Turn On All."
          ],
          "de": [
            "Öffne Health → Zusammenfassung → dein Bild → Apps → RYFT.",
            "Tippe auf „Alle aktivieren“."
          ]
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
            "en": [
              "On iPhone, open Health → Summary → your picture → Devices → your Apple Watch → Privacy Settings, and turn on Fitness Tracking.",
              "In Health → Browse → Sleep, set a sleep schedule and turn on Track Sleep with Apple Watch."
            ],
            "de": [
              "Öffne auf deinem iPhone Health → Zusammenfassung → dein Bild → Geräte → deine Apple Watch → Datenschutzeinstellungen und aktiviere Fitnessdaten.",
              "Öffne Health → Durchsuchen → Schlaf, lege einen Schlafplan fest und aktiviere „Schlaf mit Apple Watch aufzeichnen“."
            ]
          },
          "habits": {
            "en": [
              "Wear your Apple Watch to bed. Sleep stages, breathing rate and overnight blood oxygen need it.",
              "Charge it before bedtime. Turn on Charging Reminders in Watch → My Watch → Sleep."
            ],
            "de": [
              "Trage deine Apple Watch nachts. Schlafphasen, Atemfrequenz und Blutsauerstoff über Nacht brauchen das.",
              "Lade sie vor dem Schlafengehen auf. Aktiviere Laderinnerungen in Watch → Meine Watch → Schlaf."
            ]
          },
          "limits": {
            "en": [
              "Blood oxygen needs Apple Watch Series 6 or later or any Ultra. It isn't available on Apple Watch SE.",
              "Breathing rate isn't available for users under 13."
            ],
            "de": [
              "Blutsauerstoff braucht Apple Watch Series 6 oder später oder eine beliebige Ultra. Auf der Apple Watch SE ist es nicht verfügbar.",
              "Atemfrequenz ist für Nutzer unter 13 Jahren nicht verfügbar."
            ]
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
            "resting_hr": "yes",
            "sleep": "yes",
            "sleep_stages": "yes",
            "respiratory_rate": "no",
            "spo2": "no",
            "workouts": "yes",
            "steps": "yes"
          },
          "capability_notes": {
            "hrv": {
              "en": "Garmin keeps HRV in its own app.",
              "de": "Garmin behält HRV in seiner eigenen App."
            },
            "resting_hr": {
              "en": "One value per day, written at midnight.",
              "de": "Ein Wert pro Tag, um Mitternacht geschrieben."
            },
            "respiratory_rate": {
              "en": "Garmin doesn't send breathing rate to Apple Health.",
              "de": "Garmin sendet Atemfrequenz nicht an Apple Health."
            },
            "spo2": {
              "en": "Garmin doesn't send blood oxygen to Apple Health.",
              "de": "Garmin sendet Blutsauerstoff nicht an Apple Health."
            }
          },
          "setup_steps": {
            "en": [
              "Open Garmin Connect → More → Settings → Connect Apps.",
              "Under Available Apps, tap Apple Health → Connect with Apple Health.",
              "Turn on all data types, then tap Allow.",
              "To check later: open Health → Summary → your picture → Apps → Connect → Turn On All."
            ],
            "de": [
              "Öffne Garmin Connect → Mehr → Einstellungen → Connect Apps.",
              "Tippe unter „Verfügbare Apps“ auf Apple Health → Mit Apple Health verbinden.",
              "Aktiviere alle Datentypen und tippe dann auf „Zulassen“.",
              "Zum späteren Prüfen: Öffne Health → Zusammenfassung → dein Bild → Apps → Connect → Alle aktivieren."
            ]
          },
          "habits": {
            "en": [
              "Open Garmin Connect each morning and keep it on screen until it has synced. It sends data to Apple Health only while it's open in the foreground.",
              "Sync your watch first. Garmin Connect passes data to Apple Health after each successful watch sync."
            ],
            "de": [
              "Öffne Garmin Connect jeden Morgen und halte sie geöffnet, bis sie synchronisiert ist. Die App sendet Daten nur an Apple Health, während sie aktiv ist.",
              "Synchronisiere deine Uhr zuerst. Garmin Connect überträgt Daten an Apple Health nach jeder erfolgreichen Watch-Synchronisierung."
            ]
          },
          "limits": {
            "en": [
              "Garmin Connect doesn't send HRV, breathing rate or blood oxygen to Apple Health.",
              "Workout heart rate arrives as high and low values only, and GPS tracks aren't sent.",
              "Connect doesn't appear in Apple Health if only an Edge bike computer is registered to your Garmin account."
            ],
            "de": [
              "Garmin Connect sendet HRV, Atemfrequenz oder Blutsauerstoff nicht an Apple Health.",
              "Trainings-Herzfrequenz kommt nur als höchster und niedrigster Wert an, GPS-Tracks werden nicht gesendet.",
              "Connect erscheint nicht in Apple Health, wenn nur ein Edge-Fahrradcomputer bei deinem Garmin-Konto registriert ist."
            ]
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
          "capability_notes": {
            "hrv": {
              "en": "Oura doesn't export HRV to Apple Health.",
              "de": "Oura exportiert HRV nicht zu Apple Health."
            },
            "resting_hr": {
              "en": "Oura doesn't export resting heart rate to Apple Health.",
              "de": "Oura exportiert Ruhepuls nicht zu Apple Health."
            },
            "spo2": {
              "en": "Oura doesn't send blood oxygen to Apple Health.",
              "de": "Oura sendet Blutsauerstoff nicht an Apple Health."
            }
          },
          "setup_steps": {
            "en": [
              "Open Oura → menu (top left) → Settings.",
              "Under Data sharing, tap Apple Health.",
              "Turn on Connect to Health and allow all data types.",
              "To check later: open Health → Summary → your picture → Apps → Oura → Turn On All."
            ],
            "de": [
              "Öffne Oura → Menü (oben links) → Einstellungen.",
              "Tippe unter „Datenfreigabe“ auf Apple Health.",
              "Aktiviere „Mit Health verbinden“ und erlaube alle Datentypen.",
              "Zum späteren Prüfen: Öffne Health → Zusammenfassung → dein Bild → Apps → Oura → Alle aktivieren."
            ]
          },
          "habits": {
            "en": [
              "Open Oura every morning. Your data reaches Apple Health only after Oura is opened.",
              "Keep Background App Refresh on for Oura and Low Power Mode off."
            ],
            "de": [
              "Öffne Oura jeden Morgen. Deine Daten erreichen Apple Health nur, nachdem du Oura öffnest.",
              "Halte die Hintergrundaktualisierung für Oura aktiviert und den Energiesparmodus ausgeschaltet."
            ]
          },
          "limits": {
            "en": [
              "Oura doesn't send HRV, resting heart rate or blood oxygen to Apple Health.",
              "Breathing rate arrives as one nightly average.",
              "On Gen3 and later rings, Apple Health sync needs an active Oura membership."
            ],
            "de": [
              "Oura sendet HRV, Ruhepuls oder Blutsauerstoff nicht an Apple Health.",
              "Atemfrequenz kommt als durchschnittlicher Wert pro Nacht an.",
              "Bei Gen3-Ringen und später braucht die Apple-Health-Synchronisierung eine aktive Oura-Mitgliedschaft."
            ]
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
          "capability_notes": {
            "heart_rate": {
              "en": "Polar sends heart rate for workouts only.",
              "de": "Polar sendet Herzfrequenz nur für Trainings."
            }
          },
          "setup_steps": {
            "en": [
              "Open Polar Flow → More → General settings.",
              "Turn on Apple Health.",
              "Tap Turn All Categories On, then Allow.",
              "To check later: open Health → Summary → your picture → Apps → Polar Flow → Turn On All."
            ],
            "de": [
              "Öffne Polar Flow → Mehr → Allgemeine Einstellungen.",
              "Aktiviere Apple Health.",
              "Tippe auf „Alle Kategorien aktivieren“ und dann „Zulassen“.",
              "Zum späteren Prüfen: Öffne Health → Zusammenfassung → dein Bild → Apps → Polar Flow → Alle aktivieren."
            ]
          },
          "habits": {
            "en": [
              "Sync your watch with Polar Flow. New data then goes to Apple Health.",
              "Data missing? In Polar Flow → More → General settings, tap Sync now. It resends the last two weeks."
            ],
            "de": [
              "Synchronisiere deine Uhr mit Polar Flow. Neue Daten gehen dann zu Apple Health.",
              "Daten fehlen? Öffne Polar Flow → Mehr → Allgemeine Einstellungen und tippe auf „Jetzt synchronisieren“. Das sendet die letzten zwei Wochen erneut."
            ]
          },
          "limits": {
            "en": [
              "Polar Flow sends heart rate for workouts only, with no all-day heart rate.",
              "Polar Flow doesn't send HRV, resting heart rate, sleep stages, breathing rate or blood oxygen."
            ],
            "de": [
              "Polar Flow sendet Herzfrequenz nur für Trainings, ohne tägliche Herzfrequenz.",
              "Polar Flow sendet HRV, Ruhepuls, Schlafphasen, Atemfrequenz oder Blutsauerstoff nicht."
            ]
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
            "en": [
              "Open the Suunto app and go to its settings to start sharing with Apple Health.",
              "Allow all data types when iOS asks.",
              "To check later: open Health → Summary → your picture → Apps → Suunto → Turn On All."
            ],
            "de": [
              "Öffne die Suunto-App und gehe zu ihren Einstellungen, um mit Apple Health zu teilen.",
              "Erlaube alle Datentypen, wenn iOS fragt.",
              "Zum späteren Prüfen: Öffne Health → Zusammenfassung → dein Bild → Apps → Suunto → Alle aktivieren."
            ]
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [
              "Suunto doesn't publish what its app sends to Apple Health. Check sync shows what arrives."
            ],
            "de": [
              "Suunto veröffentlicht nicht, was ihre App an Apple Health sendet. Die Sync-Prüfung zeigt, was ankommt."
            ]
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
            "en": [
              "Open COROS → Profile → Settings → 3rd Party Apps → Data Sync → Apple Health.",
              "Select all data types to sync.",
              "To check later: open Health → Summary → your picture → Apps → COROS and turn on all types."
            ],
            "de": [
              "Öffne COROS → Profil → Einstellungen → Apps von Drittanbietern → Datensynchronisierung → Apple Health.",
              "Wähle alle Datentypen zum Synchronisieren aus.",
              "Zum späteren Prüfen: Öffne Health → Zusammenfassung → dein Bild → Apps → COROS und aktiviere alle Typen."
            ]
          },
          "habits": {
            "en": [
              "Sync your watch with the COROS app on a stable internet connection. Workouts go to Apple Health when the watch syncs."
            ],
            "de": [
              "Synchronisiere deine Uhr mit der COROS-App bei stabiler Internetverbindung. Trainings gehen zu Apple Health, wenn die Uhr synchronisiert."
            ]
          },
          "limits": {
            "en": [
              "COROS doesn't send HRV, resting heart rate, breathing rate or blood oxygen to Apple Health."
            ],
            "de": [
              "COROS sendet HRV, Ruhepuls, Atemfrequenz oder Blutsauerstoff nicht an Apple Health."
            ]
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
            "en": [
              "Open Withings → Profile → Settings (gear) → Export health data to Apple Health.",
              "Tap Next twice, turn on all data types, then tap Allow and Done.",
              "To check later: open Health → Summary → your picture → Apps → Withings → Turn On All."
            ],
            "de": [
              "Öffne Withings → Profil → Einstellungen (Zahnrad) → Gesundheitsdaten zu Apple Health exportieren.",
              "Tippe zweimal auf „Weiter“, aktiviere alle Datentypen, tippe dann auf „Zulassen“ und „Fertig“.",
              "Zum späteren Prüfen: Öffne Health → Zusammenfassung → dein Bild → Apps → Withings → Alle aktivieren."
            ]
          },
          "habits": {
            "en": [
              "Withings doesn't sync to Apple Health automatically. Open Withings, then the Health app, then pull down on the Withings Home tab to refresh.",
              "Allow up to 15 minutes after a measurement."
            ],
            "de": [
              "Withings synchronisiert nicht automatisch mit Apple Health. Öffne Withings, dann die Health-App, ziehe dann auf dem Withings-Home-Tab nach unten zum Aktualisieren.",
              "Erlaube bis zu 15 Minuten nach einer Messung."
            ]
          },
          "limits": {
            "en": [
              "Accounts created on or after 13 October 2026 need a Withings+ subscription to send data to Apple Health.",
              "Heart rate from the under-mattress sleep sensor doesn't reach Apple Health."
            ],
            "de": [
              "Konten, die am oder nach dem 13. Oktober 2026 erstellt wurden, brauchen ein Withings+-Abonnement, um Daten an Apple Health zu senden.",
              "Herzfrequenz vom Unter-Matratzen-Schlaf-Sensor erreicht Apple Health nicht."
            ]
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
          "capability_notes": {
            "hrv": {
              "en": "Amazfit Balance 2 series only, since August 2026.",
              "de": "Nur Amazfit Balance 2-Serie ab August 2026."
            }
          },
          "setup_steps": {
            "en": [
              "Open Zepp and let your watch sync.",
              "Allow Zepp in Health: open Health → Summary → your picture → Apps → Zepp → Turn On All."
            ],
            "de": [
              "Öffne Zepp und lass deine Uhr synchronisieren.",
              "Erlaube Zepp in Health: Öffne Health → Zusammenfassung → dein Bild → Apps → Zepp → Alle aktivieren."
            ]
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [
              "HRV reaches Apple Health only from the Amazfit Balance 2 series.",
              "Amazfit doesn't publish a full list of what Zepp sends to Apple Health. Check sync shows what arrives."
            ],
            "de": [
              "HRV erreicht Apple Health nur von der Amazfit Balance 2-Serie.",
              "Amazfit veröffentlicht keine vollständige Liste, was Zepp an Apple Health sendet. Die Sync-Prüfung zeigt, was ankommt."
            ]
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
            "en": [
              "Open Health → Summary → your picture → Apps → Ultrahuman.",
              "Tap Turn All Categories On."
            ],
            "de": [
              "Öffne Health → Zusammenfassung → dein Bild → Apps → Ultrahuman.",
              "Tippe auf „Alle Kategorien aktivieren“."
            ]
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [
              "Ultrahuman doesn't publish a list of what it sends to Apple Health. Check sync shows what arrives."
            ],
            "de": [
              "Ultrahuman veröffentlicht keine Liste, was an Apple Health gesendet wird. Die Sync-Prüfung zeigt, was ankommt."
            ]
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
            "en": [
              "Sign in to Google Health with an adult Google Account.",
              "Open Google Health → Connections (top left) → Apps and services.",
              "Under Add connections, tap Apple Health → Get started → Agree.",
              "Tap Turn All Categories On, then Allow, then Done."
            ],
            "de": [
              "Melde dich in Google Health mit einem erwachsenen Google-Konto an.",
              "Öffne Google Health → Verbindungen (oben links) → Apps und Services.",
              "Tippe unter „Verbindungen hinzufügen“ auf Apple Health → Erste Schritte → Zustimmen.",
              "Tippe auf „Alle Kategorien aktivieren“, dann „Zulassen“, dann „Fertig“."
            ]
          },
          "habits": {
            "en": [
              "Keep Google Health up to date.",
              "If Google Health shows 'New data types available', review and grant them."
            ],
            "de": [
              "Halte Google Health auf dem neuesten Stand.",
              "Wenn Google Health „Neue Datentypen verfügbar“ zeigt, überprüfe und erlaube sie."
            ]
          },
          "limits": {
            "en": [
              "Google Health doesn't send HRV to Apple Health.",
              "Needs iOS 16.4 or later and an adult Google Account."
            ],
            "de": [
              "Google Health sendet HRV nicht an Apple Health.",
              "Braucht iOS 16.4 oder später und ein erwachsenes Google-Konto."
            ]
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
            "en": [
              "Galaxy Watch4, Watch5, Watch6, Watch7, Watch Ultra and Watch FE don't work with iPhone. Samsung says they rely on Google Play services.",
              "RYFT can't read Galaxy Watch data on iPhone today."
            ],
            "de": [
              "Galaxy Watch4, Watch5, Watch6, Watch7, Watch Ultra und Watch FE funktionieren nicht mit dem iPhone. Samsung sagt, dass sie Google Play Services benötigen.",
              "RYFT kann Samsung Galaxy Watch-Daten auf dem iPhone derzeit nicht lesen."
            ]
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
            "en": [
              "Open your tracker's app and find Apple Health in its settings.",
              "Allow all data types when iOS asks.",
              "To check later: open Health → Summary → your picture → Apps → your tracker's app → Turn On All."
            ],
            "de": [
              "Öffne die App deines Trackers und finde Apple Health in ihren Einstellungen.",
              "Erlaube alle Datentypen, wenn iOS fragt.",
              "Zum späteren Prüfen: Öffne Health → Zusammenfassung → dein Bild → Apps → App deines Trackers → Alle aktivieren."
            ]
          },
          "habits": {
            "en": [],
            "de": []
          },
          "limits": {
            "en": [
              "What reaches RYFT depends on your tracker's app. Check sync shows what arrives."
            ],
            "de": [
              "Was RYFT erreicht, hängt von deiner Tracker-App ab. Die Sync-Prüfung zeigt, was ankommt."
            ]
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
            "en": [
              "Open Settings → Privacy & Security → Motion & Fitness and turn on Fitness Tracking.",
              "In Health → Browse → Sleep, set a sleep schedule."
            ],
            "de": [
              "Öffne Einstellungen → Datenschutz & Sicherheit → Bewegung & Fitness und aktiviere Fitnessdaten.",
              "Öffne Health → Durchsuchen → Schlaf und lege einen Schlafplan fest."
            ]
          },
          "habits": {
            "en": [
              "Carry your iPhone during the day. It counts steps with its own sensors."
            ],
            "de": [
              "Trage dein iPhone tagsüber bei dir. Es zählt Schritte mit seinen eigenen Sensoren."
            ]
          },
          "limits": {
            "en": [
              "Without a wearable, iPhone records no heart rate, HRV, resting heart rate, sleep stages, breathing rate or blood oxygen.",
              "Sleep is an estimate of time in bed from your sleep schedule.",
              "Heart rate arrives only during workouts with AirPods Pro 3."
            ],
            "de": [
              "Ohne tragbares Gerät erfasst das iPhone keine Herzfrequenz, HRV, Ruhepuls, Schlafphasen, Atemfrequenz oder Blutsauerstoff.",
              "Schlaf ist eine Schätzung der Bettzeit basierend auf deinem Schlafplan.",
              "Herzfrequenz kommt nur während Trainings mit AirPods Pro 3 an."
            ]
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
// swiftlint:enable line_length
// END GENERATED trackers.json
