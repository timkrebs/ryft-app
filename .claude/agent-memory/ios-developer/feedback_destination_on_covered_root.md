---
name: feedback-destination-on-covered-root
description: A navigationDestination on a conditional card doesn't pop its pushed page when the card leaves (iOS 27.2); prove a pop with a body probe and a real redraw before moving destinations
metadata:
  type: feedback
---

On iOS 27.2 (simulator, hosted test with the real TodayView), Bedtime & wake pushed from Tonight's card stayed open when
Today redrew under it without the card (a probe logged the body's Tonight decision: `false`), and Back returned to Today
without Tonight. The C4 review's "move the destination to an always-on view" was conditional on a pop, so it wasn't done;
`BedtimeHostedTests.todayKeepsThePage` guards the behaviour.

**Why:** C4 review item 5 (2026-11-19). Two traps cost a round: `isEvening()` short-circuits at 17:00+ (`hour >= 17 || …`),
so Today's body never registered a read of the plan and the clock alone never redrew it; and a covered root's
accessibility tree is empty, so "Tonight's row is gone" can't be seen while the page is up.

**How to apply:** to prove a pop, host the real screen, push, change the card's condition, then force a redraw through a
value the screen's body certainly reads (an environment value it declares, such as `dynamicTypeSize`, from a wrapper),
log body evaluations with a temporary probe, and check the page. Hosted Today needs scored days (`state.history`,
`state.today`) or it shows the first import, which hides Tonight. Observable computed properties that short-circuit can
skip a read: read every tracked value before the condition when a view depends on it (the editor's `liveCopy` had the
same bug: `copyOwner == owner ? copy : nil` never registered `copy`, so the page didn't redraw on the first change).
