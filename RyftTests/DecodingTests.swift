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
            ({ $0["healthkit"] = ["bundle_ids": ["com.garmin.connect.mobile"], "device_models": ["Watch7,1"]] },
             invalid("device.format", "trackers[0].healthkit.device_models[0]")),
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
        // The same ID, an ID under Garmin's prefix, an overlapping prefix: each refused at the later tracker.
        #expect(CatalogFixture.refusal({ add(&$0, healthkit: ["bundle_ids": ["com.garmin.connect.mobile"]]) })
                == .invalid(rule: "bundle.duplicate", path: "trackers[4].healthkit.bundle_ids[0]"))
        #expect(CatalogFixture.refusal({ add(&$0, healthkit: ["bundle_ids": ["com.garmin.connect.mobile.watchkitapp"]]) })
                == .invalid(rule: "bundle.duplicate", path: "trackers[4].healthkit.bundle_ids[0]"))
        #expect(CatalogFixture.refusal({ add(&$0, healthkit: ["bundle_id_prefixes": ["com.garmin"]]) })
                == .invalid(rule: "bundle.duplicate", path: "trackers[4].healthkit.bundle_id_prefixes[0]"))
        // A neighbour that only starts with the same letters is another app.
        #expect(CatalogFixture.refusal({ add(&$0, healthkit: ["bundle_ids": ["com.garmin.connect.mobile2"]]) }) == nil)
        // Apple Watch and iPhone share their prefix: their devices tell them apart.
        #expect(CatalogFixture.refusal() == nil)
    }

    @Test func helpLinksStayOnTheTrackersOwnHosts() throws {
        func help(_ url: String, id: String = "garmin") throws -> URL? {
            try CatalogFixture.decode(garmin: { $0["help_url"] = url; $0["id"] = id; if id != "garmin" { $0["healthkit"] = nil } })
                .tracker(id)?.help
        }
        #expect(try help("https://support.garmin.com/en-US/")?.host == "support.garmin.com")
        #expect(try help("https://garmin.com/")?.host == "garmin.com")
        #expect(try help("https://ryftapp.de/setup/garmin")?.host == "ryftapp.de")
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
        #expect(try help("https://ryftapp.de/setup", id: "newtracker")?.host == "ryftapp.de")
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
