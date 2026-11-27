---
name: project-seed-after-refresh
description: Tests that seed (AppState setters, Repository.seed) after a pull must await pullPhases and settled(); how the PR #116 host crash was reproduced (one test alone), and what hid it
metadata:
  type: project
---

PR #116 (2026-11-17): CI's Unit run on 27.2 stopped the host at `Repository.seed while read-model writes are
pending`. The caller was `TodayGaugeEntranceTests/itStaysOffThroughRefreshAndDataChanges`: `state.today =` right after
`await model.refresh()`. `pullToRefresh` returns at phase 2's end; phase 3 (history, user, trend, insights) starts at
the upload and is often still writing. Fix (319f9bb): `await state.pullPhases?.value` then
`await state.repository.settled()` before the setter. `settled()` alone passed 100/100 solo, but it isn't airtight: if
the upload is late, phase 3 submits after `settled()` returns. Since 319f9bb a misuse records an issue on its test
(`MisuseRecorder`, with the caller's frames) instead of trapping the host.

- **Reproduce such races with the single test alone:** `-only-testing:…/test()` plus `-test-iterations 20` hit it 4/20,
  because the main actor is free there. The two suites ×20 (720 runs) under a build and the full plan hit 0.
- **A slowed drain hides it:** a 30 ms sleep per batch in `ReadModelDrain.write` merged phase 3's writes into phase 2's
  batch, so the refresh returned idle. That full-plan probe found nothing, so don't use it as a sweep.
- The other sweep candidates are safe. A seed right after `committed()` is fine (the drain goes idle before tickets
  resolve). ConsentHarness's `uploader.flush()` writes no read model (`connect(repository:)` isn't called).

**Why:** a host crash takes every in-flight test with it and says nothing about the caller.

**How to apply:** for any new test that seeds after a refresh, sync or uploader flush, wait for that work and
`settled()` first. A crash like this needs the solo repro to prove its caller. Related: [[feedback-test-waits-on-actors]],
[[project-os-runtime-probes]].
