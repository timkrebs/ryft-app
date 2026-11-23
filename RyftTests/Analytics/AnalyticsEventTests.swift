import Foundation
import Testing
@testable import Ryft

struct AnalyticsStatusRow: Sendable, CustomTestStringConvertible {
    let status: Int?
    let transport: String?
    let expected: AnalyticsErrorStatus
    var testDescription: String { "status \(status.map(String.init) ?? "nil"), transport \(transport ?? "nil") -> \(expected.rawValue)" }

    static let all: [AnalyticsStatusRow] = [
        // No response.
        AnalyticsStatusRow(status: nil, transport: "notConnectedToInternet", expected: .offline),
        AnalyticsStatusRow(status: nil, transport: "timedOut", expected: .timeout),
        AnalyticsStatusRow(status: nil, transport: "networkConnectionLost", expected: .transport),
        AnalyticsStatusRow(status: nil, transport: "cannotFindHost", expected: .transport),
        AnalyticsStatusRow(status: nil, transport: "urlError-1", expected: .transport),
        AnalyticsStatusRow(status: nil, transport: "transport", expected: .transport),
        AnalyticsStatusRow(status: nil, transport: nil, expected: .other),
        // A listed status is itself.
        AnalyticsStatusRow(status: 400, transport: nil, expected: .s400),
        AnalyticsStatusRow(status: 401, transport: nil, expected: .s401),
        AnalyticsStatusRow(status: 403, transport: nil, expected: .s403),
        AnalyticsStatusRow(status: 404, transport: nil, expected: .s404),
        AnalyticsStatusRow(status: 409, transport: nil, expected: .s409),
        AnalyticsStatusRow(status: 413, transport: nil, expected: .s413),
        AnalyticsStatusRow(status: 422, transport: nil, expected: .s422),
        AnalyticsStatusRow(status: 429, transport: nil, expected: .s429),
        AnalyticsStatusRow(status: 500, transport: nil, expected: .s500),
        AnalyticsStatusRow(status: 502, transport: nil, expected: .s502),
        AnalyticsStatusRow(status: 503, transport: nil, expected: .s503),
        AnalyticsStatusRow(status: 504, transport: nil, expected: .s504),
        // Another 4xx or 5xx is its class.
        AnalyticsStatusRow(status: 405, transport: nil, expected: .s4xx),
        AnalyticsStatusRow(status: 418, transport: nil, expected: .s4xx),
        AnalyticsStatusRow(status: 499, transport: nil, expected: .s4xx),
        AnalyticsStatusRow(status: 501, transport: nil, expected: .s5xx),
        AnalyticsStatusRow(status: 599, transport: nil, expected: .s5xx),
        // Anything else.
        AnalyticsStatusRow(status: 200, transport: nil, expected: .other),
        AnalyticsStatusRow(status: 304, transport: nil, expected: .other),
        AnalyticsStatusRow(status: 399, transport: nil, expected: .other),
        AnalyticsStatusRow(status: 600, transport: nil, expected: .other),
        AnalyticsStatusRow(status: 0, transport: nil, expected: .other),
        AnalyticsStatusRow(status: -1, transport: nil, expected: .other),
        // A response beats a transport name.
        AnalyticsStatusRow(status: 503, transport: "timedOut", expected: .s503),
    ]
}

struct AnalyticsNameRow: Sendable, CustomTestStringConvertible {
    let event: AnalyticsEvent
    let name: String
    var testDescription: String { name }

    static let all: [AnalyticsNameRow] = [
        AnalyticsNameRow(event: .onboardingStep(.invite), name: "onboarding_step"),
        AnalyticsNameRow(event: .healthAccessRequested, name: "health_access_requested"),
        AnalyticsNameRow(event: .firstSyncCompleted, name: "first_sync_completed"),
        AnalyticsNameRow(event: .screenViewed(.today), name: "screen_viewed"),
        AnalyticsNameRow(event: .featureUsed(.dataExported), name: "feature_used"),
        AnalyticsNameRow(event: .errorShown(.s500, .none), name: "error_shown"),
    ]
}

@Suite("Analytics: the events")
@MainActor
struct AnalyticsEventTests {
    private func raw<T: AnalyticsToken>(_ type: T.Type) -> Set<String> {
        Set(T.allCases.map(\.rawValue))
    }

    // MARK: names and tokens are the dashboards' contract

    @Test(arguments: AnalyticsNameRow.all)
    func eventNamesAreTheContract(_ row: AnalyticsNameRow) {
        #expect(row.event.name == row.name)
    }

    @Test func noOtherEventNameExists() {
        #expect(Set(AnalyticsEvent.everyCase.map(\.name)) == [
            "onboarding_step", "health_access_requested", "first_sync_completed", "screen_viewed", "feature_used", "error_shown",
        ])
    }

    @Test func theTokensAreExactlyTheDesignsLists() {
        #expect(raw(OnboardingStepName.self) == [
            "invite", "consent", "about_you", "wear", "health", "notifications", "tracker_setup", "done",
        ])
        #expect(raw(OnboardingStepAction.self) == ["shown", "continued", "skipped"])
        #expect(raw(OnboardingPermission.self) == ["granted", "denied", "answered", "failed"])
        #expect(raw(AnalyticsScreen.self) == [
            "today", "sleep", "strain", "insights", "profile", "my_day", "sleep_schedule", "workout_detail", "activity_detail",
            "train_session", "train_history", "train_plans", "plan_builder", "train_import", "journal", "notification_settings",
            "devices_and_sync", "sync_details", "report_problem",
        ])
        #expect(raw(AnalyticsFeature.self) == [
            "train_session_started", "activity_added", "sleep_added", "journal_saved", "sleep_schedule_saved",
            "train_import_finished", "data_exported", "problem_reported", "notifications_allowed", "full_resync",
        ])
        #expect(raw(AnalyticsErrorStatus.self) == [
            "offline", "timeout", "transport", "400", "401", "403", "404", "409", "413", "422", "429", "4xx", "500", "502", "503",
            "504", "5xx", "other",
        ])
        #expect(raw(AnalyticsErrorCode.self) == [
            "none", "unknown", "invite_required", "consent_required", "import_in_progress", "import_not_enabled",
            "app_attest_required", "app_attest_challenge_invalid", "app_attest_invalid", "app_attest_key_unknown",
        ])
    }

    @Test func aFinishedSessionIsNotAnEventBecauseStartPlusFinishIsADuration() {
        #expect(!raw(AnalyticsFeature.self).contains("train_session_finished"))
    }

    @Test func everyTokenIsALowercaseWordNotAFreeTextOrAnId() {
        let all = raw(OnboardingStepName.self).union(raw(OnboardingStepAction.self)).union(raw(OnboardingPermission.self))
            .union(raw(AnalyticsScreen.self)).union(raw(AnalyticsFeature.self))
            .union(raw(AnalyticsErrorStatus.self)).union(raw(AnalyticsErrorCode.self))
        for value in all {
            #expect(value.range(of: "^[a-z0-9_]{1,40}$", options: .regularExpression) != nil, "\(value)")
        }
    }

    @Test func everyCaseIsEveryCombinationOnceWithNoDuplicates() {
        let cases = AnalyticsEvent.everyCase
        // `onboarding_step`: 7 steps × 3 actions, `done` shown only, and `continued` with Apple Health's 2 permission
        // outcomes and the notifications' 3.
        let onboarding = (OnboardingStepName.allCases.count - 1) * OnboardingStepAction.allCases.count + 1 + 2 + 3
        let expected = onboarding + 2 + AnalyticsScreen.allCases.count + AnalyticsFeature.allCases.count
            + AnalyticsErrorStatus.allCases.count * AnalyticsErrorCode.allCases.count
        #expect(cases.count == expected)
        #expect(Set(cases).count == cases.count)
    }

    // MARK: the allow-list

    /// The values each property may take, per event. Exhaustive, so a new event doesn't compile until it is listed.
    private func allowed(_ event: AnalyticsEvent) -> [String: Set<String>] {
        switch event {
        case .onboardingStep(let step, let action, let permission):
            var allowed = ["step": raw(OnboardingStepName.self), "action": raw(OnboardingStepAction.self)]
            // A permission only with the answer, and only Apple Health's (answered or failed: HealthKit never says what was
            // allowed) or the notifications' (iOS's answer).
            if permission != nil, action == .continued, step == .health { allowed["permission"] = ["answered", "failed"] }
            if permission != nil, action == .continued, step == .notifications {
                allowed["permission"] = ["granted", "denied", "failed"]
            }
            return allowed
        case .healthAccessRequested, .firstSyncCompleted: return [:]
        case .screenViewed: return ["screen": raw(AnalyticsScreen.self)]
        case .featureUsed: return ["feature": raw(AnalyticsFeature.self)]
        case .errorShown: return ["status": raw(AnalyticsErrorStatus.self), "code": raw(AnalyticsErrorCode.self)]
        }
    }

    @Test func everyPropertyValueIsOnTheAllowList() {
        for event in AnalyticsEvent.everyCase {
            let allowed = allowed(event)
            #expect(Set(event.properties.keys) == Set(allowed.keys), "\(event)")
            for (key, value) in event.properties {
                #expect(allowed[key]?.contains(value) == true, "\(event): \(key) = \(value)")
            }
        }
    }

    @Test func propertiesAreTheTokensOwnRawValues() {
        #expect(AnalyticsEvent.onboardingStep(.aboutYou).properties == ["step": "about_you", "action": "shown"])
        #expect(AnalyticsEvent.onboardingStep(.wear, .skipped).properties == ["step": "wear", "action": "skipped"])
        #expect(AnalyticsEvent.onboardingStep(.health, .continued, .answered).properties
            == ["step": "health", "action": "continued", "permission": "answered"])
        #expect(AnalyticsEvent.onboardingStep(.notifications, .continued, .denied).properties
            == ["step": "notifications", "action": "continued", "permission": "denied"])
        #expect(AnalyticsEvent.screenViewed(.myDay).properties == ["screen": "my_day"])
        #expect(AnalyticsEvent.featureUsed(.fullResync).properties == ["feature": "full_resync"])
        #expect(AnalyticsEvent.errorShown(.s4xx, .appAttestKeyUnknown).properties
            == ["status": "4xx", "code": "app_attest_key_unknown"])
        #expect(AnalyticsEvent.healthAccessRequested.properties.isEmpty && AnalyticsEvent.firstSyncCompleted.properties.isEmpty)
    }

    /// The leaves of an associated value: a payload tuple is flattened, an optional unwrapped (nil has none).
    private func leaves(_ value: Any) -> [Any] {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .tuple || mirror.displayStyle == .optional else { return [value] }
        return mirror.children.flatMap { leaves($0.value) }
    }

    @Test func aPermissionOnlyGoesWithTheAnswerOfItsOwnStep() {
        // Another step's, or one with shown or skipped, is dropped: the property is never there.
        #expect(AnalyticsEvent.onboardingStep(.wear, .continued, .granted).properties["permission"] == nil)
        #expect(AnalyticsEvent.onboardingStep(.health, .continued, .granted).properties["permission"] == nil,
                "Apple Health can't know granted")
        #expect(AnalyticsEvent.onboardingStep(.notifications, .skipped, .denied).properties["permission"] == nil)
        #expect(AnalyticsEvent.onboardingStep(.health, .shown, .answered).properties["permission"] == nil)
        let carrying = AnalyticsEvent.everyCase.filter { $0.properties["permission"] != nil }
        #expect(Set(carrying.compactMap { $0.properties["step"] }) == ["health", "notifications"])
        #expect(carrying.allSatisfy { $0.properties["action"] == "continued" })
    }

    @Test func doneIsOnlyShown() {
        let done = AnalyticsEvent.everyCase.filter { $0.properties["step"] == "done" }
        #expect(done == [.onboardingStep(.done)] && done.first?.properties == ["step": "done", "action": "shown"])
    }

    @Test func payloadsAreTokensOnly() {
        for event in AnalyticsEvent.everyCase {
            for child in Mirror(reflecting: event).children {
                for leaf in leaves(child.value) {
                    #expect(leaf is any AnalyticsToken, "\(event): \(type(of: leaf))")
                    #expect(!(leaf is String) && !(leaf is Int) && !(leaf is Double) && !(leaf is Bool) && !(leaf is Date),
                            "\(event): \(type(of: leaf))")
                }
            }
        }
    }

    @Test func aCaseWithoutAPayloadCarriesNothing() {
        #expect(Mirror(reflecting: AnalyticsEvent.healthAccessRequested).children.isEmpty)
        #expect(Mirror(reflecting: AnalyticsEvent.firstSyncCompleted).children.isEmpty)
    }

    // MARK: mappings

    @Test(arguments: AnalyticsStatusRow.all)
    func errorStatusBuckets(_ row: AnalyticsStatusRow) {
        #expect(AnalyticsErrorStatus(status: row.status, transport: row.transport) == row.expected)
    }

    @Test func errorCodeCoversEveryAPIErrorCode() {
        for code in APIErrorCode.allCases {
            #expect(AnalyticsErrorCode(code.rawValue).rawValue == code.rawValue, "\(code)")
        }
        // And the other way: nothing but the two bucket words is outside the platform's codes.
        let extra = raw(AnalyticsErrorCode.self).subtracting(APIErrorCode.allCases.map(\.rawValue))
        #expect(extra == ["none", "unknown"])
    }

    @Test func errorCodeBucketsWhatItDoesNotKnow() {
        #expect(AnalyticsErrorCode(nil) == .none)
        #expect(AnalyticsErrorCode("teapot") == .unknown)
        #expect(AnalyticsErrorCode("") == .unknown)
        // The platform can't claim the bucket words.
        #expect(AnalyticsErrorCode("none") == .unknown)
        #expect(AnalyticsErrorCode("unknown") == .unknown)
        #expect(AnalyticsErrorCode("INVITE_REQUIRED") == .unknown)
    }

    @Test func screenCoversEveryTab() {
        for tab in AppTab.allCases {
            #expect(AnalyticsScreen(tab).rawValue == tab.rawValue, "\(tab)")
        }
    }

    @Test func stepCoversEveryOnboardingStep() {
        let expected: [OnboardingCoordinator.Step: String] = [
            .invite: "invite", .consent: "consent", .aboutYou: "about_you", .wear: "wear",
        ]
        #expect(Set(expected.keys) == Set(OnboardingCoordinator.Step.allCases), "a new step needs its name here")
        for step in OnboardingCoordinator.Step.allCases {
            #expect(OnboardingStepName(step).rawValue == expected[step], "\(step)")
        }
    }

    // MARK: the error events carry a status and a code, nothing else

    @Test func aResourceErrorCarriesItsStatusAndCodeOnly() {
        let error = ResourceError(kind: .transient, status: 403, code: "consent_required", requestID: "req-7f3a",
                                  transport: nil, attempts: 3, at: .now)
        let event = AnalyticsEvent.errorShown(for: error)
        #expect(event == .errorShown(.s403, .consentRequired))
        #expect(event.properties == ["status": "403", "code": "consent_required"])
    }

    @Test func aResourceErrorWithoutAResponseIsATransportBucket() {
        let offline = ResourceError(kind: .transient, status: nil, code: nil, requestID: nil,
                                    transport: "notConnectedToInternet", attempts: 1, at: .now)
        let slow = ResourceError(kind: .transient, status: nil, code: nil, requestID: nil, transport: "timedOut",
                                 attempts: 1, at: .now)
        #expect(AnalyticsEvent.errorShown(for: offline) == .errorShown(.offline, .none))
        #expect(AnalyticsEvent.errorShown(for: slow) == .errorShown(.timeout, .none))
    }

    @Test func anAPIErrorCarriesNeitherItsMessageNorItsRequestID() {
        let error: Error = APIError.http(503, "the nightly sleep of 4h 12m could not be saved", requestID: "req-123",
                                         code: nil, retryAfter: 5)
        let event = AnalyticsEvent.errorShown(for: error)
        #expect(event == .errorShown(.s503, .none))
        #expect(event.properties == ["status": "503", "code": "none"])
    }

    @Test func anAPIGateErrorKeepsItsCode() {
        let error: Error = APIError.http(403, "", requestID: nil, code: .inviteRequired, retryAfter: nil)
        #expect(AnalyticsEvent.errorShown(for: error) == .errorShown(.s403, .inviteRequired))
    }

    @Test func transportFailuresAreBucketedByWhatTheyAre() {
        #expect(AnalyticsEvent.errorShown(for: APIError.transport(URLError(.notConnectedToInternet))) == .errorShown(.offline, .none))
        #expect(AnalyticsEvent.errorShown(for: APIError.transport(URLError(.timedOut))) == .errorShown(.timeout, .none))
        #expect(AnalyticsEvent.errorShown(for: APIError.transport(URLError(.cannotFindHost))) == .errorShown(.transport, .none))
        #expect(AnalyticsEvent.errorShown(for: URLError(.timedOut) as Error) == .errorShown(.timeout, .none))
        struct Plain: Error {}
        #expect(AnalyticsEvent.errorShown(for: APIError.transport(Plain())) == .errorShown(.transport, .none))
    }

    @Test func anErrorWithNeitherStatusNorTransportIsOther() {
        struct Decoding: Error {}
        #expect(AnalyticsEvent.errorShown(for: Decoding() as Error) == .errorShown(.other, .none))
        #expect(AnalyticsEvent.errorShown(for: APIError.signedOut) == .errorShown(.other, .none))
        #expect(AnalyticsEvent.errorShown(for: APIError.notConfigured) == .errorShown(.other, .none))
    }
}
