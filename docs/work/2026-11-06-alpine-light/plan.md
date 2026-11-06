# Alpine light pass: plan

Brief: `CLAUDE_FOLLOWUP_ALPINE_LIGHT.md` on PR #100. Notes: [`design.md`](design.md), [`architecture.md`](architecture.md).

**Goal:** the app's light appearance becomes monochrome Alpine, and dark doesn't move.

## Decisions by the user (2026-11-05)

These override the brief where they differ.

| Question | Decision |
| --- | --- |
| Which appearances | Light only, switched by appearance. Dark keeps Satoshi, its radii and hue-coded bands until the dark pass. |
| Who sees it (D1) | Those who pick Light. The default stays dark and Welcome and the auth screens stay dark. |
| Row lines (D2) | A soft row rule, ink at 0.20, for dividers, gridlines and tracks. Full-ink `separator` stays for edges. This departs from ADR 0015 and the website's row rules. |
| Good vs bad change (D4) | Polarity arrows: filled toward better, outlined toward worse. |

## Decisions by the lead

- **D3:** system-drawn destructive buttons stay red. The brief leaves confirmation sheets unchanged, and no code can make them ink.
- **D5:** Satoshi stays until the dark pass, which removes it.
- **D6:** answered in `architecture.md` §4.
- **Bold selected tab label:** dropped, because it can't be light only.
- **"Engineered for peak.":** on About in light only, owned by T6. Dark shows no hero, and onboarding and the screenshots keep theirs until the dark pass.
- **Every change is gated by look:** a token swap, string or symbol that would reach dark stays in dark as it is today. Strings that only light shows get new keys, and dark keeps the old key.
- **ADR numbers:** 0015 is #100's palette, 0016 is the wipe recovery, 0017 is "Two looks until the dark pass".
- **Where tickets land:** T1 to T5 change nothing visible, apart from the Licences row, so each is a PR to `main`. #100's CI is red on purpose, which could hide a failure in a refactor. T0 and T6 to T11 go on #100. The brief said to run everything on that branch.

## Tickets

| # | Ticket | Lands on | Owner | Depends on |
| --- | --- | --- | --- | --- |
| T1 | Dark proof: `make dark-diff`, pins, web tokens check, ADR 0017 | `main` | test-engineer | |
| T2 | `RyftLook`, `RyftFont`, the `View.font` overload; Alpine table equals classic | `main` | ios-developer | T1 |
| T3 | `RyftCorner` and the 56 metric radius lines; values unchanged | `main` | ios-developer | T2 |
| T4 | Literal radii and capsules from `design.md` §4.3; values unchanged | `main` | ios-developer | T3 |
| T5 | Inter files, `.gitignore`, `Info.plist`, Licences row, face test | `main` | ios-developer | T2 |
| T0 | `make mark-svg`, the widget's 7 colour sets | #100 | ios-developer | |
| T6 | Light type | #100 | ios-developer | T1 to T5 merged into #100 |
| T7 | Light shape, the `Rule` colour set, tab bar | #100 | ios-developer | T6 |
| T8 | Level by fill, polarity arrows, gauge and widget, re-pinned tests | #100 | ios-developer, test-engineer | T7 |
| T9 | Focused in light | #100 | ios-developer | T8 |
| T10 | Strings, en and de | #100 | localization-editor | T8 |
| T11 | Validate, screenshots, CHANGELOG, ADR 0015 §4, `docs/ARCHITECTURE.md`, the platform request | #100 | ui-validator, ios-lead | T9, T10 |

## Acceptance

- Every ticket: `make dark-diff` at 0 from T1 on, `make lint`, the Unit plan with no new failures. T5's allowed difference is the Licences row.
- T1 to T5 merged: light looks as it does on `main` today, because nothing visible changed.
- T11: `make lint` and `make test` green on #100, every scale distinguishable in greyscale, light screens validated in English and German at large sizes, and dark at 0 difference.
- #100 is merged only as a whole, so light never ships half done. It needs the user's go.

## Risks

- **The website:** #142 and #143 are open, so it hasn't moved as the brief says. T6 and T7 change values `tokens.mjs` reads, and pushing T6 turns #142's `web-checks` red. Platform runs `npm run tokens` once, after T11's last push (`architecture.md` §4.5).
- **`docs/ALPINE_STYLE.md`** isn't on this Mac. The hatch spec, button weights and hero size are the designer's own, marked "(mine)" in `design.md`.
- **Contrast:** the failures listed in `design.md` are designed around, not proven. T11 re-measures them.
- **Size:** two sets of styles sit in the views until the dark pass removes one.
