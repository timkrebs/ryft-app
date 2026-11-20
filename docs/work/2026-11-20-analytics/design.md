# Product analytics, phase 1: the seam, the gate, the opt-in (A1)

Contract: platform `API.md` → `GET /v1/config` → `analytics` and the flag `analytics.enabled` (D231, platform PR #191).
The user's decisions of 2026-11-16 (opt-in, pseudonymous, a fixed event list, a no-op seam, posthog-ios in phase 2) are
binding. Phase 1 compiles and ships **without** the SDK; phase 2 adds one file and the package.

**Problem.** Send a closed list of anonymous events to PostHog EU only while three facts hold: the flag is on, the newest
config has `analytics`, and the user opted in. When any stops holding: stop at once and drop what is queued. The host
and key come from the config, never from the build; the key is never logged or stored outside the config cache. No
call site may be able to send free text, a health value, or an account id.

| | Option | For | Against |
| --- | --- | --- | --- |
| **A** | One `@MainActor` owner, `Analytics`, on `AppEnvironment`: a pure gate, call sites `track(AnalyticsEvent)`, a 3-method `AnalyticsSink` behind it | one owner for opt-in, the running destination and the owed reset; the gate unit-tests like `OnboardingCoordinator.gate`; phase 2 is one file | the flag store needs a "newest" read and a change hook |
| B | Call sites talk to a sink protocol directly; each checks the gate | no new owner | the gate copied into every call site; a forgotten check sends |
| C | A global `Analytics.shared` like the older singletons | short call sites | a new `.shared` in new code; tests and previews can't swap it |

**Choice: A.**

## Decisions
1. **New folder `Ryft/Analytics/`** (synchronized: in the app target only, never widgets or watch): `Analytics.swift`
   (the owner and gate), `AnalyticsEvent.swift` (events and tokens), `AnalyticsSink.swift` (protocol, `NoopAnalyticsSink`,
   `AnalyticsSinks.live()`). Tests: `RyftTests/Analytics/FakeAnalyticsSink.swift` and the suites below.
2. **Wire model.** `Models.swift`: `struct AnalyticsConfig: Codable, Hashable { let host: String; let projectKey: String }`
   and `var analytics: AnalyticsConfig? = nil` on `RemoteConfig`: `null` and a missing key (configs cached before)
   decode as nil. Both fixture examples in `API.md` get a decoding test. PR 1 changes the `remote_config` fixture and adds
   `appAttest`; rebase on it, don't touch its lines. `AnalyticsConfig` conforms to `CustomStringConvertible`,
   `CustomDebugStringConvertible` and `CustomReflectable`, all printing `host` and `project_key: <redacted>`, so
   `"\(config)"`, `dump` and a `Logger` interpolation of `RemoteConfig` never show the key.
3. **Flag.** `FeatureFlag.analyticsEnabled = "analytics.enabled"`, compiled default `false`. Debug overrides work as
   for every flag (Release ignores them), so the remote `false` is the kill switch.
4. **The gate sees the newest answer, not the shown one.** `FlagStore` defers answers to the next screen so the UI
   doesn't change under the user; analytics isn't UI, and a kill switch must act now. `FeatureFlagProvider` gains:
   `func newest(_ flag: FeatureFlag) -> Bool` (launch flags and overrides, then `pending ?? shown`, then the default),
   `var newestAnalytics: AnalyticsConfig? { get }` (`pending?.config.analytics ?? shown`; `FlagStore` keeps the shown
   config's `analytics` beside `remote`), and `var onNewest: (@MainActor () -> Void)? { get set }`, called at the end of
   `apply` (shown or pending), `reload` (account or demo switch), `reset` and `setOverride`/`clearOverrides`.
   `StaticFlags` implements all three (`newest` = `isOn`; `analytics` and `overrides` fire `onNewest` in `didSet`).
   Config reads that only `ConsentState` records (onboarding's) still don't reach the flags, as today; the next
   `FeatureFlags.refresh` (launch, app active when due, every `ttl_sec`) brings them.
5. **The gate is pure:** `nonisolated static func destination(flag: Bool, config: AnalyticsConfig?, optIn: OptIn,
   demo: Bool) -> AnalyticsDestination?`. Open only for `flag && config valid && optIn == .optedIn && !demo`.
   `AnalyticsDestination(config)` is failable: `host` must parse as `https://<host>` with no user, port, path, query or
   fragment; `projectKey` must match `^phc_[A-Za-z0-9_-]{8,128}$`. Anything else counts as `null`. The destination
   redacts its key exactly like decision 2.
6. **One owner.** `@MainActor @Observable final class Analytics` (`lazy var analytics` on `AppEnvironment`, built with
   `env.analyticsSink`, a new `init` parameter defaulting to `NoopAnalyticsSink()`). It owns `optIn` (observed), and,
   unobserved, the running destination and `resetOwed`. API, and the only API call sites see:
   `track(_ event: AnalyticsEvent)`, `setOptIn(_ on: Bool)`, `reevaluate()`, `accountLeft()`, `showsPrompt`,
   `showsToggle`. `track` re-runs the gate first, so an event never rides on a stale answer.
7. **No queue of ours.** An event while the gate is closed is dropped, never buffered for later: buffering before the
   opt-in would be collecting before consent. The only queue is the SDK's (phase 2), and `stop()` empties it.
8. **The sink** (what phase 2 implements; the façade is its only caller):
   ```swift
   @MainActor protocol AnalyticsSink: AnyObject {
       /// Sending to `destination` from now on, replacing any other. `newID`: forget the stored anonymous id first.
       func start(_ destination: AnalyticsDestination, newID: Bool)
       func capture(_ name: String, properties: [String: String])
       /// Stop sending and drop everything queued, in memory and on disk. Keeps the id.
       func stop()
       /// False for the no-op: no prompt and no toggle are shown for a sink that can't send (decision 13).
       var canSend: Bool { get }
   }
   ```
   `reevaluate()`: gate closed and running → `stop()`. Open with another destination (newer host or key) → `stop()`
   (the old project's queue goes, it never reaches the new one), then `start(new, newID: resetOwed)`, then
   `resetOwed = false`. Same destination → nothing.
9. **Opt-in storage: per install, in `env.defaults`, not per account.** Key `analytics.optIn`: absent (not asked),
   `"in"`, `"out"`; key `analytics.resetOwed`: `Bool`. No account id is ever stored next to them. Opt-out
   (`setOptIn(false)`): `resetOwed = true` (written first, so a kill can't lose it), then `stop()`. Opting in again starts
   with a new id.
10. **Sign-out clears the answer too, not just the id.** `accountLeft()` sets `resetOwed`, calls `stop()` and removes
    `analytics.optIn`, so whoever signs in next on this phone is asked after their own onboarding. Called from
    `AppState.wiped(_:)` (the `auth.onWipe` hook), which runs in every wipe pass: sign-out, deletion, a final `401`, a
    sign-in over another owner, an owed wipe resumed. Not from `AuthService.wipeSharedLocalData`: that's static and would
    need `.shared`. The cost: a session expiry asks again after the next sign-in. The user may prefer to keep the answer
    across sign-outs; then only this line changes.
11. **The id is the SDK's.** PostHog makes a random anonymous id per install. `identify`, `alias` and `group` are
    never called, person profiles are `identifiedOnly`, so every event is anonymous. `resetOwed` exists because a reset
    may be asked while the SDK isn't set up in this process (flag off since launch): the next `start` honours it.
12. **Where the no-op comes from.** `AnalyticsSinks.live()` is the one switch, in `AnalyticsSink.swift`:
    ```swift
    static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AnalyticsSink {
        #if targetEnvironment(simulator)
        return NoopAnalyticsSink()
        #elseif canImport(PostHog)
        #if DEBUG
        guard arguments.contains("-RyftAnalytics") else { return NoopAnalyticsSink() }
        #endif
        return PostHogSink()
        #else
        return NoopAnalyticsSink()
        #endif
    }
    ```
    Only `.live` passes it; `.preview` and `.test` keep the default no-op (a test passes a `FakeAnalyticsSink`). Debug
    device builds send only with `-RyftAnalytics` (phase 2's verification), so developers don't pollute dashboards.
    Demo mode is a runtime state: the gate is closed while `env.isDemo`, and `FlagStore.setDemo` fires `onNewest`.
13. **Prompt and toggle exist only where they mean something.** `showsPrompt`: `sink.canSend`, `optIn == nil`,
    `newest(.analyticsEnabled)`, a valid `newestAnalytics`, `!isDemo`. `showsToggle`: `sink.canSend` and (`showsPrompt`
    preconditions minus "not asked", or `optIn == .optedIn`): someone opted in can always withdraw, even with the flag
    off. Phase 1 therefore shows neither to anyone (no-op everywhere); previews render the views directly.
14. **"Once, after the onboarding."** `AnalyticsOptInSheet` (`Features/Profile/AnalyticsOptInSheet.swift`, so the Privacy
    owner holds both), presented by a modifier `.analyticsOptInPrompt()` on RootView's `tabs` (the tabs exist only after
    every onboarding step, Apple Health and tracker setup). It presents when `showsPrompt` and no other root presentation
    is up; it joins `presentsSomething` (ADR 0017). Two equal buttons, "Share usage data" and "Don't share"; a swipe is
    "Don't share". Any answer is final until sign-out (decision 10). Copy (English, `Localizable.xcstrings`): "Help
    improve RYFT? Share anonymous usage: which screens you open and which features you use. Never your health data,
    scores or anything you type, and not linked to your account. Change it any time in Profile → Privacy."
15. **Profile → Privacy toggle: one line in `ProfileView.privacy`**, after the Privacy Policy button:
    `AnalyticsOptInRow()` (own file, `Features/Profile/AnalyticsOptInRow.swift`, reads `env.analytics` from the
    environment; `ProfileViewModel` untouched). A `Toggle` "Share usage data" with the caption "Anonymous; never health
    data. Off stops sending at once." PR #127 (nocturne) touches Profile and the tab bar: this is one inserted line in
    `privacy`, one modifier line on `tabs` and one term in `presentsSomething`, each separable.
16. **SDK configuration (phase 2, names as of posthog-ios 3.x; check the pinned version):** `captureElementInteractions`
    (autocapture), `captureScreenViews`, `sessionReplay`, `surveys`, `preloadFeatureFlags`, `sendFeatureFlagEvent` all
    off; `captureApplicationLifecycleEvents` on; `personProfiles = .identifiedOnly`; small `flushAt`/`maxQueueSize`. A
    properties sanitizer keeps our properties plus a reviewed list of the SDK's defaults (app version and build, OS
    version, device model class) and drops the rest; the reviewed list goes into the phase-2 PR. `PostHogSink` uses an
    instance (`PostHogSDK.with(config)`), not `PostHogSDK.shared`, so a new destination is close-and-recreate.

## Events (names are the dashboards' contract)
`AnalyticsEvent` cases carry only `AnalyticsToken`s: `protocol AnalyticsToken: RawRepresentable, CaseIterable, Sendable
where RawValue == String`. No event takes a `String`, `Int`, `Double` or `Date`; `name` and `properties` are computed.

| Event | Property: values | Emitted at (file → function) |
| --- | --- | --- |
| `onboarding_step` | `step`: `invite`, `consent`, `about_you`, `wear`, `health`, `tracker_setup`, `done` | `RyftApp.swift` → `RootView.content`: `.onChange(of: analyticsStep, initial: true)`; `analyticsStep` derived from `flowStep ?? sheetStep`, `needsHealthIntro`, `showsTrackerSetup`; `done` from `OnboardingCoordinator.reachedTabs()` on its first run |
| `health_access_requested` | none | `HealthPermissionView.swift` → `HealthOnboardingViewModel.connect()`, before `requestAuthorization()` |
| `first_sync_completed` | none | `RyftApp.swift` → `.onChange(of: sync.phase)`: `.done` while `!screens.push.hasSynced`, before `syncSucceeded()` |
| `screen_viewed` | `screen`: `today`, `sleep`, `strain`, `insights`, `profile`, `my_day`, `sleep_schedule`, `workout_detail`, `activity_detail`, `train_session`, `train_history`, `train_plans`, `plan_builder`, `train_import`, `journal`, `notification_settings`, `devices_and_sync`, `sync_details`, `report_problem` | tabs: `RyftApp.swift` → `.onChange(of: state.selectedTab)` and `tabs.onAppear` (not the tab bar view); others: `.analyticsScreen(.x)` on the root of `MyDayView`, `SleepScheduleView`, `WorkoutDetailView`, `ActivityDetailView`, `SessionView`, `TrainHistoryView`, `PlansView`, `PlanBuilderView`, `ImportFlowView`, `JournalSheet`, `NotificationSettingsView`, `DevicesAndSyncView`, `SyncDetailsView`, `ReportProblemView` |
| `feature_used` | `feature`: `train_session_started`, `train_session_finished`, `activity_added`, `sleep_added`, `journal_saved`, `sleep_schedule_saved`, `train_import_finished`, `data_exported`, `problem_reported`, `notifications_allowed`, `full_resync` | `TrainCoordinator.start(_:)` and `.finish(_:…)`; `AddActivityModel.save()` and `AddSleepModel.save()` on `true`; `JournalSheetModel.save()` on success; `SleepPlannerViewModel.save(account:defaults:)`; `ImportCoordinator.finish(_:)` with `openPlan`/`openHistory`; `ProfileViewModel.export()` on a file; `ReportProblemModel.send()` on sent or queued; `PushRegistrar.accept()` when granted; `ProfileViewModel.fullResync()` |
| `error_shown` | `status`: `offline`, `timeout`, `transport`, `400`, `401`, `403`, `404`, `409`, `413`, `422`, `429`, `4xx`, `500`, `502`, `503`, `504`, `5xx`, `other`; `code`: `none`, `unknown`, `invite_required`, `consent_required`, `import_in_progress`, `import_not_enabled`, `app_attest_required`, `app_attest_challenge_invalid`, `app_attest_invalid`, `app_attest_key_unknown` | `StatusViews.swift` → `RefreshIssueCard`: `.analyticsError(issue.error)` (from `ResourceError.status/transport/code`); `OnboardingCoordinator.perform(_:message:)`'s catch (from `APIError`) |
| `Application Installed`, `Application Opened`, `Application Backgrounded` | the SDK's | the SDK, only while started |

`AnalyticsErrorStatus.init(status: Int?, transport: String?)`: no status and `notConnectedToInternet` → `offline`,
`timedOut` → `timeout`, any other no-response → `transport`; a listed status as itself; other 4xx/5xx → `4xx`/`5xx`;
anything else → `other`. `AnalyticsErrorCode.init(_ raw: String?)`: nil → `none`, a known `APIErrorCode` → the exhaustive
switch (a new code fails to compile until it's mapped), else `unknown`. `AnalyticsScreen.init(_ tab: AppTab)` and
`OnboardingStepName.init(_ step: OnboardingCoordinator.Step)` are exhaustive switches too.

## Migration steps (phase 1, one PR, no SDK)
1. `AnalyticsConfig`, `RemoteConfig.analytics`, fixtures and decoding tests (after PR 1).
2. `FeatureFlag.analyticsEnabled`; `newest`, `newestAnalytics`, `onNewest` on the provider, `FlagStore`, `StaticFlags`.
3. `Ryft/Analytics/` (decisions 5–12); `AppEnvironment` gains `analyticsSink` and `lazy var analytics`; `.live` passes
   `AnalyticsSinks.live()`; ScreenModels sets `flags.onNewest = { env.analytics.reevaluate() }`; RyftApp's utility
   launch task calls `env.analytics.reevaluate()` after the first frame; `AppState.wiped` calls `accountLeft()`.
4. Call sites from the table, one line each. 5. Sheet, row, strings, dark previews. 6. CHANGELOG Unreleased: "Optional,
   anonymous usage analytics, off unless you opt in (not active yet)." `PrivacyInfo.xcprivacy` is unchanged until data
   is collected (phase 2 adds Product Interaction, not linked, Analytics; and updates `docs/APP_STORE.md`).

**Phase 2** (the user adds posthog-ios at an exact version, app target only): one new file
`Ryft/Analytics/PostHogSink.swift`, entirely inside `#if canImport(PostHog)`, plus decision 16, the manifest and the App
Store answers. No call site changes; `AnalyticsSinks.live()` already selects it.

## Tests (Swift Testing; `AnalyticsGateTests`, `AnalyticsEventTests`, `AnalyticsConfigDecodingTests`, `AnalyticsPromptTests`)
Graph: `.test(flags:)` with a `FakeAnalyticsSink` recording `starts [(destination, newID)]`, `captures`, `stops`, a
simulated `queued` that `stop()` empties; `StaticFlags.analytics` set to a valid config unless the test says otherwise.
- `noEventBeforeOptIn`: not asked, flag on, config valid; every event → no start, no capture.
- `noEventAfterDecline`: `optIn` out → nothing.
- `noEventWithFlagOff` / `noEventWithAnalyticsNull` / `noEventInDemoMode`: the one fact false → nothing.
- `sendsOnlyWhenAllThreeHold`: all true → one start with the config's destination, then the capture.
- `flagOffStopsAndDropsQueue` / `analyticsNullStopsAndDrops` / `optOutStopsAndDrops`: running with events queued; the
  fact turns false → `stop()` once, queue empty, the next `track` captures nothing.
- `pendingKillSwitchActsAtOnce`: real `FlagStore` (in-memory `TrainStore`) showing flag on; `apply` a newer answer with it
  off (pending, screens unchanged) → stopped before any `applyPending()`.
- `newestHostAndKeyUsed`: a pending answer with another host and key → `stop()`, then `start` with the new destination,
  `newID: false`; the old queue never reaches it.
- `optOutResetsID`: opt out, opt in → `start(newID: true)`.
- `signOutResetsIDAndClearsAnswer`: `accountLeft()` → `stop()`, `resetOwed`, `optIn == nil`; opting in again →
  `newID: true`. `accountSwitchClosesGate`: `switchAccount` to B whose cache has the flag off → stopped.
- `resetOwedSurvivesRelaunch`: reset while not started; a new `Analytics` on the same defaults → first start `newID: true`.
- `invalidDestinationCountsAsNull`: `http://`, a path, a port, user info, an empty or non-`phc_` key → closed.
- `keyNeverInDescriptions`: `"\(x)"`, `String(reflecting: x)` and `dump(x)` of `AnalyticsConfig`, `AnalyticsDestination`
  and `RemoteConfig` don't contain the key; `analytics.optIn`/`resetOwed` are the only `analytics.*` defaults keys.
- `eventNamesAreTheContract`: names equal the literal list above.
- `everyPropertyValueIsOnTheAllowList`: walk `AnalyticsEvent.everyCase` (built from every token's `allCases`); each
  property key is the event's, each value in that token's raw values; nothing else.
- `payloadsAreTokensOnly`: `Mirror` over every case's associated values: each is an `AnalyticsToken` (no `String`,
  number, `Date`).
- `errorStatusBuckets`, `errorCodeCoversEveryAPIErrorCode` (every `APIErrorCode.allCases` maps to its own raw value;
  `"teapot"` → `unknown`), `screenCoversEveryTab`, `stepCoversEveryOnboardingStep`.
- `analyticsDecodesFromAPIExample`, `analyticsNullDecodesAsNil`, `configCachedWithoutAnalyticsDecodes`.
- `previewAndTestGraphsUseNoop`: `.preview()` and `.test()` sinks are `NoopAnalyticsSink`; `liveSinkIsNoopInSimulator`
  (tests run in the simulator); `noopCanNotSend`.
- `promptOnlyWhereItMeansSomething`: `showsPrompt` false for the no-op, demo, flag off, `null`, after any answer;
  `toggleStaysWhileOptedInWithFlagOff`; `swipeCountsAsDecline`.

## What could go wrong
- **Onboarding events are rare by construction.** The prompt comes after onboarding and nothing is buffered, so
  `onboarding_step` only reaches PostHog for gate sheets after the first run (a new policy, an invite). The same holds
  for `health_access_requested` and often `first_sync_completed`. If the user wants an onboarding funnel, the prompt has
  to move before it. That's his call, not this PR's.
- `Application Installed` fires on the SDK's first start, not at install, and maybe again after a reset. Phase 2
  checks this against the pinned version.
- Phase 2 must check which SDK call empties the persisted queue without changing the id. If only `reset()` does,
  `stop()` resets the id too: more private, fewer returning users counted.
- Kill-switch latency is the config refresh: launch, app active when due, `ttl_sec` (6 h).
- Repo rules still say "no analytics SDKs" (`.claude/skills/ryft-app-conventions` rule 4, `docs/APP_STORE.md`). Phase 2
  needs an ADR ("analytics: opt-in PostHog behind a seam") and those lines updated along with the dependency.
