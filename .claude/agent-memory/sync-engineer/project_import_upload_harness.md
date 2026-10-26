---
name: project-import-upload-harness
description: How the training import's uploader is tested (I5, 2026-10-26) — ImportUploadHarness with separate live/demo fakes, wipe vs accountChanged for dropped answers, and the builder's fixture decisions
metadata:
  type: project
---

`RyftTests/Import/ImportUploadHarness.swift` (I5, `feat/import-upload`) builds an `AppEnvironment` with a real
`AuthService` on `MockAuthClient` (its wipe runs `TrainStore.wipe` on the test store), **two** `MockPlatformAPI`s
(`live`, `demoAPI`, each with its own `MockTrainSource()`, never `.shared`), a private `Settings` with `demoOverride: nil`
(so `h.settings.demoMode = true` toggles demo without touching `Settings.shared`), `StaticFlags([.trainImport: …])`, a
`ConnectivityMonitor.preview` you flip with `update(_:)`, and `relaunch()` for a new uploader on the same store.

Two traps found while writing it:
- **Dropped answers vs cancelled requests.** `uploader.accountChanged()` cancels the pass, and
  `MockTrainImportSource.importTraining` checks cancellation after its `beforeImport` hook, so the held request is
  never stored. To prove an answer is *dropped* by the generation check, sign in B (the wipe bumps `TrainStore.epoch`)
  and release the hold *before* calling `accountChanged()`, as the app does a runloop later.
- **"Finished" before it's stored.** `status.phase == .finished` comes from the progress; `finishedAt` is written one
  await later. Code that decides "unfinished" must use the same rule as the status (`hasWork(loaded)`), or a test that
  waits for `.finished` and starts the next import races it.

Builder tests use `ImportBuildFixture.decisions()` (every fixture source mapped to an invented library exercise, pull-ups
and push-ups bodyweight) on `ap-plans.csv` + `ap-workouts.csv`; known values: 6 sessions, 38 performed and 4 skipped
sets, overhead-press target 47.5 (same plan day) vs 52.5 (newest overall). Id vectors were computed with Python's
`uuid.uuid5` (ADR 0007 Amendment 2).

**Why:** the uploader's account/demo binding and resume are the review's focus; these patterns make them testable
without `Settings.shared` or fixed sleeps.

**How to apply:** C2 (live client) and any later change to `TrainImportUploader`/`ImportBuilder`. Related:
[[feedback-test-waits-on-actors]], [[project-demo-setting-in-tests]], [[feedback-tests-pin-decisions]].
