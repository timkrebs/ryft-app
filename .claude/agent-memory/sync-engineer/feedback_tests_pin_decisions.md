---
name: feedback-tests-pin-decisions
description: Reviews of my parser/engine work measure mutation scores; write tests that pin each decision (first vs last, increments, thresholds, guards), not just the fixtures' happy paths
metadata:
  type: feedback
---

The I2 code review (2026-10-23) ran 8 hand-written mutants (`scratchpad/rv-i2/mutate.py`) against my parser: only 2
were caught, though the suite had 80 tests and a fuzz test. Uncaught: taking the last `Day·Week` run instead of the first,
dropping the ordinal increment for wide rows, dropping `!hasMore`, moving the `.weak` threshold by one, a date-only
header with a duration turning into a plan, and the resolver's policies. It also flagged that my fuzz "step bound"
(lines + fields, ≤ 4 × lines) could never fail. After the fixes, 25 mutants were run (see the I2 handback).

**Why:** fixture tests exercise the common path; a decision in code that no test distinguishes from its neighbour
(first/last, ≥ 2/≥ 1, with/without a guard) can regress silently, and ids depend on several of them (ADR 0007).

**How to apply:** for every branch or constant that encodes a rule, add one input where the rule and its plausible
mutation give different results; before handing back, run a quick mutant script myself (apply → build-for-testing →
only the touched suites → restore from memory, never `git checkout` uncommitted work). A work bound in a fuzz test must
count characters actually scanned and must be able to fail (feed it part-heavy and long-token lines). Related:
[[project-swift-testing-macro-pitfalls]].

A survivor often means the scenario never reaches the mechanism (A3a.2 review, 2026-10-26): a 3 s burst to 13 m/s
was never *held*, so "no hold" and "held steps dropped" both survived; a taller 2 s burst to 20 m/s was. Make the test
prove the mechanism engaged (e.g. find the fix where distance stood still, compare with a limit-free pipeline). The same
mutants also exposed a real bug: `clipped()` rebuilt a `Step` and dropped a newly added field (`releasable`), so grep every
initializer when a value type gains a field.

Timing ratios (nightly `PerformanceTests`, 2026-10-23 I2 follow-up): an 8 MiB vs 1 MiB ratio stays ~8× even when a
helper is quadratic *per line*; add a per-byte ratio of long vs short lines at equal size (linear ≈ 1×, a rescanning
`parts` gave 2.2–5.3×). On this shared Mac, separate measurements drifted 3×–11× for the same code; interleave the two
sides, take the fastest of 3 each, and make both timed units similar in length (parse 1 MiB 8× vs 8 MiB once). Prove the
threshold with a mutant on the simulator before relying on it.
