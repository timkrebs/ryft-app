# 0017 — Dark is the inversion of the light system

- Status: accepted (2026-11-06, decided by the user; the Alpine plan, PR 1 of 6)
- Deciders: the user; ios-lead, ios-architect
- Applies to: `Ryft/Assets.xcassets/*.colorset`, `Design/Theme.swift`, `Shared/OrbitGaugePalette.swift`, the default appearance

## Context

ADR 0015 moved the light appearance to black and white and left dark as it was. A second look in the code would mean
two sets of rules for every scale, so the user decided on one system: paper and ink, and in dark the same ink on paper
turned over. Light becomes the default. The six PRs get there in order, so dark stays mixed for a while.

## Decision

1. **One system.** Every rule is written once, and dark differs only in colour values. No site asks which appearance
   it is in, once the inversion lands.
2. **Light is the default, in the last PR.** Those who never chose follow it, anyone who chose dark keeps it. No migration.
3. **Until then no dark colour set changes.** Shapes and textures reach dark as they land, in its hues. Where a site moves to
   another token, as text that stops using `warning` and `alert` does, dark's text moves with it.

## Consequences

- Between PR 2 and PR 6 dark carries the new type and shape in the old colours, so External releases are held for that window.
- The dark values aren't exactly `255 - x`, because contrast decides them. Say "inversion", not "exact".
