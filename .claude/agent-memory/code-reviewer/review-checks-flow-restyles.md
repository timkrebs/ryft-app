---
name: review-checks-flow-restyles
description: RYFT review checks for restyles of multi-step flows with a live result page (C5 training import, 2026-11-19) - dropped modifiers another branch reads (hidesBackButton), edge-only back-swipe disablers, "imported" counts that include server-kept items, muted live notices, missing catalog keys and plurals, incomplete teal regexes, pill tests that never tap
metadata:
  type: feedback
---

Found in the C5 import restyle review (2026-11-19, read-only, no build); identifiers, dialogs and model calls were intact:
- **A dropped modifier another branch reads.** The restyle removed `.navigationBarBackButtonHidden(step == .result)` and
  added a private probe that disables only `interactivePopGestureRecognizer`. Area A's keeper (`BackSwipeRule.mayBegin`)
  refuses on `navigationItem.hidesBackButton` and also drives iOS 26's `interactiveContentPopGestureRecognizer`; after
  the merge a content swipe pops the result page back to the step whose Import is enabled again. For every removed
  modifier, grep the *other areas' branches* (`git grep <symbol> <branch>`) for readers before accepting the removal.
- **"Imported" counters vs server-kept items.** `ImportItemCounts.done` and `planSummaries(.done)` include
  `newer_on_server` (left as it is); only `plansImported` / `sessionsImported` exclude it. A row titled "... imported"
  must read the derived property, and any name list must filter on the result code too. The mocks only had a session
  left as is, so the shots and the Done test couldn't show it: ask for a mock with a *plan* left as is.
- **`InlineMessage(announces: false)` on a page whose state changes under the user** (pause, offline, attention) mutes
  the transition for VoiceOver; fine on static pages, not on a live result. Check `.onChange` of the phase announces instead.
- **String Catalog**: `lint-strings.py` doesn't flag keys missing from the catalog, interpolated counts without plural
  variations ("%lld left as they were" for 1), or stale keys the diff orphaned. Diff `String(localized:)`/`Text("...")`
  literals against the catalog keys both ways.
- **Teal-scan regexes**: the copied `Theme\.(teal|accent\w*|onAccent|recovery)` misses `Color.accentColor`, `.tint(...)`,
  `Theme.signal` and SwiftUI shorthands `.teal/.mint/.cyan`; C1's token list in `ProfileSubpagesTests.noTeal` is broader.
- **Pill tests that read id/label/enabled/height and never activate**: swapping Discard and Done actions passes. Ask for at
  least the destructive path (tap -> confirm dialog flag, not the job gone) and the primary path.
- **A paused state whose only pinned control is a full destructive pill** ("Discard import" while waiting for a
  connection): the data continues by itself; the pill invites losing it. Quiet text action or a non-destructive primary.

**Why:** tests, lint and shots were all green; each issue needed the uploader's counters, another branch's keeper or the
catalog. **How to apply:** any restyle of a wizard/result flow or a page with live job state. See [[review-checks-form-restyles]],
[[review-checks-multistep-flows]], [[review-checks-settings-subpages]], [[review-checks-tokens-dark-only]].
