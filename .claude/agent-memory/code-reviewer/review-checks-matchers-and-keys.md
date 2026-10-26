---
name: review-checks-matchers-and-keys
description: RYFT review checks for name matchers and content-derived ids (training import I3) — generic+specific hits under a hard filter, field-vs-name equipment, keys that depend on a curated data file, NFKC eating apostrophes, locale tie-breaks, SwiftData added-entity probe
metadata:
  type: feedback
---

Found in the I3 "exercise mapping and aliases" review (2026-10-23); its 80+ tests were green:
- **Generic + specific both pass a hard filter → silent pick by name.** `exactHits` let "Deadlift" (no equipment
  word) and "Trap-bar deadlift" both through for key `deadlift|trap_bar`; `decide` sorted by name and accepted
  Deadlift (exact, 1.0, no review). Run a report over *library names × every equipment id* and flag any key with >1
  hit; a per-kind uniqueness test (`builtInsHaveDistinctKeys`) doesn't model the filter.
- **Field equipment overriding a more specific word in the name** ("EZ Bar Curl · Barbell" → key `curl|barbell` →
  Barbell curl, accepted). Probe field/name pairs where one is a refinement (ez_bar/trap_bar ⊂ barbell, smith ⊂ machine).
- **Ids derived from normalised keys whose normaliser reads a curated data file** (synonyms, equipment phrases,
  conflict drops, a fallback vocabulary): every vocabulary edit is an ADR-breaking id change, and vector tests built
  from hand-made keys can't notice. Ask for a vocabulary-independent id key or a golden key corpus.
- **NFKC before an apostrophe list:** U+00B4 becomes U+0020 U+0301, so "Farmer´s" splits (German keyboards type ´).
  Default-ignorables (U+00AD, ZWSP) as separators split compounds ("Bank­drücken").
- **Tie-break on the Accept-Language `name`** makes suggestions differ by device language; prefer slug/nameEn.
- File text that becomes a server-side name (custom exercise) needs Cc/Cf/bidi stripped, not just whitespace.

Re-review of the fixes (2026-10-23) — what the fixes themselves missed:
- **"More specific wins" computed from widened filter lists:** `machine` allowed {machine, cable, cardio} so cable ⊂
  machine, and "Crunch machine · Cable" silently became cable-crunch (4 built-ins). Run an "override" report: names
  that match exactly alone vs the same name with each field; any accepted change is a candidate wrong pick.
- **Frozen Unicode rules pinned by a plain-name golden file:** 1,029 entries with 6 distinct non-ASCII scalars; deleting
  the Default_Ignorable clause, spacing U+001F, or re-ordering the post-NFKC drop all left every test green. Mutate each
  clause of the frozen fold. An "independent" Python fold with `str.isspace()` (true for U+001C–U+001F), no
  Default_Ignorable table and `str.lower()` (Final_Sigma; Swift `lowercased()` has none) isn't faithful to the ADR.
- Scan every scalar for fold idempotence (U+0149/U+0374 NFKC into dropped apostrophes that step 4 then keeps).

Derived ids, I5 (2026-10-26):
- **Every top-level id needs its repeat rule.** Days got `␟<occurrence>`, plans didn't: two plans whose names
  *fold* alike with the same (or no) start date, or the same plans file picked twice (`merging` appends plans), share
  one plan id and one set of day ids; the second overwrites the first.
- **The existence check's read window vs the zone of the first import.** The ids are wall-clock, but `GET /v1/sessions`
  was read for the new zone's days only: a first-day 06:00 Tokyo session was missed from New York and re-sent, and the
  platform's upsert moved it 14 h (and would overwrite edits). Pad the window by a day each side.

Technique: swiftc harness with stubs (ImportLog, MainThread, a minimal `Exercise`) + the shipped JSON and fixture;
modes for unicode probes, a corpus digest run 6× (hash seeds) and with a reversed library, en-vs-de library names,
and counts-only tallies on `local-samples/`. SwiftData added-entity migration: a test that opens a file URL with
`schema minus the new model`, inserts, then reopens with the full schema (passed). Full-app mutation runs cost
~11 min each at load ~500 (other agents' builds): predict survivors by reading the tests first, run only the doubtful
ones, save each log, and parse Swift Testing's `✘ Test x() recorded an issue` (not only XCTest's "Test case … failed")
— exit 65 with no parsed names means the regex missed, not a survivor.

**Why:** none of these showed in the green suite. **How to apply:** any matcher, classifier or content-derived id.
See [[review-checks-parsers-and-import]], [[review-checks-numeric-pipelines]].
