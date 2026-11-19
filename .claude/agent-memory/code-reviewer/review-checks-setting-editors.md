---
name: review-checks-setting-editors
description: RYFT review checks for one-value setting editors that PATCH at once from a shared editor object (C3 body-setting editors and their fix round, 2026-11-19) - waitsForConnectivity hangs, failure-time offline, page-local busy, account-blind editors, off-grid steps; fix round - stale-owner exits that leave busy flags set, modal locks over long requests, 2xx-unreadable classed as refused, skipped rereads, untested page counters
metadata:
  type: feedback
---

From the C3 review (Baseline sleep need / Max HR editors, Sleep need sheet; read-only, 2026-11-19). The suite was green; none had a test:
- **`APIClient.defaultConfiguration` has `waitsForConnectivity = true` and a 300 s resource timeout.** Offline, a foreground
  PATCH doesn't fail: it spins up to 5 minutes. Tests that inject `URLError(.notConnectedToInternet)` from the mock prove a
  path the device never takes. Look for a demo-exempt pre-flight `guard isDemo || connectivity.isOnline` on every write.
- **Classifiers that read connectivity at failure time** (`if !online || code == .notConnectedToInternet → "wasn't saved"`,
  copied from `NotificationSettingsFailure`) call a lost answer (`networkConnectionLost`, timeout after the path dropped)
  "wasn't saved" though the platform may have committed. Offline only when the request never left.
- **"May not have saved" with no re-read**: the user cache TTL is 3600 s, so the old value shows as current for up to an hour.
  Ask for `refreshUser(mode: .changed(since:))` after a no-answer.
- **Page-local busy state (`@State running`) over a shared editor's flight**: close and reopen shows the pending value with no
  "Saving…", other readers (Profile rows, the need sheet row) show `pending ?? saved` as fact, and the late failure lands in
  a field the next `begin()` wipes. Check Close/Back/swipe while saving.
- **Editors owned by process-lived `ScreenModels`** with no `AccountBinding`: words written after an await (savedChange,
  rescoreStatus, birthYearError) and `pending*` carry into the next account. The store's `store(user:asOf:)` guard protects
  data, not the editor's words; `patchUser` hides `.dropped`, so "Saved." can show beside the old value.
- **Steppers stepping from off-grid values** (default 460, learned medians) defeat "one tick per step, the needle lands on a
  tick"; a test that loops `stride(by: 15)` doesn't see it.
- A failure flag added for one view (`rescoreFailed`) while another view (`RescoreStatus`) still keys on `details != nil`.
- `need == nil` as "scored before the breakdown" when API.md says old days send the whole need as `base` (`nap_min` null).


**Fix-round re-verification (same day)** - what the fixes themselves broke:
- **Stale-owner exits that skip clearing their own busy flag** (`guard owns(owner) else { return }`, `defer { if owns(owner) { busy = false } }`)
  where "owner" = generation + `AccountBinding`, but only the generation path resets the flag. `AccountBinding` includes `demo`, and the
  Demo data switch runs `AppState.reset()`, not `forgetActivityState()` (the forgetters) -> `writing`/`rescoring` stuck true until relaunch.
  Check every path that changes the binding against every path that clears the flag; clear by the call's own token instead.
- **`.disabled(saving)` + `interactiveDismissDisabled(saving)` over a request on `APIClient.defaultConfiguration`**: 60 s request timeout,
  300 s waitsForConnectivity when the path drops after the pre-flight, in-client 429 (<=60 s) and 503 (3 x <=30 s) retries -> an
  undismissable sheet; `.disabled` on the ScrollView also stops scrolling (AX3).
- **`APIClient.decode` wraps DecodingError as `APIError.http(<2xx status>, ...)`**: a classifier whose `default:` is refused calls a saved
  change "back as it was". A test with a raw `DecodingError` proves a path the device never takes.
- **Reread skipped offline with nothing scheduled later** (cache TTL 3600 s keeps the old value as fact after the page closes).
- **Late-failure surfacing by page counter** (`openPages` via onAppear/onDisappear): tests that start the save from the model with no
  page open stay green with the `.onDisappear` wiring removed; ask for a real push -> pop -> answer test.
- **"Rescored" from `scoreFetchedAt >= accepted`**: stamped at store time, `.latest` joins an in-flight fetch, `state.refresh` swallows
  failures -> proves a write happened, not that this reload got post-rescore scores.

**Why:** honest-state gaps under the user's offline-first rule (2026-11-19), left after the PR's own state tests passed.
**How to apply:** any editor/sheet that writes a setting through `PATCH /v1/me` (or similar) from a shared view model. See
[[review-checks-form-reads-and-saves]], [[review-checks-local-overrides]], [[review-checks-multistep-flows]].
