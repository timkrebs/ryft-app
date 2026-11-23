# The first run: UI spec for PR 2 (G2 to G8)

Written for the ios-developer, who builds from it. Input: `audit.md` and `plan.md` of this folder (PR #143, not yet on `main`), the
user's pick of gaps for PR 2 (**G2, G3, G4, G5, G6, G8**, plus **G7** as the event list; G1 goes to PR 3), and
`docs/work/2026-11-22-notifications/ui.md` §1.3, §5, §10 (the lock-screen rule). Spec only, with two new components and a shots
test; nothing is wired into the onboarding and `Localizable.xcstrings` is untouched.

The app is dark only (ADR 0016): every colour is a one-value asset, so "dark and light" is answered by dark. Every number below
is a `Theme` token, a `*Spec` constant that exists, or one this PR adds to its own `*Spec`. English drafts are in RYFT's own
words; the localization-editor finalises them. No wording, layout or asset of any other product is used.

**Gap numbers are the audit's.** G2 the Health primer, G3 the step indicator, G4 the notification primer, G5 Today during the first
sync, G6 tracker setup, G7 analytics, G8 the splash.

## 0. Decisions (the short version)

| # | Decision | Why |
| --- | --- | --- |
| D1 | **The step indicator is a new `FirstRunStepRule`** in `Design/`, built on `StepRuleSpec` (it does not replace `StepRule`, which the training import uses). | `StepRule` stacks its caption under the segments; under the first run's lock-up row a one-line arrangement is 16 pt shorter. Same segments, same caption string, so no new catalog key. |
| D2 | **The count comes from a plan, taken once per first run** (`FirstRunPlan.make(facts, inputs)`, pure), and a screen asks it for `(n, m)`. It is not recomputed from `missing` on every screen. | `missing` loses a step the moment it is answered, so "Step 1 of 5" would shrink to "Step 1 of 4". A snapshot keeps answered steps in the count. §2.2. |
| D3 | **The notification primer is `LockScreenMock` in `Design/`** (the one shared piece, visual only) **plus a first-run screen `NotificationPrimerStep` in `Features/Onboarding/`**. `Push/` keeps the permission logic. | Design has no dependency on Push; the first run and Profile → Notifications can both draw the mock. §4.1. |
| D4 | **The notification primer shows after Apple Health, before tracker setup, on every account with iOS status `notDetermined`, whatever `push.enabled` says.** With the flag off its example is a notification that does arrive. | Local kinds need permission whatever the flag (notifications ui.md, lead decision 2). §4.3. |
| D5 | **Today's push question leaves `ImportCard`. `PushPrePromptCard` stays as the one second chance** (the 14-day return that exists), now also for people who said "Not now" in the primer. | One ask in one place; the card is about progress. §4.5. |
| D6 | **Today, first import: the empty orbit holds the gauge's place; the import card sits under it.** No percentage. | The audit's fix; the existing `TodayGaugeEntrance` already assembles a gauge over a placeholder that was seen. §5. |
| D7 | **The splash gets a caption earlier on the first run (1 s) and a second one at 5 s; no count.** | RYFT cannot back a count: the wait ends by an answer or the 10 s timeout, and which is unknown. §7. |
| D8 | **`onboarding_step` carries `step`, `action` and, for two steps, `permission`.** | §8. |

## 1. The first run after this PR, and its step counts

Counted steps, in order. Welcome (before there is an account), the splash, the account-hint sheet and the system sheets are not
steps and never show the indicator. Today is the destination, not a step.

`invite` (only while the platform's gate applies) → `consent` → `aboutYou` → `wear` (only while `devices.setup`) →
`analytics` (**pending #137**) → `health` → `notifications` (new; only while iOS hasn't been asked) → `trackerSetup` (only for a
tracker with its own app, known once `wear` is answered).

| Path | Steps | Count | With #137 |
| --- | --- | --- | --- |
| Apple Watch | invite, consent, about you, wear, Health, notifications | **6** | 7 |
| Garmin | the same, then tracker setup | **7** (6 until the tracker is picked) | 8 |
| No device (Skip, or "Just my iPhone") | invite, consent, about you, wear, Health, notifications | **6** | 7 |
| Any path, invite gate off | one fewer | 5 / 6 / 5 | 6 / 7 / 6 |
| Any path, `devices.setup` off (no wear, no setup) | invite, consent, about you, Health, notifications | **5** | 6 |
| A second device of an account that already has consent and a birth year | Health, notifications (and wear while on) | 2 to 4 | |

An account that already allowed notifications (a second account on a phone, a reinstall) has no notifications step.

## 2. G3: the step indicator

### 2.1 What it is

Purpose: say how far along the first run is, so six or seven screens never feel endless. It is not decoration and not a
brand moment: quiet, small, always in the same place. **What the eye sees:** the title first, the rule second.

Layout (new component `FirstRunStepRule`, `Ryft/Design/FirstRunStepRule.swift`):

```
[lock-up row, 40]                      WordmarkLockup, as today
   12
[▬ ▬ ▬ ▬ ▬ ▬ ▬]  Step 6 of 7            segments left, caption right, one line
   20
Title                                   ScreenHeaderTitle
```

| Part | Value |
| --- | --- |
| Segments | `count` capsules, 3 high (`StepRuleSpec.height`), 4 apart (`StepRuleSpec.spacing`), sharing the row's width |
| Ink | `Theme.textPrimary` at 55 % done, 100 % current, 16 % to come (`StepRuleSpec.opacity(index:step:)`) |
| Caption | `.ryft(.caption)`, `monospacedDigit`, `Theme.textTertiary` (4.5:1 on `background`), never wraps |
| Gaps | lock-up row → rule 12 (`topGap`); rule → title 20 (`titleGap`, 4 less than the 24 of a screen without it); segments → caption 12 |
| Colour | no teal, no Volt, no metric colour: the words say the step |
| Motion | none of its own. The screen cross-fades (`Theme.Motion.quick`, 250 ms; at once under Reduce Motion) and the rule comes with it |

It adds the rule's own height (about 16 pt at the default size) and 8 to a page. The pinned bar does not move.

**States.**

| State | Trigger | Draws |
| --- | --- | --- |
| Shown | `count >= 2` and the screen is a first-run full-screen step | segments + "Step n of m" |
| One step | `count < 2` (`FirstRunStepRuleSpec.minimumCount`) | nothing |
| Sheet | the screen is presented as a sheet (`.presentedRoot()`: a gate after the first run, the tracker setup from Today) | nothing: the screen receives `progress: nil` |
| AX1 and up | `isAccessibilitySize` | the caption goes under the segments, 6 below (`stackedGap`) |
| Step out of range | a stale index | clamped to `1...count` |

The shot `shots/spec-step-rule-in-context.png` shows it in the first-run frame; `shots/spec-step-rule.png` shows the component.

### 2.2 The rule, as pure functions (unit-testable)

Placed in `Features/Onboarding/FirstRunPlan.swift`. All inputs are plain values; no environment.

```swift
enum FirstRunStep: String, CaseIterable, Sendable {      // CaseIterable order is the screen order
    case invite, consent, aboutYou, wear, analytics, health, notifications, trackerSetup
}

struct FirstRunPlan: Equatable, Sendable {
    /// What the app knows beyond `Facts` when the first run starts.
    struct Inputs: Equatable, Sendable {
        var analyticsStep = false        // #137: `env.analytics.showsPrompt`; false until it lands
        var healthIntro = false          // `env.health.isAvailable && !settings.healthIntroDone`
        var notificationsPrimer = false  // !demo && iOS status == .notDetermined && !primerAnswered(account)
        var trackerSetup = false         // only after `wear`: a picked tracker that `needsSetup`
    }

    let steps: [FirstRunStep]

    /// The plan, once, when `phase == .ready && isFirstRun`. `OnboardingCoordinator.missing(facts)` gives the first four
    /// (it already applies the invite and `devices.setup` rules); the rest come from `inputs`.
    static func make(_ facts: OnboardingCoordinator.Facts, _ inputs: Inputs) -> FirstRunPlan

    /// `(n, m)` for `step`, 1-based; nil when the step isn't in the plan, or `m < 2`.
    func progress(at step: FirstRunStep) -> (step: Int, count: Int)?

    /// The plan with `step` added in screen order, never before one already passed. For `trackerSetup` once `wear` is
    /// answered with a tracker that needs it, and for a gate that appears mid-run.
    func including(_ step: FirstRunStep) -> FirstRunPlan
}
```

Rules.
1. **The plan is a snapshot.** The coordinator takes it once when the first run begins (`phase == .ready`, `isFirstRun`, not demo) and keeps
   it (`private(set) var plan`), reset by `switchAccount`. Answering or deferring a step does not remove it from the plan.
2. **`m` only grows, by insertion** (tracker setup after a vendor tracker is picked; a gate that appears mid-run). It never shrinks
   during a run. A relaunch mid-run takes a new snapshot of what is still missing, so it counts from 1 again, of what remains.
3. **A screen's progress is `plan.progress(at:)`, or nil** when `!isFirstRun`, in demo, or presented as a sheet. The coordinator
   exposes `func progress(for step: FirstRunStep) -> FirstRunProgress?` (a `step, count` pair); `OnboardingFlowView`, the analytics,
   Health, notifications and tracker-setup roots pass it down. It is **never derived from `showsLockup`**: `TrackerSetupStepView` also
   draws the lock-up in its sheet from Today.
4. **`OnboardingScreen` takes `progress: FirstRunProgress? = nil`** and draws `FirstRunStepRule` 12 under the lock-up row when it is non-nil and
   `showsLockup` is true. `HealthPermissionScreen` and the new notifications screen do the same.

Tests (Swift Testing, pure): the six rows of §1's table as `Facts` plus `Inputs`; `m` never decreases across answers and deferrals; an
answered step keeps its index; `including` inserts in order; `progress` is nil for a step outside the plan and for `m == 1`; demo has an empty
plan; the sheet and demo paths pass nil.

### 2.3 VoiceOver, Dynamic Type, reduced motion

- **VoiceOver:** one element, label **"Step 6 of 7"** (the same string as `StepRule`, `Step %lld of %lld`). Reading order on a step:
  the lock-up stays hidden (as today), so VoiceOver starts at the title (heading), then "Step 6 of 7", then the lead and the
  content. The rule comes second in the reading order because the title says where you are and the count adds to it; it sits
  below the lock-up and above the title on screen, so the screen order and the reading order differ by one element, and the
  title carries `accessibilitySortPriority` to stay first.
- **Dynamic Type:** to AX5 the caption stays on one line (`fixedSize`) and goes under the segments from AX1; nothing clips. The
  segments keep 3 pt (they are a line, not text).
- **Reduced motion:** nothing animates in it, so nothing changes.

## 3. G2: the Apple Health primer

Purpose: tell the person what iOS is about to ask, in terms they can match against the sheet, and that **one tap, Turn On All**,
is what RYFT needs. A partial grant is invisible (HealthKit never reports a refused read), so this screen is the only place to prevent it.
**What the eye sees:** the title, then "On the next screen: Tap Turn On All", then the ten kinds of data, then the Continue pill.

Layout, top to bottom (`HealthPermissionScreen`, `shots/spec-health-primer.png`):

| # | Element | Component and tokens |
| --- | --- | --- |
| 1 | Lock-up row, then the step rule | `WordmarkLockup` 40; `FirstRunStepRule` 12 under it |
| 2 | The 72 pt outline mark | `HealthIllustration`, 20 above the title (`FirstRunStepRuleSpec.titleGap`), decoration (hidden from VoiceOver) |
| 3 | Title and lead | `ScreenHeaderTitle`; lead `.ryft(.body)` `textSecondary`, 12 below (`OnboardingSpec.leadGap`). Lead unchanged |
| 4 | **"On the next screen"**: two points | `GroupedCard(Text(title))` of two `OnboardingPoint`s, glyphs `switch.2` and `checkmark.circle` |
| 5 | **"The ten kinds of data"**: four groups | `GroupedCard` of four `OnboardingPoint`s, glyphs `figure.walk`, `heart`, `lungs`, `bed.double`; 18 under the card above (`GroupedListSpec.groupSpacing`) |
| 6 | Footnote and policy link | `.ryft(.caption)` `textTertiary`, 12 below; `Privacy Policy` as `ryftLink()` (opens `SafariView` as today) |
| 7 | Actions | pinned bar: `PillButton` **Continue** (busy while the system sheet is up), `LaterButton` **Not now**; from AX1 they end the page instead of pinning |

**Copy direction (English draft).**

| Element | Draft |
| --- | --- |
| Group title 4 | On the next screen |
| Point 4a | **Tap Turn On All** / It is at the top of the list and switches on all ten kinds of data below. |
| Point 4b | **Then tap Allow** / That is all RYFT needs. You can change any of them later in the Health app. |
| Group title 5 | The ten kinds of data |
| Activity | Active Energy, Steps, Workouts |
| Heart | Heart Rate, Heart Rate Variability, Resting Heart Rate, Cardio Fitness (VO₂ max) |
| Respiratory | Respiratory Rate, Blood Oxygen |
| Sleep | Sleep |
| Footnote | RYFT writes nothing to Apple Health. Your data goes to your RYFT account, where the scores are calculated. Never sold, never used for advertising. |

Rules for the copy. The names are **as Health prints them** (Apple's capitalisation), because the reader matches words against the sheet; the
grouping is the Health app's own categories, which makes ten switches readable. The sheet's own order and labels are Apple's and may
differ by iOS version: **verify on a device with iOS 27** before the strings are final (see §10, call 3). The screen does **not** draw
Apple's sheet; it describes it. The old "What RYFT reads", "Where it goes" and "You decide" points are folded into the footnote and
point 4b; the screen is about the tap, not the policy. The old sentence that RYFT "writes nothing unless you turn on saving strength
workouts" moves to Profile (the write-access hint already says it there).

**States.**

| State | Trigger | Look |
| --- | --- | --- |
| Ready | the step shows | as above |
| Busy | Continue tapped; `HealthOnboardingMachine` is in `.requesting` | the pill's spinner, the title stays; "Not now" disabled; as today |
| After the sheet | granted or declined | the next step (notifications primer, or tracker setup); the screen does not report a result: HealthKit can't |
| Not now | tap | to the next step; **PR 3 makes this skip real** (G1). This spec assumes it: no iOS sheet follows |

**VoiceOver.** Order: title (heading), lead, "On the next screen" (heading), "Tap Turn On All. It is at the top…", "Then tap Allow. …", "The
ten kinds of data" (heading), each group read as one element ("Heart. Heart Rate, Heart Rate Variability, …": `OnboardingPoint` combines
its children), the footnote, Privacy Policy (link), Continue, Not now. The step rule reads "Step 5 of 7" after the title (§2.3).
**Dynamic Type to AX5:** points stack glyph-above-title (`OnboardingPoint` does this already), the pill grows with its title, the actions end the page from AX1, so
nothing is cut by a bar. **Reduced motion:** the pulse is drawn at rest (as today); the screen cross-fade is instant.

## 4. G4: the notification primer

Purpose: before iOS asks, show **one concrete example** of what RYFT would send, on a lock screen, so the person decides knowing what
they'd get. **What the eye sees:** the lock-screen mock with the notification, then the title and lead, then Continue.

### 4.1 One shared component, and where it lives

| Piece | File | Owns |
| --- | --- | --- |
| **`LockScreenMock`** (built) | `Ryft/Design/LockScreenMock.swift` | The visual only: a `surface` phone with a 16 % ink outline, cut off at the bottom; the clock; one notification card; two stacked bars. The caller passes finished strings (title, message, time label, clock `Date`, VoiceOver sentence). It owns no copy, no permission, no Push dependency |
| `NotificationPrimerExample` (to build) | `Ryft/Push/NotificationPrimerExample.swift` | Which example to show and its words (pure, §4.3) |
| `NotificationPrimerStep` (to build) | `Ryft/Features/Onboarding/NotificationPrimerStep.swift` | The first-run screen: `OnboardingScreen` frame + `LockScreenMock` + actions; calls the registrar |

`Design/` is the home because the mock is a token-only drawing with no model, and both **the first run and Profile → Notifications can use it
without importing Push**. `LockScreenMock.Style.card` is the notification alone, for a page with no room for the phone.

### 4.2 Layout (`shots/spec-notification-primer.png`)

| # | Element | Tokens and components |
| --- | --- | --- |
| 1 | Lock-up row, step rule | as §2 |
| 2 | Title, lead | `ScreenHeaderTitle`, `.ryft(.body)` `textSecondary` |
| 3 | **The mock** | `LockScreenMock(.phone)`, 24 under the lead (`OnboardingSpec.contentGap`): phone `surface` with a `textPrimary` 16 % hairline outline, top radius 36; clock block (date `.ryft(.callout)` `textSecondary`, time Light 56 `textPrimary`); notification `surfaceRaised`, radius 22 (`neutralTileRadius`), 14 inside; app tile 38 `background` with the mark, 12 from the text; title `.ryft(.button)` `textPrimary`; message `.ryft(.callout)` and time label `.ryft(.caption)` both `textSecondary` (`textTertiary` fails on `surfaceRaised`); two ghost bars; the bottom 28 % fades to the screen |
| 4 | Caption | `.ryft(.caption)` `textTertiary`, 12 below the mock |
| 5 | Actions | pinned: `PillButton` **Continue**, `LaterButton` **Not now**; inline from AX1 |

Colour: nothing teal, no Volt. The mock is neutral so it reads as an example, not as a score.

### 4.3 What the example is, and when the screen shows

The example must be a notification that **will** arrive for this account, or the mock lies.

```swift
enum NotificationPrimerExample: Equatable, Sendable {
    case morningScore, journal, syncStale
    /// `pushEnabled`: `push.enabled`. `remindersOn`: `notifications.reminders` (known on), which gates the journal reminder and
    /// the "not syncing" fallback (`ReminderScheduler`, #141). `journalLive`: the journal is available (`availability == .live`).
    /// Nil: nothing can arrive, and there is no primer (review C1).
    static func choose(pushEnabled: Bool, remindersOn: Bool, journalLive: Bool) -> Self? {
        if pushEnabled { return .morningScore }
        guard remindersOn else { return nil }
        return journalLive ? .journal : .syncStale   // `syncStale` needs `notifications.reminders` too (not live in every mode)
    }
}
```

| Example | Title | Message | Clock | Lead (draft) |
| --- | --- | --- | --- | --- |
| `morningScore` | Your morning score is ready | Open RYFT to see how you recovered overnight. | 7:30 | RYFT can tell you when your morning score is ready, and when your data stops syncing. You choose which in Profile. |
| `journal` | How was yesterday? | A few taps, and RYFT shows how your habits change the morning after. | 9:00 | RYFT can remind you to log your day, and tell you when your data stops syncing. You choose which in Profile. |
| `syncStale` | Your data hasn't synced | Open RYFT to bring it up to date. | 9:00 | RYFT can tell you when your data stops syncing, so a quiet watch doesn't go unnoticed. |

Title of the screen for all three: **Hear from RYFT when it matters**. The words of `journal` and `syncStale` are `notifications/ui.md` §5.1 and
§5.2 verbatim; no health value, no habit name, no count in any title or message (the lock-screen rule, §5; a test: no digit in the three
titles). Caption (all three): **An example. What your lock screen shows follows your iOS setting for previews. Change what RYFT sends in
Profile → Notifications.**

**When it shows** (a pure `NotificationPrimerFacts.shows`):
`isFirstRun && !demo && authorizationStatus == .notDetermined && !primerAnswered(account) && healthIntroAnswered && example != nil`.
It shows **after Apple Health and before tracker setup**. `provisional` and `authorized` and `denied` skip it silently (not counted). It
shows **whether or not `push.enabled` is on**, as long as a notification can arrive: the local kinds need the permission whatever the push
flag (notifications ui.md, lead decision 2), and with it off the example is a local one, which needs `notifications.reminders` on (review C1).
With both flags off no notification can arrive: no primer, and the plan counts one step fewer. `primerAnswered` is one per-account
`UserDefaults` flag set by either answer, removed with a deleted account (review S2).

**The `morningScore` example and an open call.** The platform's `MORNING_SCORE_TITLE` is currently "Recovery %@" (a health value in the
title; notifications ui.md §10, call 4). The mock shows the title this spec wants, "Your morning score is ready", the form the lock-screen rule
and the hidden-preview placeholder use. Until call 4 is settled the real notification is not what the mock shows. See §10, call 1.

### 4.4 States and actions

| State | Trigger | Look | Action |
| --- | --- | --- | --- |
| Ready | the step shows | §4.2 | |
| **Continue** | tap | the pill goes busy while the system prompt is up (`PillButton(busy:)`, the title stays); then the next step | `PushRegistrar.accept()` (`requestAuthorization`, then APNs if granted); result → analytics `permission` (§8) |
| **Not now** | tap | the next step at once | `PushRegistrar.dismissPrompt()` (the existing "Not now"), **never `requestAuthorization`**. A hosted test asserts it |
| Already decided | status isn't `notDetermined` | the screen is skipped, not counted | none |
| Granted | the prompt allowed | nothing to say: Today and Profile → Notifications show the choices | |
| Declined at the system prompt | the prompt refused | nothing nags; Profile → Notifications shows its `denied` notice with "Open Settings" | none |
| Error | `requestAuthorization` throws | treated as declined: the step goes on; no banner (the person can't fix it here) | none |

**VoiceOver.** Order: title (heading), lead, the mock as **one element** ("Example notification from RYFT. Your morning score is ready. Open
RYFT to see how you recovered overnight."; the clock, date and bars are hidden), the caption, Continue (hint: "iOS asks next"), Not now. "Step 6 of 7"
after the title (§2.3). **Dynamic Type to AX5:** from AX1 the actions end the page; from AX3 the mock is the notification card alone
(`LockScreenMockSpec.compactFrom`), its tile above the words so they keep the card's width (`shots/spec-notification-primer-ax3.png`).
**Reduced motion:** the mock has no motion; the screen cross-fade is instant.

### 4.5 What happens to Today's push question

**Recommendation: it goes from `ImportCard`; `PushPrePromptCard` stays, as the one second chance.**

- Remove the question from `ImportCard` ("Tell me when my first scores are ready", Allow and Not now), the `asksForPush`, `enablePush` and
  `dismissPush` parameters, `TodayViewModel.showsImportPushPrompt` and `PushRegistrar.showsImportPrompt`. The card is about progress and
  carries one decision at most (rule 1); a second permission ask minutes after the first run's own is the thing this primer replaces.
- Keep `PushPrePromptCard` ("Get your recovery each morning"), shown after the first sync while iOS hasn't been asked. The primer's
  **Not now is the existing dismissal** (`dismissCount` 1, with its date), so the card returns **once, 14 days later**, exactly as it does
  today: no new state. An account that never saw the primer (it finished its first run before this build) still gets the card after
  its first sync, as now.
- With `push.enabled` off the card never shows (`isEnabled` gates it), so a "Not now" has no Today follow-up; Profile → Notifications
  (notAsked: the pinned "Allow notifications") is the way back.

The alternative, keeping the import-card question as the second chance, would mean the same person is asked at minute 4 of the first run (the
primer), minute 6 (the import card) and day 14 (the card). Not recommended.

## 5. G5: Today while the first sync runs

Against the reference's home-while-syncing screen (structure only): its parts are a status pill at the top, empty gauges that hold their
place, and skeleton cards. RYFT keeps what is honest and drops what isn't: the **status line** is its pill (it says what is moving, in
real counts); the **empty orbit** is its held gauge; there are **no skeleton cards**, because the cards below Today's hero are real (My Day) and a
placeholder for data RYFT does know would be a lie; and there is **no percentage**, ever.

**What the eye sees:** the greeting and the status line, then the outline orbit, then "Setting up RYFT" with its three chips and counts.
Layout, top to bottom, when `hero == .importing` (`shots/spec-today-first-import.png`):

| # | Element | Component and tokens |
| --- | --- | --- |
| 1 | Header | as today |
| 2 | Greeting, sub-line ("Your history is on its way."), status line ("Uploading 12,400 readings") | as today; `TodayLayout.greetingToSubLine`, `subLineToStatus` |
| 3 | **The empty orbit**, 14 under the status line (`statusToGauge`) | `OrbitGauge(mode: .scored(.empty), size: .hero, showsCaption: false, animatesFill: false, breathes: false)` in the 260 pt `gaugeSlot`: tracks and hollow markers, no number, **hidden from VoiceOver** (the card and the status line say everything), no motion |
| 4 | **`ImportCard`**, 12 under the orbit (`cardGap`) | unchanged except that the push block is gone (§4.5): "Setting up RYFT", Reading Apple Health > Uploading > Scoring chips, nights / readings / workouts, the 3 pt bar and "Imported through … · 61 of 90 days", "You can leave the app" |
| 5 | Cards below | My Day etc., as today |

Why the orbit sits **above** the card: the gauge's place stays where it will be, so when the first score lands nothing jumps. The existing
`TodayGaugeEntrance` (`gaugePlaceholderSeen`) then assembles the gauge over its tracks. Set `gaugePlaceholderSeen = true` when the orbit
appears while importing; nothing else is needed. The card is fully above the tab bar at 390 × 844 (the shot); the alternative, the card above the orbit,
is shorter by one gauge but moves the gauge on arrival (§10, call 4).

**States.** Importing (this layout); importing offline or paused (the status line and the card's bar say so, as today; the orbit unchanged);
slow scoring ("Taking longer than usual", as today); first score landed (`hero.kind` → `.score` or `.pending`: the 250 ms cross-fade that exists; the
card collapses to `ImportRow` while the backfill continues). **Copy:** no new strings.

**Dynamic Type.** From AX3 the placeholder orbit is dropped and the card is the page (a 260 pt circle at AX5 pushes the progress off
the first screen); `gaugePlaceholderSeen` stays false, so the gauge then appears without the assemble. Below AX3 as above.
**Reduced motion:** no entrance, no breathing; the cross-fade to a score is instant. **VoiceOver:** greeting (header), status line, "Setting up
RYFT" (heading), the three chips as "Step 2 of 3: Uploading", the three counts, the coverage line. Nothing is read twice.

## 6. G6: tracker setup

Purpose: tell a person with a tracker that has its own app what to switch on so its data reaches Apple Health, and that **the first sync is already
running**, so this is not a gate. One decision: "have you set it up, or later?".

Layout (`TrackerSetupStepView`, the first-run frame with the step rule: it is the last step):

| # | Element | Change |
| --- | --- | --- |
| 1 | Lock-up, step rule, title ("Set up your tracker" / "…trackers") | the rule is new |
| 2 | **Lead** | new copy, below |
| 3 | The tracker's card (the first open, the others collapsed) | unchanged |
| 4 | **Check sync** | from an outline pill to a text action: `Button { … }.ryftLink()` under the cards, same identifier. Its result still opens inline with its own Check again |
| 5 | Actions | pinned: `PillButton` **Done** (confirm glyph), `LaterButton` **Show me again later** (unchanged); inline from AX1 |

**Lead (draft).** `TrackerSetupLead.choose(syncRuns:)`, a pure function:
- sync running (`uploadGate(for: .healthKit) == nil` and `health.accessStatus() == .asked`): **Your first sync is already running. These steps make sure your tracker's data reaches Apple Health.**
- otherwise (Health "Not now" or no consent yet): **These steps make sure your tracker's data reaches Apple Health, so RYFT has something to read.**
The first sentence is only said when it is true: the screen is also reached after "Not now".

**States.** One tracker (its card, open); several (first open, others collapsed, each with its own "Later"); check closed / check open with a
result; Done / Show me again later (both lead to the next screen: Today). **VoiceOver:** title, "Step 7 of 7", lead, the card as
today, "Check sync" (link), Done, Show me again later. **Dynamic Type to AX5:** as today (the card scrolls; actions end the page from AX1).
**Reduced motion:** the card's expand and the check result appear without animation.

## 7. G8: the splash

Today the mark shows alone; after 3 s "Checking your account…" fades in. The first run waits for the platform up to `checkTimeout` (10 s),
where the 3 s caption is late.

| Elapsed | Restoring a session (`.restoring`) | First-run wait (`holdsFirstRun`) |
| --- | --- | --- |
| 0 to the threshold | the mark alone | the mark alone |
| threshold | 3 s (`captionDelay`, unchanged): **Checking your account…** | **1 s** (`firstRunCaptionDelay`): **Checking your account…** |
| 5 s (first run only) | | **Taking longer than usual. RYFT carries on by itself in a few seconds.** |
| 10 s | | the wait ends: the flow goes on with what it knows (`checkTimeout`), as today |

```swift
enum SplashCaption: Equatable, Sendable {
    case none, checking, slow
    static func at(elapsed: Duration, firstRun: Bool) -> Self   // none < 1 s (3 s restoring) ≤ checking < 5 s ≤ slow (first run only)
}
```

**No count, no spinner, no countdown.** RYFT cannot back one: the wait ends when the platform answers or at the timeout, and nothing says which. A
number of seconds or "1 of 3 requests" would suggest progress the app doesn't have. The captions are sentences in `textSecondary`
(`.ryft(.label)`, as now), 50 below the mark's centre, faded in with `Theme.Motion.quick`, **at once under Reduce Motion**. VoiceOver announces each caption when it
appears (`AccessibilityNotification.Announcement`), as the first does now. `SplashView` takes `firstRun: Bool` from `RootView` (`holdsFirstRun` versus `.restoring`). No step
rule here: the splash isn't a step.

## 8. G7: the events

One event, `onboarding_step`, per step, as the analytics seam already has it (`AnalyticsEvent.onboardingStep`), with two more tokens:
`step` (`OnboardingStepName`: add `analytics` (when #137 lands) and `notifications`), `action`, and `permission` for two steps. Every value is an
enum-backed `AnalyticsToken`; **no health value, no tracker name, no free text, no count**; only while `analytics.enabled`.

`action` ∈ {`shown`, `continued`, `skipped`}. `permission` ∈ {`granted`, `denied`, `not_determined`}, plus **`answered` for `health` only** (HealthKit
never reports a refused read, so "granted" would be a guess; see §10, call 2).

| Screen | `step` | `shown` when | `continued` when | `skipped` when | `permission` |
| --- | --- | --- | --- | --- | --- |
| Invite code | `invite` | the screen appears | a code was accepted | "Not now" (only while the gate is a warning) | none |
| Consent | `consent` | appears | Agree and continue recorded | "Not now" | none |
| About you | `about_you` | appears | the birth year was saved | Skip | none |
| What do you wear? | `wear` | appears | Continue (the choice saved) | Skip | none (no tracker name) |
| Usage analytics (#137) | `analytics` | appears | Share usage analytics | Not now (sent only if opted in, so in practice never) | none |
| Connect Apple Health | `health` | appears | Continue, after the system sheet closed | Not now | `answered` or `not_determined` (`accessStatus()`) |
| Notifications | `notifications` | appears | Continue, after the system prompt closed | Not now | `granted`, `denied` or `not_determined` (`authorizationStatus`) |
| Set up your tracker | `tracker_setup` | appears | Done | Show me again later | none |
| Today reached | `done` | the tabs show for the first time | | | none |

`shown` is the existing `onChange(of: analyticsStep)` in `RootView`; `analyticsStep` gains the notifications step. `continued` and `skipped` are
fired where the answer is taken (the coordinator's `answerWear`, `later`, `finishAboutYou`; `HealthOnboardingViewModel.connect` and
`notNow`; the notification step). `health_access_requested` and `first_sync_completed` stay as they are. Test: an allow-list walks every case
of `step`, `action` and `permission`; the gate test (nothing captured while off) covers every new call site.

## 9. What was built in this PR, and how to look at it

| File | What |
| --- | --- |
| `Ryft/Design/FirstRunStepRule.swift` | `FirstRunStepRuleSpec`, `FirstRunStepRule(step:count:)`; previews: 3 of 7, 1 of 6, 8 of 8, one step (nothing), AX3, AX5 |
| `Ryft/Design/LockScreenMock.swift` | `LockScreenMockSpec`, `LockScreenMock(style:clock:title:message:timeLabel:accessibilityLabel:)`; previews: phone, journal and sync examples, card, AX3, AX5 |
| `RyftTests/FirstRunSpecShotsTests.swift` | Draws the spec's screens as compositions of the two components and existing pieces when `FIRST_RUN_SPEC_DIR` is set; otherwise does nothing. Not wired into any screen. Delete it with the spec if you don't want it kept |
| `docs/work/2026-11-23-first-run/shots/spec-*.png` | `spec-step-rule`, `spec-step-rule-in-context`, `spec-lock-screen-mock`, `spec-notification-primer` (+ `-push-off`, `-ax3`), `spec-health-primer`, `spec-today-first-import` |

Both components use `Theme` tokens and `StepRuleSpec`, `CircleButton.borderOpacity`, `RyftTextStyle` only. Previews are dark; a light preview is moot (one-value
assets, ADR 0016) and the files say so. Neither adds a catalog key: `FirstRunStepRule` reuses `Step %lld of %lld`, and `LockScreenMock` takes finished strings (its previews use
`Text(verbatim:)`).

To make the shots: `TEST_RUNNER_FIRST_RUN_SPEC_DIR=<dir> xcodebuild -scheme Ryft -testPlan Unit -destination "platform=iOS Simulator,id=<private simulator>" -parallel-testing-enabled NO -only-testing:RyftTests/FirstRunSpecShotsTests test`.
The Health and Today shots are compositions with the spec's draft text; the real screens are for the ios-developer to build.

## 10. Calls that need you

1. **The morning example and `MORNING_SCORE_TITLE`** (notifications ui.md §10, call 4, still open). The mock says "Your morning score is ready"; the
   platform's title is "Recovery 82 %". Either the platform moves the score to the body (the mock is then true) or the primer's example
   becomes the hidden-preview form, or this primer ships with the `journal` example only until it is settled. Recommendation: settle call 4 first.
2. **`permission` for Apple Health.** The brief names {granted, denied, not_determined}. For `health` the app can only know that the sheet was answered
   (`.asked`), never what was allowed. Recommendation: add one value, `answered`, for `health` only.
3. **"Turn On All" and the ten names are from memory of the iOS sheet.** I could not show the system sheet in a simulator run. Verify wording, order and
   the Health categories on a device with iOS 27 before the strings are final; if the sheet has no "Turn On All" there, G2's key sentence changes.
4. **Orbit above or below the import card** (§5). Recommended: above (no jump). The alternative puts the card first and shortens the page.
5. **A growing count on the Garmin path** (§2.2): "of 6" becomes "of 7" when a tracker with its own app is picked. Recommended over counting a step
   that most people never see.
6. **Profile → Notifications, notAsked:** optionally show `LockScreenMock(.card)` under the notice ("RYFT hasn't asked to send notifications yet"), with the same example and caption.
   Not specified further; the component supports it.
7. **G1 is assumed fixed** (PR 3): "Not now" on Health really skips. Until then the Health step's "Not now" still brings up the iOS sheet.

## Lead decisions on the spec (ios-lead, 2026-11-23)

1. **The morning example stays "Your morning score is ready".** iOS's default "Show Previews: When Unlocked" makes that
   the text a locked phone shows, so the mock is true for the default. It also keeps every health value off the mock.
   Moving the score out of `MORNING_SCORE_TITLE` stays the open contract question it already is (notifications call 4).
2. **Health permission result is `answered` or `failed`**, never `granted`: HealthKit doesn't tell. Notifications use
   `granted` / `denied`.
3. **"Turn On All" and the ten names** stay as specified and go on the device checklist (STATUS, Needs you).
4. **The empty orbit goes above the import card**, as specified.
5. **The count never grows.** The plan reserves one slot for "set up your device" in every path. A tracker with
   several setup cards shows them all under that one step ("Step 5 of 6" stays on each). The total is fixed when the first
   run starts: Apple Watch, Garmin and no device all show the same M for an account.
6. **No primer on Profile → Notifications in this PR.** The page keeps its notice and its pinned Allow. The component is
   ready for it later.
7. **Strings:** every visible string in `LockScreenMock` and the new steps goes through `Localizable.xcstrings`
   (`LocalizedStringResource` / `String(localized:)`), with no `static let` English literals.
