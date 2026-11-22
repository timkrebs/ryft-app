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

**Round 2 (review fixes S1–S4, S-1, N-1..N-3, N1–N3; 9 commits 0333e50..1ed48f3):**
- Ask-again deadline: `askAgain(since:)` races `readUserBack` against `checkTimeout` in a task group. A cancelled
  ReadScheduler waiter only resumes itself (`Outcome.release`): the flight and its store go on.
- Gate holds while `agreedVersion != nil` (S3). `ConsentState.standingAgreement` voids one with `at > now` (N-3);
  `pendingAgreement` = standing and unsettled; `agreement` stays the raw record.
- One rule for gate holds on screen: `SyncIdleState.held(at:pendingGate:)` (sync, Train outbox, import via
  `ImportFlowModel.Dependencies.pendingGate`, wired in ScreenModels → ImportCoordinator).
- SyncService is another team's file: the scoring wait's R2 keeps the door's asked time in `LiveSyncSteps.asked`.
- `TestClock.set(_:)` moves the wall clock without waking sleepers. With it set back, the policy answer (answeredAt at the
  agreement) is stale → `.policyUnknown`, and `ConsentState.received` drops config answers older than the stored one.
- `ready()`'s check leaves the mock status' `consent_required` as serverGate: a late /v1/me with the consent needs a
  forced check before the flow moves on.
- Staging part of a file: `git apply --cached --unidiff-zero` with skipped -U0 hunks MISPLACES later insertions (put a
  func inside a property). Use scratchpad `consent/hunks.py stage` (applies hunks bottom-up on `git show :file`, then
  `git update-index --cacheinfo`), and `swiftc -parse` each commit's files.
- `sync-strings.py --derived-data <path> --check` when not using build/DerivedData. The Bash tool's shell is zsh:
  `${PIPESTATUS[0]}` is empty, and `--include=*.swift` must be quoted.

**Round 3 (S-1, code 1–9, N1/N2, words by cause; 9 commits fd4590f..3e9aa14 on d1240d3):**
- `Facts.withdrawing` (from `isWithdrawing`) closes `gate` for data, after the erasure line; `missing` ignores it.
  The withdrawal's `askAgain(since:settles: false)` → `readUserBack(since:settles:)` → `store(fetchedUser:askedAt:settles:)`
  → `ConsentState.heard(_:askedAt:settles:)`. A void agreement (at > now) is settled by any heard /v1/me.
- A message tied to a step: `ObservationWatch(read: { _ = self?.missing })` set after the failure, cleared by
  `clearError()`; tests need `eventually` (the watch acts on the next main-actor turn).
- Status asked time: `AppState.setSyncStatus(_:askedAt:)` (didSet on `syncStatus` clears it), used by
  `LiveSyncSteps.scoringGate` after its own `asked`; `statusReceived` is `(SyncStatus, Date?)`.
- Pause words: `SyncIdleState.PauseCause.of(_:agreementUnsettled:)` shared by Sync details and the import
  (`Dependencies.agreementUnsettled`, set in ImportCoordinator.makeFlow from env.consent).
- Profile's Check with RYFT: `OnboardingCoordinator.confirmAgreement()` = `check(userInitiated: true)`; seed a
  Retry-After with `env.reads.seed([.me: ResourceState(retryNotBefore:)])` to prove it.
- Splitting interleaved test additions across commits: scratchpad `consent/r3_tests.py <k>` reverts later commits'
  pieces (whole test funcs, single lines) from the final copy; order the appended tests by commit first.
- Mutants must build warning-free (strict warnings = errors, and test-without-building would test the stale build):
  keep a removed binding used (`|| env.clock.now() < .distantPast`, `stored.flatMap { _ -> Date? in nil }`).
- "Clear when X leaves `missing`" is a transition: capture `missing.contains(.consent)` at the tap. Hosted ConsentView
  tests (SignedOutOnboardingTests) run with no user known, so `missing` is [] all along; an "absent now → clear" rule
  wiped their policy-updated sentence. Focused suites missed it; only the full Unit plan caught it: run it before mutants.

**Round 4 (security S-2, N-a, N-b; code S, 3–7; UI; 9 commits 3132f4b..2806fa5 on 999477e):**
- Unanswered withdrawal: `ConsentState.withdrawalUnresolvedSince` in defaults (`consent.withdrawal.unresolved.<account>`)
  → `OnboardingCoordinator.withdrawalHolds` feeds `Facts.withdrawing`. Ends in `heard` (askedAt >= since), `withdrew`,
  `consented`, and `switchAccount` (old account only). `check`/`reconnected` ask while it's set, since max(agreement,
  unresolved). Harness: `h.relaunched(online:)` proves persistence.
- `awaitsConfirmation` (ConsentState: unsettled && no unresolved; coordinator: && !isWithdrawing) drives the pause
  words; Privacy's `consentAwaitsConfirmation` stays as is (`withdrawingConsent` depends on it).
- `check()` stays Void: with a return value, `Task { await check() }` becomes `Task<(any Error)?, Never>` and the
  tests' `await task.value` is an unused-value warning (= error under strict warnings), @discardableResult or not.
  The failure comes from a private `runCheck` → `confirmAgreement() -> AgreementCheck` (.confirmed /
  .unconfirmed(failure:)).
- Check failure words: transport/URLError = "RYFT didn't answer"; else `fallbackMessage(for:)` (APIError's 429/503).
  A fault `.status(429, retryAfter: 600)` fails at once (over the read cap), with requestID "fault-<key>".
- Keyed string: `String(localized: "syncdetails.workouts.paused", defaultValue: "Paused", comment:)`; tests compare to
  a static (`SyncDetailsModel.workoutsPausedText`), not a fresh `String(localized:)` of the key.
- "Read the policy" as one unit: replace spaces with U+00A0 at runtime, keep the catalog key.
- MockDevicesStates.graph(workoutsAwaitConfirmation:) = consented + Train gate .consentRequired + an onboarding for
  Sync details; queue a workout with `g.train.finish(SessionFactory.empty(in: g.store))`.
- mutant.sh got `DRY=1` (pattern check only) and all_mutants.sh `ONLY=`; re-dry-run after every fix: N-b's edit
  silently broke r3-settle's pattern.
- Never edit `mutant.sh` while `all_mutants.sh` runs: bash reads a running script by byte offset, so a longer
  line above the current point gave a syntax error mid-mutant, which skipped its revert (`git checkout -- Ryft`) and
  made the next mutant refuse a dirty tree. Fix patterns after the run, then `ONLY="…" all_mutants.sh`.
- A mutant that drops a binding's use (`.unconfirmed(failure: nil)`) fails strict warnings; keep it used
  (`failure.flatMap { _ -> (any Error)? in nil }`).
