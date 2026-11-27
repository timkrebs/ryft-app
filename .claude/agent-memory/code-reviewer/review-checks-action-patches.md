---
name: review-checks-action-patches
description: RYFT checks when an action patches a cached server overview from its own answer (PR 6 follow-ups F1, TrainLibrary.patchCatalog, 2026-11-21) - last-answer-wins against an in-flight refresh, two actions answered out of order, UserDefaults.standard keys shared by parallel Swift Testing suites, contract checked against the platform's store SQL, unobserved UserDefaults writes
metadata:
  type: feedback
---

From the `fix/pr6-follow-ups` review (read-only, 2026-11-21). The patches matched API.md and the platform's SQL; what was left:
- **A refresh in flight undoes the patch.** `TrainLibrary.refresh()` writes `catalog` and `today` whenever its binding holds,
  with no check that an action wrote since it was sent. A pre-action `GET /v1/plans` that answers after the action's `then`
  (and after its re-read) puts the old overview back. Ask for a write counter that `patchCatalog`/`reloadCatalog` bump and
  `refresh` compares before writing. Two actions in flight from two view models (each has its own `working`) can also be
  answered out of order. That needs one action at a time in the library.
- **`UserDefaults.standard` keys in tests.** The Unit plan runs suites in parallel (`SWT_..._WIDTH=4`, random order) in one
  process, and `@MainActor` tests interleave at every await. `.serialized` only covers its own suite. The
  `train.pausedPlanID` key is written by `setPaused`, removed by `enrolled`/`wipe()`, and also set by hosted-window tests
  across `w.settle()`. A save/restore `defer` doesn't isolate tests either. Grep every new test that drives `enroll`,
  `setPaused`, `deletePlan` or `wipe()`, and ask for the key in the per-rig store or an injected `UserDefaults`.
- **Contract check recipe:** read `plattform/backend/internal/store/train.go` (`ActiveEnrollment` `WHERE status='active'`,
  `Enroll`, `PauseEnrollment`, `DeletePlan`). It's faster and more exact than API.md prose for "what does GET report now".
- **UserDefaults writes aren't observed.** Before the patch, a `then` that only touched UserDefaults relied on the re-read's
  `catalog` write to re-render. Check that each patch mutates an observed property too (with `catalog == nil` it doesn't).
- A test edit that drops an equality to a removed shared field (`failure == library.error`) leaves `!= nil`. Ask for the
  sentence to be pinned another way.

**Why:** the suite was green with 16 mutants. Each of these sat between the tests' sequential fixtures and the app's real
concurrency, or in another suite. **How to apply:** any fix that writes an action's answer into a cache that a refresh
also writes, or any new test on Train's paused plan. See [[review-checks-fix-round-reverify]], [[review-checks-local-overrides]],
[[review-checks-ownership-lists]].
