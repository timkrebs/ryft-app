# Beta feedback 1 — review log

## T1 `sleep: editable sleep need everywhere`

**code-reviewer** (no blockers; 5 should fix, 4 nits) — all addressed:
- Birth-year failures were invisible in Profile → shown beside the picker (`birthYearError`).
- Save and rescore could overlap (a save during the rescore was reported as rescored) → one at a
  time (`isBusy`), buttons disabled across, tested.
- A failed rescore lost its request ID → `rescoreDetails`, shown with Details.
- The form's draft only set on appear (stale after a refusal; defaults before the account
  loaded) → follows the saved value until edited, resets after every save.
- Test gaps → 500 failure, refused "go back", birth-year failure, save during rescore, failed
  rescore, the mock keeping each change.
- Nits: dead `updateUser`, unused environment and init parameter removed; the demo platform now
  keeps each patch (it reset to the mock user); VoiceOver hint says what happens ("Opens the
  editor"); the number animates (Reduce Motion respected).

**ui-validator** (1 blocker, 3 should fix, 3 nits):
- Blocker, About you at AX3: title and value fought for the line → stacked at accessibility
  sizes (the screen already scrolls). Re-checked at AX3.
- Editor at AX3: −/+ now scale with text (`@ScaledMetric`); the title scales instead of truncating.
- Not changed: the disabled Save pill (system toolbar style), Birth year staying a menu picker
  (it is a picker), caption contrast (existing token; a design-token change is out of scope).

## T2 `notifications: legible rollout and permission states`

**code-reviewer** (no blockers; 3 should fix, nits) — addressed:
- A flag flip fetched on app-active waited in `pending`; opening the screen didn't apply it →
  `load()` applies the waiting answer (`applyPending`'s contract: a screen appears). Tested with a
  real `FlagStore`.
- Tests checked the model only and skipped the flip → flip test, Today pre-prompt test for an
  already-synced account, UI test in demo mode (no switches while rolling out).
- Identifiers now used by the UI test, on `.contain` containers.
- Nits: header trait, wrapping, the mixed-language preview replaced by denied/allowed previews,
  copy ("…when you turn notifications back on", the rollout's "choices are kept" dropped),
  `Permission` folded into `mode`, the quiet-hours test checks what's saved.

## T3 `train: quick start from Today, quick actions, intents, control`

**code-reviewer** (1 blocker, 5 should fix, nits) and **security-privacy-reviewer** (4 should fix) — addressed:
- Blocker (both): a start asked for while signed out, or during onboarding/the Health
  explanation, ran later — for the next account, or over the consent screen. Now a start runs
  only once the tabs are on screen for an account; earlier it waits for them; signing out, a
  restore that ends signed out, or another account drops it. Tested.
- `ryft://train/start` removed (any app could start a session); `ryft://train/session` and
  Siri's resume only resume, through the same gate. Intents require an unlocked device.
- Sign-out left the previous account's session presented (and a set toggle would restart its
  Live Activity) → `TrainCoordinator.accountChanged()` closes it.
- Live Activity: carries the session's ID; only that activity is reused, others (or an older
  version's) end, and at launch every activity but the running workout's ends. A rest that runs
  out while the app is away goes stale and the lock screen shows the workout again. The next set
  follows every edit; an empty workout says "Add an exercise". Title and next set are
  `.privacySensitive()`.
- Tests no longer start real Live Activities (`liveActivities: false`).
- A plan day cached on another day is fetched again (3 s at most) before a quick start uses it;
  offline it starts an empty workout instead of yesterday's day.
- Nits: scene delegate only for the app's window role, no Task hop; Siri's resume says when
  nothing runs; `make lint` checks the app/widget copies of shared types stay identical
  (`scripts/check-shared-types.py`, shown to catch a drift).
- Not done: a test for the repeat-last race (a start during the await) — the code re-checks
  after the await; the mock has no hook to hold that request.


## T4 `health: save strength workouts to Apple Health (opt-in)`

**code-reviewer + security-privacy-reviewer** (1 blocker, 6 should fix, nits) — addressed:
- Blocker: onboarding (en + de) and the TestFlight review notes still said RYFT never writes to
  Apple Health, right before the system prompt → "RYFT writes nothing to Apple Health unless you
  turn on saving strength workouts."
- Duplicates: a double-tapped Save or a second Finish could write twice → in-flight guard, Finish
  ignored while finishing, written only for a completed session, HealthKit checked by the external
  UUID, a failed write discarded.
- A watch strength workout for the same session meant two in Fitness → not written when another
  source's strength / functional / cross-training workout covers at least half of the session
  (`API.md`'s rule); one that arrives later replaces RYFT's on the next foreground (3 days back).
- "No heart rate recorded" was shown before the watch's workout could sync → "No heart rate yet".
- Refused or revoked access left the switch on, or snapped it back silently → on only while iOS
  allows it (rechecked on foreground), with "Allow it in Health → … → Workouts" and Open Health.
- The per-account choice survived sign-out → wiped with the rest.
- `STATUS.md` cited a missing request → `API_REQUESTS.md` → Train §3.
- Nits: `declined()` folded into `turnOff()`, one CHANGELOG heading, mock locking, injected bundle
  ID in the skip test, no writes in demo mode, copy no longer claims activity credit.
- Not changed: deleting a session — only an in-progress one can be discarded, and it never wrote a
  workout.

## T5 `sleep: bedtime & wake with reminder and alarm`

**code-reviewer** (3 blockers, 7 should fix, 6 nits) — addressed:
- Blocker: sign-out or another account kept the previous account's reminders, weekly alarms and
  widget bedtime → `teardown()` on every account change (and when the flag goes off or it's turned
  off); the sign-out wipe deletes every schedule and planned night.
- Blocker: between 03:00 and the wake time (and Friday 07:30 with Saturday at 08:00) the app meant
  another night than the API resolved → next-wake semantics match the API; the one remaining case
  is moved by a day (`align`), anything else isn't used; `day=` requested.
- Blocker: turning the reminder off didn't cancel it offline, with the flag off or after an error →
  cancelled at once.
- Should fix: one refresh at a time and stale answers dropped; "Set up" and back saved a schedule,
  and nothing turned it off → saves only after an edit, "Turn off Bedtime & wake"; same time on
  weekdays now normalises the hidden days; alarms set again once per launch, turned off with a
  reason when iOS no longer allows them; provisional notifications ask for full permission; the
  Tonight card shows the last plan offline instead of spinning; a night keeps its plan once bedtime
  passed.
- Nits: the iOS 26.1 alarm alert, one alarm per wake time; the widget follows every plan and shows
  a bedtime after midnight; the lock screen hides the need ("Bedtime reminder"); dead code; spoken
  planned-vs-actual; Tonight's rows stack at large text (checked at AX5); refusals announced;
  malformed stored schedules ignored; planned nights decoded once.
- Time Sensitive (wake notification below iOS 26) needs the capability in Xcode → Needs you.
