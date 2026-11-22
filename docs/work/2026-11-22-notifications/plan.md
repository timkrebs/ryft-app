# Notifications — plan (ios-lead, 2026-11-22)

## Brief (the user, 2026-11-22)
RYFT should notify like other wearables do. Five kinds:
- **an activity was detected and processed**, so you can review or name it (never during the workout);
- **the morning's scores are ready** once the night is scored;
- **bedtime reminders** from the sleep planner;
- **a morning journal reminder**;
- **system hints when the app can't sync in the background**, e.g. after it was closed completely.

RYFT's own words apply: Readiness, Recovery, Sleep, Strain, journal. No other wearable brand's name or vocabulary.

## What exists (main at 1c5f6fd)

| Kind | Today | Where |
|---|---|---|
| Morning scores | **Server push `MORNING_SCORE`**: "Recovery 82%" plus a readiness sentence, once a day when the day is final, opening `/day/<day>`. APNs is live; gated by the `push.enabled` flag (0 %, allow-list only) | `API.md` → Push notifications; `Ryft/Push/`; Profile → Notifications |
| Workout scored | **Server push `SESSION_SCORED` / `PR`**, for **Train's strength sessions only**. Apple Health workouts (recorded or auto-detected by the watch) send nothing | same |
| Bedtime | **Local `BEDTIME`**: bedtime − wind-down, the next 7 nights, from Bedtime & wake | `SleepPlannerViewModel`, `BedtimePlanner` |
| Journal | nothing | `Features/Journal/` |
| Not syncing | **Server push `SYNC_STALE`**: no HR or steps for 20 h, 09:00–21:00. Needs push (flag and permission) and the platform to see the gap. Nothing on the phone covers a force-quit app or Background App Refresh turned off | `API.md`; `Sync/ScheduledWork.swift` |

## Lead decisions
1. **Five kinds in Profile → Notifications:**
   - **Morning:** your day is ready (`MORNING_SCORE`), and the journal reminder (new, local).
   - **Training:** activity scored (new `ACTIVITY_SCORED`, server), session scored (`SESSION_SCORED`), records (`PR`).
   - **Sleep:** the bedtime reminder. This is the existing local one; the row links to Bedtime & wake, where it is set.
   - **Sync:** not syncing (`SYNC_STALE`, server), plus a local fallback (below).
2. **Local kinds don't wait for `push.enabled`.** The journal reminder, the bedtime reminder and the local sync fallback work whenever iOS allows notifications. The server kinds keep following the flag; turning it to 100 % is the user's call (Needs you).
3. **Detected activities come from the platform** as a new category `ACTIVITY_SCORED`. The platform knows when a synced Apple Health workout has been scored. The app requests it in `docs/API_REQUESTS.md` (title and body keys, `ryft.url` to the activity) and builds its side behind the category. It does not invent fields.
4. **The journal reminder is local.** It goes daily at a chosen time; the default is decided in the design. It fires only when the journal has habits and today's answers aren't in, and today's goes away as soon as they are. It respects quiet hours and opens the journal.
5. **"Not syncing" when the phone can't run RYFT:**
   - **A local fallback:** a reminder that moves forward with every successful sync, so it fires only if no sync happened for N hours. This works without push, and after a force-quit, because iOS delivers scheduled local notifications whatever the app's state. It must not double the server's `SYNC_STALE`.
   - **An in-app hint** when Background App Refresh is off for RYFT.
   - The architect decides the mechanics, including whether a notice on termination is possible or worth it.
6. **Lock screen:** notifications carry health values (Recovery 82%). The existing rule stands: with previews hidden iOS shows only the title. New local kinds put no health value in the title.

## Tickets

| # | Ticket | Owner | Depends | Acceptance (testable) |
|---|---|---|---|---|
| N0 | Design note `design.md` covering:<ul><li>one local notification scheduler (bedtime, journal, sync fallback): ids, rescheduling triggers (app active, BG refresh, sync done, journal saved, settings changed, sign-out wipe), quiet hours, the 64-pending limit</li><li>dedupe with the server's `SYNC_STALE`</li><li>Background App Refresh and force-quit detection</li><li>`UNNotificationCategory` and actions, and tap routing (`AppRoute`)</li><li>where each preference lives (server `NotificationPrefs` vs on-device)</li><li>what happens on sign-out and account switch</li></ul>An ADR if a choice is non-obvious | ios-architect | — | Every kind has a trigger, a cancel path and a test seam; sign-out removes every local request |
| N1 | UI and copy `ui.md`: the Notifications page with the five groups and their states (push rolling out, not asked, denied, allowed), the journal reminder's time row, Devices & sync's Background App Refresh hint, each notification's title, body and actions | ui-designer (+ localization-editor for copy) | N0's kinds | Every state drawn; copy in RYFT's words; previews of the new rows |
| N2 | Contract: `ACTIVITY_SCORED` in `docs/API_REQUESTS.md`: when it is sent, keys and arguments, `ryft.url`, the category in `NotificationPrefs`, quiet hours, collapse and expiry. As the existing table does | api-contract-keeper | — | The request is concrete enough for the platform to build without questions |
| N3 | Local scheduler, journal reminder and sync fallback (N0) | sync-engineer (`Sync/`, `Push/`) | N0 | Unit tests per trigger; the 7-day window; cancellation on journal save and sign-out; no duplicate with `SYNC_STALE` |
| N4 | The Notifications page and hints (N1), the `ACTIVITY_SCORED` category, its tap route to the activity, and strings | ios-developer + localization-editor | N1, N3 | Hosted tests per state; routing test from a payload fixture; strings in the catalog |
| N5 | Tests from the acceptance criteria, payload fixtures from `API.md` | test-engineer | N0, N2 | Fixture decode for the new category; scheduler tests fail against their mutants |

**Reviews:**
- always code-reviewer;
- security-privacy-reviewer: notification content, the lock screen, deep links, sign-out;
- ui-validator: the page and its states, default and AX3;
- performance-profiler: the rescheduling on every sync must stay cheap.

**PRs:**
1. `docs: notifications plan, design and the ACTIVITY_SCORED request` (N0–N2)
2. `notifications: the journal reminder and the local sync fallback` (N3 and its UI)
3. `notifications: one page for every kind` (N4)
4. `notifications: activity scored`, once the platform ships the category

## Needs you
- `push.enabled` to 100 % (operator, `OPERATIONS.md` → Feature flags), so morning scores, sessions and "not syncing" reach every account and not only the allow-list.
- The platform's `ACTIVITY_SCORED`: the plattform lead builds it from `docs/API_REQUESTS.md`.
- Device checks: delivery of each kind on the lock screen with previews hidden; the sync fallback after force-quitting RYFT.

## Risks
- **iOS limits:** 64 pending local requests. Bedtime already uses 7 (plus alarms), and a daily journal reminder for 7 days adds 7, so keep a window.
- **Force-quit:** iOS doesn't wake a force-quit app for background work, so a notice on termination can't be relied on. The moving local reminder is the dependable part.
- **Duplicate "not syncing"** from the server and the phone: N0 decides which one wins.
- **The consent lag investigation** (`fix/consent-agree-lag`) and **gate part 2** run in parallel. They don't touch these files except `Localizable.xcstrings`, which gets targeted edits and is merged with care.

## Lead decisions on N0 (2026-11-22)
- **Design and ADR 0024: accepted as written** (one `ReminderScheduler`; the server wins where push reaches).
- **Q1:** the journal reminder is on by default at 09:00 for accounts that chose habits. The user asked for it, and the brief mirrors the morning prompt. One switch turns it off.
- **Q2:** quiet hours don't hold the bedtime reminder or the wake alarm. Both are things the user set for that hour.
- **Q3:** "not syncing" goes at 20 h and once more at 72 h. A gap of days is worth a second nudge, and never more.
- **Q4:** sign-out removes every delivered RYFT notification now, ahead of ADR 0020's W4b. It's cheap and it closes a privacy gap.
- **Q5:** the one extra journal read in BG refresh is accepted (bounded, one per refresh).
- **Q6:** the Demo switch freezes the account's reminders and a tap opens Today. Accepted, because the demo is short-lived and pausing adds states for no user value.
- **Q7:** the journal reminder follows the account across devices later, if asked; nothing requested now.
- **Drift found by N0:** `ARCHITECTURE.md` §4 and §7 are fixed in N3's PR.
