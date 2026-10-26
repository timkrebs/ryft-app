---
name: review-checks-fast-paths
description: RYFT review checks for a fast path in front of a Foundation oracle (P1 RFC 3339 byte parser vs ISO8601DateFormatter) — exact-value conversion, decline-everything-else, ICU leniency facts, older-iOS risk, sweep + mutant harness, contract run.sh hygiene
metadata:
  type: feedback
---

From the P1 "fast date parsing" review (58e624e, 2026-10-23); nothing blocked, all of this held:
- **Equivalence = same arithmetic, not same date.** `ISO8601DateFormatter` (iOS 27 sim and macOS 27 alike) is CF + ICU:
  fraction truncated to ms (ICU `value /= 10^k`, int32, so >9 digits can overflow), result `Double(ms) / 1000 - 978_307_200`
  (two roundings). A single-rounding `Double(ms - 978_307_200_000) / 1000` differs on ~2 % of fractional instants (uniform 1583–9999; never on whole seconds) — check the
  PR's tests kill that mutant. `Date(timeIntervalSince1970: Double(ms)/1000)` is an equivalent mutant (don't count it).
- Pre-1970 fractions: ICU adds the non-negative ms to the whole-second field instant (`-1000 + 999 = -1`), not toward zero.
- ICU leniency (declined inputs only): Feb 30 rolls, hour 24 = next midnight, `+24:00` reads as `+02:00`, `z`, fullwidth
  digits, leading/trailing space, `.-5` all accepted; `1582-10-14` is Julian. A fast path must *decline* all of these.
- **Older iOS risk:** CI and local sims are iOS 27 only, deployment is 17.0. Reason from ICU/CF history (formula and
  truncation unchanged for years); flag as risk, ask for a one-off run on an older runtime/device or a STATUS.md note.

Technique (minutes, no app build): `git show <sha>:file` into my scratch dir + `main.swift`; compile for macOS and for
the sim (`-target arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path)`), run with
`xcrun simctl spawn`; `SIMCTL_CHILD_TZ=…` sets the process zone. Bit-compare `timeIntervalSinceReferenceDate.bitPattern`
plus an independent oracle (Fliegel–Van Flandern JDN). Every day 1583–9999 (3.07 M) takes ~5.5 min per platform.
Mutants: python extracts the Swift Testing tables + generator into a plain harness (27 mutants in ~2 min). Run spawn
sweeps *before* `xcodebuild test` — it shuts the sim down.

Contract: `scripts/contract/run.sh` does `rm -rf ${TMPDIR}/ryft-contract` — run it with `TMPDIR=<my scratch>`. The local
`../plattform` is often behind; use `git -C ../plattform show origin/main:docs/API.md` and compare with the parent commit.

**Why:** a fast path's only acceptable diff is speed. **How to apply:** any PR adding a fast path, cache or hand-rolled
replacement for a Foundation formatter/decoder. See [[review-checks-parsers-and-import]], [[review-checks-numeric-pipelines]].
