# The first run against five rules: audit (F1)

Ticket F1 of `plan.md`. Docs only: nothing here changes Swift or the string catalog. Written from the code on
`origin/main` at `d09c8b2`, plus open PR #137 (counted as "pending, #137").

**The reference** is six screenshots of another app's first run, kept outside this repo because they show its owner's own
data. It is used for **structure only**. Nothing of its text, layout, assets, product name or vocabulary is copied or quoted
below; each reference screen is named by its job:

| Ref | Job |
| --- | --- |
| R-1 | A wearable picker: one list, one tap per device, a "no device" row last. |
| R-2 | A data card before a vendor login: two short privacy points, one button. |
| R-3 | History sync: a question, a progress readout with a percentage, a spinner on the button, a skip. |
| R-4 | A notification primer: a lock-screen mock with one example notification, Continue, a skip, all before the system prompt. |
| R-5 | A location primer, same structure as R-4, with a map example. |
| R-6 | Home while the first sync runs: the sync status as a pill at the top, empty gauges with a dash, skeleton cards, the tab bar live. |

## The five rules (from `plan.md`)

1. One decision per screen.
2. A primer with a concrete example before every system prompt (Apple Health, notifications).
3. Everything except consent can be skipped, and the skip is visible.
4. The app is usable while the first sync runs.
5. The user always knows how far along they are.

Scores: **met**, **partly**, **not**, or **n/a** where the rule doesn't apply to that screen.

---

## 1. Screen by screen

The order is the order a new account sees (`RootView.content`: splash → `OnboardingFlowView` steps in
`OnboardingCoordinator.missing` order → Apple Health → tracker setup → tabs). Which screens appear depends on the account
(invite only while the platform's gate applies; wear and tracker setup only while the remote flag `devices.setup` is on, and
tracker setup only for a tracker that needs its own app). Shots are in `shots/` (§4); "code" means no shot: #137's step is not on `main`.

| # | RYFT screen | Reference screen with the same job | R1 one decision | R2 primer + example | R3 skip visible | R4 usable during sync | R5 progress known | Shot |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | **Welcome** (Sign in with Apple, Create account, Log in) | none (the reference begins at its picker) | met: which way in | n/a | n/a | n/a | n/a | `00-welcome-dark.png` |
| 0a | **Splash**, the first run waiting for `GET /v1/me` etc. (up to `checkTimeout`, 10 s) | none | n/a | n/a | n/a | not: nothing to use for up to 10 s, by design (no flash of tabs) | partly: a caption "Checking your account…" after 3 s, no count | `01-splash-waiting-dark.png` |
| 0b | **Account hint** sheet ("This is a new RYFT account"), only when another provider already has this person's data | none | met: keep or use the other account | n/a | partly: a swipe is "keep", not labelled | n/a | not | `02-account-hint-dark.png` |
| 1 | **Invite code** (while the beta gate applies) | none | met: one field, one button; the wrong-account exit sits under a rule | n/a | partly: "Not now" only while the gate is a warning; an enforced gate can't be skipped, which is correct | n/a | not: no "step n of m" | `03-invite-dark.png` |
| 2 | **Consent** ("Your health data, your consent") | R-2: facts about the data before connecting a source | met: one decision (agree), though dense: four points, age line, policy link, checkbox, button | n/a (no system prompt) | met: "Not now", and the caption says nothing syncs until agreed | n/a | not | `04-consent-dark.png` |
| 3 | **About you** (birth year; then the estimate rows) | none | met: one question; after saving, Continue only | n/a | met: Skip (gone after a save, where Continue is the only way on) | n/a | not | `05-about-you-dark.png`, `05b-about-you-saved-dark.png` |
| 4 | **What do you wear?** (`devices.setup`) | R-1: the wearable picker | met: one question, multi-select; "Just my iPhone" is exclusive. R-1 is one tap per device; RYFT needs a pick and Continue, which a multi-select justifies | n/a | met: Skip | n/a | not | `06-wear-dark.png` |
| 5 | **Share usage analytics?** (pending #137: new step between wear and Apple Health) | none | met: two equal outline pills, nothing preselected | n/a (no system prompt) | met: "Not now" is an answer and the step never returns | n/a | not: and the step adds to the count an indicator must show | code (not on `main`) |
| 6 | **Connect Apple Health** (`HealthPermissionView`) | R-2 for the explaining card; R-4 for "primer before the system prompt" | met: one decision | partly: three points (what is read, where it goes, you decide) and a policy link, but no concrete example of what the system sheet will show and no instruction to turn every category on | **not**: "Not now" is visible but does not skip. It sets `healthIntroDone` (`HealthPermissionView.swift:35`), which is part of `BootstrapKey` (`RyftApp.swift:308`), so `bootstrap()` runs again, passes its `healthIntroDone` guard and calls `env.health.requestAuthorization()` (`RyftApp.swift:436`): the iOS Health sheet appears right after "Not now", with no primer in front of it | n/a | not | `07-apple-health-dark.png` (the page's end: Continue and Not now pinned) |
| 6a | *System sheet: Health access.* Shown after Continue, and also after "Not now" (see 6) | the system's, not a screen of either app | n/a | n/a | n/a | n/a | n/a | n/a |
| 7 | **Notifications primer** | R-4: lock-screen mock, one example, Continue, skip | none: RYFT has **no first-run screen** for it | not: see 10 | n/a | n/a | n/a | n/a |
| 8 | **Set up your tracker(s)** (a tracker with its own app, e.g. Garmin; never Apple Watch or iPhone) | R-2 as the connect step for a vendor; R-3 for "sync now" | partly: cards (first open), "Check sync", Done and "Show me again later" on one screen | n/a | met: Done, or "Show me again later"; nothing is mandatory | partly: the sync already runs, but the screen doesn't say so | not | `08-tracker-setup-dark.png` |
| 9 | **History sync** (the 90-day backfill) | R-3: a history question with a percentage and a skip | none as a screen: RYFT starts the backfill after consent, with no question. Not a gap: it is background work, and R4 holds | n/a | n/a (nothing to skip) | met | met: see 10 | n/a |
| 10 | **Today during the first sync** (`ImportCard`, status line, push question inside the card) | R-6: home while syncing | partly: one card, but it also holds the push question ("Tell me when my first scores are ready", Allow / Not now) | partly: that question is one sentence and no example, shown only while `push.enabled`, and asks the system straight after Allow | met: "Not now" | met: tabs live, "You can leave the app", the status line says what is moving | met: Reading Apple Health > Uploading > Scoring (read as "Step n of 3"), counts of nights, readings, workouts, "Imported through 14 Sep · 61 of 90 days", **no percentage** | `09-today-first-import-dark.png` |
| 10a | Today with the night waiting to be scored (the hero gauge dimmed, "Scoring your night…") | R-6 (its empty gauges) | met | n/a | n/a | met | met: "Usually ready within 20 s" | `09b-today-pending-night-dark.png` |
| 10b | Today calibrating (the outer orbit fills night by night) | R-6 | met | n/a | n/a | met | met | `09c-today-calibrating-dark.png` |
| 11 | **Location primer** | R-5 | n/a | n/a | n/a | n/a | n/a | n/a |

**Row 11 is deliberate.** RYFT asks for no location permission, reads no location from Apple Health and has no map. No screen
is proposed.

**Row 7 and the push question.** Notifications are asked today in two places, both on Today and behind `push.enabled`: inside
the first import's card, and, after the first sync, as `PushPrePromptCard` ("Get your recovery each morning"; "Not now" is
remembered, asked once more after 14 days). Both are one sentence and an Allow button. Neither shows an example of what arrives.

**Where R5 stands.** Rule 5 is met only on Today (the import card). Every screen before Today (rows 1 to 8) scores **not**:
there is no "step n of m" or any other sign of how many screens remain, and the number varies by account (3 to 8).

---

## 2. Taps and screens from sign-in to Today

**What counts.** A tap is one finger tap on a control in RYFT. Typing and scrolling are not taps. Taps in system sheets are
counted separately, as "system". The "shortest honest path" accepts consent and answers each question as a person with that
device would (picks the device, grants Health access); the shortcut of skipping questions is listed at the end of each path.
The count is from the code, not from tapping through a build (the shots are of single screens). "Screens" counts RYFT's full screens including Today; the splash and system sheets
are not counted.

Assumptions: a new account, signing in with Apple, `devices.setup` **on** (the designed path, and the one the plan's tickets
assume; the compiled default is off and the repo can't say what the server serves today), the beta invite gate **on** (as
`docs/TESTFLIGHT.md` describes), and #137 **not** merged. Adjustments are below the paths.

### Apple Watch

| Tap | Screen | Control | Skippable? |
| --- | --- | --- | --- |
| 1 | Welcome | Sign in with Apple (then system: confirm, about 1 system tap) | no |
| 2 | Invite code | Paste (or type the code: no tap) | no, while the gate is enforced |
| 3 | Invite code | Continue | no |
| 4 | Consent | tick the checkbox | no, but "Not now" defers it (nothing syncs) |
| 5 | Consent | Agree and continue | |
| 6 | About you | Skip (the honest alternative: scroll the wheel, Continue, Continue = 2 taps) | yes |
| 7 | What do you wear? | Apple Watch tile | yes (Skip) |
| 8 | What do you wear? | Continue | |
| 9 | Connect Apple Health | Continue (then system: Turn On All, Allow = 2 system taps) | "Not now" is shown, but the system sheet appears after it anyway (gap 1) |
| | Tracker setup | not shown: Apple Watch needs no setup (`integration: apple_builtin`) | |
| | **Today** | the import card; first sync running | |

**9 taps + 3 system taps; 7 screens (6 before Today).**
Shortcut (consent deferred, everything skipped): taps 1, 2, 3, "Not now", Skip, Skip, "Not now" = **7 taps**, **plus the
system Health sheet, which appears anyway** (gap 1) and must still be answered (1 to 2 system taps; "Don't Allow" is the one
that matches what the user chose). Nothing uploads: Today shows "Action needed" and the empty state. Corrected from the first
version of this audit, which counted no sheet.

### Garmin

Taps 1 to 9 are the same as Apple Watch (tap 7 is the Garmin tile), then:

| Tap | Screen | Control | Skippable? |
| --- | --- | --- | --- |
| 10 | Set up your tracker | Done (optional: open the card's steps; "Check sync" = +1) | yes ("Show me again later" = also 1 tap) |
| | **Today** | the import card; first sync running | |

**10 taps + 3 system taps; 8 screens (7 before Today).** Same shortcut as above, plus "Show me again later".

### No device

| Tap | Screen | Control | Skippable? |
| --- | --- | --- | --- |
| 1 to 5 | Welcome, Invite, Consent | as above | |
| 6 | About you | Skip | yes |
| 7 | What do you wear? | Skip (the honest alternative: "Just my iPhone" + Continue = 2 taps, 9 in total) | yes |
| 8 | Connect Apple Health | Continue (then system: Turn On All, Allow) | "Not now" still brings up the system sheet (gap 1) |
| | Tracker setup | not shown: Skip answers nothing, and "Just my iPhone" is `apple_builtin` | |
| | **Today** | the import card, then the "No Health data yet" hint if nothing arrives | |

**8 taps + 3 system taps (9 with "Just my iPhone"); 7 screens (6 before Today).**

### Adjustments

| Change | Apple Watch | Garmin | No device |
| --- | --- | --- | --- |
| Shortest honest path, as above | 9 taps, 7 screens | 10 taps, 8 screens | 8 taps, 7 screens |
| #137 merged (analytics step, "Not now" = 1 tap) | 10, 8 | 11, 9 | 9, 8 |
| Invite gate off (no invite screen: 2 taps fewer) | 7, 6 | 8, 7 | 6, 6 |
| `devices.setup` off (no wear and no setup screens) | 7, 6 | 7, 6 | 7, 6 |

With `devices.setup` off every path is the same 7 taps, and a Garmin account is told nothing about turning on its app's write
access to Apple Health until Today's "No Health data yet" hint.

---

## 3. Gaps, ranked by effect on reaching Today (and on what Today then shows)

Size: **S** up to 3 h, **M** 4 to 8 h, **L** over 8 h. Hours are for the design spec, the SwiftUI, previews (dark, AX3) and
tests, not review. Fixes stay inside `Design/`, Nocturne, dark only, existing tokens; every new string goes through the
localization editor's catalog edit (ticket L).

The brief's four known gaps are all real, but not equally large. **Corrections**: Today during the first sync (gap 5) is mostly
met already; analytics per step (gap 7) is half there (the event for "shown" exists). **Added by this audit**: gaps 1, 2, 6 and 8.

| Rank | Gap | Rule | User-visible effect | Fix inside RYFT's design system | Size |
| --- | --- | --- | --- | --- | --- |
| 1 | **New, found on review.** "Not now" on Connect Apple Health doesn't skip: it still shows the iOS Health sheet, with no primer in front of it | R3, R2 | The person said no and gets the system prompt anyway. A refusal here is final in practice (iOS asks once), so the first-run's best moment to ask well is spent. Cause: the screen's "denied" end sets `healthIntroDone` (`HealthPermissionView.swift:35`), a part of `BootstrapKey` (`RyftApp.swift:308`); `bootstrap()` reruns, passes its guard and calls `requestAuthorization()` (`RyftApp.swift:436`) | `bootstrap()` asks only after Continue, or when access is already determined. A declined intro records "declined" and never prompts until the user asks from Today or Profile. Owner: sync-engineer (not a `Design/` change) | S, 2 to 3 h |
| 2 | **New.** The Apple Health primer doesn't say what to tap on the system sheet or show what it will list | R2 | A person who allows only some categories (or none) reaches Today with partial or no data, and HealthKit never says which were refused. The recovery path exists (`HealthAccessHint`: "Tap Turn On All") but only after the data failed to arrive | Add one point to the primer card: what the next sheet looks like and "Turn On All" (an `OnboardingPoint`, no new component). Coordinate with H2/H3, which rewrite this screen's groups | S, 2 h |
| 3 | **Confirmed.** No step indicator on any first-run screen | R5 | 6 to 8 screens with no sign of how many are left; the wait can feel endless, and a Garmin account sees one more screen than an Apple Watch account | One quiet indicator in the lock-up row of `OnboardingScreen` (hairline segments in `textTertiary`, the current one in `textPrimary`, no teal, no Volt): "Step n of m", read by VoiceOver. It counts only the steps this account will see (invite gate, `missing`, `devices.setup`, the tracker pick, #137's step) and is absent in the sheet presentation (F3) | M, 6 h |
| 4 | **Confirmed.** No notification primer in the first run | R2 | The first ask is a one-line card on Today, with no example, and only while `push.enabled` is on. People decide without knowing what they'd get | One shared primer component: a lock-screen mock with RYFT's morning notification (the lock-screen rule of `2026-11-22-notifications` §1.3 and §5: no health value in the title; the example's title is the placeholder's "Your morning score is ready", never the score), Continue → system prompt, "Not now" → on, never calling `requestAuthorization`. Shown after Apple Health; the Today card stays as the second chance (F2) | M, 8 h |
| 5 | **Corrected.** Today during the first sync: mostly met | R4, R5 (met); R1, R2 (partly) | Tabs are usable, the card shows real counts and the three steps, with no percentage: this is better than the reference's percentage readout, which RYFT's honesty principle rules out. What reads as unfinished: the push question sits inside the progress card (a second decision, rule 1), and the hero slot is a card where the gauge will be, so the first score arrives as a layout swap (already cross-faded in 250 ms) | Take the push question out of `ImportCard` once the primer (gap 4) exists. Optional: a quiet outline orbit under the card (existing `OrbitGauge` empty mode, "pending is an outline") so the gauge's place is held. Keep the chips, the counts and the "no percentage" rule (F4) | M, 6 h |
| 6 | **New.** The tracker setup screen carries three kinds of decision | R1, R4 | A Garmin user lands on cards, Check sync, Done and "Show me again later" at once, and isn't told that the first sync is already running | Make "Done" the one pill, "Check sync" a text action inside the open card, say "Your first sync is already running" in the lead | S, 3 h |
| 7 | **Corrected.** Analytics per step: `onboarding_step` exists (shown only) | supports R5 | No effect on users; the team can't see where people stop or skip. `health_access_requested` and `first_sync_completed` exist; there is no continue, skip or permission result | Add step results (continued, skipped, permission granted or refused as the app can know it) as enum-only events; no health value, no tracker name; allow-list test; only while `analytics.enabled`. #137's own step must be counted (F5) | M, 5 h |
| 8 | **New.** The first-run splash gives no feedback for the first 3 s and no count after | R5 | A slow network leaves a bare mark for up to 10 s | Show the caption at 1.5 s on the first run only (`SplashSpec.captionDelay` is one constant) and keep it a sentence, not a spinner | S, 1 h |

**Observations, not ranked** (not verified by running the app):
- With consent deferred ("Not now"), the flow still continues to About you, the picker and Apple Health. Can an upload happen
  before consent? By code, no: `deferred` only hides the consent screen, `missing(_:)` still lists `.consent`, so
  `gate(_:path:write:)` returns `.gate(.consentRequired)` (also when the account or a fresh policy is unknown) for every path;
  `ScreenModels` wires that gate into `SyncService`, `ActivityUploader`, `TrainSyncService` and the import uploader (ADR 0008,
  fail closed). Not tested by running; for the security reviewer, who should also check that HealthKit is only *read*, with
  the anchor not advanced, while the gate holds.
- Six screens stand before Today (seven with #137). About you and #137's analytics step don't block the first sync; moving them
  behind Today would be shorter but changes what the first scores are computed with (max heart rate). A product call, not a
  fix, and it belongs with #137's decision B.

---

## 4. Screenshots

Folder: `shots/` (PNG, dark, RYFT only, synthetic data: the mock "Alex Doe" account, nothing real). Taken on 2026-11-23 from
this branch's build (the Nocturne UI), on a private simulator (iPhone 16 Pro, iOS 27.2) made for this audit and deleted at
the end. The earlier copies from `docs/screenshots/` were replaced. Files are as captured (3x, 100 to 500 KB each; no existing
make target downsizes them).

| File | How | Screen |
| --- | --- | --- |
| `00-welcome-dark.png` | `SignedOutOnboardingShotsTests` (`a-01-welcome`) | Welcome |
| `01-splash-waiting-dark.png` | same (`a-15-splash-waiting`) | Splash after its 3 s caption |
| `02-account-hint-dark.png` | same (`a-14-account-hint`) | Account hint sheet |
| `03-invite-dark.png` | same (`a-08-invite`) | Invite code |
| `04-consent-dark.png` | same (`a-09-consent`) | Consent, the whole page |
| `05-about-you-dark.png` | app launch `-RyftScreen aboutYou`, `simctl io screenshot` | About you, the birth-year wheel |
| `05b-about-you-saved-dark.png` | `-RyftScreen aboutYouSaved` | About you after saving |
| `06-wear-dark.png` | `-RyftScreen wear` | What do you wear?, nothing picked (Continue off) |
| `07-apple-health-dark.png` | test (`a-11-apple-health`, the page's end) | Connect Apple Health, with Continue and Not now |
| `08-tracker-setup-dark.png` | `-RyftScreen tracker-setup -RyftTrackers garmin` | Set up your tracker (Garmin) |
| `09-today-first-import-dark.png` | `-RyftTab today -RyftScenario import` | Today during the first import |
| `09b-today-pending-night-dark.png` | `-RyftScenario pending` | Today, the night being scored |
| `09c-today-calibrating-dark.png` | `-RyftScenario calibrating` | Today, calibrating |

Notes. The test shots are stitched whole pages; where a page pins its actions, the stitch repeats the bar, which is why the
Apple Health shot is the page's end and the wear, About you and tracker-setup shots are real single windows from the app.
The analytics step of #137 is not on `main`, so it has no shot. The system sheets (Health access, notifications) are the
system's and are not captured. The first simulator named in the ticket (iPhone 17 Pro, 128EA51D-…) has no data on disk and
was left alone; `xcrun simctl erase` of it was refused by the permission system.

## 5. Sources read

`OnboardingCoordinator` (`Step`, `missing`, `canDefer`, `later`, the wear and tracker-setup extension), `OnboardingSteps`,
`OnboardingTrackerSteps`, `TrackerPickerGrid`, `HealthPermissionView`, `HealthAccessHint`, `RootView` in `RyftApp.swift`
(the order of screens, `analyticsStep`), `SplashView`, `WelcomeView`, `ImportCard` and `ImportRow` in `TodayView`,
`TodayViewModel` (`ImportProgress`, `showsImportPushPrompt`), `PushRegistrar` and `PushPrePromptCard`, `Content/trackers.json`
(`integration` per tracker), `AnalyticsEvent`, `docs/work/2026-11-22-notifications/ui.md` §1.3 and §5, PR #137's diff
(`AnalyticsOptInStepView`, the new order: invite, consent, about you, wear, analytics, Apple Health, tracker setup, tabs), and the six reference images.
