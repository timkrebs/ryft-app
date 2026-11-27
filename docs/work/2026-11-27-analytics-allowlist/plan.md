# Analytics: a typed allow-list and the nutrition events (2026-11-27)

Brief: head-architect, 2026-11-27 ("Product analytics: a typed allow-list and the nutrition events (privacy first)").
User decisions of 2026-11-27: opt-in stays (no default-on, not in the beta either); the anonymous per-install ID stays
(no hashed account id, no `identify`, no server-side events); interactions only (nothing derived from HealthKit, no food
names, queries, nutrient or calorie values, no email or name).

Branch `feat/analytics-allowlist` from `origin/main` (`bde11d8`), worktree `.worktrees/analytics-allowlist`. One PR.

## Starting point

- `main` has phase 1: `Analytics` (gate, opt-in, anonymous id reset), `AnalyticsEvent` with typed tokens
  (`AnalyticsToken`), `NoopAnalyticsSink`, and a placeholder `PostHogSink` that can't send. **The SDK isn't on `main`.**
- **#137 (phase 2, open, green)** adds posthog-ios 3.98.2, the real `PostHogSink` with `configuration(for:)` and a
  `beforeSend` allow-list (`allowedEvents`, `allowedProperties`) hard-coded in the sink, and `PostHogFence`.

## Decisions

1. **SDK-agnostic, on `main`.** This PR doesn't stack on #137. The catalogue becomes the one place that lists every event
   and property key, including the SDK's lifecycle events and `$` keys that #137's `beforeSend` keeps
   (`AnalyticsCatalog.sdkEventNames`, `.sdkPropertyKeys`). Whichever of the two PRs lands second swaps #137's literals for
   the catalogue's sets, and makes `configuration(for:)` assert `AnalyticsSDKSettings(config) == .required` (a test pins it too).
   This PR pins the required SDK settings as a value (`AnalyticsSDKSettings.required`) with a test. On `main` no sink
   can send, so nothing reaches PostHog either way.
2. **Two checks before the sink.** `Analytics.track(_:)` (typed) goes through `deliver(_:properties:)`, which runs
   `AnalyticsCatalog.check(name:properties:)` before the gate. That means an unknown event, an unknown or denied key, a value
   that isn't on the key's list, or an unsafe value (email-like, longer than 40, not `^[a-z0-9_+]{1,40}$`) never reaches
   the sink. A refusal calls `onRefused` (injected; the default is `assertionFailure`, a no-op in Release). Its
   description names the event and the key, never the value.
3. **Bools are typed parameters.** They are sent as `"true"`/`"false"`. `payloadsAreTokensOnly` now allows `Bool`, but no
   `String`, `Int`, `Double` or `Date`.
4. **Buckets, not numbers.** Every count and duration is mapped to a token by a total `init` (no value falls outside).
5. **`has_results` is derived** from the results bucket (`results != .zero`), so the two can't disagree.
6. **`nutrition_search_completed` also carries `lookup` (`name` | `barcode`).** Otherwise barcode digit counts would mix
   into `query_length`. It fires once per completed first page or barcode result. A failure isn't "completed" (it's an
   error, not an event here). Load more isn't a new search.
7. **`is_canonical_staple`** = the match's `type == "generic"`: a catalogue generic food, not branded and not private.
   The API has no "staple" field. If the platform adds one, the event switches to it and keeps its name.
8. **`nutrition_food_logged` fires on a successful meal save**, deduplicated per save: once per distinct
   `(entry_point, unit_mode, is_fractional)` among the items added in this editor session, in first-seen order
   (`NutritionLogContext.loggedEvents`). Not once per food: with timestamps, per-food events add up to a meal log, and
   their count would tell how many foods the meal has. A quick add that was undone is gone by then. The entry point
   and unit mode travel on `NutritionDraftItem` as a local, non-wire field. Rows loaded from a saved meal have none, so
   a reopen-and-save logs nothing for them.
9. **`nutrition_food_opened`** fires when a search result opens the food detail: tapping the row, or "+" on a food
   without a quick selection. It doesn't fire for "Edit amount" after a quick add, nor for a suggestion.
10. **`sync_triggered` / `sync_completed`** fire only for Profile's "Sync now" row (`trigger_source: profile_button`).
    The status retry and the connection test call `syncNow()` too, but don't track. `status` is `success` | `failed` |
    `skipped` | `deferred`, from the run's `SyncCoordinator.Outcome` (awaited after the spinner ends): `failed` with an
    `error` or `cancelled`; `skipped` when pull-to-refresh returned without starting (offline, no data source);
    `deferred` when HealthKit was locked (`Outcome.waitingForUnlock`; the rest follows the unlock). `duration_ms` runs
    from the tap to `pullToRefreshRun` returning: the spinner phase the person waits for, not the coordinator's
    wait for scores (up to 300 s).
11. **Existing events vs rule 3:** every existing property is a closed token. None carries a value from HealthKit,
    a name, a query or a number. `health_access_requested`, `sleep_added` and `first_sync_completed` name an interaction,
    not health. No change beyond moving them under the catalogue.

## The catalogue (API agreed for parallel work)

```swift
// Ryft/Analytics/AnalyticsEvent.swift — new cases
case nutritionSearchCompleted(lookup: AnalyticsSearchLookup, queryLength: AnalyticsQueryLength,
                              results: AnalyticsResultCount, latency: AnalyticsLatency)
case nutritionFoodOpened(rank: AnalyticsRank, isCanonicalStaple: Bool, hasDefaultPortion: Bool, hasLastUsedPortion: Bool)
case nutritionFoodLogged(entryPoint: AnalyticsNutritionEntryPoint, unitMode: AnalyticsUnitMode, isFractional: Bool)
case nutritionDiaryReopened(hasPreservedPortionLabel: Bool)
case syncTriggered(AnalyticsSyncTrigger)
case syncCompleted(AnalyticsSyncTrigger, status: AnalyticsSyncStatus, duration: AnalyticsSyncDuration)
```

| event | key → values |
|---|---|
| `nutrition_search_completed` | `lookup`: name, barcode · `query_length`: 1_2, 3_5, 6_10, 11_20, 21+ · `results_count`: 0, 1, 2_5, 6_10, 11_20, 21+ · `has_results`: true, false · `latency_ms`: lt_250, 250_499, 500_999, 1000_1999, 2000_4999, 5000+ |
| `nutrition_food_opened` | `rank_position`: 1 … 10, 10+ · `is_canonical_staple`, `has_default_portion`, `has_last_used_portion`: true, false |
| `nutrition_food_logged` | `entry_point`: quick_add_button, detail_sheet, barcode, suggestion, private_food · `unit_mode`: curated_portion, last_used_portion, grams, ml · `is_fractional`: true, false |
| `nutrition_diary_reopened` | `has_preserved_portion_label`: true, false |
| `sync_triggered` | `trigger_source`: profile_button |
| `sync_completed` | `trigger_source`: profile_button · `status`: success, failed, skipped, deferred · `duration_ms`: lt_1000, 1000_4999, 5000_14999, 15000_59999, 60000+ |

Bucket initialisers (total): `AnalyticsQueryLength(characters:)` (≤2 → 1_2), `AnalyticsResultCount(_:)` (≤0 → 0),
`AnalyticsLatency(_ duration: Duration)` (by milliseconds), `AnalyticsRank(position:)` (1-based, ≤1 → 1, ≥11 → 10+),
`AnalyticsSyncDuration(_ duration: Duration)`.

```swift
// Ryft/Analytics/AnalyticsCatalog.swift
enum AnalyticsCatalog {
    /// event name → property key → allowed values. Literal keys; values from the tokens' allCases.
    static let events: [String: [String: Set<String>]]
    static var eventNames: Set<String> { get }
    static var propertyKeys: Set<String> { get }
    /// What #137's beforeSend keeps besides ours: lifecycle events and the SDK's own keys.
    static let sdkEventNames: Set<String>
    static let sdkPropertyKeys: Set<String>
    static func isDeniedKey(_ key: String) -> Bool      // the deny-list, exact and prefix (sleep_*, quality*)
    static func isUnsafeValue(_ value: String) -> Bool  // email-like, > 40, not ^[a-z0-9_+]{1,40}$
    enum Refusal: Error, Equatable, CustomStringConvertible {
        case unknownEvent, unknownKey(event: String, key: String), deniedKey(event: String, key: String),
             valueNotAllowed(event: String, key: String), unsafeValue(event: String, key: String),
             missingKey(event: String, key: String)
    }
    static func check(name: String, properties: [String: String]) -> Refusal?
}

/// The SDK settings the design allows (pinned; #137's configuration asserts it).
struct AnalyticsSDKSettings: Equatable, Sendable { … static let required: AnalyticsSDKSettings }

// Analytics
init(sink:flags:defaults:isDemo:isSignedIn:onRefused: @escaping @MainActor (AnalyticsCatalog.Refusal) -> Void = { assertionFailure("\($0)") })
func track(_ event: AnalyticsEvent)                  // → deliver(event.name, properties: event.properties)
func deliver(_ name: String, properties: [String: String])  // internal: catalogue check, then the gate, then the sink
```

## Verification (2026-11-27)
- `xcodebuild build` (generic iOS Simulator): succeeded, zero warnings in our code.
- 12 suites, 231 tests passed (Analytics ×7, NutritionDiary, NutritionCatalog, NutritionEditorSafety, ProfileData,
  SyncCoordinator) on a private iPhone 17 Pro simulator (iOS 27.2), serially. The full Unit plan runs in CI.
- Simulator only. Nothing was sent: on `main` every sink is a no-op.

## Tickets

| # | ticket | owner | depends | files |
|---|---|---|---|---|
| T1 | Catalogue, refusal in `Analytics`, `AnalyticsSDKSettings`, new events and buckets; call sites in Nutrition and Profile | ios-developer | — | `Ryft/Analytics/*`, `Ryft/Features/Nutrition/*`, `Ryft/Features/Profile/ProfileView.swift`, `ProfileViewModel.swift` |
| T2 | Tests: deny-list never reaches the sink; catalogue == allow-list; buckets; SDK settings pinned; refusal asserts; existing suites updated | test-engineer | API above (parallel) | `RyftTests/Analytics/*` |
| T3 | `docs/ANALYTICS.md`, privacy sentences for #252, CHANGELOG, STATUS | ios-lead | T1 | docs |
| T4 | Review: code-reviewer (one pass), security-privacy-reviewer | — | T1–T3 | read-only |

### Acceptance criteria
- A1 No event name or property key outside `AnalyticsCatalog.events` reaches the sink. A deny-listed key
  (`food_name`, `query`, `raw_query`, `search`, `hrv`, `hrv_ms`, `rhr`, `weight`, `kcal`, `calories`, `protein`,
  `email`, `name`, `sleep_*`, `quality*`), an email-like value, or a free text longer than 40 never reaches it, even on
  a listed event. Each refusal calls `onRefused` once.
- A2 The keys and values that `AnalyticsEvent.everyCase` produces equal `AnalyticsCatalog.events` exactly.
- A3 No allow-listed key matches the deny-list, and no allowed value is unsafe.
- A4 Every bucket's `init` is total and its boundaries are pinned (e.g. 249 ms → lt_250, 250 → 250_499; rank 10 → 10, 11 → 10+).
- A5 `AnalyticsSDKSettings.required` has replay off, screen views off, element interactions off (UIKit and SwiftUI),
  rage clicks off, surveys and flags off, push capture off, crash autocapture off, swizzling off, person profiles
  `never` (the brief: person profiles off, so even a stray `identify` makes none) with `identifies == false`, GeoIP
  off, and lifecycle on.
- A6 The six new events fire at the places in decisions 6 to 10, with the tokens the code there knows. Zero warnings,
  and the Unit plan is green.
