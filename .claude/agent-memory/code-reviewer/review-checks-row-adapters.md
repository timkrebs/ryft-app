---
name: review-checks-row-adapters
description: RYFT review checks for shared row components extended for one screen (Nocturne T6B.6 My Day, 2026-11-19) - preview-only closures, trailing actions vs 320 x xxxLarge word breaks, reused string keys and comment collisions, offline tests that never go offline
metadata:
  type: feedback
---

Found in the T6B.6 review (My Day on `ActivityListRow`, read-only, 2026-11-19); the default layout of the shared row was unchanged:
- **Controls drawn only when a closure is passed** (`retry:` on the state mark): previews and shot tests pass `{}`, so the
  shots show "Retry", but `git grep` of the production call sites (`MyDayRow(item:)` in the card and the screen) passed
  nil, before and after. For every optional closure that draws a control, grep the live callers for a non-nil argument.
- **A fixed trailing action beside a flexible title** (`ActivityListRow` `action:`, "Add sleep") stacks only from AX1.
  At 320 pt (SE with Display Zoom) in a card (248 content, 216 inside the row) at xxxLarge the title got 66 pt and
  "recorded" (81.8 pt) broke mid-word. Measure the longest word vs what is left at 320 for L..xxxL. Probe recipe: macOS
  swiftc, `CTFontManagerRegisterFontsForURL` on `Ryft/Resources/Fonts/Satoshi-Regular.otf`, `ImageRenderer` of a copy
  of the row, `@main` + `-parse-as-library`; callout scale = Apple's callout table / 16 (xL 18, xxL 20, xxxL 22).
- **Reused keys:** Xcode joins differing comments of one key with "\n" (seen on `%@ kg`); implementers copy the other
  site's comment verbatim instead, so the comment names the wrong screen ("Yesterday · %@" with Sleep's). Also list keys
  whose last caller left (stale) and keys whose comment now names a screen that no longer uses them ("Show all %lld").
- **Offline tests that never go offline:** VM tests set `api.failure = transport(.notConnectedToInternet)` while
  connectivity is online; real offline makes `ReadScheduler.enter` return nil without a call or an error, so a phase
  that needs a thrown error to leave `.loading` never leaves it (see [[review-checks-screen-restyles]]).
- Tests that compare `content.spoken == MyDayRow.spoken(item)` or pass `MyDayActions()` to prove "outside the window"
  are tautologies; say which rule they don't reach.

**Why:** all were invisible in green suites and matching shots. **How to apply:** any ticket that extends a shared row or
component for one screen, or that restyles a screen with offline/loading phases. See [[review-checks-screen-loads]],
[[review-checks-large-text]], [[review-checks-dark-launch]].
