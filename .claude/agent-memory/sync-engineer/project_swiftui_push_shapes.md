---
name: swiftui-push-shapes
description: SwiftUI (iOS 27.2 sim) ignores a NavigationLink(value:) under two view-destination pushes (isPresented/item), wherever the destination is registered, bound path or not
metadata:
  type: project
---

Probed in a hosted window, 2026-11-20 (iOS 27.2 simulator), destination registered at the stack root unless noted.

Pushes:
- isPresented → item → value link
- item → item → value link
- the same on a `NavigationStack(path:)`
- isPresented → item → value link, with the destination registered on the leaf

Do nothing:
- isPresented → item → value link (Today → My Day full screen → workout → "Logged session")
- item → item → value link
- the same on a bound `NavigationStack(path:)`
- isPresented → item → value link with the destination registered on the leaf

What does push:
- item → value
- isPresented → item → item
- isPresented → value → value
- all value
- value → item → value

In short: a value link fails once two view-destination levels sit above it.

**Why:** review S2 ("Logged session does nothing from Today") was diagnosed as a missing `.trainDestinations()` on Today's stack. Adding it fixed only the card's one-level push; the full screen stayed broken. Both a hosted test and a real-tap UI test timed out. The cause wasn't the hosted `activate()`, as first assumed.

**How to apply:**
- Before blaming a missing registration, count the view-destination pushes above the link.
- The fix is an `item` push for the link (`@State` id plus `.navigationDestination(item:)`), or value pushes all the way down.
- Probe a shape with a small hosted `NavigationStack` of Buttons and Text-labelled links: `HostedWindow` `activate()` drives both.

Applied in PR 6 R2: WorkoutDetailPage pushes "Logged session" by item and Today no longer registers `.trainDestinations()`.
The real-tap pins are `MyDayUITests.testALoggedSessionOpensFromItsWorkout` (full screen) and `StrainLoggedSessionUITests`.
See [[hosted-window-tests]].
