# The first run against a reference, and Apple Health by group: plan (ios-lead, 2026-11-23)

Source: the head-architect's brief `onboarding-health-app` (2026-11-23) and its cross-repo plan (§1, §2). The reference is
another app's first run, six screenshots kept outside this repo. It is a reference for **structure** only: no copy,
layout, asset, product name or vocabulary from it lands here, and no screenshot of it is committed (they show the user's
own data).

## Five rules the first run is measured against
1. One decision per screen.
2. A primer with a concrete example before every system prompt (Apple Health, notifications).
3. Everything except consent can be skipped, and the skip is visible.
4. The app is usable while the first sync runs.
5. The user always knows how far along they are.

## Tickets

| # | Ticket | Owner | Depends | Acceptance (testable) |
|---|---|---|---|---|
| F1 | Audit `audit.md`: each RYFT first-run screen beside the reference screen with the same job, scored on the five rules; a ranked gap list with an estimate per gap; taps and screens from sign-in to Today for Apple Watch, Garmin and no device | ui-designer | — | Every step of `OnboardingCoordinator` and `HealthPermissionView` captured (dark) and scored; tap counts reproducible from the listed steps; no reference copy or image in the repo |
| F2 | The notification primer: one shared component (lock-screen mock with RYFT's morning notification, under the lock-screen rule of `2026-11-22-notifications`), shown in the first run after Apple Health; Continue → system prompt, Not now → on | ui-designer (spec) → ios-developer | F1 | One primer type in the app; the example has no health value in its title; hosted test: Not now never calls `requestAuthorization` |
| F3 | Quiet step indicator on first-run screens, not on gates shown later as a sheet | ios-developer | F1 | Indicator counts only steps the account will see; absent in sheet presentation; VoiceOver reads "Step N of M" |
| F4 | Today during the first sync: `ImportCard` and the pending gauges checked against reference 6; fix what reads as broken | ios-developer (ui-designer spec) | F1 | No percentage; previews of pending Today in dark and light |
| F5 | Analytics: one event per first-run step (shown, continued, skipped, permission result), via the existing sink, only while `analytics.enabled`; no health value, no tracker name; listed in the analytics doc | ios-developer + test-engineer | F2, F3 | Allow-list test walks every new event; gate test: nothing captured while off |
| H0 | Design note `health-groups.md`: `HealthPermissionGroup` registry, per-account "asked" record, derivation of `readTypes`/background delivery/observers, the `about` read, migration of existing accounts | ios-architect | — | Every question in §"Health groups" below answered; ADR if a choice is non-obvious |
| H1 | Registry + `core` (unchanged ten types) + `about` (date of birth → year only); tests: every type has a consumer and appears in the usage description list | sync-engineer | H0 | Existing accounts see no new prompt; `readTypes` equals today's ten for an account that asked only `core` |
| H2 | About you: "Use my birth year from Apple Health", its short primer, the refused state with "Allow in Health" | ios-developer | H1 | The date never leaves `Health/`; only the year reaches the wheel; nothing persisted beyond the year |
| H3 | Docs: usage description, `docs/APP_STORE.md` privacy section, the data inventory, `docs/API_REQUESTS.md` note | sync-engineer + localization-editor | H1 | Usage description names only shipped groups |
| L | Strings for F2–F5 and H2 (targeted catalog edits only) | localization-editor | each ticket | Catalog `--stat` in the tens of lines |

## PRs
1. `docs: the first run against five rules (audit)`: F1 and this plan. **Stops for the user's pick of gaps.**
2. `onboarding: notifications primer, progress and the first sync`: F2–F5 (or the user's pick).
3. `health: Apple Health by group, and the birth year from Health`: H0–H3.

PR 1 and H0 run in parallel now; PR 3 doesn't depend on the audit.

## Health groups (H0's questions)
- Where "asked" lives per account, and what an account that already granted the ten types records on first launch.
- Whether background delivery and observers can stay unchanged for `core` (they must; no change to sync paging).
- `about` is a characteristic (`dateOfBirthComponents`), not a sample: no observer, no anchor, no upload.
- The usage-description test: how the list of types is read (Info.plist string vs registry).
- *Not yet requestable* groups: declared, never in `readTypes`, never requested.

## Reviews
- code-reviewer: every PR.
- ui-validator: PR 2 (dark, light, AX5) against the audit.
- security-privacy-reviewer: PR 3 (no type read before its group was asked; only the year leaves the phone from `about`), and PR 2's analytics events.

## Overlaps with open PRs
- #137 (analytics SDK; the opt-in becomes an onboarding step) and #142 (consent agree) both change `OnboardingCoordinator.swift`.
  PR 2 rebases onto whichever lands first; the step indicator must count #137's opt-in step once it is there.
- #141 (reminder scheduler) owns notification scheduling; the primer only asks for permission through the existing `notifier` seam.
- `Localizable.xcstrings`: targeted edits on every branch, merged with care.

## Risks
- The audit names gaps larger than PR 2 can hold: the user picks.
- HealthKit never reports a read refusal: "asked" is the app's memory, per account; a reinstall forgets it (asks again, harmless).
