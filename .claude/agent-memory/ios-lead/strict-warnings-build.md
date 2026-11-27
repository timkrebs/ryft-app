---
name: strict-warnings-build
description: CI builds with RYFT_STRICT_WARNINGS=YES (warnings are errors) plus a grep; agents' "zero warnings" claims missed a warning that failed CI
metadata:
  type: feedback
---

Before pushing a branch, build it myself the way CI does:
`xcodebuild build-for-testing … RYFT_STRICT_WARNINGS=YES | tee build.log`, then
`grep -E "^/.*/(Ryft|RyftTests|RyftUITests|RyftWidgets|Shared)/.*: warning:" build.log` must find nothing.

**Why:** on 2026-11-17, PR #116 (P1) failed CI on `var removed` never mutated (a warning, an error under strict
warnings), although the sync-engineer reported "zero warnings" and `make lint` and `make style` passed. Plain local
builds only print the warning, and an agent's summary can miss it.

**How to apply:** after an implementer's last round and before `git push`, run the strict build or grep its log. A
combined trial-merge build (see [[integration-branch]]) catches the same thing for several PRs at once. Related:
[[lint-is-two-targets]], [[resumed-agent-reports]].
