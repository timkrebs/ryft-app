---
name: review-checks-screen-restyles
description: RYFT review checks for Nocturne screen restyles (T6B.1 live shell, T6B.3-4 summary and Plans, 2026-11-19) - mocks the API never sends, spec states contradicting field notes, unplaced validation issues, endless loading, - pixel-test tolerance vs the regression's delta, spec constants no view uses, shared ink constants read by another ticket's file, "shared by both layouts" rules gated to one
metadata:
  type: feedback
---

Found in the T6B.1 live-shell review (2026-11-19, read-only, no build); behaviour and identifiers were intact:
- **Pixel tolerance vs the delta it must catch.** Hosted tests used `isClose(..., 0.06)` per channel. `surface` vs
  `background` differ by 0.035 and the old 6 % teal row tint over `surface` by 0.044, so "a done row has no tint" and
  "inside is surface, not a fill" pass on the broken look too. Compute the old look's composite (`python3 -I`) and compare
  with the tolerance; suggest 0.02 or a reference pixel from the same card.
- **Spec constants that no view reads** (`LiveSessionSpec.headerMinHeight` = 56, real header ~72) pinned by a test:
  grep each new `…Spec.x` for uses in `Ryft/` (a loop with `grep -c`).
- **A shared ink constant changed under another ticket's file**: `FocusedRowInk.activeTint` 0.10 -> 0.05 also halved List's
  teal `CurrentSetHighlight` (T6B.2's file). Grep every changed static for readers outside the ticket's files.
- **"Shared by both layouts" rules gated to one** (`isCompactHeader` Focused-only): measure the other layout at 320 with
  CoreText (Satoshi in `Ryft/Resources/Fonts`, swiftc in the scratchpad; type-annotate or swiftc times out).
- `FocusedRowInk.value(onRaisedField:)` covered upcoming only; a done row under the keypad with an empty buffer is still
  `textTertiary` on `surfaceRaised` (3.94). Walk every state x (raised, focused) pair.
- Shots vs drafts: list deviations against the approved draft PNGs and `build-plan.md` (it wins over the spec), not just
  the spec text.

**Why:** the suite was green and the shots matched; only these checks showed what the tests and constants don't prove.
**How to apply:** any Nocturne screen ticket with hosted pixel tests or a `…Spec` enum. See [[review-checks-tokens-dark-only]],
[[review-checks-large-text]], [[review-checks-session-ui]].

Recurred/extended in T6B.3+T6B.4 (summary, Plans, builder; 2026-11-19, read-only):
- **Mock shapes the API never sends.** `MockTrain.catalog(paused: true)` puts a paused enrolment in `active`; GET /v1/plans
  selects `status='active'` only (checked in `plattform/backend/internal/store/train.go`), so the approved paused shot,
  its tests and "week %lld waits" are unreachable; production shows the UserDefaults-only pause. Check each state's mock
  against API.md (and the platform query when the doc is terse).
- **Spec states that contradict the contract**: a "no heart rate" unlit-strain state, but `Session.strain` is the muscular
  load alone and always present after `/complete`. Read the field's Notes column before accepting a state's sentence.
- **Per-field validation lines**: enumerate every `PlanIssue` case and find where each renders. Unplaced ones (`noDays`,
  `lonelySuperset`) + a disabled commit = a silent dead end (the old top issue list was the only surface).
- **`loading = cache nil && error nil`** never ends offline: `ReadScheduler.run` returns nil without an error. Same for a
  detail whose error renders only inside the loaded branch.
- `.accessibilityElement(children: .ignore)` + a composed spoken label drops on-screen lines (plan exercise notes).
- Busy `PillButton` inside a parent `.disabled(working)` dims to 35 % (PillButton reads `isEnabled`).

Recurred in T6B.6 (My Day, 2026-11-19): `MyDayViewModel.content` is `.loading` until `failed` holds the day, and only a
thrown read error fills it; offline the scheduler returns nil, so an uncached day shows outline rows forever (pre-existing,
against the user's offline rule). Trace the offline path through `ReadScheduler.enter`, not the API mock.
