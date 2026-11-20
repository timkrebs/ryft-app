---
name: review-checks-combine-guards-and-lints
description: RYFT checks for a combine that puts one branch's side guard into another branch's model (PR 6 combine, 2026-11-20) - a guard at Save only while loads/Try again/strip still read the new side, Demo keeping a sheet up through a sign-out, token lints probed with a snippet harness (aliases, arrays, named-constant marks, whole-function allow entries), re-implemented helpers
metadata:
  type: feedback
---

From the PR 6 combine review (A + B + C, read-only, 2026-11-20). The merges themselves survived a line-survival check; these were the gaps:
- **A side guard merged in at one entry point.** C's `owns(opened)` sat in `save()` only; B's model brought `retry()`, the
  failed phase, `select`, `habitsChanged` and the reconnect reload, all of which read through the store *after* its forget. A late
  load rebuilds onto the other side's empty store ("Couldn't load this day"), Try again loads the other side's catalog and day into
  a sheet bound to the old side, and Save then closes silently. List every async entry point of the merged model and ask which
  ones check the owner; dismiss on `!owns` (the generation and `AccountBinding` are observable).
- **Reachability: Demo data keeps the root on the tabs** (`settings.demoMode ? .signedIn : auth.state`), so a sheet survives an
  account sign-out (expired session) while Demo is on, and `forgetsAccountState` still bumps the journal's generation.
- **Token lints: probe, don't read.** Load the script with `importlib` from a scratchpad file (`python3 -I`) and run
  `check_source(path, snippet, ALLOW)` on snippets. Misses found: `Theme.teal` (documented as accent's colour), `Color("Teal")`,
  `Theme.zones[i]`, `MetricSpec.x.color`, SwiftUI `.teal`/`Color.accentColor`, `Color("Accent", bundle:)`; named constants of
  allowed marks (`FocusedRowInk.mark`) whose uses nobody checks; allow entries keyed on a whole `func`/call (text-colour
  arguments inside pass); a destructive range running to the end of the line.
- **A new helper beside an existing one.** `JournalStore.time` used `Calendar.date(bySettingHour:of: now)` (02:30 on the
  spring-forward day comes back 03:00, swiftc-probed) while `Fmt.time(hour:minute:)` already formats on 2001-01-01 for that
  reason. Grep `Fmt` and its extensions for the same job before accepting a new formatter.
- Locale threading: a function given `locale:` that still calls a component formatting on its own (`StrainHero.numeral`,
  `Fmt.load` without it) mixes separators in tests and previews only; users see one locale. Nit unless a test pins it.

Mechanics: a test-name survival script doing `git show` per file over 4 revisions takes > 2 min; run it in the background.

**Why:** the merge diff and each side's tests were clean; these needed the other branch's entry points, the root's Demo rule,
or a lint probe.
**How to apply:** any integration of parallel branches that share a model or a store; any new source-scan lint. See
[[review-checks-merges-and-wiring]], [[review-checks-side-split-rounds]], [[review-checks-form-reads-and-saves]].
