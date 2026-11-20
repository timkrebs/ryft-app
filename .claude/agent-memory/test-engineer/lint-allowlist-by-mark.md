---
name: lint-allowlist-by-mark
description: scripts/check-accent-use.py ALLOW entries must match the mark's own expression plus a use count, never a func/call/struct around it
type: feedback
---
Review of PR 6's colour lint found function-wide allowlist anchors (`func draw(`, `InsightRows(`) let Volt ride on labels and lines beside the mark, and named constants (FocusedRowInk.mark) were only checked at their definition.
**Why:** an anchor that opens a construct allows everything inside it; aliases of a banned token escape unless they are tokens too.
**How to apply:** key allow entries on `Circle().fill(Theme.signal)`-style spans with a `uses` count; add every alias constant to the token; prove each new token by planting it in a linted file and running `make lint`. Compare new self-test cases against the previous script version to show each flips.
