# Refresh resilience — plan

Brief: `CLAUDE_FOLLOWUP_REFRESH_RESILIENCE.md` (TestFlight 1.0.0 `20261021.141128`, iPhone17,1, iOS 27.0.1,
2026-10-21 18:12). This is a stability release with no new features. Lead: this session. Reviewers per `docs/AGENT_FLEET.md`.

## Constraints found while planning
- `Ryft/` and `RyftTests/` are still **classic groups**: a new `.swift` file there isn't compiled without
  editing the pbxproj, which isn't allowed. New types go into existing files, close to the code that
  uses them. (Converting the groups to folders is still on the user's list.)
- Four PRs are open (#17, #21, #22, #24). Every ticket here branches from `origin/main` (`99f6edb`) in its
  own worktree, and none of them touches those PRs' files beyond shared docs.
- Rate limits (`API.md` → Conventions): per user, bursts of 60 and then 10/s; per IP at the edge, 20/s with
  bursts of 50 and a plain-text `429` body. The API gets 15 s and then `503 "request timed out"` with
  `Retry-After`. `APIClient` already retries `429`/`503` once.
- What the screenshot shows: tiles and gauge both read `state.today?.score` (`TodayViewModel.facts`), and
  `calibrating` is decoded from the platform (no default `true`). So a row with `recovery: 75` and
  `calibrating: true, baseline_days: 0` reached the screen. That comes from the platform or from our
  read-model round trip, and T0 decides which.

## Where it stands (2026-10-22)

| # | PR | Review | CI | State |
| --- | --- | --- | --- | --- |
| T3 | #26 `feat: report a problem with diagnostics` | approved (code, security, UI, l10n) | green | **merged** (c34bb9a) |
| T2 | #28 `fix: one consistent Today state` | approved (code, UI, l10n) | green | **merged** (9745392) |
| T1 | #27 `fix: refresh per resource with silent retries` | approved (code, security, perf, UI, tests) | green (UI smoke timeouts before were the runner) | **merged** (d7996f5) |
| T5 | #31 `feat: send a refresh problem to RYFT` | approved (code, security ×2) | green on 31b025c; CI on 64a968d running | `main` merged in (7de4bdd = 31b025c + #30); **ready**, next to merge |
| CI | #30 `ci: UI tests get 180 s before they count as hung` (UISmoke + nightly Full) | lead | green | **merged** (1864e28) |
| T4 | #29 `docs: refresh resilience` (draft) | — | docs only | `main` merged in; last, after #31 |

## Tickets

| # | PR title | Owner | Brief | Depends on | Worktree / branch |
| --- | --- | --- | --- | --- | --- |
| T0 | (no PR; incident write-up goes into T4) | debugger | §0 | — | `wt-debug` · `debug/refresh-repro` |
| D1 | (design note) | ios-architect | §1, §2 | — | `wt-docs` → `design.md` |
| D2 | (UI spec) | ui-designer | §1–§4 states | — | `wt-docs` → `ui.md` |
| T1 | `fix: refresh per resource with silent retries` | sync-engineer → test-engineer | §1, §3 | D1, D2, T0 | `wt-refresh` · `fix/refresh-per-resource` |
| T2 | `fix: one consistent Today state` | ios-developer → test-engineer | §2 | D1, D2, T0 | `wt-today` · `fix/today-consistent-state` |
| T3 | `feat: report a problem with diagnostics` | ios-developer → test-engineer | §4 | D2 | `wt-feedback` · `feat/report-a-problem` |
| T4 | `docs: refresh resilience` | lead (+ localization-editor for notes) | §0, Ship | T0–T3 | `wt-docs` · `docs/refresh-resilience` |

Order: T0, D1 and D2 run in parallel. Then T1, T2 and T3 run in parallel, each in its own worktree
(the shared files `AppState.swift`, `TodayViewModel.swift` and `Repository.swift` are split by region, see
below). Each branch gets test-engineer on the same branch after its implementer finishes, then the
reviewers in parallel, then fixes and the PR. T4 goes last.

**Who writes which region** (classic groups mean shared files, so the split is by region, not by file):
- T1: `Repository` refresh functions and per-resource state; `AppState.refresh` / `refreshDays`;
  `APIClient` retry; `TodayViewModel.status` and `refresh()`; `TodayStates.line` (the stale line).
- T2: `TodayStates.hero` and the new `TodayState` decision; `TodayViewModel.facts` and the tile and trend
  accessors; `DailyScore.empty` and its uses; the widget snapshot's calibrating branch
  (`Repository.swift` ~L560–590); `TodayView` gauge and tiles.
- T3: Profile → Report a problem (inside an existing Profile file); `PlatformAPI.postFeedback` plus the demo
  and fake APIs; a feedback queue for offline; the "Send to RYFT" entry point (T1's Details sheet calls it
  through a closure, so whichever merges second wires it up).

Simulators, one per worktree, so parallel test runs don't share a device: debug → iPhone 18 Pro Max,
refresh → iPhone 18 Pro, today → iPhone 17, feedback → iPhone Air, ui-validator → iPhone 17e.

## T0 — root cause (debugger)
- Reproduce pull-to-refresh during a sync in demo mode with fault injection (add a DEBUG-only seam if none
  exists: launch argument `-RyftFault <path>=<status|timeout|cancel>`). Inject `429`, `503`, timeout,
  `404` and **cancellation** (`.refreshable` cancels its task when the view's identity changes; a
  `URLError.cancelled` / `CancellationError` must never show as a failure).
- Prove which call fails in the reported situation and why the whole refresh turns into the error.
- Item 3: decide (a) unscored today, (b) the platform's `calibrating: true, baseline_days: 0`, or (c) a
  read-model round trip that loses `baseline_days` / `calibrating`. Prove it with a test.
- Trends "— vs 7 d" with a full line: why `MetricDelta.vsSevenDayMean` returns nil.
- Accept: a written root cause per item with file:line, each with a failing test committed on
  `debug/refresh-repro` that T1/T2 cherry-pick, plus the one evidence request for the user.

## T1 — refresh that degrades gracefully (sync-engineer)
Acceptance criteria (test-engineer turns each into a test):
1. Each read (`day`, `history`, `me`, `sync status`, `trends`, `insights`, `journal`, `config`, Train) succeeds
   or fails on its own. A failure of one leaves the others updated, and no error card appears.
2. The repository keeps `fetchedAt`, `lastError` (status, `code`, request ID, at) and `consecutiveFailures`
   per resource. Success resets the count.
3. Transient failures (`transport`, `5xx`, `429`, timeout) retry at most 2 times in a foreground refresh,
   with exponential backoff and jitter, honouring `Retry-After` (capped). Covered by tests with `TestClock`,
   with no real sleeps.
4. Cancellation is never a failure: no count, no `lastError`, no card.
5. Order: pull-to-refresh (1) starts the coordinator's upload, (2) at once fetches `today` and `GET /v1/me/sync`,
   (3) fetches the rest after the upload ends or after 2 s, whichever comes first, with at most 3 requests in
   flight and never a burst of more than 5.
6. Coalescing: a second refresh of a resource that's in flight joins it (one request).
7. An error is shown only when (a) the same resource failed ≥ 3 times in a row **and** what's on screen is
   older than its stale threshold (today 2 h, history 24 h), or (b) the error is one the user can act on
   (signed out, gate, consent, app too old). Offline is never an error.
8. The line: "Syncing · sleep" → "Scoring your night" → "Up to date · just now"; past the threshold
   "Showing data from 14:05 · Try again". Tapping it opens Sync details.
9. The error card is calm and shows the reason, "Showing data from 14:05", **Try again** and **Details**
   (resource, status, code, request ID). Strings are in en + de.
10. Sync details / Copy diagnostics list the per-resource state.

## T2 — one consistent Today (ios-developer)
1. One function `TodayState.decide(…)` returns gauge, tiles and note together. It's tested as the brief's
   decision table, including the screenshot's inputs (unscored today with scored history → pending, never
   "0 of 7").
2. `DailyScore.empty` no longer carries `.calibrating`. An unknown day is `unknown`, a distinct state. Every
   use is audited (copy, tiles, widget snapshot, Trends).
3. `Baselines · n of 7` uses `baseline_days` of the **latest scored** day, never an unscored row's.
4. When the platform says calibrating but history has ≥ 7 scored days, show the readiness of the latest
   scored day plus a "Recalculating" note, and file the platform bug (T4).
5. Pending: yesterday's values dimmed with their date in the tiles, and last night's raw sleep labelled
   unscored.
6. Trends: with a 7-day line the delta shows; otherwise the "— vs 7 d" placeholder is hidden.
7. The widget snapshot follows the same decision.
8. Previews for every row of the table, dark and light. Screenshots are compared with the brand board.

## T3 — report a problem (ios-developer)
1. Profile → Report a problem: message, category (`FeedbackCategory`) and an "Include diagnostics" toggle
   (on by default). The diagnostics are app version and build, device, iOS, the last 20 requests (method,
   path, status, `code`, request ID, duration), per-resource `fetchedAt`/`lastError`, engine state, gates and
   flags. No health values.
2. `POST /v1/feedback` per `API.md` (body ≤ 64 KiB, `204`, `429` after 10 a day). When offline, the report is
   queued and sent on reconnect.
3. The error card's Details sheet has "Send to RYFT", which opens the report pre-filled.
4. Tests: payload shape against the API.md example, the size cap, the queue, and no health values in the
   diagnostics.

## T4 — docs
`docs/STATUS.md` (Incidents, device checks), `CHANGELOG.md` → Unreleased (the brief's sentence),
`docs/TESTFLIGHT_NOTES.md` en + de, `docs/TESTFLIGHT.md` (Report a problem), `docs/API_REQUESTS.md` if T0
finds (b), and this plan and the review log.

## Risks
- Three branches touch `TodayViewModel.swift`, so merge conflicts are expected. They're kept to separate
  regions, and the second and third PRs merge `origin/main` before review.
- Silent retries can hide a real outage. That's why the count and `lastError` are kept and shown in Sync
  details, and why the error appears after the threshold.
- A retry inside the foreground refresh plus `APIClient`'s own `429`/`503` retry could multiply. There must
  be one retry layer for reads (D1 decides which).
- Fault injection must be compiled out of Release.

## Needs the user (collected as we go)
- (T0) Profile → Data sources → Sync details → **Copy diagnostics**, pasted here, plus the platform commands.
- (T0, if b) Paste `API_REQUESTS.md` → the rescore request into the platform session.
- Device checks after T1 and T2: pull-to-refresh during a sync 5×, toggling airplane mode, force-quit and
  reopen in the evening before the night is scored.

## Decisions (lead)
- **UI-1 "App too old":** `API.md` has no signal for it (no code, no status, nothing in `/v1/config`). The card class
  is **not shipped**. T4 files `API_REQUESTS.md` → "minimum app version" (e.g. `GET /v1/config` →
  `min_app_build`, or a `426`/`app_too_old` code). The copy stays in `ui.md` for later.
- **UI-2 Trends delta:** pending T0. If the "—" is the flat case (< 2 %), "Steady vs 7 d" is approved. If the
  delta is nil, nothing renders (the brief says to show it or hide the placeholder).
- **UI-3 Feedback size:** we design to `API.md`, which says `diagnostics` ≤ 32 KiB (any JSON object) and
  `request_ids` ≤ 20. The plan's "≤ 64 KiB" was the general body limit. `FeedbackPost.diagnostics` may become
  a JSON object if `API.md`'s Swift mirror allows it; otherwise the values are strings.
- **UI-4 Two sleep figures in row C:** kept as the brief asks (yesterday's scored tile, dimmed and dated, plus
  last night's raw card labelled "not scored yet"). ui-validator judges whether it reads as a contradiction.
  If so, the Sleep tile shows "—" in row C.
- **UI-5 Motion:** `quick` for the hero cross-fade, and nothing under reduced motion.
- **UI-6 Contrast:** ui-validator measures the dimmed `textTertiary` numbers in light mode (≥ 4.5:1 for the
  value text or it moves to `textSecondary`).

## T0 result (debugger, `debug/refresh-repro`: 4b7c83c seam · fd1f070 refresh · 1462944 calibration · 721d9cf delta)
- **All-or-nothing: confirmed.** `AppState.refresh` awaits `(day, days, me)` in that order, and the first one that throws
  skips trends and insights and sets `state.error`. `refreshDays` (after a sync or silent push) sets it too and rethrows.
- **Likeliest field failure: a transport-class error, most likely cancellation.** The card had no Details, and
  Details exists only for `APIError.http`, so it wasn't a 429/503/404. `APIClient` wraps `URLError.cancelled` in
  `.transport`. A cancelled `Task.sleep` throws a raw `CancellationError`. Neither is filtered. Other
  candidates are a 60 s URL timeout (`waitsForConnectivity`) and a decode failure. Transport failures aren't
  recorded in `APIStatus.requests`, so Copy diagnostics can't show them. The device evidence is still to come.
- **"0 of 7": verdict (b), medium confidence.** (a) is ruled out: unscored or `.empty` rows decode `calibrating = false`. (c) is
  ruled out by round-trip tests. The platform sets `calibrating` when either baseline's N < 7
  (`baseline_days = min(N_lnHRV, N_rhr)` over the 30 scored days before), and it still scores recovery and readiness.
  Migration 0006 defaulted `baseline_days` to 0 "until rescored". So either today was scored before the earlier
  days (ordering or merge), or the user has no HRV or resting HR (N = 0 every day). The app has its own share of the bug:
  `hero` puts `calibrating` ahead of a score without looking at scored history, and the widget disagrees
  (`ReadinessSnapshot.make` → `.score`).
- **"— vs 7 d" isn't nil.** It's a flat delta (< 2 %), which `DeltaLabel` renders as "—". UI-2 is decided: **"Steady vs 7 d"**.
- **Feedback:** no `postFeedback` exists and nothing calls it. Pull-to-refresh goes through `ScreenModels.pullToRefresh`.
  `TodayViewModel.refresh` is only Retry.

**Adjustments:** T1 adds criteria 11 (cancellation, from `URLError.cancelled` or `CancellationError`, is
classified as cancellation in `APIClient`, not `.transport`) and 12 (transport failures are recorded in
`APIStatus.requests` with duration). T2's row 4 note keeps its reason in an enum, so it can say "no HRV yet"
instead of "Recalculating" once the platform says why (`API_REQUESTS.md`).

## Decisions on D1's open questions (lead)
1. **App too old:** reserved (`FailureKind.appTooOld` is never produced). T4 files the `426 app_update_required` / `min_build`
   request. This agrees with UI-1.
2. **Row D trigger:** accepted. `vitals ≥ 7` (nights with HRV and RHR among the 30 prior scored days), not just scored
   days. **In addition (lead):** row 4 (B) gets a note when the history isn't short but the vitals are, i.e.
   `prior.count ≥ 7 && vitals < 7`. The note is `Note.needsVitals` → GaugeNote "Baselines need heart-rate variability
   and resting heart rate from nights with your watch." That way a long history with no HRV never reads as a bare
   "0 of 7 nights" with no reason given. If T0's evidence shows the reporter has no HRV, this is the row they'll see.
3. **Nothing cached → card after 1 failed pass:** accepted.
4. **Journal, config, Train:** scheduled, but left out of pull's phase 3. Accepted, and the deviation from the brief is noted here.
5. **Persist per-resource state:** accepted. No health values go in it.
6. **T0 tests:** they are already separate commits. T1 cherry-picks `4b7c83c` (seam) and `fd1f070` (refresh). T2 cherry-picks
   `1462944` (calibration) and `721d9cf` (delta). Neither T2 commit uses the seam.
7. `ui.md` wording: fixed by the lead (errata at the top of `ui.md`). Where the two differ, `design.md` §7 is authoritative
   for the decision table.

Base moved: `origin/main` is now `858fb45` (#21, #22 merged). Every ticket worktree was fast-forwarded before work started.
