---
name: project-wall-clock-dst
description: Turning zone-less wall-clock times into instants — Calendar.nextDate(.nextTimePreservingSmallerComponents) is wrong for 30-minute DST zones; resolve by UTC offsets
metadata:
  type: project
---

Found in the I2 review (2026-10-23, `ImportTimeResolver`): `Calendar.nextDate(after: midnight − 1 s, matching: h:m,
matchingPolicy: .nextTimePreservingSmallerComponents, repeatedTimePolicy: .first)` resolved Australia/Lord_Howe
`2026-10-04 02:15` (gap 02:00→02:30) **23.5 h late** (it matched the next day), and gave no "repeated" signal for the
30-minute fold `2026-04-05 01:45`. Berlin and New York (1-hour changes) looked fine, so tests on those alone miss it.

The fix that passed review: read the wall clock as UTC (`u`, days-from-civil, no Calendar), collect the zone's
offsets at `u − 24 h … u + 24 h` in 12 h steps, keep candidates `u − offset` whose real offset equals `offset`.
One = normal; two = fold (take the earlier, note it); none = gap (use the offset at `u − 24 h`, i.e. before the gap, so
the time moves forward by the gap's length). Verified on Lord_Howe, Berlin, New York, Havana and Santiago (folds across
midnight), Sao Paulo 2018 (midnight skipped), Cairo, Tehran, Apia 2011 (a whole day skipped) and 1900 LMT offsets.

**Why:** any feature that stores local times without a zone (imports, sleep plans, journal times) hits this.

**How to apply:** reuse the offset method (see `Ryft/Train/Import/Builder/ImportTimeResolver.swift`); always test a
30-minute zone plus a zone with a fold or a gap across midnight, not only Berlin/New York.
