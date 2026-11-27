# Product analytics

How RYFT counts how the app is used, what it never counts, and how a feature adds an event. The original design is
`docs/work/2026-11-20-analytics/design.md` (phase 1: the seam, gate and opt-in). Phase 2, the SDK adapter, is #137 and
ADR 0026. The allow-list is in `docs/work/2026-11-27-analytics-allowlist/plan.md`.

## The rules (the user's decisions of 2026-11-16 and 2026-11-27)

1. **Opt-in, per install.** Nothing is sent, queued or kept before a yes, and nothing is on by default, in the beta
   too (TDDDG §25(1), GDPR Art. 6(1)(a)). The answer lives in `defaults` (`analytics.optIn`), never next to an account
   id. Sign-out forgets it. Opting out stops sending at once and deletes the queue.
2. **An anonymous per-install ID, nothing else.** It's random, it's deleted on opt-out and on sign-out, and it isn't
   derived from the account. No `identify`, `alias`, `group` or `register`, no hashed user id as `distinct_id`, and no
   server-side events.
3. **Interactions only.** No property says anything about health. No sleep duration, quality, N2R, recovery or strain
   bucket, and nothing read from HealthKit or derived from it (App Review 5.1.3). No food names, query strings,
   nutrient or calorie values, weights, and no email or name. Counts and durations are bucketed.
4. **Only PostHog's EU cloud**, `https://eu.i.posthog.com` (`AnalyticsDestination.allowedHost`). Another host needs a
   new build and new copy.
5. **No sending from the simulator, previews, tests, demo mode, or Debug builds** without `-RyftAnalytics`.

## How it's enforced

| layer | what it does | pinned by |
|---|---|---|
| `AnalyticsEvent` | Every event is a case with typed parameters: closed `AnalyticsToken` enums, bucket enums with total initialisers, and `Bool`. No case takes a `String`, `Int`, `Double` or `Date`, so feature code can't pass free text. | `AnalyticsEventTests.payloadsAreTokensOnly` |
| `AnalyticsCatalog` | The allow-list: every event name, its keys and each key's allowed values, in one table. It also lists the SDK's lifecycle events and `$` keys that the sink's `beforeSend` keeps. | `AnalyticsAllowListTests`: catalogue == `everyCase`, in both directions |
| `Analytics.deliver` | Before the gate, `AnalyticsCatalog.check` refuses an unknown event, an unknown, missing or deny-listed key, a value not on its key's list, and any unsafe value (email-like, longer than 40, not `^[a-z0-9_+]{1,40}$`). A refusal never reaches the sink. In Debug it asserts; the message names the event and key, never the value. | `AnalyticsAllowListTests` (the deny-list) |
| the gate | Sends only while `analytics.enabled` is on, the config has a valid destination, the user opted in, someone is signed in and demo mode is off. | `AnalyticsGateTests` |
| `AnalyticsSDKSettings.required` | The SDK settings the design allows (below). The adapter's `configuration(for:)` must produce exactly this. | `AnalyticsSDKSettingsTests` (and #137's `PostHogSinkTests` once both are in) |
| `PostHogSink` `beforeSend` (#137) | Drops any event or key the catalogue doesn't list, including whatever a later SDK adds. | #137's `PostHogSinkTests` |
| `PostHogFence` (#137) | The SDK's network gets only `POST https://eu.i.posthog.com/batch`, and only while started. | #137's `PostHogSinkTests` |

### SDK settings (posthog-ios 3.98.2, #137)

| setting | value | why |
|---|---|---|
| `sessionReplay` | off | no screen recording |
| `captureScreenViews` | off | screens are our own `screen_viewed` tokens |
| `captureElementInteractions`, `captureSwiftUIElementInteractions` (autocapture) | off | autocapture would read view labels and text |
| `rageClickConfig.enabled` | off | another autocapture |
| `surveys`, `preloadFeatureFlags`, `sendFeatureFlagEvent` | off | flags come from `GET /v1/config`; `/flags` carries `$device_id` |
| `setDefaultPersonProperties` | off | no person properties |
| `capturePushNotificationSubscriptions`, `capturePushNotificationOpened` | off | would send the APNs token |
| `errorTrackingConfig.autoCapture` | off | crash reports aren't in the policy |
| `enableSwizzling`, `debug` | off | |
| `personProfiles` | `.identifiedOnly`, and we never identify | so PostHog never creates a person profile; every event is anonymous |
| `disableGeoIp` | on | no location from the IP |
| `captureApplicationLifecycleEvents` | on | `Application Installed / Opened / Backgrounded`: the only SDK events kept |

## The events

Every value is one of the listed tokens. Bools are sent as `true` / `false`.

| event | properties | fires when |
|---|---|---|
| `onboarding_step` | `step`: invite, consent, about_you, wear, health, tracker_setup, done | an onboarding step shows (after the yes) |
| `health_access_requested` | none | the Apple Health permission sheet is asked for (not what was granted) |
| `first_sync_completed` | none | the first sync of the install finishes (no counts) |
| `screen_viewed` | `screen`: the tabs and 14 pushed screens (`AnalyticsScreen`) | a screen appears |
| `feature_used` | `feature`: train_session_started, activity_added, sleep_added, journal_saved, sleep_schedule_saved, train_import_finished, data_exported, problem_reported, notifications_allowed, full_resync | the action succeeded (only a session's start: start plus finish would give a workout's duration) |
| `error_shown` | `status`: a status bucket · `code`: the platform's error code token | an error card or inline failure shows (never its message or request id) |
| `nutrition_search_completed` | `lookup`: name, barcode · `query_length`: 1_2, 3_5, 6_10, 11_20, 21+ · `results_count`: 0, 1, 2_5, 6_10, 11_20, 21+ · `has_results` · `latency_ms`: lt_250, 250_499, 500_999, 1000_1999, 2000_4999, 5000+ | a food search or barcode lookup returns its first page (not a failure, not "Load more") |
| `nutrition_food_opened` | `rank_position`: 1 … 10, 10+ · `is_canonical_staple` (the catalogue's generic food, not branded or private) · `has_default_portion` · `has_last_used_portion` | a search result opens the food's detail |
| `nutrition_food_logged` | `entry_point`: quick_add_button, detail_sheet, barcode, suggestion, private_food · `unit_mode`: curated_portion, last_used_portion, grams, ml · `is_fractional` (e.g. ½ or 1½ portions) | the meal is saved, once per food added in that editor |
| `nutrition_diary_reopened` | `has_preserved_portion_label` | a saved meal is opened again |
| `sync_triggered` | `trigger_source`: profile_button | Profile → Sync now is tapped |
| `sync_completed` | `trigger_source`: profile_button · `status`: success, failed, skipped · `duration_ms`: lt_1000, 1000_4999, 5000_14999, 15000_59999, 60000+ | that sync ends |
| `Application Installed`, `Application Opened`, `Application Backgrounded` | the SDK's app version and build, OS name and version, device type, library version, session id | the SDK, only while started |

Checked against rule 3 on 2026-11-27: no existing event carries a health value, a name or free text. `sleep_added` and
`health_access_requested` record that something was done, not what. No existing event was changed.

## Adding an event

1. **Is it an interaction?** If any property could tell a reader something about the person's body, sleep, food or
   identity, it doesn't go in. Ask in the PR.
2. Add a case to `AnalyticsEvent` with typed parameters: a new `AnalyticsToken` enum, a bucket enum with a total `init`
   (pin every boundary in `AnalyticsBucketTests`), or a `Bool`. Never a `String` or a number.
3. Add `name`, `properties` and the new combinations to `everyCase`.
4. Add the event and its keys and values to `AnalyticsCatalog.events`. The tests fail until the catalogue and
   `everyCase` agree, and until no key is on the deny-list.
5. Track it with `env.analytics.track(.yourEvent(…))` where the action succeeds.
6. Add a row to the table above, and the same line in plain words to the privacy policy's event list (below).
7. Run `AnalyticsEventTests`, `AnalyticsAllowListTests` and `AnalyticsBucketTests`. The privacy reviewer looks at
   every new event.

## For the privacy policy (legal PR #252)

Proposed text for the policy's "Usage analytics" section, matching what the app does. It's English, as is the rest of
the policy.

> **Usage analytics (only if you say yes).** If you agree, RYFT sends anonymous usage events to PostHog, a product
> analytics service run by PostHog Inc. We use only its EU cloud (eu.i.posthog.com), so the data is processed in the
> EU. We use these events to see which parts of the app people use and where they get stuck, so we can improve RYFT.
> Nothing is sent until you agree. The legal basis is your consent (Art. 6(1)(a) GDPR, § 25(1) TDDDG). You can
> withdraw it at any time in Profile → Privacy → Share usage data. Sending stops at once, and events not yet sent are
> deleted on your phone.
>
> **What is sent.** A random ID that RYFT creates for this installation. It isn't your account, email, name or Apple
> ID, and it's deleted when you turn analytics off or sign out (you get a new one if you turn it on again). With it:
> which onboarding step and which screen you opened; which features you used (for example that you saved a journal
> entry or started a training session); that an error was shown, by its type (for example "offline" or "500"); for
> food logging, whether a search found anything, rough ranges for how long the search was and how many results it
> had, how high up the result you chose was, and whether you added a food by quick add, the detail page or a barcode,
> and in portions, grams or millilitres; for Profile → Sync now, that you tapped it and whether it worked, with a rough
> duration; and when the app was installed, opened or closed, with the app version, iOS version and device type
> (phone or tablet).
>
> **What is never sent.** Your health data, or anything read from Apple Health or calculated from it (sleep, heart
> rate, HRV, recovery, strain, weight, scores). What you type or search for, food names, amounts, calories or
> nutrients. Your name, email or account ID. Screen recordings or taps. We don't use the events to identify you, we
> don't link them to your account, we don't use them for advertising, and we don't share them with anyone else.
>
> **Retention.** PostHog keeps the events for [**retention period — to be filled in from the PostHog project
> settings**] and then deletes them. PostHog processes them on our behalf under a data processing agreement.

Facts the policy states that the code doesn't settle (for the user, with #252):
- The retention period set in the PostHog project.
- That the data processing agreement with PostHog is signed.
- That "Discard client IP data" is on in the PostHog project. The app disables GeoIP, but the server still sees the
  connection's IP. If that setting is off, the policy must say PostHog receives the IP address.
