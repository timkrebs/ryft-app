# 0001 — One retry layer for reads, above `PlatformAPI`

- Status: proposed (2026-10-21, refresh resilience, `docs/work/2026-10-21-refresh-resilience/design.md`)
- Deciders: ios-lead, on ios-architect's proposal
- Applies to: `Networking/APIClient.swift`, `Networking/APIStatus.swift`, `Persistence/Repository.swift`,
  `Environment/AppEnvironment.swift`, `App/AppState.swift`, `Sync/SyncCoordinator.swift`

## Context

TestFlight 1.0.0 showed "Couldn't refresh just now" after a pull to refresh while a sync ran. Retries for
reads happened in several places, none of them suited to reads:

- **`APIClient`** retries a `429` once (up to 60 s) and a `503` up to three times (up to 30 s each), for every
  method. It doesn't retry transport errors or timeouts. It waits with its own `Task.sleep`, not
  `AppEnvironment.clock`.
- **The upload** (`SyncCoordinator.uploadWithBackoff`) retries transport errors and 5xx again on top of that.
- **Nothing above `APIClient` retried a read.** One failed read failed the whole refresh, because
  `AppState.refresh` ran `try await (day, days, me)`.
- **Demo mode and the unit tests run on `MockPlatformAPI`.** It never goes through `APIClient`, so a retry
  there can't be exercised by `AppEnvironment.test` or by the demo UI tests.
- **Reads come from many places at once:**
  - pull to refresh;
  - the sync pipeline;
  - `.task(id: lastUpdated)` reloads in Sleep, Insights, the journal and Bedtime;
  - Train;
  - flags;
  - onboarding.

  Nothing coalesced them or bounded them against the platform's rate limits (per user: bursts of 60, then
  10/s; per IP: 20/s). `.task(id:)` cancellations arrived as `APIError.transport(URLError.cancelled)` and
  counted as failures.

Each read needs to succeed or fail on its own, retry silently with backoff and jitter, honour
`Retry-After`, coalesce, stay within at most 3 in flight and at most 5 starts per second, and tell
cancellation from failure. All of that has to be testable on `TestClock`.

## Decision

1. **`ReadScheduler` is the only place that retries a read.** It's `@MainActor @Observable`, one per
   `AppEnvironment` (`env.reads`). It sits above `PlatformAPI`, so it behaves the same for `APIClient` and
   `MockPlatformAPI`. It does five things:
   - coalesces by `ReadKey` (`ReadMode.latest` joins a fetch in flight; `.changed(since:)` joins only one
     started after the change, else one shared follow-up);
   - classifies every failure (`FailureKind`: transient, cancelled, signed out, gate, app too old, other);
   - retries transient failures by `RetryPolicy`: foreground 2 retries, background 1, full jitter,
     `Retry-After` honoured up to a cap, and `retryNotBefore` beyond the cap;
   - records the outcome per `ReadResource`: last success, last error with status, code, request ID and kind,
     and consecutive failures (persisted per live account);
   - runs each fetch in a task it owns, so a caller's cancellation never cancels or fails a shared read.
2. **`RequestBudget`** (an actor) admits scheduled reads. It allows at most 3 in flight and at most 5 starts in
   any 1 s window, with high priority first (today, `GET /v1/me/sync`). A slot is released during a backoff.
3. **`APIClient` makes one attempt for a scheduled read** (and for `POST /v1/feedback`).
   The scheduler sets the task-local `APIClient.$singleAttempt`. With it set, `exchange`:
   - skips its `429`/`503` loop;
   - puts `Retry-After` on `APIError.http(…, retryAfter:)`;
   - uses the fail-fast session;
   - doesn't post `APIStatus.retryNotice`.

   The `401` refresh-once stays, because that's authentication, not a retry. `URLError.cancelled` is rethrown
   as `CancellationError`.
4. **What doesn't change yet:**
   - GETs that aren't scheduled keep `APIClient`'s loop, so nothing regresses;
   - writes keep it too;
   - `POST /v1/sync` keeps both its layers.

   One request never sees two retry layers, because the task-local switches `APIClient`'s loop off exactly
   when the scheduler retries.
5. **Whether staleness or an error is shown** is decided by pure functions over the recorded states:
   `RefreshPolicy.staleSince` for the status line and `RefreshPolicy.issue` for the card.
   Nothing writes a screen-wide error string any more (`AppState.error` is removed).

## Consequences

**Good:**
- One policy, tested on `TestClock` with an injected random source.
- The demo UI tests exercise the real retry path, because fault injection (`-RyftFault`, DEBUG only) sits in
  `MockPlatformAPI`, below the scheduler.
- Per-resource diagnostics come for free: Sync details, Copy diagnostics, Report a problem.
- Bursts are bounded wherever a read comes from.
- Cancellation stops being a failure.

**Costs:**
- `APIError.http` gains a fifth associated value, so 15 pattern sites change.
- The scheduler is one more type on the read path.
- During the migration two retry implementations exist side by side (scheduled, and `APIClient`'s legacy
  loop), even though no single request is retried twice.
- Read decoding still runs on the main actor (pre-existing), and this decision doesn't move it.

**Follow-ups:**
- Schedule the remaining GETs (workout detail, exercise history, sleep plan, plan detail, sessions list), then
  delete `APIClient`'s loop for GETs.
- Revisit the upload's stacked retries (`APIClient` 429/503 × `uploadWithBackoff`).
- Decode responses in a `@concurrent` function.
- Key the `.task(id: lastUpdated)` reloads on a refresh generation instead of today's fetch time.

**Rejected alternatives:**
- **Retries inside `APIClient` only.** One place for every endpoint, and `Retry-After` stays local. But it has
  no resource identity, so no coalescing and no per-resource state. Demo and tests bypass it. It can't release
  a limiter slot during a backoff. It can't tell a user watching from a screen revalidating.
- **Retries per call site** (each `refresh*` or view model). That repeats the policy and multiplies requests,
  which is the situation we started from.
