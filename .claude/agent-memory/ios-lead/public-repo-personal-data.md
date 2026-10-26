---
name: public-repo-personal-data
description: The app repo is public. Briefs the user pastes can quote his real data, so scan and redact before copying a brief or writing docs, fixtures or PR bodies
metadata:
  type: feedback
---

`ryft-app` is a public repo. Before committing a copy of a brief (`docs/work/<date>-<slug>/brief.md`), any doc, a fixture or
a PR body that came near real user data, I scan it against the real files. Where a real value appears, I replace it with a
synthetic one in the same format and add a "copy note" saying so.

Real values here means: exercise or plan names, dates, times, durations, loads (e.g. a "+N" that is his body weight), and
device or account identifiers.

Agents that may read real data:
- get it only locally, by absolute path (`local-samples/` is git-ignored since #40);
- report counts, never content;
- write synthetic fixtures.

**Why:** on 2026-10-23 the training-import brief (written by the user) quoted lines from his real Alpha Progression export.
Every example matched his file: dates, workout times, durations, day names, and "+96", probably his body weight. A
token scan (fields of the sample CSVs grepped across the docs) caught them before the design PR (#41). ui.md had copied two
of them too.

**How to apply:** any brief that mentions samples, exports, screenshots or "my data". Run the scan before every docs commit in
that feature, and tell the user what was redacted. See [[device-sessions]] for the same care on his iPhone.
