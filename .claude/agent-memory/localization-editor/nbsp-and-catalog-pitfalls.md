---
name: NBSP units and catalog pitfalls
description: What bit the G5 pass (no-break spaces, sentence keys, catalog renames, test expectations). Read before touching units or catalog keys.
type: project
---
- Swift writes a no-break space as `\u{00A0}` (the convention in Ryft/). The catalog stores the literal U+00A0 char.
- Xcode's stringsdata puts every string of a `#Preview` body on the `#Preview` line (77/77 checked). A helper a preview calls (e.g. RulerScale's `rulersAtSize`) is catalogued where it sits.
- Plural and `substitutions` (`%#@x@`) variants carry their own English `value`s. Renaming a key also needs its variant values (`one`/`other`, and `%arg` substitution values), and top-level `value`s. Scan for these, and use a literal space in the scan: `\s` matches U+00A0.
- `sync-strings.py` adds and removes keys but writes no comments or plural variants. Rename a key in place (line edit), keep its comment, then run `--check`. The JSON round-trip of the catalog is byte-identical, so the script's writes are safe.
- Formatter output (`Duration.formatted`, `Fmt.spokenDuration`, PlanSpeech's rest/day text, E1RM overWindow, the trend and workout subtitles) is not catalog-backed. Keep test expectations for those plain.
- Read the NBSP position of an actual value from the result bundle (`xcrun xcresulttool get test-results tests`), not from the printed text: NBSP prints like a space.
- Load gate: `sysctl -n vm.loadavg` prints {1m 5m 15m}. The 5-minute value is the second number.
