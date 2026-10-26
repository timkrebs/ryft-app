# Training import: review log

Lead: ios-lead. Reviews are read-only; their findings go back to the owner.

**Personal data:** the user's real exports stay in the git-ignored `local-samples/`. Every commit was scanned against their
fields, and only generic exercise and equipment words match. Agents report counts only.

## I2 `train: CSV import parser (Alpha Progression)`

**Commits:**

| Commit | What |
| --- | --- |
| c7bfa20 | Parser, reader, token table, time resolver, synthetic fixtures, fuzz (sync-engineer) |
| bcd0c63 | Warning strings reviewed; two German sentences completed (localization-editor) |
| a74ff0e | Review fixes |
| bcfff2b | Encoding heuristic, detection on the decoded text, nightly linearity ratios |

**Gates:**
- strict build clean;
- Unit 1,061;
- `make lint`;
- mutation score 2/8 → 25/25, plus 5/5 for the last batch.

**Real samples (counts only):** 1 plan, 2 days, 19 plan exercises, 13 sessions (8 plan, 5 standalone), 429 sets, 7 skipped,
0 warnings.

**"12 or 13" (the brief says 12):** the newest workout has its last two exercises entirely skipped, which accounts for all 7
skipped sets. The source app may count only completed workouts; the user confirms.

**security-privacy-reviewer: signed off.**
- Logs carry counts and kinds only.
- Warnings carry no file text.
- Nothing is stored or uploaded.
- Fixtures are synthetic (an independent overlap check found 0).

It asked for three things, all done: merging #40 first (bf0bc19), caps across files, and stripping Cc/Cf at the parse boundary (both a74ff0e).

### code-reviewer (c7bfa20): 6 should-fix, 6 nits, nothing blocking

| # | Finding | Result |
| --- | --- | --- |
| 1 | A 30-minute DST gap (Lord_Howe) moved a workout 23.5 h; a fold got no note | Resolver rewritten on UTC offsets. Brute force over 443 zones and 1900–2100 transitions: 0 mismatches |
| 2 | A numeric workout title was read as a set row and merged into the previous workout | A set row needs unquoted digits and no date in field 1 |
| 3 | The day-without-week fallback was greedy ("… · Day 3 · Standalone workout" became a plan session) | The first full `Day·Week·plan` run wins; a standalone token is never a plan |
| 4 | One `.empty` for two UI states (P6 blank file, D7 recognised but empty) | An empty bundle for D7 |
| 5 | The fuzz work bound could never fail | `visited` counts bytes and characters; a nightly ratio over size and line length catches quadratic work inside helpers |
| 6 | Mutations caught 2/8 | 25/25 |
| 7–11 | Slow digit scan; SwiftFormat skips `Build/` folders; no-break spaces; Windows-1252 files; duplicate day numbers | Capped; folder renamed `Builder/`; whitespace-tolerant; a cp1252 fallback (see below); `.duplicateDay` |
| lead | Session caps were 200, but the platform takes 50 exercises and 50 sets per exercise | 50/50 with `.overPlatformLimit`; I5 clamps plan sets to 1–20 |

### code-reviewer re-verification (a74ff0e): nothing blocking

- **Stray byte:** one stray byte sent a whole UTF-8 file to cp1252 and garbled it. Now cp1252 applies only when invalid bytes
  outnumber well-formed multi-byte sequences.
- **Detection:** it ran on raw bytes, so a German cp1252 plans file was refused. The reader now decodes once for both detection
  and parsing.
- **Work counter:** it missed quadratic work inside a helper. A nightly per-line ratio now covers that.
- **Quoted set index:** it now advances the ordinal.

### Carried to later tickets

- **I5:**
  - clamp plan-exercise sets to 1–20;
  - ids keyed on the day number must tell duplicate days apart (`.duplicateDay`).
- **I4:**
  - "Line N" is the UI's own key;
  - the per-file read gives D6/D7.

## I3 `train: exercise mapping and aliases`

**Commits:**

| Commit | What |
| --- | --- |
| 53eb7e5 | Matcher (remembered → exact → alias → fuzzy), normaliser, a 134-entry en/de alias catalogue, `ImportMapping` per account, derived custom-exercise ids, export of remembered matches |
| 4c2c9ad | Review fixes |
| a8b6e67 | The id key is independent of the alias vocabulary |
| 737ad3c, 2c975e5 | ADR 0007 Amendment 1 |
| 607b046 | `fold` pinned and checked independently; machine and cable kept apart |

**Gates:**
- strict build clean;
- Unit 1,348 on the merged branch;
- `make lint`, including `scripts/import-fold-check.py` (1,065 golden keys agree) and `scripts/builtin-exercises.py --check`;
- mutations 22/22, then 6/6.

**Real export (counts only):** 20 distinct exercises; 14 exact, 2 alias, 4 to check, 0 new.

**Personal data:** the alias catalogue is generic. Only short common names overlap the real export, and none of its distinctive
names appear. Every changed file was scanned.

**security-privacy-reviewer: signed off.**
- Matches are per account, wiped at sign-out, cleared with "Clear remembered matches", and exported.
- Demo matches are forgotten when demo turns off.
- The export's account binding (S1) is fixed generally in #47 (`AccountBinding`).

### code-reviewer (53eb7e5): 1 blocking, 4 should-fix

| # | Finding | Result |
| --- | --- | --- |
| 1 | **Blocking:** a generic exercise was accepted over a specific built-in ("Trap Bar Deadlift" → `deadlift`) | Specific equipment wins; a field vs name contradiction becomes a check; all-pairs test (1.8 M combinations in the re-review) |
| 2 | Custom-exercise ids depended on the editable alias file | The key is `fold(name)` and `fold(field)` only (ADR 0007 Amendment 1); golden file of 1,065 keys |
| 3 | Control and bidi characters in custom names | Stripped; 80-scalar cut on character boundaries; fallbacks |
| 4 | A German-keyboard apostrophe and the soft hyphen broke normalisation | Dropped before NFKC |
| 5 | Hand-copied built-in fixture | `builtin-exercises.py --check` against the platform seed (read-only) |

### code-reviewer re-verification (737ad3c): nothing blocking
- **N1:** "Crunch machine · Cable" silently matched the cable exercise. Now an explicit refinement map (`ez_bar` / `trap_bar` refine barbell; `smith_machine` / `assisted` refine machine); cable vs machine is a check.
- **N2:** `fold` didn't quite match the ADR (step 4 order, Final_Sigma) and the golden file didn't pin the tricky clauses.
  Now `fold` is idempotent and matches the ADR word for word, and 36 tricky inputs are pinned. A faithful stdlib-only checker
  with explicit Unicode tables runs in `make lint`.

### For I4
- Call `match(_:)` from the `@concurrent` read path, not the main thread.
- "Accept N likely matches" uses `isLikely`.
- Remember the derived ids of "new" rows.
