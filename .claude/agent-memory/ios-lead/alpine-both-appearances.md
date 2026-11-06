---
name: alpine-both-appearances
description: Alpine is RYFT's whole identity since 2026-11-06, with light the default and dark the exact inversion; one system, no second look
metadata:
  type: project
---

On 2026-11-06 the user replaced his answer of the day before (light only, default dark). Alpine now applies to both appearances: light
default, dark inverted. Existing users who never chose follow the default, and it flips in the last PR.

**Why:** the Alpine brief makes black and white the identity, not a theme, so a second look has no reason to exist.

**How to apply:** one system, no appearance-dependent code paths. A decision can be overturned by a later brief: when one conflicts with
an earlier answer, ask rather than pick. `docs/work/2026-11-06-alpine/plan.md` holds the decisions.
