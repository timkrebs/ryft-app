# P2 · Fitness and Nutrition tabs, Profile behind the avatar, Quick log (flag `app.structure_v2`)

Brief: head-architect, 2026-11-28 (user approved D1–D7 with A1–A7 on 2026-11-27). One PR, `feat/structure-p2`. Codex
drafts (`.codex-prompt.md`, deleted before commit), ios-lead reviews behaviour and owns it.

## Goal
Navigation only, no new data. Everything new behind `app.structure_v2` (compiled default off). Flag off = today's main.

## Acceptance criteria (testable)
1. Flag off: tab list, titles, identifiers, headers, Today's sync button, quick log, Nutrition row, Strain's plus,
   analytics events identical to main. Existing unit and UI tests pass unchanged.
2. Flag on: tabs Today · Sleep · Fitness (`tab.strain`) · Nutrition (`tab.nutrition`) · Insights; no `tab.profile`.
3. A selected tab that isn't visible under the current flag value (launch argument, a flag flip) falls back to Today.
4. Flag on: every tab's header has `header.quickLog` and `header.avatar` top right, 44 pt targets; Today keeps the calendar
   and loses `today.header.sync`.
5. Avatar badge: green up to date, amber error, none stale, a ring while syncing (static under Reduce Motion); long-press
   = #151's sync menu; VoiceOver value = the sync value. `HomeSyncModel` and the sync state machine unchanged.
6. Avatar tap → Profile sheet (large detent, grabber, Done); P1's pages push inside; dismissing doesn't cancel a sync.
7. Quick log sheet (medium): Log meal, Scan barcode, Start workout, Add activity, Journal, Add sleep, each only when
   available; Today's and Strain's pluses are gone with the flag on, their destinations reachable here.
8. Entry points to the old Profile tab (Today's setup card) open the sheet with the flag on; deep links keep their targets.
9. Analytics: `screen_viewed` gains `nutrition`, `quick_log`, `profile_sheet`; new `quick_log_action` (`action` token).
   `docs/ANALYTICS.md` updated, the privacy-text line noted in the PR.
10. Strings en + de; `make lint` green.

## Decisions the proposal left open (ios-lead, 2026-11-28)
- **Sleep's header**: its three-slot night row stays; with the flag on an actions row sits above it, so the avatar is in
  the same top-right spot on every tab. Re-laying Sleep is not P2's scope.
- **Insights**: the range picker moves under the header row with the flag on (title + two buttons + picker don't fit in
  353 pt).
- **Fitness**: the screen title follows the tab ("Fitness"); the Strain score keeps its name and colour.
- **Nutrition tab when Nutrition is unavailable** (demo, no account, flags off): the tab stays (five tabs everywhere,
  HIG) with an empty state, instead of a tab bar that changes with the account.
- **Add activity from Quick log** uses Fitness's shown day when Fitness is selected (what Strain's plus did), else today.
- **Add sleep (A4)**: `recovery.checkin` isn't on main (#153 open), so it's the manual Add sleep where My Day offers it;
  hidden otherwise. A TODO marks where #153's check-in plugs in.
- **Sync from the avatar menu** reuses `trigger_source = homescreen_top_right` (same place, same action): no new token.
- **Analytics token for the tab** is `nutrition`, like the other tabs' tokens (`today`, `sleep`, …), not `tab_nutrition`.

## Risks
- Sheet ownership: Quick log, its destinations and the Profile sheet live on `RootTabs`; the onboarding gate sheet sits
  above. Verified by the flag-on UI test.
- Flag flips arrive between screens (`applyPending`): the selected tab is normalised on every change.

## Verification
Unit tests (flag on/off tabs, mapping, Quick log availability, badge), the flag-off smoke unchanged, one flag-on UI
test, one code-reviewer pass. Device checklist in the PR.
