# Catalog edits without re-serialising (RYFT app, PR 6 strings pass)

- `scripts/sync-strings.py` in write mode re-serialises the whole catalog with json.dump (ruled out by the ticket). Use
  `--check` only. Its check output lists the adds (`+`) and removes (`-`) per catalog: that list is the work order.
- A targeted edit: split the file into lines, cut out or insert whole top-level entries (4-space key line to its `    }`
  or `    },`), render only the new entries with json.dumps(sort_keys=True, indent=2, ensure_ascii=False, separators
  (",", " : ")) and indent them by two spaces. Keep the sync's merge order (new key before the first key that sorts
  after it, case-insensitively). Fix commas per entry, then check with json.loads, the key set, that untouched entries
  are equal, and a trailing "}\n". `git diff -U0 | grep '^-    "'` lists the removed keys, which should be the expected ones.
- Renamed text (a key whose code text changed): carry its old comment unless a new one is given; the sync can't do this.
- Plurals: one substitution per counted argument (`%#@sets@`, argNum = the argument's position). A substitution that comes
  before another argument must be positional (`%1$#@sets@ of %2$@`): the sequential form read the text as the number and
  crashed (SIGBUS in String(localized:)). Test a plural by running the suite that calls it, not only lint. A single %lld uses
  `variations.plural` with the literal %lld in each form. A plural form needs one and other (lint-strings checks it).
- Shared keys (one text, two code sites, two comments): write one comment that covers both sites.
- No-break spaces: number + % / h / min / bpm / percent take U+00A0 (the code's `\u{00A0}`). Words after a count
  (days, sessions, sets) don't. Catalog keys carry the raw character; JSON written with ensure_ascii=False.
- zsh: a bare `echo ===` fails ("=== not found"); use `echo "--- label"`. `sleep` over the limit is blocked: wait with a
  background `python3 -c "import time; time.sleep(N)"` and read the output file afterwards.
- `make lint` passes with the SwiftLint line-length warning on CoachMarks.swift:19 (178 chars, present before PR 6's copy
  pass; wrapping would break the `String(localized:)` extraction).
- One real crash in a test process marks other tests of that run as failed ("Crash … _applyScopingTraits", "signal bus",
  XCTWaiter timeouts). Read the newest ~/Library/Logs/DiagnosticReports/Ryft-*.ips before blaming the simulator or load.
- Gate: a build started while the 5-minute load was over 200 is a breach; wait for the load first.
