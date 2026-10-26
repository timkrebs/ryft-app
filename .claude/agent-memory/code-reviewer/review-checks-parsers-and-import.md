---
name: review-checks-parsers-and-import
description: RYFT review checks for file parsers/importers (training CSV import I2) — tautological/charged work counters, classifier ambiguity, greedy anchors, DST sub-hour gaps + zone brute force, encoding fallbacks, SwiftFormat skipping Build/, error cases vs ui.md states, counts-only runs on local samples
metadata:
  type: feedback
---

Found in the I2 "CSV import parser" review (2026-10-23); the implementer's 80 tests and 3,000-case fuzz were green:
- **Work counters that can't fail.** `ParseStats.steps` = 1 per line + fields (≤ 3) ⇒ ≤ 4 × lines by construction, so
  "quadratic work fails as a count" was false. Grep every increment of a "steps" counter; real super-linear risk is
  inside a line. Measure instead: 8 MiB worst-case files per shape (digit runs, many ` · ` parts, CR-only, one line).
- **Classifier fast paths steal other line kinds:** a set-row test "first field is an integer" also eats a session
  header titled `"5"` → its exercises join the previous session. Probe each fast path with the other kinds' shapes.
- **Fallback anchors run greedy:** "day-only" plan refs matched `Arms · Day 3 · Standalone workout`. Ask for the strict
  form first; spot-mutate "first run" → "last run" to see if any test notices.
- **`Calendar.nextDate(.nextTimePreservingSmallerComponents)` jumps a whole day** for a 30-min gap
  (Australia/Lord_Howe 2026-10-04 02:15 → next day), and `repeatedTimePolicy: .last` misses 30-min folds. Probe
  Lord_Howe, Havana/Santiago/Beirut (midnight gaps), Apia 2011-12-30, Tehran 2021 besides Berlin/NY.
- **SwiftFormat 0.64 skips any folder named `Build`** (built in, config-independent), so CI's `swiftformat --lint .`
  never checks it; SwiftLint does. Check new folder names against tool skip lists, not just `.gitignore`.
- **One error case for two ui.md states** (`.empty` = blank file P6 *and* recognised-but-empty D7, warnings dropped).
  Map every thrown error to the ui.md state table.

Re-review of the fixes (a74ff0e, 2026-10-23) — what the fixes broke or missed:
- **Charged work meters** (`visited += field length` per scanner call) catch extra *calls*, not quadratic work *inside*
  a helper: a quadratic `CSVFields.parts` kept `visited` identical while 64 KiB went 0.01 → 0.7 s. Mutate a helper's
  internals, not just its call sites; ask for one coarse nightly time ratio.
- **Whole-file encoding fallbacks** keyed on "not valid UTF-8" flip a BOM-less UTF-8 file with one stray byte (or a
  truncated last character) to Windows-1252: every `·` becomes `Â·`, all plan refs and equipment lost, only a note.
  Suggest "invalid sequences outnumber well-formed multi-byte ones". Also check detection decodes the same way as
  parse (German cp1252 plans file: parse fine, detect `.none` → `.notRecognised`).
- **Zone math, brute force:** `TimeZone.nextDaylightSavingTimeTransition(after:)` lists every offset change (raw ones
  too); tzdata 1900–2100 has no regime shorter than 36 h (443 zones, 45,885 transitions). Compare against ground truth
  at minute walls around every transition (1.6 M walls, ~2 s) and mutate the resolver to prove the harness has teeth.

Technique: compile the pure sources with a `main.swift` via `swiftc -O` in my own scratch dir (stub `MainThread`); run
the parser on `local-samples/` printing **counts only** (sessions, warnings by kind/line, non-ASCII scalar census) and
a counts-only overlap check fixtures vs real files. Mutation runs via a python apply/revert script — never edit the
build tree while a background mutation build is running.

**Why:** none showed in the green suite. **How to apply:** any PR adding a parser, importer or zone math. See
[[review-checks-numeric-pipelines]], [[review-checks-wire-drafts-and-flags]].
