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
- (2026-11-19) Give the runner the main runs' `-derivedDataPath build/DerivedData` and `RYFT_STRICT_WARNINGS=YES`: a
  different path or setting is a second full build (~1.2 GB, 10+ min under load). Then mutant texts must be
  warning-free: `&& s.id == UUID()` instead of `&& false` ("will never be executed"), `_ = cap` instead of deleting
  the only use of a `let`.
- (2026-11-19) "ERROR 65" with "SwiftData … backing data was detached" and "Restarting after unexpected exit" means
  the mutant made code touch a deleted model's rows. That counts as a kill by crash, not by the test's checks. Say so
  in the test's doc comment rather than claiming the row checks catch it.
- (2026-11-21) After a parallel Unit/UISmoke run the original device is shut down (the clones ran the tests); the
  runner's `-parallel-testing-enabled NO` run then failed with "The test runner hung before establishing connection"
  and no `✘` lines, which a naive parser reads as SURVIVED. Boot + `bootstatus -b` before each test step, and retry
  when the log has no "Test run with N tests" line.
- (2026-11-21) Parameterized tests: the issue lines read `✘ Test f(late:reloadFails:) recorded an issue with 2
  arguments late → .plans, reloadFails → false at …`; match per case to show which arguments a mutant breaks.
- (2026-11-22) Put the shared-Mac gate (no booted "RYFT CI", 5-minute load < 200, < 3 xcodebuilds) in the runner
  before each xcodebuild, not once before the script: a 7-mutant run spans CI jobs.
- (2026-11-22) A mutant that makes a test hang shows as exit 65 with "Time limit was exceeded: 60.000 seconds",
  "Restarting after unexpected exit…", and then a relaunch's "✔ Test run with N tests passed". It's a kill by the time
  limit, not by the checks, and the runner's `✘` parser lists nothing. Grep for "Time limit|Restarting". Fix the
  test's hold, a continuation gate that holds every `wait()` forever, so it stays open after `release()`. Then the
  mutant's later calls finish and the `#expect`s fail.

**Why:** reviews re-run mutants ([[feedback-tests-pin-decisions]]); doing it by hand for 20+ mutants is slow and
error-prone. **How to apply:** any round that asks for mutation results.
