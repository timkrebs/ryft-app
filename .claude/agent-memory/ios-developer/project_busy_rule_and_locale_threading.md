---
name: project-busy-rule-and-locale-threading
description: M3b (PR 6 follow-ups) — how the busy rule is built and tested per control kind, what was left, how Train history threads a locale, the launch-test margin
metadata:
  type: project
---

M3b (2026-11-20), branch `feat/nocturne-pr6`, worktree scratchpad/wt-pr6. Lead decision: a busy control shows a spinner,
keeps its title, takes no tap, VoiceOver value "In progress" (C spec §2.6 now points at this rule).

**Why:** the next strings pass, reviews and any new busy control land on the same seams.

**How to apply:**
- `PillButton(…, busy:)` disables itself (`isEnabled == false` in the accessibility tree) and sets "In progress"; it does
  not dim. `GroupedRow.action`/`.destructive(…, busy:)` only swallow taps (`allowsHitTesting(!busy)` + guard), so they
  stay *enabled* for VoiceOver: prove "no tap" by `node.activate()` + `settle()` and checking nothing happened (no
  alert, the API call count unchanged).
- Hosted busy tests: forms take `showsBusy: true` (LogIn, CreateAccount, ForgotPassword, SetNewPassword,
  HealthPermissionView); live holds use `MockPlatformAPI.beforeInvite` / `beforeConsent` (+ `Gate`), CheckInbox takes an
  injected `InboxResendModel` (`resend:` is internal). Suite: `RyftTests/BusyKeepsTitleTests.swift`.
- Deliberately left: `InlineMessage`'s text retry "Trying again…" (A §a-17 designs a gerund text button, no spinner:
  needs design), DEBUG catalog "Playing…", every row value/status ("Saving…", "Syncing…", "Reading…", "Importing…").
- Train history formatters: `Fmt.kg/volume/load/strain/distance(…, locale:)` default `.autoupdatingCurrent`.
  `Fmt.kgNumber` keeps a separate one-argument overload because the live workout passes it as a function
  (`map(Fmt.kgNumber)` in SetRow, SetColumn, RestTimerView, EditTargetsSheet, ExercisePage): a defaulted parameter
  breaks every such reference. Grep `Fmt\.\w+[^(]` before adding a parameter to any `Fmt` function.
- `Week.summary` is now `summary(locale:)`; `RecentRow` has `var locale` (memberwise init, last); `E1RMChange.text/spoken`,
  `SessionDetailContent.text`, `SetText.short` take `locale:`. Views pass `@Environment(\.locale)`; `E1RMChart` gained it.
- Proof recipe: German region inside the sim only (`xcrun simctl spawn <udid> defaults write -g AppleLocale -string
  en_US@rg=dezzzz`), run T6B.5 + shots, reset to `en_US`, `simctl shutdown` + `boot`. A fresh sim already inherits
  `en_US@rg=dezzzz` from this Mac. Before the fix 12 issues in 5 tests; after, 40/40 including the German-locale test.
- `LaunchSequenceUITests.testATapSkipsIt`: on a loaded runner `launch()` can return after the whole 5.2 s + 0.4 s
  sequence; the test now waits sequence + 5 s and relaunches up to 3 times until the overlay is seen.
- Area A shots (`SignedOutOnboardingShotsTests`, `TEST_RUNNER_A_SCREENS_DIR`) gained `a-10-about-you-missed` and
  `a-11-apple-health-busy`.
