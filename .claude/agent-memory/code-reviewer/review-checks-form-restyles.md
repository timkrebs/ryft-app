---
name: review-checks-form-restyles
description: RYFT review checks for restyled forms and onboarding steps (Nocturne PR 6 A, 2026-11-18) - label echoed as placeholder, .task autofocus re-firing on pop, UI tests that dodge a failing gesture, PR-time UI coverage gaps, grabbers on undismissable sheets
metadata:
  type: feedback
---

Found in the PR 6 A review (signed out, onboarding, splash, Details sheet; 2026-11-18). Behaviour was preserved; these were not
visible in the green suite:
- **`TextField(text:prompt: nil) { Text(label) }` shows the label as the placeholder.** Inside `FormField` (visible label above)
  every empty field reads "Email / Email". Drafts only show filled fields, so compare the *empty* after-shots. Fix: an explicit
  prompt (`Text(verbatim: "")` or a real example).
- **Autofocus via `.task { sleep; focus = x }`** re-runs each time a NavigationStack page reappears after a pop: coming back
  from a pushed page (Check inbox "Use another email") puts the keyboard on the first field, not the one to fix.
- **A UI test moved to dodge a failing gesture** ("swipe high, mid-height doesn't pop on the 27.2 sim"): read the implementer's
  probe log (scratchpad `a6/ui-probe.log`). If every failing variant had the keyboard up and there is no control (keyboard down,
  base commit with the system bar), "simulator quirk" is unproven; ask for the control probes before accepting.
- **PR-time UI coverage:** `StoreSmokeUITests`' reviewer walkthrough skips without `RYFT_DEMO_*` (CI has none), so no UISmoke test
  runs the signed-out flow; new `-RyftScreen` UI tests outside UISmoke only run nightly (Full).
- **Shared frames hard-code presentation modifiers** (`.presentationDragIndicator(.visible)` in `OnboardingScreen`) while a caller
  sets `interactiveDismissDisabled` (enforced invite gate): a grabber on a sheet that can't move.
- **Monospaced IDs in a row:** 36 chars x 0.6 em vs the row's text width at 390 pt (footnote 13 pt = 281 > 274): it wraps at a
  hyphen with push-out line breaking. Check against the after-shot at 390, not 402.
- `WordmarkLockup` carries `.isHeader`: put above a step title it becomes the first heading on every step.

Fix round (b710e3d, 2026-11-18): S1 was real, not a sim quirk (base popped a slow mid-height drag; the scaffold didn't) and was fixed by
also delegating iOS 26's `interactiveContentPopGestureRecognizer`. Checks for any pop-gesture keeper: it is installed once per
navigation controller and never restored, so it rules every later page of that stack, system-bar pages included; it ignores
`navigationItem.hidesBackButton` (`.navigationBarBackButtonHidden`), which UIKit honours (Import's result step relies on it);
replacing UIKit's delegate drops its other methods (failure/simultaneity with list `.swipeActions`): forward them instead.
Also: a generic error fallback that replaces *all* non-transport text also drops `APIError`'s own RYFT-written 429/503
sentences (here the spec asked for it, so only a nit; read the spec before calling an over-applied fix a regression); `PillButton(.secondary)` ignores `systemImage` (a "glyph added" fix can be a no-op); a new local
"stale version" branch next to an old server-422 test is still untested (assert no POST).

Recurred in T6B.2 (2026-11-19): `CustomExerciseForm`'s `TextField(text:) { Text("Name") }` inside `FormField(Text("Name"))` -
the empty form (Custom exercise with no search text, the common path) reads "Name / Name" in the system placeholder grey, and
the shots only showed a filled name. Grep every `TextField(` inside a `FormField` for a `prompt:`.

**Why:** each needed the screenshots, the probe logs or the plan files, not the diff. **How to apply:** any restyle of forms,
pushed pages with hidden bars, or onboarding frames. See [[review-checks-launch-overlays]], [[review-checks-large-text]],
[[review-checks-dark-launch]].
