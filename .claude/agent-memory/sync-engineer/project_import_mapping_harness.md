---
name: project-import-mapping-harness
description: How to iterate on the training-import matcher and alias catalogue in seconds (swiftc harness) and run the real-sample check with counts only
metadata:
  type: project
---

The training import's pure code (`Ryft/Train/Import/{Model,Parsing,Formats,Build}` and `Mapping/` without the SwiftData
files `ImportMapping.swift`/`ImportMappingStore.swift`) builds as a macOS tool with `xcrun swiftc -O -swift-version 5`
plus a stub file and a `main.swift`. Do NOT pass `-parse-as-library` (it rejects top-level code in main.swift).
- **The stub:** extract it with python from `Networking/Models.swift`, from `enum ExerciseKind` up to the
  `/// \`POST /v1/exercises\`` comment (ExerciseKind, LoadType, Muscle, decodeLenientList, Exercise), plus
  `enum MainThread` from `Environment/HealthStore.swift`.
- **Checks it ran in I3 (2026-10-23):**
  - every alias name resolves to its slug (the same check as `ExerciseAliasesTests.everyAliasResolvesToItsSlug`);
  - probes of single names;
  - timings;
  - the real sample (`local-samples/*.csv` in the user's checkout, read only), printing **counts only**.
  Each round took seconds, against about 3 minutes for build-for-testing.
- **Built-in library:** `RyftTests/Fixtures/Import/builtin-exercises.json` snapshots the platform seed
  (`../plattform/backend/internal/db/seed/exercises.json`). Its ids are
  `uuid5(1c7e3b9a-5d2f-4e8b-9a61-3f0d2c4b7e15, "exercise:<slug>")` (`backend/internal/train/train.go`); back-squat
  = `053b5627-…`, as in API.md. Regenerate it when the platform adds built-ins.

- **Two keys since the I3 review (2026-10-23):** `SourceExerciseKey` (`normalizer.key`) is the frozen id key.
  Since the lead's call it is fully vocabulary-free: `fold(name)` and `fold(field)`, never an equipment id. It is
  pinned by `Fixtures/Import/source-keys.golden.json` (the harness's `golden` mode generates it; Python's
  `unicodedata` cross-checked it). `MatchKey` (`normalizer.matchKey`) is the vocabulary key, used only for matching and
  for a custom exercise's kind. Harness probes of matching must use `matchKey`.
- **Probe modes worth keeping (re-review, 2026-10-23):**
  - `idem`: fold idempotence over all 0x10FFFF scalars in three contexts, about 2 s;
  - `override`: any accepted match a field changes, which must be refinement-only;
  - `tables`: Swift's White_Space and Default_Ignorable ranges, to keep `scripts/import-fold-check.py`'s tables
    honest after an OS or Unicode update.
- **Mutation testing:** `scratchpad/rv-i3/mutate-i3r.py` runs on a copy of the worktree with its own DerivedData,
  without parallel testing. Check that every anchor string occurs exactly once first; one duplicate aborts the run.

**Why:** the alias catalogue is about 130 entries. One shadowed or filtered alias would otherwise take a full
xcodebuild round trip to find.

**How to apply:** any I5/I4 change to matching, normalisation or `exercise-aliases.json`. Never print exercise names
from the real files. Related: [[project-track-fixture-evaluation]], [[project-dev-machine-disk]].
