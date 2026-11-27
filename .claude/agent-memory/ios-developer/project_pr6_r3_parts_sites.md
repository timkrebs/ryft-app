---
name: project-pr6-r3-parts-sites
description: PR 6 R3 (2026-11-20) — PartsLine on the remaining "a · b" lines, PushedHeader subtitle+parts and loading placeholder, the sweep's leftovers, test/mutant techniques
metadata:
  type: project
---

R3 (branch feat/nocturne-pr6-fix-r3, commits 816bcb5, 52f8e72, 50233ad on a0bd5c2):
- `PushedHeader(subtitle:subtitleParts:)` together: `subtitle` is the line below AX1 (page's own wording, plain " · "),
  parts only from AX1; VoiceOver: spokenSubtitle ?? subtitle ?? parts joined. Used by the exercise page, My Day
  (`MyDayPage.subtitle/subtitleParts(_:isToday:isYesterday:locale:)` statics) and the activity detail
  (`subtitleParts(locale:)`).
- `PushedHeader(loading:placeholder:)` (EmptySlot extension): the outline capsule in the title's place, a clear one-line
  title under it; SessionDetailView's nothing-known header uses it (it was an overlay over the whole header).
- Rows: About you + Sleep need sheet use `.detailParts`; `BodySettingContent.sourceParts` drawn by
  `PartsLine(parts, joined: source, spoken:)`, centred; `BedtimePlanner.summaryDetailParts(_:)` static for Profile's row;
  start sheet `option(detailParts:)` + `StartOptionText` (todayParts/lastParts/planParts/line).
- Sweep leftovers (listed, not fixed): Strain workout detail `when` (PR 5 hand-drawn header), Sleep header "Last night ·",
  start sheet plan-day rows, plan page lines, Strain→Train details, import/AddExercise row metas, Profile diagnostics
  (Sync details, Licences, Check sync, status row), Today/Journal sentence keys.

**Why:** validator's AX3 shots; the shared helpers make each site a one-line change.

**How to apply:**
- Pixel test of a stacked subtitle: ink box under the title line (header node frame minus `lineSize(title)`), width ≤ widest
  part + 2, height ≥ 2.4 caption lines (3 parts). Squat ("Barbell · Quads · Glutes") is the 3-part mock exercise.
- Outline (surface on background) threshold: sum |Δrgb| > 0.05 (surface−background ≈ 0.10).
- Mutants that also break the hosted test (any change to a site's subtitle shows in VoiceOver value or pixels) go in
  their own group; 3 groups for 11 mutants.
- `LargeTextHostedTests.startSheetDetailWraps` lays out the drawn detail: update it when the drawn text changes.
- Unit plan on an unsigned build (`CODE_SIGNING_ALLOWED=NO`): `AppAttestHeaderTests/theKeychainStoreWritesThatItemAndReadsItBack`
  fails with -34018 (no keychain entitlement without signing; from #128, not ours, reproduces alone);
  `AppAttestRequiredTests/fiveConcurrentRefusalsWaitForOneRenewal` can fail under load 200+ (heldCount 0) and passes alone.
- Shot scene for the activity detail: use `tapprefix:myday.view.row.activity.`; a `tapin` at a row low on the page hits
  the floating Add activity button (uiv-6's `x-b21` is that sheet, not the detail).
