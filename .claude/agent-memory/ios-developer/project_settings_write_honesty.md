---
name: project-settings-write-honesty
description: How RYFT settings pages judge and word a failed write (SettingsWriteFailure), and the Swift Testing pitfalls that cost build rounds in C3's fix round
metadata:
  type: project
---

Settings writes (body-setting editors, Notifications) share `Ryft/Features/Profile/SettingsWriteFailure.swift`:
offline only when nothing left the phone (`notConnectedToInternet`, `dataNotAllowed`, `internationalRoamingOff`, or a
pre-flight `state.isDemo || isOnline` guard); every other transport failure and 408 is `noAnswer`; 5xx (not 501) is
`serverError`; the rest `refused`. `noAnswer`/`serverError` re-read with `refreshUser(mode: .changed(since: now))` and
say "Saved." only if the re-read holds the change. `AppState.patchUser` returns `false` when the store dropped the
answer: never "Saved." on that.

**Why:** C3 review (2026-11-19): an offline save spun 300 s, a timeout read as offline, "Saved."/"rescored" were
claimed without being seen.

**How to apply:** a new settings write takes the classifier, guards offline before sending, takes an `AccountBinding`
before each await, and keeps its in-flight state in the shared editor (rows show "Saving…", not the pending value).

Build pitfalls seen: `@Test` display names must be one string literal (no `+`); in `#expect(a && <try/await …>)` the
right side is an autoclosure, so hoist into `let`s; a closure inside `#expect(await eventually { … })` nested in another
closure tripped SIL ("function type mismatch"), use `w.wait` instead; `User.maxHr`/`sleepBaseMin` are `let`.
