---
name: project-mutation-runner
description: How mutation checks ran for the P1 fix round - one python runner, text mutants, build + test-without-building per suite, restore in finally, killpg on timeout
metadata:
  type: project
---

Leads ask for a mutation check per new test ("break what it guards, see it fail, revert"). What worked
(2026-11-17, 29 mutants for the P1 fix round):

- One python script holds a table of (name, [(file, old, new)], suites, tests that must fail). For each: assert `old`
  matches exactly once, write the mutant, `xcodebuild build-for-testing`, then `test-without-building` with
  `-only-testing:RyftTests/<Suite>` per suite, grep `✘ Test <name>(` / `✔ Test <name>(`, and restore the files in a
  `finally`. Dry-run the table first (every `old` matches once).
- Popen with `start_new_session=True` and `os.killpg` on a timeout: only the runner's own processes die, never another
  agent's xcodebuild.
- Commit first, so the working tree equals HEAD and a crash leaves nothing half-mutated; don't edit sources while it
  runs (each mutant's build compiles whatever is on disk).
- A suite filter per mutant keeps each to a few minutes on the shared Mac; budget about 3–5 min a mutant.
- A test that survives its mutant is a finding about the test, not the code: rework or drop it and say so.

**Why:** reviews re-run mutants ([[feedback-tests-pin-decisions]]); doing it by hand for 20+ mutants is slow and
error-prone. **How to apply:** any round that asks for mutation results.
