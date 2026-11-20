import Foundation

/// A value an event may carry: one of a closed list, its raw value the dashboards' word. No event takes a `String`,
/// a number or a `Date`, so no call site can send free text, a health value or an account id (design.md, Events).
protocol AnalyticsToken: RawRepresentable, CaseIterable, Sendable where RawValue == String {}

/// The closed list of events. `name` and `properties` are the dashboards' contract: change them only with them.
enum AnalyticsEvent: Hashable, Sendable {
    case onboardingStep(OnboardingStepName)
    case healthAccessRequested
    case firstSyncCompleted
    case screenViewed(AnalyticsScreen)
    case featureUsed(AnalyticsFeature)
    case errorShown(AnalyticsErrorStatus, AnalyticsErrorCode)

    var name: String {
        switch self {
        case .onboardingStep: return "onboarding_step"
        case .healthAccessRequested: return "health_access_requested"
        case .firstSyncCompleted: return "first_sync_completed"
        case .screenViewed: return "screen_viewed"
        case .featureUsed: return "feature_used"
        case .errorShown: return "error_shown"
        }
    }

    var properties: [String: String] {
        switch self {
        case .onboardingStep(let step): return ["step": step.rawValue]
        case .healthAccessRequested, .firstSyncCompleted: return [:]
        case .screenViewed(let screen): return ["screen": screen.rawValue]
        case .featureUsed(let feature): return ["feature": feature.rawValue]
        case .errorShown(let status, let code): return ["status": status.rawValue, "code": code.rawValue]
        }
    }

    /// Every event there can be, from every token's `allCases` (the allow-list tests walk it).
    static var everyCase: [AnalyticsEvent] {
        OnboardingStepName.allCases.map(AnalyticsEvent.onboardingStep)
            + [.healthAccessRequested, .firstSyncCompleted]
            + AnalyticsScreen.allCases.map(AnalyticsEvent.screenViewed)
            + AnalyticsFeature.allCases.map(AnalyticsEvent.featureUsed)
            + AnalyticsErrorStatus.allCases.flatMap { status in
                AnalyticsErrorCode.allCases.map { AnalyticsEvent.errorShown(status, $0) }
            }
    }

    /// An error card's failure (`RefreshIssueCard`): its status bucket and code, nothing else of it.
    static func errorShown(for error: ResourceError) -> AnalyticsEvent {
        .errorShown(AnalyticsErrorStatus(status: error.status, transport: error.transport),
                    AnalyticsErrorCode(error.code))
    }

    /// A failure shown inline (onboarding's steps): from `APIError`'s status, transport and code.
    static func errorShown(for error: Error) -> AnalyticsEvent {
        let api = error as? APIError
        var transport: String?
        if case .transport(let inner)? = api { transport = (inner as? URLError)?.code.name ?? "transport" }
        if let url = error as? URLError { transport = url.code.name }
        return .errorShown(AnalyticsErrorStatus(status: api?.status, transport: transport),
                           AnalyticsErrorCode(api?.code?.rawValue))
    }
}

/// `onboarding_step` → `step`.
enum OnboardingStepName: String, AnalyticsToken {
    case invite, consent
    case aboutYou = "about_you"
    case wear, health
    case trackerSetup = "tracker_setup"
    case done

    init(_ step: OnboardingCoordinator.Step) {
        switch step {
        case .invite: self = .invite
        case .consent: self = .consent
        case .aboutYou: self = .aboutYou
        case .wear: self = .wear
        }
    }
}

/// `screen_viewed` → `screen`.
enum AnalyticsScreen: String, AnalyticsToken {
    case today, sleep, strain, insights, profile
    case myDay = "my_day"
    case sleepSchedule = "sleep_schedule"
    case workoutDetail = "workout_detail"
    case activityDetail = "activity_detail"
    case trainSession = "train_session"
    case trainHistory = "train_history"
    case trainPlans = "train_plans"
    case planBuilder = "plan_builder"
    case trainImport = "train_import"
    case journal
    case notificationSettings = "notification_settings"
    case devicesAndSync = "devices_and_sync"
    case syncDetails = "sync_details"
    case reportProblem = "report_problem"

    init(_ tab: AppTab) {
        switch tab {
        case .today: self = .today
        case .sleep: self = .sleep
        case .strain: self = .strain
        case .insights: self = .insights
        case .profile: self = .profile
        }
    }
}

/// `feature_used` → `feature`.
enum AnalyticsFeature: String, AnalyticsToken {
    case trainSessionStarted = "train_session_started"
    case trainSessionFinished = "train_session_finished"
    case activityAdded = "activity_added"
    case sleepAdded = "sleep_added"
    case journalSaved = "journal_saved"
    case sleepScheduleSaved = "sleep_schedule_saved"
    case trainImportFinished = "train_import_finished"
    case dataExported = "data_exported"
    case problemReported = "problem_reported"
    case notificationsAllowed = "notifications_allowed"
    case fullResync = "full_resync"
}

/// `error_shown` → `status`: a bucket, never a message.
enum AnalyticsErrorStatus: String, AnalyticsToken {
    case offline, timeout, transport
    case s400 = "400", s401 = "401", s403 = "403", s404 = "404", s409 = "409", s413 = "413", s422 = "422"
    case s429 = "429"
    case s4xx = "4xx"
    case s500 = "500", s502 = "502", s503 = "503", s504 = "504"
    case s5xx = "5xx"
    case other

    /// No response: `notConnectedToInternet` → offline, `timedOut` → timeout, any other transport failure →
    /// transport. A response: a listed status as itself, another 4xx or 5xx as its class, anything else (and a failure
    /// with neither a status nor a transport, a decoding error) → other.
    init(status: Int?, transport: String?) {
        guard let status else {
            switch transport {
            case "notConnectedToInternet"?: self = .offline
            case "timedOut"?: self = .timeout
            case .some: self = .transport
            case nil: self = .other
            }
            return
        }
        if let listed = Self(rawValue: String(status)) {
            self = listed
        } else if (400..<500).contains(status) {
            self = .s4xx
        } else if (500..<600).contains(status) {
            self = .s5xx
        } else {
            self = .other
        }
    }
}

/// `error_shown` → `code`: the body's `code`, mapped one by one.
enum AnalyticsErrorCode: String, AnalyticsToken {
    case none, unknown
    case inviteRequired = "invite_required"
    case consentRequired = "consent_required"
    case importInProgress = "import_in_progress"
    case importNotEnabled = "import_not_enabled"
    case appAttestRequired = "app_attest_required"
    case appAttestChallengeInvalid = "app_attest_challenge_invalid"
    case appAttestInvalid = "app_attest_invalid"
    case appAttestKeyUnknown = "app_attest_key_unknown"

    /// nil → none; a code this build knows → its own (a new `APIErrorCode` doesn't compile until it's mapped);
    /// anything else → unknown.
    init(_ raw: String?) {
        guard let raw else {
            self = .none
            return
        }
        guard let code = APIErrorCode(rawValue: raw) else {
            self = .unknown
            return
        }
        switch code {
        case .inviteRequired: self = .inviteRequired
        case .consentRequired: self = .consentRequired
        case .importInProgress: self = .importInProgress
        case .importNotEnabled: self = .importNotEnabled
        case .appAttestRequired: self = .appAttestRequired
        case .appAttestChallengeInvalid: self = .appAttestChallengeInvalid
        case .appAttestInvalid: self = .appAttestInvalid
        case .appAttestKeyUnknown: self = .appAttestKeyUnknown
        }
    }
}
