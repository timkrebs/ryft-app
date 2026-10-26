---
name: project-strings-catalog-insertion
description: Localizable.xcstrings round-trips byte-identically through Python json with the repo's settings; how to add en keys + de translations with a diff of only added lines
metadata:
  type: project
---

On 2026-10-23 (I2 import parser) `Ryft/Resources/Localizable.xcstrings` round-tripped **byte-identically** through
`json.load` → `json.dump(d, f, ensure_ascii=False, indent=2, separators=(",", " : "))` + a trailing `"\n"` (the same
settings `scripts/sync-strings.py` writes with). So a scripted insertion is safe when:
1. a round-trip compare of the untouched file says "identical" first (if not, fall back to text insertion);
2. new keys go before the first existing key that sorts after them case-insensitively (sync-strings' `merged()` rule);
3. each entry is `{"comment": …, "localizations": {"de": {"stringUnit": {"state": "translated", "value": …}}}}`, no
   `en` entry; a brand/source name gets `"shouldTranslate": false` (lint skips it);
4. the code's `comment:` text equals the catalog's `comment` exactly (Xcode would otherwise rewrite it later).

Result: `git diff --stat` showed only insertions (20 keys → 213 lines, 0 deletions); `make lint` and
`python3 scripts/sync-strings.py --derived-data build/DerivedData --check` (after a build) both passed.

**Why:** ios-lead's rule forbids re-serialising the catalog after an incident with `": "` separators; the round-trip
check proves the dump changes nothing else.

**How to apply:** any ticket that adds strings without Xcode. Related: [[project-swift-testing-macro-pitfalls]] (a
test that checks every warning kind has German via `resource.locale = Locale(identifier: "de")` +
`String(localized:)` works in the hosted unit tests).
