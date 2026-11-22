---
name: Consent agree lag (C1-C3, ADR 0025)
description: Agree moves on at the 204; agreement in ConsentState; R2 in both status doors; ReadScheduler.runAsked; fail-fast consent POST; test seams and pitfalls
type: project
---
Work: docs/work/2026-11-22-consent-agree-lag (branch fix/consent-agree-lag, 2026-11-22). Commits: C1 measurement
(AgreeTiming.swift: agree line, Signposts.onboarding, APIClient attempt/retry-wait, AppAttestor first-token-wait), C2
(ConsentState.Record.agreement {version, at, settled}; missing counts it, gate never; readUserBack after perform; R2),
C3 (failingFast helper shared with the withdrawal; no answer → readUserBack(since: sentAt)), tests ConsentAgreeTests.

**Why / how to apply (code facts that took digging):**
- ReadScheduler: the first `store` given to a flight wins; a joiner's store never runs. To learn a flight's start without
  stealing the sync poll's store, use `reads.runAsked(...)` (Outcome.started, set by `start` and `followUp`).
- `Repository.store(user:)` is written through: `user()` shows it in the same step, and `ConsentState.heard` runs at
  submit, before the commit. Settling there causes no flicker of the consent step.
- `.changed(since:)` joins the flight in progress and then follows up: a withdrawal's re-check waits behind a held
  `/v1/me`. Hold only the first call (`FirstCallsHold` in ConsentAgreeTests) and run the withdrawal in a Task.
- PillButton runs its async action in an unstructured Task: the consent step going away doesn't cancel `agree`.
- `Flight` = binding + turn; `turn` changes only in `switchAccount`, never for a withdrawal.
- A 503 on a fail-fast write already gets APIError's words via `fallbackMessage`/`hasOwnWords`: no new string needed.
- `make style`: SwiftLint's line_length ERROR is 280 (warning 160). A long Regex literal in a template dict fails it;
  build it with `try Regex(#"…\#(part)…"# + …, as: Substring.self)`.
- Gate runner: never pipe `run.sh` into `head`: "gate wait" lines fill it, and its output is lost (the run continues).
- ProfileWithdrawalHoldTests' hosted `w.settle()` can time out under load (load5 > 150): rerun alone before blaming code.
- A harness with `demoOverride: nil` (to switch Demo data mid-test) must set `settings.demoMode = false` first: it is ON
  by default in the simulator (`Settings.demoDefault`), and then `missing` is empty.
- `env.connectivity` is `any Connectivity`: keep the `ConnectivityMonitor.preview(online:)` you pass in, to `update(_:)`.
- A private test type behind `typealias H = …` in a suite needs `fileprivate typealias`.
- Mutants: dropping agree's Flight check after the re-read is caught only by `agree`'s return value (reads are cancelled
  on the switch, `AgreeTimer.save` checks the account, `startSync` needs `read`): defence in depth, say so.
- Fixing an earlier local commit: `git commit --fixup=<sha>` + `GIT_EDITOR=true git rebase --autosquash <base>` works
  without -i on git 2.56; check `git rev-parse HEAD^{tree}` equals the tree you expected.
