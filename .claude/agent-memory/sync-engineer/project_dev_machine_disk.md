---
name: project-dev-machine-disk
description: The dev Mac's disk runs near full when several agents build in parallel; how to build and test without filling it
metadata:
  type: project
---

On 2026-10-21/22 the shared data volume had 0.5–2.5 GiB free while several agents built in parallel; one of
my Release builds died with "No space left on device".

**Why:** each agent keeps its own DerivedData and worktree in the session scratchpad, and result bundles and
test diagnostics add hundreds of MB per run.

**How to apply:** reuse the one DerivedData you were given (no clean builds); pass
`-collect-test-diagnostics never` (it also avoids a 600 s hang after a failing test) and delete `.xcresult`
bundles after reading them; delete Release products after a compile check; a watchdog (`df -m`) can stop a
build before the disk fills. Delete only your own artifacts. Related: [[feedback-test-waits-on-actors]].

**Mutant restores (2026-11-22, N3 round 2):** the disk filled during a mutant build and the script's restore of the
mutated source then failed with `ENOSPC`. Restore the file right after `build-for-testing` (the built product is what
the test runs), assert the restore, and have the gate refuse to start a run under the coordinator's floor (8 GB):
`df -g /System/Volumes/Data`. A mutant build leaves mutated products: rebuild HEAD before the full plan.
