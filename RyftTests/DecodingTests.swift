import Foundation
import Testing
@testable import Ryft

/// Every fixture is a JSON example from ../plattform/docs/API.md, decoded with
/// the app's real decoder.
@Suite("API decoding")
struct DecodingTests {
    @Test func syncResponse() throws {
        let r = try Fixture.decode(SyncResponse.self, "sync_response")
        #expect(r.samples == 1380)
        #expect(r.daysTouched == ["2026-10-17", "2026-10-18"])
    }

    @Test func me() throws {
        let u = try Fixture.decode(User.self, "me")
        #expect(u.name == "Tim K")
        #expect(u.email == "tim@example.com")
        #expect(u.provider == "apple")
        #expect(u.tz == "Europe/Berlin")
        #expect(u.maxHr == 190)
        #expect(u.sleepBaseMin == 455)
        #expect(u.sleepBaseSource == .learned && u.sleepBaseLearnedMin == 455 && u.sleepBaseLearnedAt != nil)
        #expect(u.notifications.isOn(.morningScore) && !u.notifications.isOn(.pr))
        #expect(u.notifications.quietHours == QuietHours(from: "22:30", to: "07:00"))
    }

    @Test func userFromBeforeNotificationsDecodesWithDefaults() throws {
        let json = #"{"id":"5f0e8c1a-6c1b-4a4e-9d55-1f1d2f6a3b7c","name":"","tz":"Europe/Berlin","max_hr":190,"sleep_base_min":460}"#
        let u = try APIClient.jsonDecoder.decode(User.self, from: Data(json.utf8))
        #expect(u.sleepBaseSource == .default)
        #expect(NotificationCategory.allCases.allSatisfy(u.notifications.isOn))
    }

    @Test func remoteConfig() throws {
        let c = try Fixture.decode(RemoteConfig.self, "remote_config")
        #expect(c.flags["train.enabled"] == true && c.flags["today.redesign"] == false)
        #expect(c.flags.count == 6)
        #expect(c.ttlSec == 21600)
    }

    @Test func notificationPrefs() throws {
        let p = try Fixture.decode(NotificationPrefs.self, "notification_prefs")
        #expect(p.categories["PR"] == false)
        #expect(p.quietHours?.from == "22:30")
    }

    @Test func notificationPatchLeavesOutClearsOrSetsQuietHours() throws {
        func json(_ p: NotificationPatch) throws -> String {
            try #require(String(data: APIClient.jsonEncoder.encode(p), encoding: .utf8))
        }
        #expect(try json(NotificationPatch(categories: ["PR": true])) == #"{"categories":{"PR":true}}"#)
        #expect(try json(NotificationPatch(quietHours: .some(nil))) == #"{"quiet_hours":null}"#)
        let set = try json(NotificationPatch(quietHours: QuietHours(from: "22:30", to: "07:00")))
        #expect(set.contains(#""quiet_hours":{"#) && set.contains(#""from":"22:30""#))
    }

    @Test func pushRegistrationBody() throws {
        let body = PushRegistration(token: "8a5ec41f", env: .sandbox, locale: "de-DE")
        let json = try #require(String(data: APIClient.jsonEncoder.encode(body), encoding: .utf8))
        #expect(json.contains(#""env":"sandbox""#) && json.contains(#""locale":"de-DE""#))
    }

    /// The `ryft` object of an alert and of the silent refresh (API.md → Push notifications).
    @Test func pushInfo() throws {
        struct Payload: Decodable { let ryft: RyftPushInfo }
        let alert = try Fixture.decode(Payload.self, "push_alert").ryft
        #expect(alert.category == "MORNING_SCORE" && alert.day == "2026-10-19")
        #expect(alert.url == "https://ryftapp.de/day/2026-10-19" && alert.kind == nil)
        let refresh = try Fixture.decode(Payload.self, "push_refresh").ryft
        #expect(refresh.kind == "refresh" && refresh.category == nil && refresh.url == nil)
    }

    @Test func days() throws {
        let days = try Fixture.decode([DailyScore].self, "days")
        #expect(days.count == 2)
        let full = days[0]
        #expect(full.readiness == 84)
        #expect(full.state == .balanced)
        #expect(full.strain == 12.4)
        #expect(full.steps == 9412)
        #expect(full.activeKcal == 612)
        #expect(full.strengthMin == 59 && full.volumeKg == 7420)
        #expect(days[1].strengthMin == nil)
        #expect(full.hrvBaselineMs == 53.1)
        #expect(full.rhrBaseline == 50.2)
        #expect(full.baselineDays == 30)
        #expect(!full.calibrating)
        #expect(full.computedAt != nil) // microsecond fraction parsed
    }

    @Test func calibratingDayHasNullsAndPlaceholders() throws {
        let day = try Fixture.decode([DailyScore].self, "days")[1]
        #expect(day.calibrating)
        #expect(day.readiness == nil && day.recovery == nil && day.strain == nil && day.steps == nil)
        #expect(day.resolvedState == .calibrating)
        #expect(day.nightsToGo == 4)
        #expect(Fmt.percent(day.recovery) == "–")
        #expect(Fmt.strain(day.strain) == "–")
        #expect(Fmt.duration(minutes: day.sleepActualMin) == "–")
    }

    @Test func dayDetail() throws {
        let d = try Fixture.decode(DayDetail.self, "day_detail")
        let sleep = try #require(d.sleep)
        #expect(sleep.totalMin == 468)
        #expect(sleep.inBedMin == 492)
        #expect(sleep.efficiency == 95)
        #expect(sleep.qualityLabel == .good)
        #expect(sleep.resolvedQualityLabel == "Good")
        #expect(sleep.stages.map(\.stage) == [.deep, .light, .rem, .awake])
        #expect(sleep.displayStages.map { $0.pct } == [24, 56, 20, 2]) // as sent, never rescaled
        #expect(sleep.segments.count == 5)
        #expect(sleep.segments[2].stage == .asleep)
        let strain = try #require(d.strain)
        #expect(strain.trimp == 99)
        #expect(strain.hrMin == 912)
        #expect(strain.zoneMin == [12, 24, 37, 7, 0])
        #expect(strain.steps == 9412)
        #expect(strain.muscularTrimp == 55)
        #expect(strain.sessions?.first?.title == "Upper A")
        #expect(strain.sessions?.first?.durationMin == 59)
        #expect(d.workouts.first?.strain == 14.9)
        #expect(d.workouts.first?.distanceM == 11800)
    }

    @Test func unscoredDay() throws {
        let d = try Fixture.decode(DayDetail.self, "day_unscored")
        #expect(d.sleep == nil && d.strain == nil && d.workouts.isEmpty)
        #expect(d.score.resolvedState == .calibrating)
        #expect(!d.score.calibrating) // baseline isn't the reason; there's no readiness yet
        #expect(ReadinessCopy.sentence(score: d.score) == "No readiness yet today. It appears once last night has synced.")
    }

    @Test func sleepRange() throws {
        let r = try Fixture.decode(SleepRange.self, "sleep_range")
        #expect(r.range == "week")
        #expect(r.from == "2026-10-12" && r.to == "2026-10-18")
        #expect(r.nights == 2)
        #expect(r.days.count == 2) // missing nights are absent
        #expect(r.days[0].minutes(for: .deep) == 95)
        #expect(r.days[1].hasStages == false)
        #expect(r.days[1].qualityLabel == .fair)
        #expect(r.avgTotalMin == 455)
        #expect(r.avgEfficiency == 94)
        #expect(r.avgStages.count == 4)
    }

    @Test func workouts() throws {
        let w = try Fixture.decode([Workout].self, "workouts")
        #expect(w.count == 2)
        #expect(w[1].avgHr == nil && w[1].strain == nil && w[1].energyKcal == nil) // omitted fields
        #expect(w[0].sessionId == nil && w[0].muscularLoad == nil)
        #expect(w[0].duration == 70 * 60)
    }

    @Test func workoutDetail() throws {
        let d = try Fixture.decode(WorkoutDetail.self, "workout_detail")
        #expect(d.workout.activity == "running")
        #expect(d.hr.count == 3)
        #expect(d.hr[1].bpm == 131)
        #expect(d.zoneMin == [2, 24, 37, 7, 0])
        #expect(d.trimp == 99)
    }

    @Test func trends() throws {
        let t = try Fixture.decode(TrendSeries.self, "trends")
        #expect(t.metric == "hrv")
        #expect(t.points.count == 3) // days without a value are absent
        #expect(t.avg == 51.7)
        #expect(t.baseline == 52.3)
    }

    @Test func trendMetricsMatchTheAPI() {
        #expect(TrendMetric.allCases.map(\.rawValue)
                == ["readiness", "recovery", "strain", "sleep", "sleep_min", "hrv", "rhr", "steps", "active_kcal",
                    "strength_min", "volume_kg", "sleep_quality", "sleep_consistency", "nap_min"])
    }

    @Test func insights() throws {
        let i = try Fixture.decode([Insight].self, "insights")
        #expect(i.count == 3)
        #expect(i.map(\.severity) == [.warn, .notice, .info])
        #expect(i[0].id == "hrv-low-3d")
        #expect(i[0].metric == "hrv")
    }

    @Test func errorBody() throws {
        let e = try Fixture.decode(APIErrorBody.self, "error")
        #expect(e.error == "human-readable message")
        #expect(e.requestId == "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c")
    }

    @Test func accountDeleted() throws {
        let d = try Fixture.decode(AccountDeleted.self, "account_deleted")
        #expect(d.status == "deleted")
        #expect(d.authUserDeleted)
        #expect(d.appleTokenRevoked == true)
        // Email accounts: no Apple token was stored.
        let email = try APIClient.jsonDecoder.decode(AccountDeleted.self, from: Data(
            #"{"status":"deleted","auth_user_deleted":false,"apple_token_revoked":null}"#.utf8))
        #expect(email.appleTokenRevoked == nil && !email.authUserDeleted)
    }

    @Test func appleAuthorization() throws {
        let a = try Fixture.decode(AppleAuthorization.self, "apple_authorization")
        #expect(a.code.hasPrefix("c1b2"))
        let body = try #require(String(data: APIClient.jsonEncoder.encode(a), encoding: .utf8))
        #expect(body.hasPrefix("{\"code\":"))
    }

    @Test func cacheRoundTripKeepsTypedFields() throws {
        let d = try Fixture.decode(DayDetail.self, "day_detail")
        let data = try APIClient.jsonEncoder.encode(d)
        let back = try APIClient.jsonDecoder.decode(DayDetail.self, from: data)
        // `computed_at` loses its microseconds (the encoder writes whole seconds); everything else survives.
        #expect(back.sleep == d.sleep)
        #expect(back.strain == d.strain)
        #expect(back.workouts == d.workouts)
        var score = back.score
        score.computedAt = d.score.computedAt
        #expect(score == d.score)
    }
}

// MARK: - tracker catalog (design.md §2.3–2.5, §4.3, §5)

/// The catalog tests' fixture: a valid copy (Garmin, Apple Watch, iPhone, Other) as JSON, changed by `edit`.
private enum CatalogFixture {
    /// 2026-10-22 12:00 UTC: the copies are checked that day.
    static let now = Date(timeIntervalSince1970: 1_792_670_400)

    static var garmin: [String: Any] {
        ["id": "garmin", "name": "Garmin", "form": "watch", "app_name": "Garmin Connect", "integration": "vendor_app",
         "healthkit": ["bundle_ids": ["com.garmin.connect.mobile"], "bundle_id_prefixes": ["com.garmin.connect.mobile"],
                       "source_names": ["Connect"], "device_models": [String](), "verified": ["bundle_ids": true]],
         "app_store_id": "583446403",
         "capabilities": ["heart_rate": "yes", "hrv": "no", "sleep_stages": "unverified"],
         "capability_notes": ["hrv": ["en": "Garmin Connect doesn't share HRV.", "de": "Garmin Connect teilt keine HRV."]],
         "setup_steps": ["en": ["Open Garmin Connect."], "de": ["Öffne Garmin Connect."]],
         "help_url": "https://support.garmin.com/en-US/?faq=lK5FPB9iPF5PXFkIpFlFPA", "checked": "2026-10-22"]
    }

    static func apple(_ id: String, model: String) -> [String: Any] {
        ["id": id, "name": id == "iphone" ? "Just my iPhone" : "Apple Watch", "form": id == "iphone" ? "phone" : "watch",
         "integration": "apple_builtin",
         "healthkit": ["bundle_id_prefixes": ["com.apple.health."], "device_models": [model]],
         "help_url": "https://support.apple.com/en-us/108779", "checked": "2026-10-22"]
    }

    static var other: [String: Any] {
        ["id": "other", "name": "Other", "form": "other", "app_name": NSNull(), "integration": "unknown", "checked": "2026-10-22"]
    }

    static func json(_ edit: (inout [String: Any]) -> Void = { _ in }, garmin change: (inout [String: Any]) -> Void = { _ in }) -> Data {
        var g = garmin
        change(&g)
        var doc: [String: Any] = [
            "schema_version": 1, "version": "2026-10-22.1", "checked": "2026-10-22",
            "health_access": ["steps": ["en": ["Open Health → Summary → your picture → Apps → RYFT."],
                                        "de": ["Öffne Health → Übersicht → dein Bild → Apps → RYFT."]],
                              "checked": "2026-10-22"],
            "trackers": [g, apple("apple_watch", model: "Watch"), apple("iphone", model: "iPhone"), other],
        ]
        edit(&doc)
        return (try? JSONSerialization.data(withJSONObject: doc)) ?? Data()
    }

    static func decode(_ edit: (inout [String: Any]) -> Void = { _ in },
                       garmin change: (inout [String: Any]) -> Void = { _ in }) throws(CatalogError) -> TrackerCatalog {
        try TrackerCatalog.decode(json(edit, garmin: change), now: now)
    }

    /// The rule and path a copy is refused for; nil when it's accepted.
    static func refusal(_ edit: (inout [String: Any]) -> Void = { _ in },
                        garmin change: (inout [String: Any]) -> Void = { _ in }) -> CatalogError? {
        do {
            _ = try decode(edit, garmin: change)
            return nil
        } catch {
            return error
        }
    }
}

private func ref(_ name: String, _ bundleID: String?, _ model: String? = nil) -> SourceRef {
    SourceRef(name: name, bundleID: bundleID, deviceModel: model)
}

/// trackers.json: the bundled copy, every validation rule, matching and names (design.md §2.3, §4.3, §5).
@Suite("Tracker catalog")
struct TrackerCatalogTests {
    @Test func theBundledCopyPassesEveryRule() throws {
        // Against today's clock too, not only the bundled path's (which skips the dates).
        let decoded = try TrackerCatalog.decode(Data(TrackerCatalog.bundledJSON.utf8), now: .now)
        #expect(decoded == TrackerCatalog.bundled)
        let c = TrackerCatalog.bundled
        #expect(c.version == "2026-10-22.1")
        #expect(c.trackers.map(\.id) == ["apple_watch", "garmin", "oura", "polar", "suunto", "coros", "withings", "amazfit",
                                         "ultrahuman", "fitbit", "samsung_galaxy_watch", "other", "iphone"])
        let garmin = try #require(c.tracker("garmin"))
        #expect(garmin.appName == "Garmin Connect" && garmin.form == .watch && garmin.integration == .vendorApp)
        #expect(garmin.capabilities[.hrv] == .no && garmin.capabilities[.restingHR] == .no)
        #expect(garmin.capabilities[.heartRate] == .yes && garmin.capabilities[.sleepStages] == .unverified)
        #expect(garmin.capabilities.count == TrackerSignal.allCases.count)
        #expect(garmin.appStoreURL?.absoluteString == "https://apps.apple.com/app/id583446403")
        #expect(garmin.help?.host == "support.garmin.com")
        // T1 carries identity and capabilities; the guide text comes with T5.
        #expect(garmin.setup == Localized(en: [], de: []) && garmin.notes.isEmpty && c.healthAccess.en.isEmpty)
        #expect(c.tracker("samsung_galaxy_watch")?.capabilities.values.allSatisfy { $0 == .no } == true)
        #expect(c.tracker("oura")?.form == .ring && c.tracker("iphone")?.form == .phone)
        // R1 found no guide for Suunto; the App Store page isn't one.
        #expect(c.tracker("suunto")?.help == nil)
        #expect(c.tracker("other")?.help?.host == "support.apple.com")
    }

    @Test func aValidCopyDecodes() throws {
        let c = try CatalogFixture.decode()
        #expect(c.trackers.count == 4)
        let garmin = try #require(c.tracker("garmin"))
        #expect(garmin.notes[.hrv] == Localized(en: "Garmin Connect doesn't share HRV.", de: "Garmin Connect teilt keine HRV."))
        #expect(garmin.setup.de == ["Öffne Garmin Connect."])
        // A signal the copy leaves out is unverified; for integration none, no.
        #expect(garmin.capabilities[.spo2] == .unverified)
        #expect(c.tracker("other")?.capabilities[.steps] == .unverified)
        #expect(c.healthAccess.en.count == 1)
        #expect(c.tracker("other")?.identity == SourceIdentity.none)
    }

    @Test func unknownKeysAndTheContentsStoreURLAreIgnored() throws {
        let c = try CatalogFixture.decode({
            $0["status_values"] = ["yes", "no"]
            $0["future_field"] = ["anything": [1, 2, 3]]
        }, garmin: {
            $0["app_store_url"] = "https://apps.apple.com/us/app/garmin-connect/id583446403"
            $0["sources"] = [["url": "https://support.garmin.com", "covers": "everything"]]
            $0["capabilities"] = ["heart_rate": "yes", "vo2max": "yes", "blood_pressure": "maybe"]
        })
        let garmin = try #require(c.tracker("garmin"))
        // Storefront-neutral, from the digits: content never supplies a navigable store URL.
        #expect(garmin.appStoreURL?.absoluteString == "https://apps.apple.com/app/id583446403")
        #expect(garmin.capabilities[.heartRate] == .yes)
    }

    @Test func eachRuleRefusesTheWholeCopyNamingItsPath() {
        typealias Edit = (inout [String: Any]) -> Void
        func trackers(_ doc: inout [String: Any], _ change: (inout [[String: Any]]) -> Void) {
            var list = doc["trackers"] as? [[String: Any]] ?? []
            change(&list)
            doc["trackers"] = list
        }
        func invalid(_ rule: String, _ path: String) -> CatalogError { .invalid(rule: rule, path: path) }
        let brand = ["wh", "00", "p"].joined()

        // 1: size, JSON, schema.
        #expect(throws: CatalogError.tooLarge) { try TrackerCatalog.decode(Data(repeating: 0x20, count: 262_145), now: .now) }
        #expect(throws: CatalogError.notJSON) { try TrackerCatalog.decode(Data("{".utf8), now: .now) }
        #expect(throws: CatalogError.notJSON) { try TrackerCatalog.decode(Data("[1]".utf8), now: .now) }
        #expect(throws: CatalogError.notJSON) { try TrackerCatalog.decode(Data([0x7B, 0xFF, 0x7D]), now: .now) }
        #expect(CatalogFixture.refusal({ $0["schema_version"] = 2 }) == .schema(2))
        #expect(CatalogFixture.refusal({ $0["schema_version"] = nil }) == .schema(0))
        #expect(CatalogFixture.refusal({ $0["schema_version"] = "1" }) == .schema(0))
        // 2: version and dates, never after tomorrow.
        #expect(CatalogFixture.refusal({ $0["version"] = "2026-10-22" }) == invalid("version", "version"))
        #expect(CatalogFixture.refusal({ $0["version"] = "2027-01-01.1" }) == invalid("version", "version"))
        #expect(CatalogFixture.refusal(garmin: { $0["checked"] = "2026-02-30" }) == invalid("date", "trackers[0].checked"))
        #expect(CatalogFixture.refusal(garmin: { $0["checked"] = "2026-10-25" }) == invalid("date", "trackers[0].checked"))
        #expect(CatalogFixture.refusal(garmin: { $0["checked"] = "2026-10-23" }) == nil) // tomorrow somewhere already
        // 3: the list and its ids.
        #expect(CatalogFixture.refusal({ trackers(&$0) { $0 = Array($0.prefix(1)) } }) == invalid("trackers.count", "trackers"))
        #expect(CatalogFixture.refusal(garmin: { $0["id"] = "Garmin" }) == invalid("id.format", "trackers[0].id"))
        #expect(CatalogFixture.refusal({ trackers(&$0) { $0[3]["id"] = "garmin" } }) == invalid("id.duplicate", "trackers[3].id"))
        #expect(CatalogFixture.refusal({ trackers(&$0) { $0.remove(at: 2) } }) == invalid("id.required", "trackers"))
        // 4: closed enums; an unknown signal key is ignored (above).
        #expect(CatalogFixture.refusal(garmin: { $0["form"] = "wristband" }) == invalid("enum.form", "trackers[0].form"))
        #expect(CatalogFixture.refusal(garmin: { $0["integration"] = "cloud" }) == invalid("enum.integration", "trackers[0].integration"))
        #expect(CatalogFixture.refusal(garmin: { $0["capabilities"] = ["hrv": "maybe"] })
                == invalid("enum.capability", "trackers[0].capabilities.hrv"))
        #expect(CatalogFixture.refusal(garmin: { $0["name"] = 5 }) == invalid("type", "trackers[0].name"))
        #expect(CatalogFixture.refusal(garmin: { $0["name"] = nil }) == invalid("missing", "trackers[0].name"))
        // 5: plain text of bounded size, en and de complete.
        let cases: [(Edit, CatalogError)] = [
            ({ $0["name"] = String(repeating: "G", count: 41) }, invalid("text.length", "trackers[0].name")),
            ({ $0["setup_steps"] = ["en": ["Tap <b>Sync</b>."], "de": ["x"]] }, invalid("text.markup", "trackers[0].setup_steps.en[0]")),
            ({ $0["setup_steps"] = ["en": ["Tap [here](x)."], "de": ["x"]] }, invalid("text.markup", "trackers[0].setup_steps.en[0]")),
            ({ $0["setup_steps"] = ["en": ["x"], "de": ["Siehe https://example.com"]] }, invalid("text.markup", "trackers[0].setup_steps.de[0]")),
            ({ $0["habits"] = ["en": ["Visit WWW.example.com"], "de": ["x"]] }, invalid("text.markup", "trackers[0].habits.en[0]")),
            ({ $0["limits"] = ["en": ["Open \u{202E}tcennoC"], "de": ["x"]] }, invalid("text.control", "trackers[0].limits.en[0]")),
            ({ $0["limits"] = ["en": ["Zero\u{200B}width"], "de": ["x"]] }, invalid("text.control", "trackers[0].limits.en[0]")),
            ({ $0["limits"] = ["en": ["Two\nlines"], "de": ["x"]] }, invalid("text.control", "trackers[0].limits.en[0]")),
            ({ $0["app_name"] = "Not " + brand.uppercased() }, invalid("text.brand", "trackers[0].app_name")),
            ({ $0["habits"] = ["en": [["W", "h", "o", "o", "p"].joined(separator: ".")], "de": ["x"]] },
             invalid("text.brand", "trackers[0].habits.en[0]")),
            ({ $0["setup_steps"] = ["en": [" "], "de": ["x"]] }, invalid("text.empty", "trackers[0].setup_steps.en[0]")),
            ({ $0["setup_steps"] = ["en": ["a", "b"], "de": ["a"]] }, invalid("text.pair", "trackers[0].setup_steps")),
            ({ $0["setup_steps"] = ["en": ["a"]] }, invalid("text.pair", "trackers[0].setup_steps")),
            ({ $0["setup_steps"] = ["en": Array(repeating: "a", count: 13), "de": Array(repeating: "a", count: 13)] },
             invalid("text.count", "trackers[0].setup_steps")),
            ({ $0["habits"] = ["en": Array(repeating: "a", count: 9), "de": Array(repeating: "a", count: 9)] },
             invalid("text.count", "trackers[0].habits")),
            ({ $0["setup_steps"] = ["en": [String(repeating: "a", count: 241)], "de": ["x"]] },
             invalid("text.length", "trackers[0].setup_steps.en[0]")),
            ({ $0["capability_notes"] = ["hrv": ["en": "No HRV."]] }, invalid("text.pair", "trackers[0].capability_notes.hrv")),
            // 6: identity.
            ({ $0["healthkit"] = ["bundle_ids": ["com garmin"]] }, invalid("bundle.format", "trackers[0].healthkit.bundle_ids[0]")),
            ({ $0["healthkit"] = ["bundle_ids": [String(repeating: "a", count: 156)]] },
             invalid("bundle.format", "trackers[0].healthkit.bundle_ids[0]")),
            ({ $0["healthkit"] = ["bundle_id_prefixes": ["com.apple.health."]] },
             invalid("bundle.apple", "trackers[0].healthkit.bundle_id_prefixes[0]")),
            ({ $0["healthkit"] = ["bundle_ids": ["COM.APPLE.Bridge"]] }, invalid("bundle.apple", "trackers[0].healthkit.bundle_ids[0]")),
            ({ $0["healthkit"] = ["bundle_ids": ["com.garmin.connect.mobile"], "device_models": ["Watch"]] },
             invalid("device.apple", "trackers[0].healthkit.device_models")),
            ({ $0["healthkit"] = ["bundle_ids": (1...9).map { "com.garmin.app\($0)" }] },
             invalid("identity.count", "trackers[0].healthkit.bundle_ids")),
            ({ $0["healthkit"] = ["source_names": (1...9).map { "Connect \($0)" }] },
             invalid("identity.count", "trackers[0].healthkit.source_names")),
            ({ $0["healthkit"] = ["bundle_id_prefixes": ["com.garmin"]] }, invalid("bundle.prefix", "trackers[0].healthkit.bundle_id_prefixes[0]")),
            ({ $0["healthkit"] = ["source_names": ["<Connect>"]] }, invalid("text.markup", "trackers[0].healthkit.source_names[0]")),
            // 7: store id digits only.
            ({ $0["app_store_id"] = "id583446403" }, invalid("store.format", "trackers[0].app_store_id")),
            // 8: integration none and unknown carry no identity; none shares nothing.
            ({ $0["integration"] = "none"; $0["healthkit"] = [String: Any](); $0["capabilities"] = ["steps": "yes"] },
             invalid("integration.none", "trackers[0].capabilities.steps")),
            ({ $0["integration"] = "none"; $0["capabilities"] = [String: Any]() }, invalid("integration.identity", "trackers[0].healthkit")),
            ({ $0["integration"] = "unknown" }, invalid("integration.identity", "trackers[0].healthkit")),
        ]
        for (i, (edit, error)) in cases.enumerated() {
            #expect(CatalogFixture.refusal(garmin: edit) == error, "case \(i)")
        }
    }

    @Test func oneBundleIDBelongsToOneTracker() {
        func add(_ doc: inout [String: Any], healthkit: [String: Any]) {
            var list = doc["trackers"] as? [[String: Any]] ?? []
            list.append(["id": "oura", "name": "Oura", "form": "ring", "integration": "vendor_app", "healthkit": healthkit,
                         "checked": "2026-10-22"])
            doc["trackers"] = list
        }
        // The same ID, an ID under Garmin's prefix: refused at the tracker that repeats or falls under it.
        #expect(CatalogFixture.refusal({ add(&$0, healthkit: ["bundle_ids": ["com.garmin.connect.mobile"]]) })
                == .invalid(rule: "bundle.duplicate", path: "trackers[4].healthkit.bundle_ids[0]"))
        #expect(CatalogFixture.refusal({ add(&$0, healthkit: ["bundle_ids": ["com.garmin.connect.mobile.watchkitapp"]]) })
                == .invalid(rule: "bundle.duplicate", path: "trackers[4].healthkit.bundle_ids[0]"))
        // A wider prefix over Garmin's IDs: Garmin's own ID is the one taken away.
        #expect(CatalogFixture.refusal({ add(&$0, healthkit: ["bundle_id_prefixes": ["com.garmin.connect"]]) })
                == .invalid(rule: "bundle.duplicate", path: "trackers[0].healthkit.bundle_ids[0]"))
        #expect(CatalogFixture.refusal({ add(&$0, healthkit: ["bundle_id_prefixes": ["com.garmin.connect.mobile."]]) })
                == .invalid(rule: "bundle.duplicate", path: "trackers[0].healthkit.bundle_ids[0]"))
        // A neighbour that only starts with the same letters is another app.
        #expect(CatalogFixture.refusal({ add(&$0, healthkit: ["bundle_ids": ["com.garmin.connect.mobile2"]]) }) == nil)
        // Apple Watch and iPhone share their prefix: their devices tell them apart.
        #expect(CatalogFixture.refusal() == nil)
    }

    @Test func helpLinksStayOnTheTrackersOwnHosts() throws {
        func help(_ url: String, id: String = "garmin") throws -> URL? {
            try CatalogFixture.decode(garmin: {
                $0["help_url"] = url
                $0["id"] = id
                if id != "garmin" { $0["app_store_id"] = nil }
            }).tracker(id)?.help
        }
        #expect(try help("https://support.garmin.com/en-US/")?.host == "support.garmin.com")
        #expect(try help("https://SUPPORT.garmin.com/")?.host != nil)
        #expect(try help("https://ryftapp.de/setup/garmin")?.host == "ryftapp.de")
        #expect(try help("https://ryftapp.de/help/sync")?.host == "ryftapp.de")
        // On RYFT's host, content pages only: never the universal-link routes, nor the root.
        #expect(try help("https://ryftapp.de/auth/callback?code=x") == nil)
        #expect(try help("https://ryftapp.de/invite/ABC123") == nil)
        #expect(try help("https://ryftapp.de/") == nil)
        // Exact hosts only: no other subdomain, no bare domain, no subdomain of RYFT's.
        #expect(try help("https://garmin.com/") == nil)
        #expect(try help("https://connect.garmin.com/") == nil)
        #expect(try help("https://www.ryftapp.de/setup") == nil)
        #expect(try help("https://evil.ryftapp.de/setup") == nil)
        // Dropped, the rest of the copy kept: another host, a look-alike, http, a port, user info.
        #expect(try help("https://evil.example/garmin") == nil)
        #expect(try help("https://support.garmin.com.evil.example/") == nil)
        #expect(try help("https://notgarmin.com/") == nil)
        #expect(try help("http://support.garmin.com/") == nil)
        #expect(try help("https://support.garmin.com:8443/") == nil)
        #expect(try help("https://me@support.garmin.com/") == nil)
        #expect(try help("javascript:alert(1)") == nil)
        // Another tracker's host isn't Garmin's; a new id has only RYFT's until a release lists it.
        #expect(try help("https://support.ouraring.com/") == nil)
        #expect(try help("https://support.garmin.com/", id: "newtracker") == nil)
        #expect(try help("https://ryftapp.de/setup/newtracker", id: "newtracker")?.host == "ryftapp.de")
    }

    // MARK: a hostile remote copy (security review)

    @Test func deepNestingIsRefusedBeforeParsing() throws {
        func nested(_ levels: Int) -> Data {
            var doc = String(data: CatalogFixture.json(), encoding: .utf8) ?? ""
            doc.removeLast() // the closing brace
            doc += #","ignored":"# + String(repeating: "[", count: levels) + String(repeating: "]", count: levels) + "}"
            return Data(doc.utf8)
        }
        // 440 levels under a key the app ignores: refused on the bytes, nothing recursed.
        #expect(throws: CatalogError.invalid(rule: "depth", path: "")) { try TrackerCatalog.decode(nested(440), now: CatalogFixture.now) }
        #expect(TrackerCatalog.nesting(nested(440)) == TrackerCatalog.maxDepth + 1) // it stops counting there
        // 8 in all is the limit (the root object and 7 arrays); brackets inside strings don't count.
        _ = try TrackerCatalog.decode(nested(7), now: CatalogFixture.now)
        #expect(throws: CatalogError.invalid(rule: "depth", path: "")) { try TrackerCatalog.decode(nested(8), now: CatalogFixture.now) }
        #expect(TrackerCatalog.nesting(Data(#"{"a":"[[[[[[[[[[\"[[[["}"#.utf8)) == 1)
        #expect(TrackerCatalog.nesting(Data(TrackerCatalog.bundledJSON.utf8)) <= 5)
    }

    @Test func onlyAppleTrackersClaimAppleIDsAndDevices() {
        func garmin(_ healthkit: [String: Any]) -> CatalogError? {
            CatalogFixture.refusal(garmin: { $0["healthkit"] = healthkit })
        }
        // Anything that equals or covers Apple's IDs, however it's written.
        for prefix in ["com", "com.", "com.apple", "COM.APPLE", "com.apple.", "com.apple.health", "com.applesauce.app"] {
            #expect(garmin(["bundle_id_prefixes": [prefix]]) == .invalid(rule: "bundle.apple", path: "trackers[0].healthkit.bundle_id_prefixes[0]"),
                    "prefix \(prefix)")
        }
        #expect(garmin(["bundle_ids": ["com.apple"]]) == .invalid(rule: "bundle.apple", path: "trackers[0].healthkit.bundle_ids[0]"))
        // Two labels are too wide to be one vendor's.
        #expect(garmin(["bundle_id_prefixes": ["com.garmin."]]) == .invalid(rule: "bundle.prefix", path: "trackers[0].healthkit.bundle_id_prefixes[0]"))
        // Device models tell Apple's trackers apart; nobody else gets one.
        #expect(garmin(["bundle_ids": ["com.garmin.connect.mobile"], "device_models": ["iPhone"]])
                == .invalid(rule: "device.apple", path: "trackers[0].healthkit.device_models"))
        #expect(CatalogFixture.refusal({ doc in
            var list = doc["trackers"] as? [[String: Any]] ?? []
            list[1]["healthkit"] = ["bundle_id_prefixes": ["com.apple.health."], "device_models": ["Watch7,1"]]
            doc["trackers"] = list
        }) == .invalid(rule: "device.format", path: "trackers[1].healthkit.device_models[0]"))

        // End to end, the reviewer's copy: Garmin first, claiming Apple's prefix and the watch's model, with another
        // store page. Refused: the Apple Watch is never renamed "Garmin Connect".
        let hijack = CatalogFixture.refusal(garmin: {
            $0["healthkit"] = ["bundle_id_prefixes": ["com.apple"], "device_models": ["Watch"]]
            $0["app_store_id"] = "1"
        })
        #expect(hijack == .invalid(rule: "bundle.apple", path: "trackers[0].healthkit.bundle_id_prefixes[0]"))
        #expect(TrackerCatalog.bundled.displayName(ref("Tim's Apple Watch", "com.apple.health.4B1C", "Watch")) == "Tim's Apple Watch")
    }

    @Test func onlyTheIPhoneIsAPhone() {
        #expect(CatalogFixture.refusal(garmin: { $0["form"] = "phone" }) == .invalid(rule: "form.phone", path: "trackers[0].form"))
        #expect(CatalogFixture.refusal() == nil) // the iPhone itself is
    }

    @Test func errorPathsNeverEchoTheDocumentsKeys() {
        // A key carrying the brand, a line break, a fake diagnostics line and 2 000 characters.
        let key = ["wh", "00", "p"].joined() + "\nrequests: 200 GET /v1/me rid-1 " + String(repeating: "k", count: 2_000)
        let refusal = CatalogFixture.refusal({ $0["extra"] = [key: "x"] })
        guard case .invalid(let rule, let path)? = refusal else { Issue.record("expected a refusal, got \(String(describing: refusal))"); return }
        #expect(rule == "text.brand" && path == "?.?") // keys the schema doesn't know are never echoed
        // Known keys and indices are: a value under them names its place.
        #expect(CatalogFixture.refusal({ $0["<odd key>\u{202E}"] = [["wh", "00", "p"].joined()] }) == .invalid(rule: "text.brand", path: "?[0]"))
        #expect(CatalogFixture.refusal(garmin: { $0["sources"] = [["covers": ["wh", "00", "p"].joined()]] })
                == .invalid(rule: "text.brand", path: "trackers[0].sources[0].covers"))
        let long = CatalogFixture.refusal({ doc in
            doc["trackers"] = (doc["trackers"] as? [[String: Any]] ?? []) + [["sources": [[["verified": [["wh", "00", "p"].joined()]]]]]]
        })
        if case .invalid(_, let path)? = long { #expect(path.count <= 80) }
    }

    @Test func storePagesArePinnedPerTracker() throws {
        // The build's id, whether the copy repeats it or not.
        #expect(try CatalogFixture.decode(garmin: { $0["app_store_id"] = nil }).tracker("garmin")?.appStoreID == "583446403")
        #expect(CatalogFixture.refusal(garmin: { $0["app_store_id"] = "1" }) == .invalid(rule: "store.pinned", path: "trackers[0].app_store_id"))
        // A tracker the build doesn't pin gets no store page from content.
        #expect(CatalogFixture.refusal({ doc in
            var list = doc["trackers"] as? [[String: Any]] ?? []
            list[3]["app_store_id"] = "583446403"
            doc["trackers"] = list
        }) == .invalid(rule: "store.pinned", path: "trackers[3].app_store_id"))
        #expect(try CatalogFixture.decode().tracker("other")?.appStoreURL == nil)
    }

    @Test func helpHostsAreExactAndPlain() throws {
        func help(_ url: String, id: String) throws -> URL? {
            try CatalogFixture.decode(garmin: { $0["help_url"] = url; $0["id"] = id; $0["app_store_id"] = nil }).tracker(id)?.help
        }
        #expect(try help("https://support.google.com/googlehealth/answer/17037331", id: "fitbit") != nil)
        #expect(try help("https://support.google.com/accounts/answer/1", id: "fitbit") == nil) // Google's, not Fitbit's
        #expect(try help("https://sites.google.com/view/fitbit", id: "fitbit") == nil)
        #expect(try help("https://www.google.com/url?q=https://evil.example", id: "fitbit") == nil)
        #expect(try help("https://www.ultrahuman.com/blog/x/", id: "ultrahuman") != nil)
        #expect(try help("https://ultrahuman.com/blog/x/", id: "ultrahuman") == nil)
        // The host as sent must be plain ASCII: no punycode tricks through percent-encoding.
        #expect(try help("https://support.garmin%2Ecom/", id: "garmin") == nil)
        #expect(try help("https://xn--suppor-gva.garmin.com/", id: "garmin") == nil)
    }

    @Test func textRulesHoldAgainstLookAlikesAndBombs() {
        let cases: [(String, String)] = [
            ("a" + String(repeating: "\u{0301}", count: 120), "text.length"),  // one character, 121 scalars
            ("Open \u{E000}", "text.control"),                                 // private use
            ("Line\u{2028}break", "text.control"),                             // line separator
            ("Para\u{2029}graph", "text.control"),
            ("Open \u{0378}", "text.control"),                                 // unassigned
            ("G\u{0430}rmin", "text.script"),                                  // a Cyrillic a
            ("Ελληνικά", "text.script"),
            ("support@example.com", "text.markup"),
            ("Write to mailto:x", "text.markup"),
            ("Call tel:0123", "text.markup"),
        ]
        for (text, rule) in cases {
            #expect(CatalogFixture.refusal(garmin: { $0["name"] = text }) == .invalid(rule: rule, path: "trackers[0].name"), "\(rule): \(text)")
        }
        // German, typographic quotes, arrows and decomposed umlauts are text.
        #expect(CatalogFixture.refusal(garmin: {
            $0["setup_steps"] = ["en": ["Open Health → Summary → “Apps”."], "de": ["Öffne Health → „Apps“ → U\u{0308}bersicht."]]
        }) == nil)
    }

    @Test func theBrandIsRefusedInEveryStringAndEveryDisguise() {
        let plain = ["wh", "00", "p"].joined()
        let fullwidth = "\u{FF37}\u{FF28}\u{FF2F}\u{FF2F}\u{FF30}"
        let accented = "w\u{0301}h" + "oop"
        for disguise in [plain, plain.uppercased(), fullwidth, accented] {
            #expect(CatalogFixture.refusal(garmin: { $0["name"] = "Not \(disguise)" }) == .invalid(rule: "text.brand", path: "trackers[0].name"))
        }
        // Not only the text the app shows: ids, bundle IDs, links, keys it ignores.
        #expect(CatalogFixture.refusal(garmin: { $0["id"] = plain }) == .invalid(rule: "text.brand", path: "trackers[0].id"))
        #expect(CatalogFixture.refusal(garmin: { $0["healthkit"] = ["bundle_ids": ["com.\(plain).app"]] })
                == .invalid(rule: "text.brand", path: "trackers[0].healthkit.bundle_ids[0]"))
        #expect(CatalogFixture.refusal(garmin: { $0["help_url"] = "https://support.garmin.com/\(plain)" })
                == .invalid(rule: "text.brand", path: "trackers[0].help_url"))
        #expect(CatalogFixture.refusal({ $0["notes"] = ["x": accented] }) == .invalid(rule: "text.brand", path: "?.?")) // keys unknown to the schema
    }

    @Test func theBrandScanAgreesWithTheHooksPattern() {
        let name = ["wh", "o", "op"].joined()
        let samples = [name, name.uppercased(), "x" + name + "y", ["w", "h", "o", "o", "p"].joined(separator: "."),
                       ["W", "H", "0", "0", "P"].joined(separator: " "), ["w", "h", "o", "o", "p"].joined(separator: "-"),
                       ["wh", "0", "op"].joined(), "whop", "wh-oop", "w.h.o.o", "where", "whoa poop", "w h o o x", "", "w", "wh00",
                       "\u{FF37}\u{FF28}\u{FF2F}\u{FF2F}\u{FF30}", "w\u{0301}h" + "oop", "Open Garmin Connect"]
        for s in samples {
            let folded = s.precomposedStringWithCompatibilityMapping
                .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            let regex = folded.range(of: TrackerCatalog.brandPattern, options: [.regularExpression, .caseInsensitive]) != nil
            #expect(TrackerCatalog.containsBrand(s) == regex, "\(s)")
        }
    }

    @Test func versionsCompareByDateThenNumber() {
        #expect(TrackerCatalog.versionOrder("2026-10-22.10")! == ("2026-10-22", 10))
        #expect(TrackerCatalog.isNewer("2026-10-22.10", than: "2026-10-22.9"))
        #expect(TrackerCatalog.isNewer("2026-10-23.1", than: "2026-10-22.999"))
        #expect(!TrackerCatalog.isNewer("2026-10-22.1", than: "2026-10-22.1"))
        #expect(!TrackerCatalog.isNewer("2026-10-21.5", than: "2026-10-22.1"))
        #expect(!TrackerCatalog.isNewer("2027-01-01", than: "2026-10-22.1")) // not a version
        #expect(TrackerCatalog.isNewer("2026-10-22.1", than: "0"))           // an empty fallback catalog
        #expect(TrackerCatalog.versionOrder("2026-10-22.1x") == nil && TrackerCatalog.versionOrder("") == nil)
    }

    @Test func aMaximalHostileCopyValidatesQuickly() throws {
        // 40 trackers, every identity list at its cap, long German text in every note and most steps: the most a
        // copy can weigh (256 KiB) spent on the slowest rules.
        let step = String(repeating: "Öffne die App → Einstellungen → „Apple Health“ ", count: 3)
        func vendor(_ i: Int, steps: Int) -> [String: Any] {
            ["id": "tracker\(i)", "name": "Tracker \(i)", "form": "watch", "integration": "vendor_app",
             "healthkit": ["bundle_ids": (0..<8).map { "com.vendor\(i).app\($0)" },
                           "bundle_id_prefixes": (0..<8).map { "com.vendor\(i).kit\($0)" },
                           "source_names": (0..<8).map { "Vendor \(i) app \($0)" }],
             "capabilities": Dictionary(uniqueKeysWithValues: TrackerSignal.allCases.map { ($0.rawValue, "partial") }),
             "capability_notes": Dictionary(uniqueKeysWithValues: TrackerSignal.allCases.map { ($0.rawValue, ["en": step, "de": step]) }),
             "setup_steps": ["en": Array(repeating: step, count: steps), "de": Array(repeating: step, count: steps)],
             "checked": "2026-10-22"]
        }
        var steps = 8
        var data = Data()
        repeat {
            data = CatalogFixture.json({ doc in
                doc["trackers"] = [CatalogFixture.apple("iphone", model: "iPhone"), CatalogFixture.other] + (2..<40).map { vendor($0, steps: steps) }
            })
            steps -= 1
        } while data.count > TrackerCatalog.maxBytes
        #expect(data.count > 220_000, "\(data.count) bytes")
        let clock = ContinuousClock()
        var catalog: TrackerCatalog?
        // The best of three: a busy simulator (the parallel Unit plan) shouldn't decide it.
        var elapsed = Duration.seconds(1)
        for _ in 0..<3 {
            elapsed = min(elapsed, try clock.measure { catalog = try TrackerCatalog.decode(data, now: CatalogFixture.now) })
        }
        #expect(catalog?.trackers.count == 40)
        #expect(elapsed < .milliseconds(100), "\(elapsed)") // about 45 ms in a Debug build on the simulator
    }

    // MARK: matching and names

    @Test func sourcesMatchByBundleIDAtADotBoundary() {
        let c = TrackerCatalog.bundled
        #expect(c.match(ref("Connect", "com.garmin.connect.mobile"))?.id == "garmin")
        #expect(c.match(ref("Connect", "com.garmin.connect.mobile.watchkitapp"))?.id == "garmin")
        #expect(c.match(ref("Connect", "COM.Garmin.Connect.Mobile"))?.id == "garmin")
        #expect(c.match(ref("Connect", "com.garmin.connect.mobile2")) == nil)
        #expect(c.match(ref("Google Health", "com.fitbit.FitbitMobile"))?.id == "fitbit")
        #expect(c.match(ref("Oura", "com.ouraring.oura"))?.id == "oura")
    }

    @Test func appleDevicesAreToldApartByTheirModel() {
        let c = TrackerCatalog.bundled
        #expect(c.match(ref("Tim's Apple Watch", "com.apple.health.4B1C2D3E", "Watch"))?.id == "apple_watch")
        #expect(c.match(ref("Tim's iPhone", "com.apple.health.3F0A9B8C", "iPhone"))?.id == "iphone")
        // Without a device model (a platform `User.sources` row), neither: HealthKit's name stays.
        #expect(c.match(ref("Tim's Apple Watch", "com.apple.health.4B1C2D3E")) == nil)
        #expect(c.match(ref("Tim's iPad", "com.apple.health.77AA", "iPad")) == nil)
    }

    @Test func namesMatchOnlyWithoutABundleID() {
        let c = TrackerCatalog.bundled
        #expect(c.match(ref("Connect", nil))?.id == "garmin")
        #expect(c.match(ref("  connect ", nil))?.id == "garmin")
        #expect(c.match(ref("Health Mate", nil))?.id == "withings")
        #expect(c.match(ref("ÖURA", nil))?.id == "oura") // case and diacritics aside
        // A bundle ID always wins: a renamed source named "Connect" from another app isn't Garmin.
        #expect(c.match(ref("Connect", "com.example.connect")) == nil)
        #expect(c.match(ref("", nil)) == nil)
    }

    @Test func displayNamesAreTheAppsOrTheDevicesOwn() {
        let c = TrackerCatalog.bundled
        #expect(c.displayName(ref("Connect", "com.garmin.connect.mobile")) == "Garmin Connect")
        #expect(c.displayName(ref("Connect", nil)) == "Garmin Connect")
        #expect(c.displayName(ref("Fitbit", "com.fitbit.FitbitMobile")) == "Google Health")
        #expect(c.displayName(ref("Tim's Apple Watch", "com.apple.health.4B1C", "Watch")) == "Tim's Apple Watch")
        // Unknown sources keep HealthKit's name.
        #expect(c.displayName(ref("Sleep Diary", "com.example.sleep")) == "Sleep Diary")
        #expect(c.displayName(ref("Connect", "com.garmin.connect.mobile2")) == "Connect")
    }

    @Test func localizedTextFollowsTheAppsLanguage() {
        let text = Localized(en: "Open Garmin Connect.", de: "Öffne Garmin Connect.")
        #expect(text.value(for: "de") == text.de && text.value(for: "de-DE") == text.de && text.value(for: "DE_at") == text.de)
        #expect(text.value(for: "en") == text.en && text.value(for: "fr") == text.en && text.value(for: nil) == text.en)
        #expect(text.current == text.value(for: Bundle.main.preferredLocalizations.first))
    }

    @Test func signalsMapToTheirStreams() {
        #expect(TrackerSignal.hrv.stream == .quantity(.hrvSDNN))
        #expect(TrackerSignal.restingHR.stream == .quantity(.restingHR))
        #expect(TrackerSignal.sleepStages.stream == nil)
        #expect(TrackerSignal.allCases.count == 9)
    }
}
