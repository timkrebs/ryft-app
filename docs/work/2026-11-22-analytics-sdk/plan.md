# A1 phase 2: the PostHog SDK and the opt-in in the onboarding (2026-11-22)

> Superseded in part (2026-11-27, merge with #150): `personProfiles = .never`, and `beforeSend` uses
> `AnalyticsCatalog` instead of its own lists. See ADR 0026 (amended) and `docs/ANALYTICS.md`.

Brief: head-architect, 2026-11-20 (the user's decisions of that day). Phase 1: #130 (`4bc1800`), its docs in
`docs/work/2026-11-20-analytics/`. Branch `feat/analytics-sdk` (deps commit `8dcf63d` on main `7341d55`). One PR.

**Verified first:** `Package.resolved` pins `posthog-ios` at **3.98.2** (revision `a4deb72`). The pbxproj has an `exactVersion`
requirement, and the product `PostHog` is in the `Ryft` target's frameworks phase and `packageProductDependencies` only.

## What the pinned SDK does (read from the 3.98.2 checkout)
- **At launch: nothing.** It has no `+load`, no `__attribute__((constructor))` and no module initialiser. Its Swift
  `static let shared` values are lazy. The two `+initialize` (vendored PLCrashReporter) run only when their class is
  first messaged, which happens only with crash autocapture on (we keep it off). `import PostHog` runs no code. Nothing
  touches the network until `setup`.
- **`setup` (via `PostHogSDK.with`) touches the network once at once:** a `GET https://eu-assets.i.posthog.com/array/<key>/config`
  (remote config, "always loaded", no public switch), and `/flags` only with `preloadFeatureFlags`. The fence below
  refuses every host but `eu.i.posthog.com`, so that request fails, and nothing reaches the assets CDN.
- **Defaults that would collect more than the contract**, all turned off: `captureScreenViews` (true), the rage-click
  integration (`rageClickConfig.enabled` true), push-token registration and push-open capture
  (`capturePushNotificationSubscriptions`/`…Opened` true, which send the APNs token to PostHog), `surveys` (true),
  `preloadFeatureFlags` and `sendFeatureFlagEvent` (true), `setDefaultPersonProperties` (true), `enableSwizzling`
  (true). These are off by default: autocapture, session replay, error-tracking autocapture.
- **`close()` flushes first** (one batch goes out) and leaves the rest on disk for the next setup. So `stop()` can't just
  be `close()`.
- **`reset()` keeps `$device_id`** (`posthog.deviceId`, "persists across identify() and reset()"). So a reset through
  the SDK alone isn't a new id. We delete the SDK's files ourselves.
- **Storage:** `Application Support/<bundle id>/<project key>/`. The app doesn't use that folder for anything else.
  Files are written with `Data.write(to:)` and no options, so they get the app's default class, which is complete until
  first user authentication, since `Ryft.entitlements` sets no data-protection class. That meets the phase 1 review's
  "complete-until-first-unlock or better". All of it is excluded from backup.
- **Every request goes through one `URLSession`** built from `config.urlSessionConfiguration` (`PostHogApi`), which is
  where the fence sits.
- **Manifests:** PostHog declares Product Interaction and Other Usage Data (not linked, no tracking, Analytics), plus
  the required-reason APIs UserDefaults CA92.1, SystemBootTime 35F9.1 and FileTimestamp C617.1. It has no
  `NSPrivacyTracking` key (so false) and no tracking domains. PLCrashReporter's own manifest declares `NSPrivacyTracking`
  false, an empty `NSPrivacyTrackingDomains`, and Crash Data plus Other Diagnostic Data (App Functionality). We never
  turn the crash reporter on.

## Design: the adapter (ticket T1)
`Ryft/Analytics/PostHogSink.swift`, all inside `#if canImport(PostHog)`. It's `@MainActor final class PostHogSink:
AnalyticsSink` (from the protocol). Its `init(root: URL = PostHogSink.defaultRoot)` does no SDK work. `defaultRoot` is
`URL.applicationSupportDirectory/<Bundle.main.bundleIdentifier>`, the SDK's own base folder.
- `canSend`: `true`.
- `start(dest, newID:)`, which starts only after the three conditions hold (`Analytics.reevaluate` calls it only then):
  1. if running, `stop()` first;
  2. `newID`: `forgetFiles()`, which deletes `root`, every project's id and queue;
  3. `PostHogFence.open(true)`;
  4. `sdk = PostHogSDK.with(Self.configuration(for: dest))`.
- `capture(name, properties)`: `sdk?.capture(name, properties: properties)`. Nil while stopped.
- `stop()`, in this order:
  1. `PostHogFence.open(false)`, so no request of the SDK's leaves from here;
  2. `deleteQueues()`, which runs for every child folder of `root`, also with no SDK set up in this process. It removes
     `posthog.queueFolder.uuid`, `posthog.queueFolder`, `posthog.queue.plist`, `posthog.replayFolder.uuid`,
     `posthog.replayFolder`, `posthog.replayBufferFolder`, `posthog.logsFolder` and `posthog.optOut`;
  3. `sdk?.close()`: its flush finds no files (the SDK skips missing files) and is fenced anyway. Integrations are
     uninstalled and lifecycle events stop;
  4. `sdk = nil`.

  A batch already on the wire when the fence closes can't be recalled. It was captured while opted in.
- `forgetID()`: `stop()`, then `forgetFiles()`.
- `nonisolated static func configuration(for: AnalyticsDestination) -> PostHogConfig`. It's pure and unit-tested:
  - host `dest.host.absoluteString`, key `dest.projectKey`;
  - `captureScreenViews`, `captureElementInteractions`, `captureSwiftUIElementInteractions`, `rageClickConfig.enabled`,
    `sessionReplay`, `surveys`, `preloadFeatureFlags`, `sendFeatureFlagEvent`, `setDefaultPersonProperties`,
    `capturePushNotificationSubscriptions`, `capturePushNotificationOpened`, `errorTrackingConfig.autoCapture`,
    `enableSwizzling` and `debug` all **false**;
  - `captureApplicationLifecycleEvents` **true**; `personProfiles = .identifiedOnly`; `disableGeoIp = true`;
  - `flushAt = 10`, `maxQueueSize = 200`;
  - `urlSessionConfiguration` is `.ephemeral`, with `protocolClasses = [PostHogFence.self] + existing`;
  - `setBeforeSend(PostHogSink.sanitize)`.
- `nonisolated static func sanitize(_ e: PostHogEvent) -> PostHogEvent?`. It's pure and unit-tested:
  - **Event names allowed:** `AnalyticsEvent`'s names plus `Application Installed`, `Application Opened` and
    `Application Backgrounded`. Anything else returns nil: `$screen`, `$rageclick`, `$exception`, `$identify`, `$set`,
    `$feature_flag_called`, `$snapshot`, `Application Updated` and so on.
  - **Property keys allowed:** our own (`step`, `screen`, `feature`, `status`, `code`); `$app_version`, `$app_build`,
    `$os_name`, `$os_version`, `$device_type`, `$lib`, `$lib_version`, `$session_id`, `$process_person_profile`,
    `$geoip_disable`; and the lifecycle ones (`version`, `build`, `previous_version`, `previous_build`,
    `from_background`). Every other key is removed: `$device_id`, `$device_name`, `$device_model`, `$locale`,
    `$timezone`, `$network_*`, `$screen_*`, `$set*`, `url`, `referring_application`, `$referrer` and the rest.
  - The allow-lists are `static let` sets, written out in the file. The PR body lists them.
- `PostHogFence: URLProtocol` (same file, or `PostHogFence.swift`). A `static` lock-guarded `open: Bool` (an
  `OSAllocatedUnfairLock`), and `nonisolated static func blocks(_ request: URLRequest) -> Bool`, which is pure and
  tested. It blocks unless the fence is open **and** the host is exactly `AnalyticsDestination.allowedHost`.
  `canInit` returns `blocks(request)`, and `startLoading` fails with `URLError(.cancelled)`.
- Never `identify`, `alias`, `group` or `register`. Never `PostHogSDK.shared`. No logging of the destination or key.
- `AnalyticsSinks.live()` stays as phase 1 built it: the simulator gets the no-op, a Debug device build gets it unless
  launched with `-RyftAnalytics`, and only Release device builds get `PostHogSink`. Previews and tests never call
  `live()`, and demo mode closes the gate.

## Design: decision B (ticket T2)
- **The step:** `OnboardingCoordinator.showsAnalyticsStep`. It's true only while all of these hold:
  - `phase == .ready`;
  - `isFirstRun` (this account hasn't reached the tabs on this phone);
  - `flowStep == nil` (invite, consent, about you and wear are done);
  - not demo, signed in;
  - `env.analytics.showsPrompt` (not answered, a sink that can send, the flag on, a valid `analytics`).

  Review change: an Apple Health condition (`!settings.healthIntroDone`) was dropped. That flag is per install and turns
  true by itself on a phone where iOS already asked, so a second account would never have been asked.

  RootView's `content` switch gets a case between `flowStep` and `needsHealthIntro`, a full-screen
  `AnalyticsOptInStepView`, with the same fade and `LaunchSignpost.screenAppeared`. The order:
  invite → consent → about you → wear → **analytics** → health → tracker setup → tabs.
- **The view:** today's `AnalyticsOptInSheet` content, as a full-screen onboarding step with no sheet and no swipe. It has
  the same title, lead, four points and footnote. There are **two equal buttons**: "Share usage analytics" and "Not now".
  They're the same `PillButton(style: .secondary)`, with neither pre-selected and neither primary. "Not now" is
  `setOptIn(false)`, and the "Not now" string is reused if the catalog has it. The identifiers stay `analytics.share`
  and `analytics.decline`.
- **`onboarding_step` while the step shows:** RootView's `analyticsStep` returns **nil** while `showsAnalyticsStep`.
  Otherwise it would already say `.health` under the question, and a yes would never send it. After a yes it becomes
  `.health` and fires through the open gate; after "Not now" it fires into a closed gate and is dropped.
- **The post-onboarding sheet goes:** `analyticsOptInPrompt(blocked:)`, `AnalyticsOptInPrompt`, `tabsShown` and the
  `presentsSomething` term are removed. No path needs it any more:
  - accounts past their first run aren't asked again (decision B), and Profile → Privacy keeps the toggle;
  - "Not now" answers, so the step never comes back.

  Its previews and `DebugScreen.analyticsPrompt` move to the step view.
- **Who is never asked by the app:**
  - accounts that finished onboarding on this phone before this build (`firstRunDone`);
  - "Not now";
  - accounts signing in again on a phone where they already reached the tabs. Sign-out clears the answer (phase 1 rule),
    but `firstRunDone` is per account, so they see no step. Profile → Privacy is their way in.
- **Config timing:** the step shows only if the flag and `analytics` are known when the gates end. Otherwise it's
  skipped (never retried as a sheet). If they arrive while the Health intro is up, the step appears before Health; it's
  still "before health". The launch `FeatureFlags.refresh` normally lands long before.

## Tickets
| # | Owner | What | Files | Depends |
|---|---|---|---|---|
| T1 | sync-engineer | `PostHogSink`, `PostHogFence`, `configuration`, `sanitize` | `Ryft/Analytics/PostHogSink.swift` (+ `PostHogFence.swift`), doc lines in `AnalyticsSink.swift` | — |
| T2 | ios-developer | Decision B: the step, the view, the sheet removed, strings, previews | `RyftApp.swift`, `OnboardingCoordinator.swift`, `Features/Profile/AnalyticsOptIn*.swift`, `Localizable.xcstrings`, `NocturneGateSweepHostedTests.swift`, doc lines in `Analytics.swift` | — |
| T3 | test-engineer | Tests for T1 and T2 from the criteria below | `RyftTests/Analytics/*` (new suites, updates to `AnalyticsPromptTests`) | T1/T2 interfaces (this file) |
| T4 | ios-architect | ADR 0026; `CLAUDE.md` → Rules; `README.md`; `docs/APP_STORE.md` | those files | — |
| T5 | ios-lead | `PrivacyInfo.xcprivacy`, `LicensesView` entry, `CHANGELOG`, `STATUS`, licence entry for the platform | those files | — |

ADR number: 0025 is taken on another branch (`a-consent-204-…`), so this is **0026**.

## Acceptance criteria (T3 tests them)
- A1 `configurationTurnsEverythingOffButLifecycle`: every flag listed in T1 has its value.
- A2 `sanitizeDropsUnlistedEventsAndProperties`: `$screen`, `$exception`, `Application Updated` and `$identify` give
  nil. A contract event keeps only allowed keys: `$device_id`, `$locale`, `$timezone` and `url` are gone; `step` and
  `$process_person_profile` stay.
- A3 `fenceBlocksOtherHostsAndWhenClosed`: `eu-assets.i.posthog.com`, `us.i.posthog.com` and `api.ryftlab.de` are
  blocked even when open; `eu.i.posthog.com` is blocked when closed and allowed when open.
- A4 `stopDeletesQueuesEvenWithoutSetup` (a temp `root` with fake project folders): the queue folders and `optOut` are
  gone, and the anonymous id file stays. `forgetIDDeletesEverything`: `root` is gone. `startWithNewIDForgetsFirst` is
  tested through `forgetFiles` only; tests never call `PostHogSDK.with`.
- A5 `noEventBeforeTheYes`: a first run through invite, consent, about you and wear with a fake sink that can send →
  no start and no capture. After the yes, `onboarding_step health` is the first capture.
- A6 `notNowSendsNothing`: "Not now" → no start; health, tracker setup and done → no capture; the step doesn't come
  back.
- A7 `stepOrder`: the step shows only after `flowStep` is nil and before Health; never with the flag off, `analytics`
  null, demo mode or a no-op sink.
- A8 `accountsPastOnboardingAreNotPrompted`: `firstRunDone` set → no step, no sheet; the Profile toggle is still
  there.
- Existing: all 99 phase 1 analytics tests, Profile row tests and `PresentedRootTests` stay green; `make lint` passes.
- The build has zero warnings in our code.

## Risks
- **SDK internals move:** the folder names, the `close()` flush and the remote-config host are 3.98.2 facts. The exact pin
  and the ADR say that any bump re-reads them.
- **Remote config is fenced:** the SDK logs a failed fetch (only with `debug`) and may retry. No functional loss for us.
- **An in-flight batch** can land after an opt-out (it was consented).
- **Onboarding events:** `onboarding_step` for invite, consent, about you and wear stays empty on a first run by design.
