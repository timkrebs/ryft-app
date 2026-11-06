# Alpine: plan

Brief: [`brief.md`](brief.md). Light pass: `CLAUDE_FOLLOWUP_ALPINE_LIGHT.md` on PR #100. Notes: [`design.md`](design.md), [`architecture.md`](architecture.md).

**Goal:** RYFT's identity becomes black and white in both appearances: Inter, ink rules, square shapes, and level by fill rather than hue.

## Decisions by the user

These win over the brief and the notes where they differ. The 2026-11-06 answers replace the light-only and default-dark answers of 2026-11-05.

| Question | Decision |
| --- | --- |
| Appearances (2026-11-06) | Light is the default. Dark stays, as the exact inversion. One system: no second look in the code. |
| Existing users (2026-11-06) | Those who never chose follow the new default. Anyone who chose dark keeps it. No migration. The default flips in the last PR, so nobody lands on a half-done look. |
| Row lines (2026-11-05) | A soft row rule, ink at 0.20, for dividers inside a card. Full-ink rules stay for edges. Departs from ADR 0015. |
| Good vs bad change (2026-11-05) | Polarity arrows: filled toward better, outlined toward worse. |
| Zones (2026-11-06) | Hatch for all five, with the label above. Departs from the brief's grey steps. |
| Caption case (2026-11-06) | Captions stay in sentence case. Labels stay uppercase. Departs from the brief. |
| German hero (2026-11-06) | "Engineered for peak." stays in English, as a brand line. |

## Decisions by the lead

- **System-drawn destructive buttons stay red.** No code can make them ink.
- **Satoshi goes** when Inter lands. There's no second look to keep it for.
- **ADR numbers:** 0015 is the palette, 0016 is the wipe recovery, so the brief's dark inversion ADR is 0017.
- **Merging:** the brief's six PRs merge in order when green. That covers those six only.
- **Stage greys below 3:1:** the brief's tokens stay. Four greys can't each reach 3:1, so the edge, the row and the label carry them.
- **Rule width:** 1 pt, and `Metrics.hairline` stays. `1 / displayScale` doesn't compile in a `static let`, and the brief and ADR 0015 both say 1 pt.
- **Eyebrow numbering:** the five tab screens only.
- **Name:** `BandStyle`, the brief's, not `BandLevel`.

## PRs, in order

| # | PR | Owner | Must be true |
| --- | --- | --- | --- |
| 0 | Design system: `design.md`, catalog | ui-designer | Nothing is built on an undecided rule |
| 1 | `design: light pass` (#100) | ios-developer, test-engineer | Lint and tests green |
| 2 | `design: inter, square shapes, hairline surfaces` | ios-developer | `tokens:check` result recorded |
| 3 | `design: ink gauges and charts` | ios-developer, test-engineer | Every scale reads in greyscale |
| 4 | `today, sleep, strain in the alpine system` | ios-developer | Screens and widgets |
| 5 | `train, insights, profile, onboarding, icon` | ios-developer, release-manager | Welcome and auth no longer force dark |
| 6 | `design: dark as the inversion` | ios-developer | Default flips to light, `CLAUDE.md` updated |

Each PR is validated by ui-validator in greyscale screenshots, in English and German at large sizes. The dark look stays mixed between PR 2 and PR 6: new type and shape, old colours.

## Facts that differ from the brief

- **The website isn't live in this style.** #142 and #143 are open, and ryftapp.de shows the old copy. Its tokens have to land with or after this work, not before.
- **`tokens.mjs` can't read a negative wordmark tracking**, and it throws. Platform has to change `tokens.mjs:188`, or the wordmark needs another form.
- **`accessibility-reviewer` isn't in the fleet.** ui-validator takes contrast and non-colour cues.
- **D18 to D21 aren't in this Mac's `plattform` checkout.** They're probably on an open web branch.
- **The temporary `ref:` in `../plattform`'s CI** isn't editable from this repo. That's a request for platform-lead.

## Gates

- **P1 before PR 1 merges:** platform pins the app checkout in its CI to commits. `delete_branch_on_merge` is on, and #142 and #143 check out `design/alpine-light-palette` by name, so merging #100 would break them.
- **P2 before PR 2 merges:** platform changes `tokens.mjs:188` to accept a minus.
- **`tokens:check`:** run `RYFT_APP_DIR="$PWD" npm --prefix ../plattform/web run tokens:check` from the app. The brief's command passes falsely.
- **Website in dark (D5):** decide before PR 6.

The full platform request is in `architecture.md` §3.4.
