---
name: project-strings-catalog-insertion
description: How to add a key to Localizable.xcstrings by hand with a diff of only added lines; English only now, the file isn't one sorted run, and the lead's entry shape
metadata:
  type: project
---

Rule from ios-lead: never re-serialise `Ryft/Resources/Localizable.xcstrings`; add keys by **text insertion**, in their
own `l10n:` commit, and check `git diff --stat` shows only insertions. Then `json.loads` the file to prove it parses.

What a hand-inserted entry looks like (P1b, 2026-11-18, lead's commit 5774c29 and mine 953af53): RYFT is **English
only** now (no `de`), so an entry is the key with its `comment` and, when asked, an `en` stringUnit:
`"Key" : { "comment" : "…", "localizations" : { "en" : { "stringUnit" : { "state" : "translated", "value" : "Key" } } } },`
(2-space indent, `" : "` separators, literal non-ASCII such as `→`). A plural uses `variations.plural.one/other`. The
code's `comment:` text must equal the catalog's `comment` exactly, or Xcode rewrites it later.

**The file isn't one sorted run:** about 54 places break case-insensitive order (Xcode-extracted keys sit in a second
run, e.g. "Deep + REM" near line 1588 and "Deep" near 4979). "Sorted position" therefore means next to its nearest
neighbours (e.g. "Demo data couldn't…" between "Demo data" and "Demo data · "), not a global bisect.

Older note (2026-10-23): the file round-tripped byte-identically through `json.dump(…, ensure_ascii=False, indent=2,
separators=(",", " : "))` + `"\n"` (sync-strings' settings), so a scripted dump was once safe. Prefer text insertion now:
it's what the lead asks for.

**Why:** an incident with `": "` separators made re-serialising forbidden; insertion-only diffs are easy to review.

**How to apply:** any ticket that adds strings without Xcode. If Xcode rewrites the file during a build, `git checkout
-- Ryft/Resources/Localizable.xcstrings` and insert again. Related: [[project-swift-testing-macro-pitfalls]].
