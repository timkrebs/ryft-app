# Reviews: the first run (PR 2)

PR 3's reviews are in the same file on `feat/health-groups` (#144).

## PR 2, #145 (`feat/first-run`), round 1 (2026-11-23)

### Before the PR (screenshots and strings pass)
| # | Severity | Finding | Status |
|---|---|---|---|
| P0a | blocking | `HealthPermissionView.swift:94` dropped "unless you turn on saving strength workouts", so the screen said RYFT writes nothing to Apple Health, which is false with strength saving on | fixed (16daca0) |
| P0b | blocking | `TodayStatesUITests:52` asserted the removed "Tell me when my first scores are ready" | fixed (16daca0) |
| P0c | should-fix | ui.md §3/§4/§6: from AX1 the actions should end the page; they stayed pinned (about 40 % of the screen at AX5) | fixed (16daca0): an `actions:` slot on `OnboardingScreen`; `pinnedBar` unchanged |
| P0d | — | The footnote looked clipped in the shots; this was a bug in the shot tool (`PagedWindowShot`), not in the app | fixed (16daca0) |

### code-reviewer
| # | Severity | Finding | Owner | Status |
|---|---|---|---|---|
| C1 | blocking | `NotificationPrimerExample.swift:13,:91` (`RyftApp.swift:623`): `choose`/`counts` ignore `notifications.reminders` (off by default; #141's `ReminderScheduler` sends journal and sync-stale reminders only when it's on). With push off and reminders dark, the primer shows a notification that can never arrive and asks for a permission nothing uses | ios-developer | fixed (e05a56c): `choose`/`current(flags:)` read `push.enabled` and `notifications.reminders` (`known`, as `ReminderScheduler`); no example, no primer, one step fewer; ui.md §4.3 corrected |
| C2 | should-fix | `OnboardingCoordinator.swift:366–369, :412`: the plan is taken while `userKnown` is false (the first check timed out or was offline), so About you and wear drop out of the count and show later with no step rule | ios-developer | fixed (e05a56c): `takePlan` waits for `facts.userKnown`; test `noPlanBeforeTheUserIsKnown` |
| C3 | nit | `NotificationPrimerExample.swift:84` counts `.provisional`; §4.3 says provisional skips the primer | ios-developer | fixed (e05a56c): only `.notDetermined` asks; provisional in the tests |
| C4 | nit | `OnboardingTrackerSteps.swift`: `.task { syncRuns = … }` shows the "not syncing" lead for one frame, then swaps it | ios-developer | fixed (e05a56c): no lead until `syncRuns` is known |
| C5 | nit | The catalog keeps the unused `"Tell me when my first scores are ready"` | ios-developer | fixed (e05a56c): key removed (1 line); only the UI test's absence check names it |

### security-privacy-reviewer
| # | Severity | Finding | Owner | Status |
|---|---|---|---|---|
| S1 | should-fix | `PushRegistrar.swift:154, :179-180`: `accept()` (now on every new account's path, via the primer) and `send()` register without `!isInviteBlocked`. The code reviewer judged the primer unreachable behind an enforced gate; **lead decision: guard anyway** (one line, matches `refresh()`, closes the disagreement) | ios-developer | fixed (e05a56c): `accept()` and `send()` check `!isInviteBlocked`; test `continueBehindTheInviteGate` |
| S2 | note | `push.primerAnswered.<account>` stays in UserDefaults after account deletion; add it to the deletion cleanup with `dismissCount` | ios-developer | fixed (e05a56c): `PushRegistrar.forgetAnswers` at deletion; no `dismissCount` cleanup existed, so all four push keys go; test `PushAnswersDeletionTests` |

### ui-validator
- All 12 shots pass the spec. The notification example has no health value. At AX5 the actions end the page.
- **Lead decision:** the Health footnote keeps "RYFT writes nothing to Apple Health unless you turn on saving strength workouts…" although ui.md §3 moves that sentence to Profile. Without it the screen's claim is false; the spec gives way.
- The lock-screen clock reads "07:30" on a German-region Mac and "7:30" in the US: the format follows the region. Accepted.
- Nits outside this PR: tracker tile names break mid-word at AX5; the import card's "readings" wraps at AX5.
- Not verified: live VoiceOver, the primers and step rule running in the app (`-RyftScreen` has no case for them, and the step rule is nil in demo), the real system sheets. These are device items.

### The two AX3 failures
- `NocturneGateSweepHostedTests.importCardStepsAtAX3()` also fails on `main` (2e85e38), with identical numbers. It is not from this PR; it's a follow-up.
- `SignedOutOnboardingTests` passes on this branch and on `main` on an iPhone 17 Pro; it didn't reproduce.
