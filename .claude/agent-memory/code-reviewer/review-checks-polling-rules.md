---
name: review-checks-polling-rules
description: RYFT review checks for test-harness wait/settle rules (HostedSettling, PR 119, 2026-11-18) - mutate each clause of the rule and run the PR's own test scripts against it with a swiftc probe
metadata:
  type: feedback
---

When a PR changes a polling rule (settle "N equal in a row AND T since the last change", wait "N polls", budgets):
- **Mutate each clause and run the PR's test scripts against the mutant.** Copy the rule file plus a stub of any outer
  type (e.g. `enum HostedWindow { enum HostError: Error { case timeout(String) } }`), port the scripted tests into a
  main.swift (`await run()` in its own main.swift, not after a declaration file), build with `xcrun swiftc -swift-version 5`.
  PR 119: dropping `quiet = 0` and measuring the window from `start` instead of `lastChange` both passed all six rule tests.
  Typical gaps: scripts change only *before* any equal sample (reset untested), and `quietFor: .zero` everywhere except a
  no-change test (the time anchor untested).
- **Ask for an injected clock** (`now:` closure advanced by the scripted `pause`) instead of real sleeps and main-actor
  busy-waits: lower-bound-only timing tests don't flake, but pass trivially under load, and busy-waits add the very
  main-actor contention the harness fix is about.
- What a sampled-quiet rule can never see, whatever N is: periodic changes slower than the window, A->B->A aliasing
  between samples, and attributes not in the sample (HostedSettling compares label + frame, not value or traits).
- Budgets as `Int(timeout / interval)`: Duration / Duration is Double and exact for the round defaults; check the literal
  interval isn't duplicated between the budget and the default pause.

**Why:** the rule's code was right, but the tests named after its guarantees didn't pin them. **How to apply:** any
settle/eventually/wait helper change in RyftTests. See [[review-checks-large-text]], [[review-checks-shared-transport]].
