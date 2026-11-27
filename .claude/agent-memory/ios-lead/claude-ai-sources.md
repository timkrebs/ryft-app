---
name: claude-ai-sources
description: Which claude.ai sources a brief can point at that I can actually read — design canvases yes (artifact list_files/read_file), claude.ai project knowledge files no
metadata:
  type: reference
---

Briefs written in claude.ai can cite two kinds of sources:
- **Design canvases** (`https://claude.ai/artifact/<id>`): readable. `read_artifact` only returns the type's
  instructions; call `list_files` on the slug it returns, then `read_file` on `project/canvas.json` and each
  `project/<Board>.dc.html`. The boards hold exact hexes, sizes and stroke widths.
- **Files in a claude.ai project's knowledge** (e.g. `docs/NOCTURNE_STYLE.md` in project "RYFT App"): not
  readable. `list_artifacts`, Claude Docs and the canvas don't hold them.

**Why:** on 2026-11-16 the Nocturne brief named NOCTURNE_STYLE.md v0.2 as the source of truth (measurements,
launch angles §5, accessibility §6) and asked for it as PR 1's first commit. It was only in the project's
knowledge, so I had to stop and ask the user to paste it.

**How to apply:** when a brief cites a claude.ai project file that isn't in the repo, ask for the text in the
first reply, together with the read-only prep (canvas values, asset comparison). Don't rebuild the spec
from the mockups and pass it off as the document. See [[public-repo-personal-data]] before committing a pasted copy.
