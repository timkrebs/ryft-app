---
name: feedback-destination-on-covered-root
description: Host a pushed page's navigationDestination on an always-mounted view, not on a conditional card; how to test a covered root, tap a dialog, and dodge a closure-mangling compiler bug
metadata:
  type: feedback
---

Host a `navigationDestination` on a view that is always mounted (Today hosts Bedtime & wake through
`@State bedtimeOpening` and passes `openSchedule` down to TonightCard; TodayHeader does the same for My day), not on a
card that can leave. On iOS 27.2 and 18.6 the page didn't pop when Tonight's card left, but the lead wants the host to be
always mounted anyway (C4 round 2, S5): don't rely on unspecified SwiftUI behaviour. A card that keeps a fallback
`@State` destination for previews (`openSchedule == nil`) is fine.

**Why:** C4 review item 5, rounds 1 and 2 (2026-11-19). Round 1 proved "no pop" and skipped the move; the lead asked for
it anyway.

**How to apply:**
- Prove a redraw under a pushed page: host the real screen, push, change the card's condition, then force a redraw
  through a value the body certainly reads (`dynamicTypeSize` from a wrapper, `TodayPoke`). Hosted Today needs scored
  days (`state.history`, `state.insights`, `state.readinessWeek`, `state.today`) or it shows the first import.
- A covered NavigationStack root is out of the window. Walk it through
  `UINavigationController.viewControllers.first?.view` (`BedtimeHostedTests.covered(_:)`). Wait on a positive signal
  (the card's id has left the covered tree and some `today.` id is still there), not on a timeout.
- Short-circuiting Observable computed properties skip tracked reads (`isEvening()` at 17:00+, `liveCopy`). Read every
  tracked value before the condition.
- Tapping a UIAlertController button in a hosted test: dismiss first, then call the action's private `handler` in the
  completion, as UIKit does (`choose(_:in:)`). Calling the handler while the alert is still up passes on 27.2 but on
  18.6 SwiftUI drops a `dismiss()` the action triggers, so the page never pops.
- Compiler bug (Xcode 27, Swift 5.10 mode): `#expect(await eventually { planner.x == y })` inside a hosted-test closure
  failed with "SIL function type mismatch". Use `try await w.wait("…") { … }` there.
