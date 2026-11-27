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
| `PostHogSink` `beforeSend` (#137) | Drops any event or key the catalogue doesn't list, including whatever a later SDK adds. At integration it must run `AnalyticsCatalog.check` for our events (key, value and event together, not a flat key list), and keep only `sdkPropertyKeys` on `sdkEventNames`. | #137's `PostHogSinkTests` |
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
| `personProfiles` | `.never` (and we never identify) | no person profile is ever created, even after a stray `identify`. `PostHogSink.configuration(for:)` sets it and asserts `AnalyticsSDKSettings(config) == .required` |
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
| `nutrition_search_completed` | `lookup`: name, barcode · `query_length`: 1_2, 3_5, 6_10, 11_20, 21+ · `results_count`: 0, 1, 2_5, 6_10, 11_20, 21+ · `has_results` · `latency_ms`: lt_250, 250_499, 500_999, 1000_1999, 2000_4999, 5000+ | a food search or barcode lookup returns its first page: once per search, not again when the page reappears, not for a failure or "Load more". Pages and barcode results hold at most 20, so `11_20` includes a full page |
| `nutrition_food_opened` | `rank_position`: 1 … 10, 10+ · `is_canonical_staple` (the catalogue's generic food, not branded or private) · `has_default_portion` · `has_last_used_portion` | a search result opens the food's detail |
| `nutrition_food_logged` | `entry_point`: quick_add_button, detail_sheet, barcode, suggestion, private_food · `unit_mode`: curated_portion, last_used_portion, grams, ml · `is_fractional` (e.g. ½ or 1½ portions) | the meal is saved: one event per **distinct** combination among the foods added in that editor, so three quick-added gram foods send one event. The number of foods in a meal is never sent (a per-food event with timestamps would add up to a meal log) |
| `nutrition_diary_reopened` | `has_preserved_portion_label` | a saved meal is opened again |
| `sync_triggered` | `trigger_source`: profile_button | Profile → Sync now is tapped |
| `sync_completed` | `trigger_source`: profile_button · `status`: success, failed, skipped (nothing started: offline or no data source), deferred (Apple Health locked) · `duration_ms`: lt_1000, 1000_4999, 5000_14999, 15000_59999, 60000+ | the sync run ends. `status` is the run's outcome; `duration_ms` runs from the tap to the end of the spinner phase the person waits for, not the platform's scoring afterwards |
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

> **Usage analytics (only if you say yes).** If you agree, RYFT sends pseudonymous usage events to PostHog, a product
> analytics service run by PostHog Inc., which processes them on our behalf under a data processing agreement. The
> controller is the one named in [section "Who is responsible"]. We use these events to see which parts of the app
> people use and where they get stuck, so we can improve RYFT. We don't use them for advertising, and we don't link
> them to your account.
>
> **Your consent.** Nothing is sent or stored for analytics until you agree. The legal basis is your consent
> (Art. 6(1)(a) GDPR; for storing and reading the ID on your phone, § 25(1) TDDDG). You can withdraw it at any time in
> Profile → Privacy → Share usage analytics. Sending stops at once, and events not yet sent are deleted from your
> phone. Withdrawing doesn't affect the lawfulness of what was sent before.
>
> **What is sent.** A random ID that RYFT creates for this installation. It isn't your account, email, name or Apple
> ID. It's deleted when you turn analytics off or sign out, and you get a new one if you turn analytics on again.
> With it, these events:
> - which onboarding step you're on, which screen you opened, and that you asked to connect Apple Health (not what you
>   allowed);
> - that the first sync finished;
> - which features you used, for example that you saved a journal entry or started a training session;
> - that an error was shown, by its type (for example "offline" or "500");
> - for food logging: whether a search found anything, a range for how many characters it had, how many results it had
>   and how long the results took; how high up the list the food you opened was, whether it's a generic or a branded
>   food, and whether it had a default or last-used portion; when you save a meal, how you added its foods (quick add,
>   the food's page, a barcode, a suggestion or a private food), whether in portions (catalogue or last-used), grams or
>   millilitres, and whether a portion count was fractional, but not how many foods; and that you reopened a saved meal;
> - for Profile → Sync now: that you tapped it, whether it worked, and a range for how long it took;
> - when the app was installed, opened or closed, with the app version and build, iOS version, device type, the
>   analytics library's version and a session ID.
>
> **What is never sent.** Your health data, or anything read from Apple Health or calculated from it (sleep, heart
> rate, HRV, recovery, strain, weight, scores). What you type or search for, food names, amounts, calories or
> nutrients. Your name, email or account ID. No screen recordings, and nothing about your taps beyond the events listed
> here. We don't share the events with anyone besides PostHog and its sub-processors.
>
> **Where.** The events are stored on PostHog's servers in the EU (eu.i.posthog.com). PostHog Inc. is a US company.
> Where it accesses the data from the US, this is covered by [**the EU-US Data Privacy Framework / Standard Contractual
> Clauses in the DPA — whichever applies**]. When the app connects, PostHog receives your IP address. We have set
> PostHog to discard it and not to derive a location from it.
>
> **Retention.** Until they are sent, up to 200 events wait on your phone. PostHog keeps the events for [**retention
> period, from the PostHog project settings**] and then deletes them.
>
> **Your rights.** You have the rights to access, erasure, restriction and objection, as set out in [section "Your
> rights"]. Because the ID is random and not linked to your account, we can only find your events if you give us the
> ID while it still exists. Once it's deleted (on opt-out or sign-out), we can no longer tell which events were yours
> (Art. 11 GDPR).

Facts the policy states that the code doesn't settle (for the user, with #252):
- The retention period set in the PostHog project.
- That the data processing agreement with PostHog is signed, and whether the transfer basis is the DPF or SCCs.
- That "Discard client IP data" is on in the PostHog project. The app disables GeoIP, but the server still sees the
  connection's IP. If that setting is off, drop the sentence "We have set PostHog to discard it…" and say PostHog
  stores the IP address.
- Whether legal wants the consent to cite Art. 9(2)(a) GDPR as well: the food events say how and when a meal was
  logged, never what was in it.
- The ID can't be shown in the app today, so "if you give us the ID" is only theoretical. Either add a "Copy analytics
  ID" row later, or simplify that sentence to the Art. 11 statement.
