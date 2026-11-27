# No-watch recovery in the app: morning check-in, sleep dial, session RPE

Brief: head-architect, 2026-11-27. Contract: platform `docs/API.md` → "Recovery without a watch — check-ins and session
RPE (D291–D295, D298, D299)", served by platform #260 behind `recovery.checkin` (D300 adds the consent re-check at the
write). Privacy text: platform #252 (R12 asks the app's consent copy to cover what the user enters).

One PR (`feat/recovery-checkin-ui`), drafted by Codex from `.codex-prompt.md`, reviewed and fixed by ios-lead.

## Acceptance criteria
1. **Flag off = nothing.** With `recovery.checkin` off: no card, no RPE row or prompt, and no request to any recovery
   route (status, pending retry, RPE). Unit test counts the fake's calls.
2. **Wearable wins.** `source == wearable`, or today's check-in `superseded`: no card, no dial.
3. **Due.** `needs_checkin` → the Today card; the sheet pre-fills from `suggested_*`, else 23:00/07:00; editing takes
   the stored times on the check-in's own clock.
4. **Dial.** 24 h, 5-min steps, a haptic per step, two VoiceOver-adjustable elements; Reduce Motion; large text.
5. **Time zones and the wake day.** `{date}` = calendar date of `wake_time + tz_offset_sec`; `tz_offset_sec` =
   `secondsFromGMT(for: wakeTime)`; bedtime on the previous calendar day when it is later on the clock than wake;
   true elapsed minutes on DST nights; 60–960 min; wake ≤ now + 5 min. Unit tests incl. Berlin 2026-03-29/10-25.
6. **Offline save and retry.** Offline/transport/408/429/5xx → kept per account on the iPhone, sent on the next
   `load()` online; `422` → inline, not queued; `404` → hidden, kept, not sent; `403 consent_required` → kept, gate
   reported. Account switch drops the previous account's.
7. **Session RPE** 1–10 on the workout's detail (prompt when no heart rate) and after a Train session with a
   `workout_id`; editable and clearable; `DELETE` `404` = done.
8. **Consent copy** names what the user enters (check-in, RPE); "export everything" softened.
9. **Analytics**: `recovery_checkin` (`opened`/`saved`/`skipped`) and `feature_used.session_rpe_saved`; no answer,
   time, score or RPE value. `docs/ANALYTICS.md` updated, plus the two privacy-review corrections.
10. English and German strings; decode tests from the contract's examples; one UI test with the flag on.

## Out of scope (follow-ups)
The Today ring's estimated fill from `RecoveryStatus.recovery_score`; `CoachingBriefing.recovery` /
`readiness_display`; `N2RScore.bedtime_source`; check-in history and delete UI; a reminder.

## Risks
- Codex can't build: compile errors and invariant breaks that compile (as in #151). Review behaviour, not just the diff.
- The string catalog: targeted edits only; check `--stat` and a semantic diff.
- `Workout` is uploaded by the sync: the new optional fields must stay omitted when nil.
