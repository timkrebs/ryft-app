# Review: analytics allow-list (2026-11-27)

One code-review pass (code-reviewer) and one privacy review (security-privacy-reviewer), both read-only, on the
first commit.

## code-reviewer: no blockers

| # | finding | severity | outcome |
|---|---|---|---|
| C1 | `nutrition_search_completed` fires again every time the search page reappears (`.task(id:)` restarts after Back, Add to meal, Edit amount or private food), and the cached refetch lands in `lt_250` | should-fix | fixed: `reportedSearch` tracks once per `SearchTask` (a Retry still counts) |
| C2 | No tests for the call-site helpers (`unitMode`, `isFractional`, `openedEvent`, sync statuses), so A6 is unproven | should-fix | fixed: `NutritionLogContextTests`, plus the skipped sync case where the rig allows |
| C3 | `sync_completed` waits for the coordinator's score wait (up to 300 s), so `duration_ms` measures platform scoring; `waitingForUnlock` counts as success | should-fix | fixed: the duration ends when the spinner phase ends; `deferred` added for a locked HealthKit |
| C4 | Rank falls back to 1 when the food isn't in `matches` | nit | fixed: no event then |
| C5 | `results_count: 21+` can't happen (pages and barcode results are capped at 20) | nit | kept: harmless; documented that `11_20` includes a full page |
| C6 | Latency uses `ContinuousClock`, not `env.clock` | nit | fixed |
| C7 | The length is checked twice in `isUnsafeValue` | nit | fixed |

## security-privacy-reviewer

| # | finding | severity | outcome |
|---|---|---|---|
| P1 | The policy says "anonymous"; a lasting install id plus the IP PostHog sees is pseudonymous | blocker (#252 text) | fixed in `docs/ANALYTICS.md` |
| P2 | "processed in the EU" overclaims; PostHog Inc. is a US company, so Art. 13(1)(f) needs a transfer statement | blocker (#252 text) | fixed, with a placeholder for the DPF or SCC basis (user to confirm) |
| P3 | Retention is a placeholder; the up to 200 unsent events kept on the phone aren't mentioned | blocker (#252 text) | phone queue added; the PostHog retention period is the user's to fill in |
| P4 | One `nutrition_food_logged` per food, with timestamps, adds up to a meal log (possibly Art. 9, CJEU C-21/23) | should-fix | fixed: one event per **distinct** (entry point, unit mode, fractional) per save; the number of foods isn't sent. Asking legal whether the consent should also cite Art. 9(2)(a) is in "Needs you" |
| P5 | The consent copy (#137's onboarding step; the Profile toggle's "Screens used and errors shown.") doesn't name the food search, logging and Sync now events | should-fix | **open, for #137**: the copy lives there; the new events can't send before #137 lands |
| P6 | #137's `sanitize` checks keys across all events, and its `allowedEvents` lacks the six new events | should-fix | **open, for #137 / the integration**: `beforeSend` should run `AnalyticsCatalog.check` for our events and allow only `sdkPropertyKeys` on `sdkEventNames` (`docs/ANALYTICS.md` says so) |
| P7 | Person profiles should be `.never`, not `.identifiedOnly` | should-fix | fixed in `AnalyticsSDKSettings.required`; #137 has to follow |
| P8 | Sentence fixes: toggle name, search wording, missing events, the "taps" contradiction, sub-processors, the effect of withdrawal, rights, controller | should-fix | fixed in `docs/ANALYTICS.md` |
| P9 | `latency_ms`/`duration_ms` may be Apple's Performance Data | note | **open, for #137's manifest**: declare Performance Data (not linked, Analytics) when the analytics entries land |
| P10 | `AnalyticsSDKSettings` doesn't pin `optOut`, `beforeSend`, the fence, `flushAt`/`maxQueueSize` or the logs feature | note | kept out of scope: #137's `PostHogSinkTests` pins those against the real `PostHogConfig` |
| P11 | The worktree's `CLAUDE.md` (EN+DE) differs from the main checkout's (EN only) | note | not this PR: the main checkout is on an older or dirty `CLAUDE.md` |
