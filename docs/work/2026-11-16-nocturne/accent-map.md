# Nocturne PR 5 — T5.0 accent map (every `Theme.accent` use)

Generated 2026-11-18 from `main` at 9af6049 (`grep -rn "Theme\.accent\b" Ryft`: **229 uses in 68 files**), then classified by hand
where the pattern was not enough. This is the appendix of `design.md` §P5-1. The rule is L27: teal is recovery only; links,
toggles, checkmarks and icon tints are `textPrimary`; the primary button is the light pill; Volt is the one marked thing.

After T5.0 `Theme.accent`, `Theme.onAccent` (25 uses → `Theme.background`) and `Theme.teal` do not exist: the compiler finds
every site. The legend reads `Theme.recovery`, `Theme.metricSleep`, `Theme.metricStrain`.

## Classes

| Class | Count | Pattern | Replacement |
|---|---|---|---|
| **P** | 12 | `ProgressView().tint(Theme.accent)` | `.tint(Theme.textSecondary)` (a spinner is never a call to action) |
| **T** | 38 | `.tint(Theme.accent)`: 2 app-wide (`RyftApp.swift:167`, `PreviewSupport.swift:58`), the rest on a control | The two app-wide ones become `.tint(Theme.textPrimary)`; a `Toggle` loses the line and gets `.toggleStyle(.ryft)` (≈ 20 sites); a menu `Picker`, `DatePicker`, `Stepper`, `DisclosureGroup` loses the line (it inherits the app tint) |
| **M** | 23 | glyph in `Theme.accent` on a `Theme.accent.opacity(0.1x)` circle or capsule | A circle becomes `IconDisc` (glyph `textPrimary`, 1 pt ring `textPrimary` 16 %, no fill); a capsule chip becomes `surfaceRaised` with `textPrimary` ink |
| **F** | 15 | solid `Theme.accent` fill (usually with `onAccent` ink), also the conditional fills | The inverse fill: `textPrimary` with `Theme.background` ink and glyph. A button-sized one is a `PillButton` instead |
| **G** | 25 | bars, rings, rules, focus borders drawn in `Theme.accent` | `textPrimary` (progress, step rule, rest ring, focus border); never a metric colour unless the value is that metric |
| **S** | 16 | `isSelected ? Theme.accent : …` | `textPrimary`, and the selected state also changes shape (filled glyph, 1.5 pt ring, inverse chip), because hue is gone as a cue |
| **X** | 74 | `.foregroundStyle(Theme.accent)` on a glyph or text | A glyph: `textPrimary`. Text that is a control on its own line: `ryftLink()` (`textPrimary`, underlined). A status glyph: `textPrimary` and its shape carries the state |
| **D** | 26 | data, legend or special | The table at the end |

## Per file (classes and line numbers)

| File | Uses |
|---|---|
| `App/RyftApp.swift` | **T** 167; |
| `Design/Card.swift` | **G** 131; **S** 111 122; |
| `Design/DeltaLabel.swift` | **S** 55 56; |
| `Design/EffortScale.swift` | **F** 82; |
| `Design/ImportProgressBar.swift` | **G** 22 26; |
| `Design/InsightCard.swift` | **X** 60; |
| `Design/MetricGauge.swift` | **X** 256; |
| `Design/StatusViews.swift` | **P** 147; **M** 1411; **F** 592 947; **S** 686; **X** 149 286 292 313 924 1409; |
| `Design/StepRule.swift` | **S** 14; |
| `Design/UndoToast.swift` | **X** 34; |
| `Features/Activities/ActivityDetailView.swift` | **M** 108; **X** 106; |
| `Features/Activities/AddActivitySheet.swift` | **T** 63 160; **M** 99; **X** 97; |
| `Features/Activities/AddSleepSheet.swift` | **T** 47 141; |
| `Features/Activities/SplitsTable.swift` | **G** 149; |
| `Features/Activities/SportPicker.swift` | **M** 98; **X** 96 107; |
| `Features/Auth/AuthComponents.swift` | **X** 187; |
| `Features/Auth/CheckInboxView.swift` | **X** 18; |
| `Features/Auth/SetNewPasswordView.swift` | **X** 25; |
| `Features/Auth/WelcomeView.swift` | **G** 134; **X** 132; |
| `Features/Journal/BehaviorsSection.swift` | **S** 99 100; |
| `Features/Journal/JournalSettingsView.swift` | **T** 36; **X** 56; |
| `Features/Journal/JournalViews.swift` | **T** 120; **F** 169; **X** 16 38; |
| `Features/Onboarding/HealthIllustration.swift` | **G** 14 16; |
| `Features/Onboarding/HealthPermissionView.swift` | **T** 693; **S** 814; **X** 606 757 792 1297 1329 1409; |
| `Features/Profile/FeatureFlagsDebugView.swift` | **T** 101; **X** 106; |
| `Features/Profile/NotificationSettingsView.swift` | **T** 130 157; |
| `Features/Profile/ProfileView.swift` | **P** 463 1191; **T** 249 262 319 454 514 557 889 2162; **M** 1878; **F** 2479; **S** 2238; **X** 210 219 291 391 488 1051 1128 1876 2132 2548; |
| `Features/Sleep/SleepPlannerView.swift` | **P** 36 177; **T** 24 307 375 404 441; **X** 216 333 432; |
| `Features/Sleep/SleepView.swift` | **P** 492; |
| `Features/Strain/StrainComponents.swift` | **M** 83 126 168; **X** 81 124; |
| `Features/Strain/StrainView.swift` | **P** 118 147; |
| `Features/Strain/WorkoutDetailView.swift` | **P** 116; **M** 69; **X** 67; |
| `Features/Today/TodayView.swift` | **T** 684 770; **F** 731; **X** 670; |
| `Features/Train/History/ExerciseDetailView.swift` | **X** 57 131; |
| `Features/Train/History/TrainHistoryView.swift` | **P** 24 129; **M** 72; **X** 70; |
| `Features/Train/Import/BodyweightQuestion.swift` | **G** 84; **S** 62; |
| `Features/Train/Import/DateRangeControl.swift` | **T** 26; **X** 88; |
| `Features/Train/Import/ExerciseMatchRow.swift` | **X** 198; |
| `Features/Train/Import/ImportChooseView.swift` | **T** 72 107 123 176; |
| `Features/Train/Import/ImportFlowView.swift` | **T** 24; **X** 176; |
| `Features/Train/Import/ImportMapView.swift` | **T** 169; |
| `Features/Train/Import/ImportPreviewView.swift` | **T** 132; |
| `Features/Train/Import/ImportRejectionRow.swift` | **X** 94; |
| `Features/Train/Import/ImportResumeRow.swift` | **M** 19; **X** 17 48 84; |
| `Features/Train/Import/ImportSessionRow.swift` | **S** 113; |
| `Features/Train/Plans/PlanBuilderView.swift` | **T** 119 292; **M** 197 362; **X** 195 360; |
| `Features/Train/Plans/PlansView.swift` | **P** 228; **M** 348; **X** 261 298 346; |
| `Features/Train/Session/AddExerciseSheet.swift` | **T** 243; **M** 289; **F** 340; **G** 198; **X** 287; |
| `Features/Train/Session/CollapsedExerciseRow.swift` | **G** 125 129; **X** 17; |
| `Features/Train/Session/EditTargetsSheet.swift` | **M** 233; **S** 231; **X** 140; |
| `Features/Train/Session/ExerciseCard.swift` | **M** 193; **G** 214 241 474 703; **S** 258; **X** 550 602; |
| `Features/Train/Session/ExercisePage.swift` | **X** 400; |
| `Features/Train/Session/ExerciseStrip.swift` | **F** 83; **G** 74 173; |
| `Features/Train/Session/RestBar.swift` | **F** 178 214; **G** 72 88 96 99; |
| `Features/Train/Session/RestPill.swift` | **F** 96; **G** 78; |
| `Features/Train/Session/RestSheet.swift` | **M** 113; **S** 111; **X** 174 222; |
| `Features/Train/Session/RestTimerView.swift` | **M** 108 206; **F** 126; **X** 65 106 204; |
| `Features/Train/Session/SessionView.swift` | **F** 289; **G** 291; **S** 540; **X** 487; |
| `Features/Train/TrainComponents.swift` | **M** 131 150; **F** 200; **G** 205 220; **X** 148; |
| `Features/Train/TrainSection.swift` | **M** 142; **F** 157; **X** 182 252; |
| `Preview/PreviewSupport.swift` | **T** 58; |

## D: data, legend and special cases (26)

| File:line | What it is | Replacement |
|---|---|---|
| `Design/MetricSpec.swift:90`, `:93` | Readiness and recovery colour | `Theme.recovery` (the same teal; the legend) |
| `Design/MetricSpec.swift:107` | HRV colour | `Theme.recovery`: HRV belongs to recovery (design.md §P5-5, decision D5-9) |
| `Design/MetricSpec.swift:134` | Estimated 1RM colour | `Theme.textPrimary` (a strength number, not a metric of the rings) |
| `Design/RangeBar.swift:35` | "In range" colour, catalog only | `Theme.recovery` (a personal range of a recovery metric) |
| `Design/ScoreRing.swift:11` | Default ring colour (only `DateStrip` uses it, for strain) | `Theme.metricStrain` |
| `Design/Card.swift:170` | Capability state `.yes` | `textPrimary` with the checkmark glyph |
| `Design/MetricTile.swift:8` | Default tint | deleted with the tile (only Strain used it, §P5-3) |
| `Design/MetricGauge.swift:241` | Doc comment | the file is deleted (§P5-3) |
| `Design/StatusViews.swift:791` | Status `.ok` | `textPrimary` with the check glyph |
| `Features/Strain/StrainComponents.swift:165` | `StrainPill` ink | deleted: the row shows the strain as a 20 pt Light `textPrimary` number |
| `Features/MyDay/MyDayRow.swift:127`, `:128` | Activity row tint and disc | `textPrimary` glyph on an `IconDisc` (PR 6 restyles the row) |
| `Features/MyDay/MyDayCard.swift:361` | "Try again" | `ryftLink()`; `textTertiary` while retrying |
| `Features/Profile/ProfileView.swift:1354` | `PrimaryButton.background` | `PrimaryButton` is deleted |
| `Features/Train/Plans/PlansView.swift:142` | "Active" label | `textPrimary` (paused stays `warning`) |
| `Features/Train/Plans/PlansView.swift:323` | Superset glyph | `textPrimary` |
| `Features/Sleep/SleepView.swift:455` | `ProgressBar` default colour (Sleep need) | `Theme.metricSleep` |
| `Features/Sleep/SleepView.swift:563` | Regularity `.steady` | `Theme.metricSleep` (consistency is a sleep metric); `.fair` becomes `textSecondary` |
| `Features/Train/TrainComponents.swift:129`, `TrainSection.swift:140` | `TealButtonStyle` / the plan row's ink | `PillButton` / `textPrimary` |
| `Features/Train/Import/ImportResultView.swift:393` | Row role colour | `role == .destructive ? Theme.alert : Theme.textPrimary` |
| `Features/Train/Session/RestTimerView.swift:261` | Rest zone at 10 s | `textPrimary` |
| `Features/Train/Session/ExerciseCard.swift:256`, `:699` | Active set fill; label ink | `textPrimary` (the completed set: inverse fill with a `background` check) |
| `Features/Train/Session/SessionView.swift:297` | Finish button ink | `Theme.background` on the `textPrimary` fill, `textPrimary` on the outline (T5.0 swaps the token; PR 6 restyles the screen) |

Uses of `accent` that this grep does not see (no `Theme.` prefix, inside `Theme.swift`): `band(forScore:)` returns `recovery` for 67 and
up (the readiness band, stays teal: it is the recovery metric's band); `color(for severity)`: info becomes `textSecondary`, notice
`warning`, warn `alert`; `zones` (HRR zone colours, including `accentSecondary`) is deleted with `ZoneBar`.

## D3: light and `de` previews that PR 5 removes

92 files carry a `SchemePair`, a `scheme: .light` preview, a "· light" or "· de" preview (`grep -rlE 'scheme: \.light|#Preview\("[^"]*(light|· de)|SchemePair' Ryft`). Each keeps its dark previews (default and AX3) and loses the rest; `SchemePair` then has no caller and is deleted, `DarkPreview` stays. The tickets of §P5-12 split the list by directory; `Features/Strain`, `Insights`, `Profile`, `Sleep` go with their screen (T5.2–T5.5), the rest with T5.0b.

- `Ryft/Auth/AppleSignInButton.swift`
- `Ryft/Design/ActivityStateMark.swift`
- `Ryft/Design/BedtimeStrip.swift`
- `Ryft/Design/Card.swift`
- `Ryft/Design/DateStrip.swift`
- `Ryft/Design/DeltaLabel.swift`
- `Ryft/Design/EffortScale.swift`
- `Ryft/Design/ImportProgressBar.swift`
- `Ryft/Design/InsightCard.swift`
- `Ryft/Design/MetricGauge.swift`
- `Ryft/Design/MetricTile.swift`
- `Ryft/Design/RangeBar.swift`
- `Ryft/Design/ScoreRing.swift`
- `Ryft/Design/SegmentedPicker.swift`
- `Ryft/Design/SleepNeedBar.swift`
- `Ryft/Design/SourceBadge.swift`
- `Ryft/Design/StatusViews.swift`
- `Ryft/Design/StepRule.swift`
- `Ryft/Design/TrendChart.swift`
- `Ryft/Design/UndoToast.swift`
- `Ryft/Design/ZoneBar.swift`
- `Ryft/Features/Activities/ActivityDetailView.swift`
- `Ryft/Features/Activities/AddActivitySheet.swift`
- `Ryft/Features/Activities/AddSleepSheet.swift`
- `Ryft/Features/Activities/SplitsTable.swift`
- `Ryft/Features/Activities/SportPicker.swift`
- `Ryft/Features/Auth/AuthComponents.swift`
- `Ryft/Features/Auth/CheckInboxView.swift`
- `Ryft/Features/Auth/CreateAccountView.swift`
- `Ryft/Features/Auth/LogInView.swift`
- `Ryft/Features/Auth/ParkedActivitiesNotice.swift`
- `Ryft/Features/Auth/WelcomeView.swift`
- `Ryft/Features/Insights/InsightsView.swift`
- `Ryft/Features/Journal/BehaviorsSection.swift`
- `Ryft/Features/Journal/JournalSettingsView.swift`
- `Ryft/Features/Journal/JournalViews.swift`
- `Ryft/Features/MyDay/MyDayCard.swift`
- `Ryft/Features/MyDay/MyDayRow.swift`
- `Ryft/Features/MyDay/MyDayView.swift`
- `Ryft/Features/Onboarding/HealthIllustration.swift`
- `Ryft/Features/Onboarding/HealthPermissionView.swift`
- `Ryft/Features/Profile/FeatureFlagsDebugView.swift`
- `Ryft/Features/Profile/NotificationSettingsView.swift`
- `Ryft/Features/Profile/ProfileView.swift`
- `Ryft/Features/Sleep/SleepPlannerView.swift`
- `Ryft/Features/Strain/StrainComponents.swift`
- `Ryft/Features/Strain/StrainView.swift`
- `Ryft/Features/Strain/WorkoutDetailView.swift`
- `Ryft/Features/Today/TodayView.swift`
- `Ryft/Features/Train/History/ExerciseDetailView.swift`
- `Ryft/Features/Train/History/TrainHistoryView.swift`
- `Ryft/Features/Train/Import/BodyweightQuestion.swift`
- `Ryft/Features/Train/Import/DateRangeControl.swift`
- `Ryft/Features/Train/Import/ExerciseMatchRow.swift`
- `Ryft/Features/Train/Import/ImportChooseView.swift`
- `Ryft/Features/Train/Import/ImportDetectedView.swift`
- `Ryft/Features/Train/Import/ImportFileSlot.swift`
- `Ryft/Features/Train/Import/ImportFlowView.swift`
- `Ryft/Features/Train/Import/ImportMapView.swift`
- `Ryft/Features/Train/Import/ImportPickView.swift`
- `Ryft/Features/Train/Import/ImportPreviewView.swift`
- `Ryft/Features/Train/Import/ImportProfileRows.swift`
- `Ryft/Features/Train/Import/ImportRejectionRow.swift`
- `Ryft/Features/Train/Import/ImportResultView.swift`
- `Ryft/Features/Train/Import/ImportResumeRow.swift`
- `Ryft/Features/Train/Import/ImportSessionDetailSheet.swift`
- `Ryft/Features/Train/Import/ImportSessionRow.swift`
- `Ryft/Features/Train/Import/ImportSummaryCard.swift`
- `Ryft/Features/Train/Import/ImportWarningsList.swift`
- `Ryft/Features/Train/Plans/PlanBuilderView.swift`
- `Ryft/Features/Train/Plans/PlansView.swift`
- `Ryft/Features/Train/Session/AddExerciseSheet.swift`
- `Ryft/Features/Train/Session/AllSetsDoneCard.swift`
- `Ryft/Features/Train/Session/CollapsedExerciseRow.swift`
- `Ryft/Features/Train/Session/EditTargetsSheet.swift`
- `Ryft/Features/Train/Session/ExerciseCardLastTimePreview.swift`
- `Ryft/Features/Train/Session/ExerciseMenuItems.swift`
- `Ryft/Features/Train/Session/ExerciseNotesSheet.swift`
- `Ryft/Features/Train/Session/ExerciseStrip.swift`
- `Ryft/Features/Train/Session/FocusedSessionView.swift`
- `Ryft/Features/Train/Session/RestBar.swift`
- `Ryft/Features/Train/Session/RestPill.swift`
- `Ryft/Features/Train/Session/RestSheet.swift`
- `Ryft/Features/Train/Session/RestTimerView.swift`
- `Ryft/Features/Train/Session/SessionPager.swift`
- `Ryft/Features/Train/Session/SessionToastOverlay.swift`
- `Ryft/Features/Train/Session/SessionView.swift`
- `Ryft/Features/Train/Session/SetColumnPreview.swift`
- `Ryft/Features/Train/TrainComponents.swift`
- `Ryft/Features/Train/TrainSection.swift`
- `Ryft/Preview/PreviewSupport.swift`
- `Ryft/Push/PushPrePromptCard.swift`

The 74 committed `docs/screenshots/*-light*.png` (PR 1 review row 6) go in the same PR as the last previews; `make screenshots` is dark only after PR 1.
Tests that render a light variant (PR 1 design §9: they pass because light resolves to the dark tokens) lose the variant: `FocusedSessionShotsTests`, `HostedAccessibility`, `ImportScreenshotTests`, `FocusedPolishHostedTests` and `NocturneSharedShotsTests` (grep `colorScheme` and `.light` in `RyftTests`).
