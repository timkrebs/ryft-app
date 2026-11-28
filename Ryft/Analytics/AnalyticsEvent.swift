import Foundation

/// A value an event may carry: one of a closed list, its raw value the dashboards' word (`^[a-z0-9_+]{1,40}$`; the
/// `+` is a bucket's open end, `21+`). Besides tokens an event takes only a typed `Bool` (sent as `"true"`/`"false"`),
/// never a `String`, a number or a `Date`, so no call site can send free text, a health value, a count or an account id
/// (design.md, Events). Counts and durations reach an event only as a bucket, through its total initialiser.
/// `AnalyticsCatalog` lists every value again and refuses anything else before the sink.
protocol AnalyticsToken: RawRepresentable, CaseIterable, Sendable where RawValue == String {}

/// The closed list of events. `name` and `properties` are the dashboards' contract: change them only with them, and
/// with `AnalyticsCatalog.events`.
enum AnalyticsEvent: Hashable, Sendable {
    case onboardingStep(OnboardingStepName)
    case healthAccessRequested
    case firstSyncCompleted
    case screenViewed(AnalyticsScreen)
    case quickLogAction(AnalyticsQuickLogAction)
    case featureUsed(AnalyticsFeature)
    case errorShown(AnalyticsErrorStatus, AnalyticsErrorCode)
    /// A food search's first page, or a barcode's result, arrived (a failure and Load more aren't one). Only the
    /// query's length bucket, never the query.
    case nutritionSearchCompleted(lookup: AnalyticsSearchLookup, queryLength: AnalyticsQueryLength,
                                  results: AnalyticsResultCount, latency: AnalyticsLatency)
    /// A search result opened the food's detail (its row, or "+" without a quick selection). Never the food.
    case nutritionFoodOpened(rank: AnalyticsRank, isCanonicalStaple: Bool, hasDefaultPortion: Bool, hasLastUsedPortion: Bool)
    /// A food added in this editor session was saved with its meal: how it was added and in which unit, never what or
    /// how much.
    case nutritionFoodLogged(entryPoint: AnalyticsNutritionEntryPoint, unitMode: AnalyticsUnitMode, isFractional: Bool)
    /// A saved meal was opened again for editing.
    case nutritionDiaryReopened(hasPreservedPortionLabel: Bool)
    case syncTriggered(AnalyticsSyncTrigger, previousState: AnalyticsSyncPreviousState)
    case syncCompleted(AnalyticsSyncTrigger, status: AnalyticsSyncStatus, duration: AnalyticsSyncDuration,
                       connectedProviders: AnalyticsConnectedProviders)

    var name: String {
        switch self {
        case .onboardingStep: return "onboarding_step"
        case .healthAccessRequested: return "health_access_requested"
        case .firstSyncCompleted: return "first_sync_completed"
        case .screenViewed: return "screen_viewed"
        case .quickLogAction: return "quick_log_action"
        case .featureUsed: return "feature_used"
        case .errorShown: return "error_shown"
        case .nutritionSearchCompleted: return "nutrition_search_completed"
        case .nutritionFoodOpened: return "nutrition_food_opened"
        case .nutritionFoodLogged: return "nutrition_food_logged"
        case .nutritionDiaryReopened: return "nutrition_diary_reopened"
        case .syncTriggered: return "sync_triggered"
        case .syncCompleted: return "sync_completed"
        }
    }

    var properties: [String: String] {
        switch self {
        case .onboardingStep(let step): return ["step": step.rawValue]
        case .healthAccessRequested, .firstSyncCompleted: return [:]
        case .screenViewed(let screen): return ["screen": screen.rawValue]
        case .quickLogAction(let action): return ["action": action.rawValue]
        case .featureUsed(let feature): return ["feature": feature.rawValue]
        case .errorShown(let status, let code): return ["status": status.rawValue, "code": code.rawValue]
        case .nutritionSearchCompleted(let lookup, let queryLength, let results, let latency):
            // `has_results` comes from the bucket, so the two can't disagree (plan, decision 5).
            return ["lookup": lookup.rawValue, "query_length": queryLength.rawValue, "results_count": results.rawValue,
                    "has_results": Self.word(results != .zero), "latency_ms": latency.rawValue]
        case .nutritionFoodOpened(let rank, let isCanonicalStaple, let hasDefaultPortion, let hasLastUsedPortion):
            return ["rank_position": rank.rawValue, "is_canonical_staple": Self.word(isCanonicalStaple),
                    "has_default_portion": Self.word(hasDefaultPortion),
                    "has_last_used_portion": Self.word(hasLastUsedPortion)]
        case .nutritionFoodLogged(let entryPoint, let unitMode, let isFractional):
            return ["entry_point": entryPoint.rawValue, "unit_mode": unitMode.rawValue,
                    "is_fractional": Self.word(isFractional)]
        case .nutritionDiaryReopened(let hasPreservedPortionLabel):
            return ["has_preserved_portion_label": Self.word(hasPreservedPortionLabel)]
        case .syncTriggered(let source, let previousState):
            return ["trigger_source": source.rawValue, "previous_state": previousState.rawValue]
        case .syncCompleted(let source, let status, let duration, let connectedProviders):
            return ["trigger_source": source.rawValue, "status": status.rawValue, "duration_ms": duration.rawValue,
                    "connected_providers_count": connectedProviders.rawValue]
        }
    }

    /// A typed `Bool`'s word on the wire.
    private static func word(_ value: Bool) -> String { value ? "true" : "false" }

    /// Every event there can be, from every token's `allCases` and both values of every `Bool` (the allow-list tests
    /// walk it; `AnalyticsCatalog.events` must equal what it produces).
    static var everyCase: [AnalyticsEvent] {
        let bools = [false, true]
        let existing: [AnalyticsEvent] = OnboardingStepName.allCases.map(AnalyticsEvent.onboardingStep)
            + [.healthAccessRequested, .firstSyncCompleted]
            + AnalyticsScreen.allCases.map(AnalyticsEvent.screenViewed)
            + AnalyticsFeature.allCases.map(AnalyticsEvent.featureUsed)
            + AnalyticsErrorStatus.allCases.flatMap { status in
                AnalyticsErrorCode.allCases.map { AnalyticsEvent.errorShown(status, $0) }
            }
        var searches: [AnalyticsEvent] = []
        for lookup in AnalyticsSearchLookup.allCases {
            for length in AnalyticsQueryLength.allCases {
                for results in AnalyticsResultCount.allCases {
                    for latency in AnalyticsLatency.allCases {
                        searches.append(.nutritionSearchCompleted(lookup: lookup, queryLength: length, results: results,
                                                                  latency: latency))
                    }
                }
            }
        }
        var opened: [AnalyticsEvent] = []
        for rank in AnalyticsRank.allCases {
            for staple in bools {
                for hasDefault in bools {
                    for hasLastUsed in bools {
                        opened.append(.nutritionFoodOpened(rank: rank, isCanonicalStaple: staple,
                                                           hasDefaultPortion: hasDefault, hasLastUsedPortion: hasLastUsed))
                    }
                }
            }
        }
        var logged: [AnalyticsEvent] = []
        for entryPoint in AnalyticsNutritionEntryPoint.allCases {
            for unitMode in AnalyticsUnitMode.allCases {
                for fractional in bools {
                    logged.append(.nutritionFoodLogged(entryPoint: entryPoint, unitMode: unitMode, isFractional: fractional))
                }
            }
        }
        let reopened = bools.map(AnalyticsEvent.nutritionDiaryReopened)
        let triggered = AnalyticsSyncTrigger.allCases.flatMap { source in
            AnalyticsSyncPreviousState.allCases.map { AnalyticsEvent.syncTriggered(source, previousState: $0) }
        }
        var completed: [AnalyticsEvent] = []
        for source in AnalyticsSyncTrigger.allCases {
            for status in AnalyticsSyncStatus.allCases {
                for duration in AnalyticsSyncDuration.allCases {
                    for count in AnalyticsConnectedProviders.allCases {
                        completed.append(.syncCompleted(source, status: status, duration: duration, connectedProviders: count))
                    }
                }
            }
        }
        let quickLog = AnalyticsQuickLogAction.allCases.map(AnalyticsEvent.quickLogAction)
        return existing + searches + opened + logged + reopened + triggered + completed + quickLog
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
    case nutrition
    case quickLog = "quick_log"
    case profileSheet = "profile_sheet"
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
        case .nutrition: self = .nutrition
        }
    }
}

/// `quick_log_action` → `action`.
enum AnalyticsQuickLogAction: String, AnalyticsToken {
    case logMeal = "log_meal"
    case scanBarcode = "scan_barcode"
    case startWorkout = "start_workout"
    case addActivity = "add_activity"
    case journal
    case addSleep = "add_sleep"
}

/// `feature_used` → `feature`.
enum AnalyticsFeature: String, AnalyticsToken {
    /// Only the start: a start and a finish together would give a workout's duration (privacy review).
    case trainSessionStarted = "train_session_started"
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

    /// Maps API errors to the established set of analytics tokens.
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
        case .unknownProvider, .connectionLimit, .connectTicketInvalid, .connectExpired: self = .unknown
        }
    }
}

// MARK: nutrition and sync tokens (plan 2026-11-27, "The catalogue")

/// `nutrition_search_completed` → `lookup`: a typed name or barcode digits, so a barcode's digit count never mixes into
/// `query_length`.
enum AnalyticsSearchLookup: String, AnalyticsToken {
    case name, barcode
}

/// `nutrition_search_completed` → `query_length`: the query's length as a bucket, never the query.
enum AnalyticsQueryLength: String, AnalyticsToken {
    case oneToTwo = "1_2"
    case threeToFive = "3_5"
    case sixToTen = "6_10"
    case elevenToTwenty = "11_20"
    case overTwenty = "21+"

    /// Total: anything up to 2 (also 0 or less) is `1_2`, anything over 20 is `21+`.
    init(characters: Int) {
        switch characters {
        case ...2: self = .oneToTwo
        case 3...5: self = .threeToFive
        case 6...10: self = .sixToTen
        case 11...20: self = .elevenToTwenty
        default: self = .overTwenty
        }
    }
}

/// `nutrition_search_completed` → `results_count`: how many matches the first page or the barcode gave, as a bucket.
enum AnalyticsResultCount: String, AnalyticsToken {
    case zero = "0"
    case one = "1"
    case twoToFive = "2_5"
    case sixToTen = "6_10"
    case elevenToTwenty = "11_20"
    case overTwenty = "21+"

    /// Total: 0 or less is `0`, anything over 20 is `21+`.
    init(_ count: Int) {
        switch count {
        case ...0: self = .zero
        case 1: self = .one
        case 2...5: self = .twoToFive
        case 6...10: self = .sixToTen
        case 11...20: self = .elevenToTwenty
        default: self = .overTwenty
        }
    }
}

/// `nutrition_search_completed` → `latency_ms`: from after the debounce to the result, as a bucket.
enum AnalyticsLatency: String, AnalyticsToken {
    case under250 = "lt_250"
    case from250To499 = "250_499"
    case from500To999 = "500_999"
    case from1000To1999 = "1000_1999"
    case from2000To4999 = "2000_4999"
    case atLeast5000 = "5000+"

    /// Total, by whole milliseconds: a negative duration is `lt_250`, 5 s and more `5000+`.
    init(_ duration: Duration) {
        switch duration.analyticsMilliseconds {
        case ..<250: self = .under250
        case 250..<500: self = .from250To499
        case 500..<1000: self = .from500To999
        case 1000..<2000: self = .from1000To1999
        case 2000..<5000: self = .from2000To4999
        default: self = .atLeast5000
        }
    }
}

/// `nutrition_food_opened` → `rank_position`: the result's 1-based place in the list, the first ten one by one.
enum AnalyticsRank: String, AnalyticsToken {
    case first = "1", second = "2", third = "3", fourth = "4", fifth = "5"
    case sixth = "6", seventh = "7", eighth = "8", ninth = "9", tenth = "10"
    case afterTenth = "10+"

    /// Total, 1-based: 1 or less is `1`, 11 and more `10+`.
    init(position: Int) {
        switch position {
        case ...1: self = .first
        case 2: self = .second
        case 3: self = .third
        case 4: self = .fourth
        case 5: self = .fifth
        case 6: self = .sixth
        case 7: self = .seventh
        case 8: self = .eighth
        case 9: self = .ninth
        case 10: self = .tenth
        default: self = .afterTenth
        }
    }
}

/// `nutrition_food_logged` → `entry_point`: where the food was added to the meal.
enum AnalyticsNutritionEntryPoint: String, AnalyticsToken {
    /// A search result's "+" with its quick selection.
    case quickAddButton = "quick_add_button"
    /// The food detail's Add to meal, from a name search.
    case detailSheet = "detail_sheet"
    /// Any add from a barcode's result, quick or from the detail.
    case barcode
    /// The diary's suggested food (the picker's `initialFood`).
    case suggestion
    /// A private food created in the editor.
    case privateFood = "private_food"
}

/// `nutrition_food_logged` → `unit_mode`: the kind of amount, never the amount.
enum AnalyticsUnitMode: String, AnalyticsToken {
    case curatedPortion = "curated_portion"
    case lastUsedPortion = "last_used_portion"
    case grams
    case ml
}

/// `sync_triggered` / `sync_completed` → `trigger_source`: manual and automatic foreground sync.
enum AnalyticsSyncTrigger: String, AnalyticsToken {
    case profileButton = "profile_button"
    case homescreenTopRight = "homescreen_top_right"
    case homescreenPullToRefresh = "homescreen_pull_to_refresh"
    case autoForeground = "auto_foreground"
}

/// `sync_triggered` → `previous_state`: the sync button's state at the trigger (`SyncIndicatorState`). A trigger while
/// syncing joins the running sync and sends nothing; a server-side scoring wait with no run of ours reads as `stale`.
enum AnalyticsSyncPreviousState: String, AnalyticsToken {
    case upToDate = "up_to_date"
    case stale, error
}

/// `sync_completed` → `connected_providers_count`: the direct connections in `GET /v1/me/sync` → `sources` (every entry
/// but `healthkit`), as a bucket; never which ones.
enum AnalyticsConnectedProviders: String, AnalyticsToken {
    case none = "0"
    case one = "1"
    case multiple = "2+"

    init(count: Int) {
        self = count == 0 ? .none : count == 1 ? .one : .multiple
    }
}

/// `sync_completed` → `status`, from the run's `SyncCoordinator.Outcome`. `failed`: an error or a cancellation;
/// `skipped`: nothing started (offline, or no data source); `deferred`: HealthKit was locked
/// (`Outcome.waitingForUnlock`), the rest follows the unlock. `partial`: scores were still pending at the cutoff.
enum AnalyticsSyncStatus: String, AnalyticsToken {
    case success, failed, skipped, deferred, partial
}

/// `sync_completed` → `duration_ms`: from the tap to the end of the spinner phase (`pullToRefreshRun` returning),
/// what the person waits for; not the coordinator's wait for scores. As a bucket.
enum AnalyticsSyncDuration: String, AnalyticsToken {
    case under1000 = "lt_1000"
    case from1000To4999 = "1000_4999"
    case from5000To14999 = "5000_14999"
    case from15000To59999 = "15000_59999"
    case atLeast60000 = "60000+"

    /// Total, by whole milliseconds: a negative duration is `lt_1000`, a minute and more `60000+`.
    init(_ duration: Duration) {
        switch duration.analyticsMilliseconds {
        case ..<1000: self = .under1000
        case 1000..<5000: self = .from1000To4999
        case 5000..<15000: self = .from5000To14999
        case 15000..<60000: self = .from15000To59999
        default: self = .atLeast60000
        }
    }
}

extension Duration {
    /// Whole milliseconds, rounded toward zero and clamped instead of overflowing: a bucket initialiser's input.
    fileprivate var analyticsMilliseconds: Int64 {
        let (seconds, attoseconds) = components
        let (whole, overflow) = seconds.multipliedReportingOverflow(by: 1000)
        if overflow { return seconds < 0 ? .min : .max }
        let (sum, overflowed) = whole.addingReportingOverflow(attoseconds / 1_000_000_000_000_000)
        if overflowed { return whole < 0 ? .min : .max }
        return sum
    }
}
