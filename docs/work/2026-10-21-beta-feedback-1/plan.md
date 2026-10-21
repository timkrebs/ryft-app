# Beta feedback 1 — plan

Brief: `CLAUDE_FOLLOWUP_BETA_FEEDBACK_1.md` (TestFlight 1.0.0 `20261021.141128`). Lead: this session.
Reviewers per `docs/AGENT_FLEET.md`: code-reviewer on every PR; security-privacy-reviewer on T4 (HealthKit
write) and T3 (intents, URL routes); ui-validator on every PR with visible changes.

**Constraint found while planning:** `Ryft/` and `RyftTests/` are classic groups (only `RyftWidgets/` and
`RyftUITests/` are synchronized). New app code goes into existing files; the conventions skill says otherwise
(reported). New widget-side files are fine.

| # | PR title | Brief | Depends on |
| --- | --- | --- | --- |
| T1 | `sleep: editable sleep need everywhere` | §1 | — |
| T2 | `notifications: legible rollout and permission states` | §2 | — |
| T3 | `train: quick start from Today, quick actions, intents, control` | §3 entry points | — |
| T4 | `health: save strength workouts to Apple Health (opt-in)` | §3 Apple Health | #19 (purpose string), #18 (`APP_STORE_METADATA.md`) |
| T5 | `sleep: bedtime & wake with reminder and alarm` | §4 | T1 (Profile → Sleep) |
| T6 | `docs: beta feedback 1` | §5, §6 | T1–T5 |

## Where it stands (2026-10-21)

| # | PR | Base | Review | CI |
| --- | --- | --- | --- | --- |
| T1 | #20 | `main` | addressed | green |
| T2 | #21 | `main` | addressed | green |
| T3 | #22 | `main` | addressed | green |
| T4 | #24 | `chore/app-groups-fleet` (#18) + #19 | addressed | green |
| T5 | #23 | `feat/editable-sleep-need` (#20) | addressed | see the PR |
| T6 | this | `feat/editable-sleep-need` (#20) | — | — |

Merge order: #20, then #23 and this PR (retarget to `main` after #20); #21 and #22 any time;
#24 after #18 and #19 (then retarget to `main`). Expected conflicts, all in files several
tickets touched: `docs/STATUS.md` and `CHANGELOG.md` (keep every section),
`Ryft/App/RyftApp.swift` (`DebugScreen` cases, keep all), `RyftWidgets/RyftWidgets.swift`
(the widget bundle: keep the Train control and the wake-alarm activity) and
`Localizable.xcstrings` (keep both sets of keys).

## T1 — editable sleep need
- One vocabulary: **Sleep need** (tonight's, from the API) and **Baseline sleep need** (the editable part), en + de.
- One editor (`BodySettingsEditor`) and two sheets (baseline sleep need: 15-min steps, 4–12 h; maximum heart
  rate: 100–230 bpm), used from onboarding → About you, the Sleep tab and Profile.
- Saves at once (`PATCH /v1/me`): the value shows immediately (optimistic), a refusal (`422`) shows inline in
  the sheet and the value goes back. "Use the learned value" / "Use the estimate" send `…_manual: false`.
- Past days aren't rescored on their own: the sheet says so and offers "Rescore the last 90 days".
- Sleep tab: the need row opens the breakdown (base + strain + debt − nap credit = total, `DayDetail.sleep.need`)
  with "Change baseline".
- Profile: a **Sleep** section with the baseline (T5 adds Bedtime & wake there); Body keeps max HR and birth year.
- Accept: view-model tests for `default` / `learned` / `manual` source text, the patch for a set value
  (`sleep_base_min`) and for going back (`sleep_base_manual: false`), revert on `422`, the breakdown sums.

## T2 — notifications
- Flag off: no toggles that look on; a read-only list of what will come, and "We'll let you know here…".
  Stored choices kept.
- Flag on, iOS not asked: live toggles, the Today pre-prompt once. Denied in iOS: toggles visible, "Notifications
  are off in iOS Settings" + Open Settings. Quiet hours: pickers inline only when on (22:30–07:00).
- Accept: tests for the three states' controls.

## T3 — start a workout from anywhere
- Every entry point lands in one `TrainCoordinator` call: resume a running session, else today's plan day,
  else an empty session (or "repeat last").
- Today: "Start strength workout" on the Train card; "Quick start" row without a plan.
- Home-screen quick actions (dynamic Start / Resume), App Intents + App Shortcuts (Siri, Spotlight, Shortcuts,
  Action Button), a Control Center / Lock Screen control (iOS 18+), the Live Activity with elapsed time and
  the next set.
- Accept: each entry point → the same coordinator call; resume, never a second session; intent parameters.
- Risk: the control lives in the widget extension and the intents in the app; verify against Apple's docs how a
  control opens the app into a session without sharing a type across targets.

## T4 — save strength workouts to Apple Health (opt-in)
- Asked once after the first completed session, and in Profile; write permission for workouts only, requested
  only when turned on. `HKWorkoutBuilder`, `.traditionalStrengthTraining`, brand "RYFT", external UUID = session id.
- RYFT-written workouts are not uploaded again (skip by source and external UUID) until the platform says how
  to link them (`docs/API_REQUESTS.md`).
- `NSHealthUpdateUsageDescription` (en + de) says what's true; `APP_STORE_METADATA.md`, privacy notes; the
  user updates `ryftapp.de/privacy`.
- Accept: no write without opt-in; written once per session; self-written workouts skipped in the upload.

## T5 — bedtime & wake
- Sleep schedule (wake per weekday or weekdays/weekend, goal Peak 100 % / Perform 85 % / Get by 70 %,
  wind-down 15–60 min) stored per user; Tonight card on Today from 17:00 and on Sleep; numbers only from
  `GET /v1/sleep/plan`; re-query after syncs that touch today and in the evening refresh; reschedule when the
  bedtime moves ≥ 10 min; bedtime reminder (local, its own toggle); optional wake alarm (AlarmKit on iOS 26+,
  verified against Apple's docs; a time-sensitive notification below, labelled as not an alarm); planned vs
  actual the next morning; "Bed by 22:41" on the widget in the evening. Behind `sleep.planner`.
- Accept: weekday → wake parameter; goal → bedtime; reschedule threshold; reminder/alarm through fakes;
  DST and midnight-spanning plans; flag gating.

## T6 — docs
- `docs/API_REQUESTS.md` §5 shipped with the features it belongs to: Bedtime & wake §1–4 (schedule on
  the account, planned vs actual, server `BEDTIME` push, `day=`) in T5, Train §3 (RYFT-written workouts)
  in T4. This PR: `docs/TESTFLIGHT_NOTES.md` (en + de, replies to the two comments), this plan, the
  review log, `docs/STATUS.md`.

## Needs the user (collected as we go)
- `push.enabled` to 100 % (the brief's `curl`), then open the app twice and allow notifications.
- `ryftapp.de/privacy`: RYFT may write strength workouts to Apple Health, opt-in (T4).
- Paste `API_REQUESTS.md` → Bedtime & wake §1–4 and Train §3 into the platform session.
- Xcode: Time Sensitive Notifications capability (optional; the wake notification below iOS 26).
  App Groups are in #17/#18. App Intents, quick actions and AlarmKit need no capability (AlarmKit:
  `NSAlarmKitUsageDescription`, done).
- Convert `Ryft/` and `RyftTests/` to folders (Xcode → the group → Convert to Folder), then
  `AppShortcuts.xcstrings` can give Siri German phrases.
- Device checks: quick action, Action Button, Control Center control, alarm in Silent mode, the bedtime
  reminder, the `HKWorkout` in Fitness (and only one with a watch workout).
- #18's PR title fails `pr-title.yml`; #17 is contained in #18.
