# Review: analytics phase 1 (2026-11-20)

Commit reviewed: 59ab39d. One code-reviewer, one security-privacy-reviewer. Fixes by ios-lead in the next commit.

## Blocking
- **code-reviewer:** a wipe resumed at launch (inside `AuthService.shared`'s init) runs before `onWipe` is bound, so
  `accountLeft()` never ran. A's opt-in survived and B's events would have gone under A's id. **Fixed:**
  `Analytics.forgetAnswer(defaults:)` in `wipeSharedLocalData`'s `before` step.

## Should-fix (all fixed)
- privacy: `reevaluate()` ran before `finishOwedWipe`. **Fixed:** it moved after it. The gate is also closed while
  nobody is signed in (`isSignedIn`), so no `track` opens it before an owed wipe.
- privacy: opting out kept the old id on disk until the next start. **Fixed:** the sink gained `forgetID()`, called on
  opt-out and sign-out (phase 2 deletes the SDK's stored id and queue there).
- privacy: "anonymous" wasn't accurate (a random id plus the IP is pseudonymous). **Fixed:** the title is now "Share
  usage analytics?", plus the VoiceOver hint and the CHANGELOG line. "In the EU" wasn't enforced. **Fixed:** the only
  host accepted is `eu.i.posthog.com`.
- privacy: `train_session_started` + `train_session_finished` gave workout duration. **Fixed:** `finished` removed.
- code-reviewer: a sign-out with the prompt up could record "Don't share" for the next user. **Fixed:** a dismissal
  counts as a decline only while `showsPrompt` holds.
- code-reviewer + privacy: the sink was reachable from any call site. **Fixed:** `Analytics.sink` and
  `AppEnvironment.analyticsSink` are private.
- code-reviewer: adding the package before phase 2 would break the build (`canImport(PostHog)` without `PostHogSink`).
  **Fixed:** a `PostHogSink` stub that can't send.

## Nit (fixed)
- code-reviewer: `presentsSomething` counted the prompt while the tabs weren't shown. **Fixed:** it counts only
  while they are (`tabsShown`).

## Phase 2 must (from the privacy review)
- `stop()` empties the SDK's whole on-disk queue, even if the SDK wasn't set up in this process. `forgetID()` deletes
  its stored id. `start(newID:)` makes a fresh id before the first send.
- Lifecycle events only between `start` and `stop`.
- A property sanitizer that drops `$device_name`, `$timezone`, `$locale`, `$network_carrier` and the like.
- The SDK's files: complete-until-first-unlock protection or better.
- `PrivacyInfo.xcprivacy`: Product Interaction, plus probably Device ID and Other Diagnostic Data (`error_shown`).
  Each is Analytics, not linked, no tracking. Add Coarse Location if PostHog's GeoIP stays on.
- The new ADR; `CLAUDE.md` → Rules; `docs/APP_STORE.md`; the conventions skill's rule 4.
- For the user: the privacy policy names PostHog EU as a processor, the legal basis (consent, Art. 6(1)(a)),
  retention, and Art. 11. In PostHog: "Discard client IP data" on, GeoIP off.

## Open for the user
- `onboarding_step`, `health_access_requested` and often `first_sync_completed` rarely fire. The opt-in comes after the
  onboarding, and nothing is buffered before consent.
- A sign-out clears the opt-in answer (design.md §10). The privacy reviewer agrees: consent is one person's.
