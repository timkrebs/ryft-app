---
name: review-checks-side-effect-passes
description: RYFT review checks for "save at once, side effects in serialized passes" fixes (C4 re-verification, Bedtime & wake, 2026-11-19) - memo flags not reset after an owner-change undo, sibling surfaces left stale, off-main mock counters racing polls, OS-specific SwiftUI probes, sticky page modes in retained tab stacks, tests that hang when the fix is reverted
metadata:
  type: feedback
---

From the C4 fix-round re-verification (BedtimePlanner passes + one shared editor, read-only, 2026-11-19). The fixes held; these were left:
- **A memo of what's set (`alarmsSet`/`alarmsKnown`) must be invalidated when a stale pass undoes its effect.** "Scheduled, then
  cancelled because the owner moved" left the memo saying "set"; only the account-change path reset it (teardown), not a demo
  toggle (AccountBinding.demo moves the owner, nothing calls accountChanged). Same for a catch that returns before its cancel.
  Ask: after every early return or undo, does the next pass reconcile, or does it hit `if known, set == want { return }`?
- **A fix for one stale surface: list every surface fed by the same value.** Reminders were moved off the old bedtime after an
  offline wake change; the widget's `repository.tonightBedtime` (shown when in the future) was not, and Today said "needs a
  connection". Grep the writes of the shared value and check each branch that ends without a plan.
- **The app and unit-test targets do NOT use approachable concurrency** (pbxproj: only widget + UI tests set it; STATUS.md
  "Finding #11"). Nonisolated async (MockPlatformAPI calls, test gates) runs on the global executor, so a mock that appends to a
  recorded list and then registers in a gate is two steps a main-actor `eventually` poll can split. A bare `#expect` right after
  an `eventually` on the first step races. Prefer counting the event itself (e.g. cancellations) over a snapshot count.
  The skill text says the opposite: trust the pbxproj.
- **A guard test for a SwiftUI behaviour (a conditional `navigationDestination` host not popping) proves only CI's newest
  runtime** (scripts/ci-simulator.sh), not the 18.6 deployment target, and a fixed sleep plus a final check after Back has no
  positive proof the host left while covered. Prefer the always-mounted host; else ask for a probe on 18.x and a positive signal.
- **Page modes stored per page (`opening: .setUp`) persist in TabView stacks**: every later disappear re-fires them (set up
  again after Turn off elsewhere). Ask whether the mode is consumed once used.
- **Tests that hang, not fail, when the fix is reverted** (awaiting `settle()` behind a gate released after it): ask for
  `.timeLimit`. And check a confirmation dialog test actually taps the destructive action, not just inspects it.
- **Comments claiming parity** ("as on Sleep -> Bedtime: not announced"): grep the other screen; it still announced.
- **String catalog owned by a later copy ticket**: list the new keys and the replaced key that goes stale on the next
  sync (`lint-strings.py` fails on stale keys).

**Why:** these survived a green suite after a fix round that addressed every first-review item.
**How to apply:** any re-verification of serialized side effects, owner/epoch guards or shared editors. See
[[review-checks-autosave-editors]], [[review-checks-setting-editors]], [[review-checks-outbox-queues]],
[[review-checks-polling-rules]].
