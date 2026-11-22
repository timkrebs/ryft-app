# 0026 — Opt-in analytics: posthog-ios, pinned, behind a seam

- Status: proposed (2026-11-22, T4 of `docs/work/2026-11-22-analytics-sdk/`)
- Deciders: Tim Krebs; recorded by ios-architect
- Applies to: `Ryft/Analytics/` (`Analytics`, `AnalyticsEvent`, `AnalyticsSink`, `PostHogSink`, `PostHogFence`),
  the package list, `PrivacyInfo.xcprivacy`, `docs/APP_STORE.md`, `.github/dependabot.yml`, `CLAUDE.md` → Rules

## Context

- Platform D231 (`API.md` → `GET /v1/config` → `analytics`, flag `analytics.enabled`) gives the app a PostHog
  destination for product analytics. Until now the rule was one dependency (`supabase-swift`) and no analytics, crash
  or tracking SDK.
- The user's decisions of 2026-11-16: opt-in, pseudonymous, a closed event list, a no-op seam first, posthog-ios in
  phase 2. Of 2026-11-20: EU only (`eu.i.posthog.com`, nothing else), and **decision B**: the opt-in is its own
  onboarding step, after wear and before Apple Health, with two equal buttons.
- Phase 1 (#130, `docs/work/2026-11-20-analytics/`) built the owner (`Analytics`), the gate, the token-only events and
  the `AnalyticsSink` seam, and shipped without the SDK. Its privacy review set what phase 2 must do: drop the whole
  queue on stop, delete the id on opt-out and sign-out, send lifecycle events only while started, sanitize properties,
  keep the files at complete-until-first-unlock or better.
- The pinned SDK, read from the 3.98.2 checkout (plan.md → "What the pinned SDK does"), collects more by default than
  the contract allows, fetches a remote config at setup with no switch to stop it, flushes on `close()`, and keeps
  `$device_id` across `reset()`.

## Decision

1. **The app's second dependency is posthog-ios, exact version 3.98.2**, product `PostHog`, linked into the `Ryft` app
   target only: never `RyftWidgetsExtension`, a notification service extension or the test targets' own link phases.
   The pbxproj requirement is `exactVersion`; `Package.resolved` pins revision `a4deb72`.
2. **The SDK lives behind `AnalyticsSink` and nowhere else.** Only `Ryft/Analytics/PostHogSink.swift` (and
   `PostHogFence.swift`) import `PostHog`, entirely inside `#if canImport(PostHog)`. It uses an instance
   (`PostHogSDK.with(config)`), never `PostHogSDK.shared`. Call sites see `Analytics.track(AnalyticsEvent)` only, and
   every event carries only `AnalyticsToken`s: no free text, number, date, health value or account id can be sent.
3. **The gate opens only when all of these hold:** `analytics.enabled` on in the newest config, a valid `analytics`
   destination (host exactly `eu.i.posthog.com`, a `phc_` key), the user opted in, someone signed in, demo data off.
   Any one turning false stops the sink at once. An event while it's closed is dropped, never buffered.
4. **No SDK code runs before the gate opens.** The 3.98.2 SDK has no `+load`, constructor or module initialiser, and
   `import PostHog` runs nothing; `PostHogSink.init` does no SDK work. `PostHogSDK.with` is called only from `start`,
   which `Analytics.reevaluate` calls only with the gate open.
5. **Where the real sink exists.** `AnalyticsSinks.live()` returns the no-op in the simulator, in Debug device builds
   unless launched with `-RyftAnalytics`, and whenever the package is missing. Only Release device builds get
   `PostHogSink` unconditionally. Previews and tests never call `live()`; they keep the no-op or a
   `FakeAnalyticsSink`.
6. **Everything off but lifecycle** (`PostHogSink.configuration(for:)`, pure and unit-tested): screen views, element
   and SwiftUI interactions, rage clicks, session replay, surveys, feature-flag preload and the flag-called event,
   default person properties, push-token registration and push-open capture, error-tracking autocapture (so the
   vendored PLCrashReporter is never started), swizzling and debug are all false. `captureApplicationLifecycleEvents`
   is true, `personProfiles = .identifiedOnly`, `disableGeoIp = true`, `flushAt = 10`, `maxQueueSize = 200`, and the
   URL session configuration is `.ephemeral`.
7. **An allow-list, not a deny-list** (`PostHogSink.sanitize`, the SDK's `beforeSend`, pure and unit-tested). Events:
   `AnalyticsEvent`'s names plus `Application Installed`, `Application Opened` and `Application Backgrounded`; anything
   else is dropped. Properties: ours (`step`, `screen`, `feature`, `status`, `code`), a reviewed set of the SDK's
   (`$app_version`, `$app_build`, `$os_name`, `$os_version`, `$device_type`, `$lib`, `$lib_version`, `$session_id`,
   `$process_person_profile`, `$geoip_disable`) and the lifecycle ones (`version`, `build`, `previous_version`,
   `previous_build`, `from_background`). Every other key is removed, `$device_id`, `$device_name`, `$locale` and
   `$timezone` included. A key a later SDK version adds is dropped until someone reviews it.
8. **The URLProtocol fence.** `PostHogFence` sits first in the SDK's `protocolClasses`, and every SDK request goes
   through that one session. It refuses every request unless the fence is open **and** the host is exactly
   `eu.i.posthog.com`. It's open only between `start` and `stop`. So the remote-config `GET` to
   `eu-assets.i.posthog.com` at setup is refused, and nothing the SDK does after `stop` leaves the phone.
9. **Our own deletion, because the SDK's isn't enough.** `close()` flushes a batch first and keeps the rest on disk;
   `reset()` keeps `$device_id`. So `stop()` closes the fence, deletes the queue, replay, logs and opt-out files under
   `Application Support/<bundle id>/<project key>/` (also when the SDK wasn't set up in this process), and only then
   calls `close()`. `forgetID()` and `start(newID: true)` delete the whole folder, id included.
10. **No identify, ever.** No `identify`, `alias`, `group` or `register`. With `identifiedOnly` every event is
    anonymous: a random per-install id that the next opt-out or sign-out deletes.

## Consequences

- **Any version bump is a review, not a merge.** Before a new posthog-ios version lands, someone re-reads these
  3.98.2 facts in the new checkout and updates `PostHogSink`, `PostHogFence` and their tests where they moved:
  1. no code at launch: no `+load`, constructor or eager static; PLCrashReporter's `+initialize` only with crash
     autocapture;
  2. the network at setup: only the remote-config `GET` (host and path), and `/flags` only with `preloadFeatureFlags`;
  3. every request goes through the one session built from `config.urlSessionConfiguration`;
  4. the config's property names, and which of them default to true;
  5. `close()` flushes and keeps files; `reset()` keeps `$device_id`;
  6. the storage path and the file and folder names `stop()` deletes; the write options (data protection) and the
     backup exclusion;
  7. `beforeSend` sees every event, `$`-events and lifecycle included, and nil drops it;
  8. the lifecycle event names and the default property keys;
  9. the privacy manifests: data types, required-reason APIs, `NSPrivacyTracking`, tracking domains.
- **Dependabot never bumps it.** `.github/dependabot.yml` ignores `posthog-ios`; a bump is a hand-made PR that cites
  this list.
- **The PostHog project is the user's to configure:** "Discard client IP data" on, GeoIP off, the retention period.
  The app sets `disableGeoIp` and sends no IP property, but the address on the connection is PostHog's to discard.
- **An in-flight batch can't be recalled.** A request already on the wire when the fence closes may land after an
  opt-out. It was captured while the user was opted in.
- **The kill switch is as fast as the config refresh**: launch, app active when due, `ttl_sec` (6 h).
- **Counts are per opt-in, not per person.** Every new id (opt-out, sign-out, opting in again) is a new anonymous
  user. `Application Installed` fires once per install, not per id: the SDK keeps the last version and build in
  `UserDefaults.standard` (`PHGVersionKey`, `PHGBuildKeyV2`), which our file deletion doesn't touch (no id in them).
  A new id after that starts with `Application Opened`; `Application Updated` is dropped by the allow-list.
- **App Store answers change** (`docs/APP_STORE.md`): Product Interaction and Other Usage Data, not linked, not used
  for tracking, purpose Analytics. Still no tracking, no ATT, no tracking domains. The binary contains a crash
  reporter that is never turned on, and its manifest shows up in Xcode's privacy report.
- **Tests never set up the SDK.** They test `configuration`, `sanitize`, `PostHogFence.blocks` and the file deletion
  against a temp root, plus the gate and the onboarding step with a fake sink.

## Alternatives considered

- **No SDK: our own sender to PostHog's `/batch`.** About a hundred lines on `URLSession`: our event JSON, a small
  queue, `flushAt`, a retry. For: nothing to fence, no remote config, no vendored crash reporter or swizzling code in
  the binary, no third-party manifest, no version facts to re-read, no second dependency. Against: we own batching,
  retry, the session id and the lifecycle events, and we track PostHog's ingestion contract ourselves. The user chose
  the SDK on 2026-11-16, and the fence and the allow-list make it hold the contract. **This stays the fallback**: if a
  bump breaks a fact above that can't be fenced, or review objects to what the SDK puts in the binary, a sender
  replaces `PostHogSink` behind the same seam and no call site changes.
- **`PostHogSDK.shared`.** Shorter, but a new global in new code, against the seams rule (`ARCHITECTURE.md` §1).
  Changing destination becomes reconfiguring a live singleton instead of close-and-recreate, and nothing stops a
  second caller from reaching it around `Analytics`.
