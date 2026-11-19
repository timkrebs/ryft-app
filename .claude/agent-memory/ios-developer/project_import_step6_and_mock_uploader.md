---
name: project-import-step6-and-mock-uploader
description: Training import step 6 rules (no way back, counts of what was written, VoiceOver per phase) and the preview uploader's weak env trap
metadata:
  type: project
---

- `TrainImportUploader` holds its `AppEnvironment` weakly. A preview uploader built on an inline `.preview()` env loses it
  at once: no binding, so `uploadsAvailable` is false everywhere and step 5 shows "Keep on this iPhone" by default.
  `ImportMockData.uploader(_:available:)` keeps two static envs (flag on, flag off) for that reason.
- A preview uploader's `markResultSeen()` and `discard()` do nothing (no loaded job). To test Done or Discard taps, run a
  real job on `ImportUploadHarness` and pass `h.uploader` to `ImportMockData.flow(.result, uploader:)`.
- To capture announcements, copy the seeded flow's `deps` (a struct; `announce` is a var), set `announce`, build a new
  `ImportFlowModel(deps:)` and copy `path`.
- Step 6 has no way back: `.navigationBarBackButtonHidden(step == .result)` (the subpage keeper refuses a swipe when
  `hidesBackButton` is set), and the probe also turns off `interactiveContentPopGestureRecognizer` on iOS 26.
- Counts on the result say what was written: `plansImported` and `sessionsImported`, never `plans.done` or `sessions.done`
  (`newer_on_server` counts as done but was left as it is). `ImportPlanSummary.result` carries the code; `isImported`.
- The lead word lives in `ImportResultText.lead(_:hasRejected:)`; `announcement(from:to:)` decides what VoiceOver hears
  on a phase change (the lead when its words change, the result when it finishes). Notices keep `announces: false`.
- Tests that strip comments before a token scan: copy `ProfileSubpagesTests.noTeal`'s regex `(^|[^:])//.*`; match
  `PrimaryButton` as a word, since `ImportPrimaryButton` is a `PillButton`.
