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

## I5 `train: batch upload, ids and duplicates` (2026-10-26)

The data side of the import. The live request waits for C2: the live client throws `notPublished`, so a job waits as
"saved on this iPhone", while demo mode runs end to end against the mock.

**Commits:**

| Commit | What |
| --- | --- |
| 40ba3d1 | The interface I4 builds on, with a fake |
| aae7d5a, c7cf81c, 6615c34, 444762f | Builder (ids, verdicts, plans), uploader and saved job, status fields, a test |
| 89e73cb, c45d73a, 94b46dc | Review fixes; the job's one-by-one wipe and the data export |
| 8d6aa87, 05fbb96 | An identical plan picked in two files is kept once; the bisect stops without refusing good sessions |

**Gates:** strict build clean; Unit 2,281 passed; `make lint`; 25 hand-written mutants caught (one S1 mutant is
equivalent on iOS 27, see below).

**Measured** (Debug simulator, signposts, a 1,200-workout synthetic export, all off the main actor):

| Stage | Time |
| --- | --- |
| read + parse | 241 ms |
| build | 86 ms |
| encode the job | 78 ms |
| 24 batches, encode + mock upload | 417 ms |

### code-reviewer (444762f): 4 should-fix, 5 nits, nothing blocking

| # | Finding | Result |
| --- | --- | --- |
| 1 | A re-import from another time zone re-sent sessions from the edge days, and the platform moved their start | The existence check reads 2 days past the import's days (zones can be 26 h apart); `aReimportInAnotherZoneSendsNothing` |
| 2 | Two plans whose names fold the same shared one id, so the second replaced the first | Occurrence ids for plans (ADR 0007 Amendment 2); an identical plan in two picked files is kept once, with a note |
| 3 | A 403 without a known code refused the whole import | Any 403 pauses the job, with nothing refused (ADR 0008: held, never dropped) |
| 4 | One session the platform can't take kept a whole batch of 50 out, and Retry resent the same batch | A whole-request 400/422 bisects down to the refused item; Retry resends only what's refused |
| Nits | `Retry-After` uncapped; answers not checked against their job; plan links after an offline preview; the upgrade test's store options; O(n) main-actor work per request | Capped at 1 h; checked; dropped as online; matched; documented with sizes (fine at hundreds of sessions) |

### security-privacy-reviewer (444762f): signed off, 2 should-fix

| # | Finding | Result |
| --- | --- | --- |
| S1 | The account wipe deleted the saved job in bulk, which may leave its external payload file (the whole imported history) on disk | Deleted one by one, with on-disk tests for sign-out and expiry. On iOS 27 the bulk delete removes the file too, so that mutant is equivalent there; the one-by-one delete is kept for iOS 17/18 |
| S2 | "Export my data" didn't include an unsent import | `pending_import` with the items not yet on the platform, bound to the export's account |
| Low | Demo's custom exercises went into the account's exercise cache; stale comments | Skipped for demo; updated |

**Checked and sound:**
- **On disk:** minimal (no notes, file name, URL or raw lines), bound to its account or demo, wiped everywhere (the
  expiry path too).
- **Logging:** carries counts only.
- **No other account and no demo:** the upload can't reach another account or go through the live client in demo.
- **Gate:** asked before every request.

### code-reviewer re-check (8d6aa87): merge

Findings 1–4, the nits and S1/S2 are fixed as intended. Checked: the bisect terminates; identical-plan dedupe can't merge
plans that differ in content; the 2-day padding can't call a new session on a neighbouring day "already imported" (ids
are wall-clock). One more should-fix, fixed in the last commit: after three single refusals in a row the bisect stopped
splitting and refused whole batches of good sessions (61 in the probe), and Retry repeated it. Splitting now stops only
when nothing was accepted in the pass, and what's left stays pending. A 403 without a known code pauses with its own
reason instead of the consent one.

**Platform:**
- T13: every item named in `results`, and the request ID on 2xx answers too.
- R25 (4): an import's consent refusal is the whole request's `403`, never a per-item `rejected`.

**Open, for the user:** does Alpha Progression export the wall-clock time a workout was recorded, or re-render times in
the phone's current zone? If it re-renders, an export made after a zone change would come back as all-new workouts.

**Before the flag goes on:** C2 (contract mirror, live client), privacy-policy lines (import read on the device, an
unsent import kept up to 30 days, `import_source` stored), and a device check of a batch finishing in the background.

## I4 `train: import flow` (2026-10-26)

The six-step import flow behind `train.import` (off by default; on in Debug demo), built on I5's seam. The "Open in"
routing (E5–E10) is complete, but the CSV document type stays out of Info.plist until the flag-on PR.

**Gates (7f2c1a4):**
- strict build clean;
- Unit 1,812 passed (46 new tests);
- UISmoke 32 (1 skip predates I4);
- `ImportUITests` 4/4, with the end-to-end test in UISmoke at about 60 s locally;
- `make lint`;
- 251 strings (en + de), insertions only.

### code-reviewer (7c74ca4): 3 should-fix, nits, nothing blocking

| # | Finding | Result |
| --- | --- | --- |
| 1 | A stale preview build (or mapping) could land after the user went back and changed a match | Matching and building are cancellable tasks with a generation, checked after every await; `aStaleBuildNeverWins` |
| 2 | "Choose another exercise" → "Custom exercise" created a real exercise at once, with a random id | It opens the draft form; nothing is created before Import |
| 3 | A partly failed result marked itself seen, so its Retry and the resume row were lost at the next purge | Seen only when nothing was refused, or on Done |
| Nits | Clear-matches keyed on the account only; detection re-merged per access; a full second decode; V5 silent refusal; a duplicate alert | Fixed |

**Re-check (7f2c1a4): merge.** Carried to C2: `.needsAttention` resumes on every automatic trigger and should wait for
Try again.

### security-privacy-reviewer (7c74ca4): signed off, 2 should-fix

| # | Finding | Result |
| --- | --- | --- |
| S1 | With the flag off, an "Open in" file left iOS's copy in `Documents/Inbox` | Owned copies are removed without being read; the user's own file is never touched |
| S2 | A saved job couldn't be discarded, and "kept on this iPhone" didn't say for how long | "Discard import" in every paused or saved state; "Kept on this iPhone for up to 30 days. Signing out removes it." |

Also: synthetic demo files only (no distinctive overlap with the user's real exports), file access paired and capped,
no URL or text kept, nothing spoken from notes.

**Re-check (7f2c1a4): signed off.**

### ui-validator: partial (usage limit)

The validator captured all steps at AX3 (en, de) and AX5 (en) in dark mode, but stopped before its report. Seen by
the lead:
- the German step-4 title truncates at AX3 ("Übungen zuord…");
- at AX5, step 4's sticky section header and the bottom bar (count, Continue, search) leave little room for rows.

**Before the flag goes on:**
- a full UI validation (AX5, light, the paused and saved states);
- these two layout items;
- privacy's wording suggestion for the discard confirmation: "Exercises, plans and workouts already sent stay in RYFT."
