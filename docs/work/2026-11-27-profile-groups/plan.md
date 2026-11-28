# P1: Profile in five groups, one level of sub-pages (2026-11-27)

Brief: head-architect, "P1: regroup Profile (four groups, sub-pages); Codex drafts, you own it". Proposal v1, Nocturne v0.2.
Branch `feat/profile-groups`, built on #151 (`feat/home-sync-indicator`, not merged yet). One PR.

## Goal
Profile regrouped with no new data: You · General · Data · Resources · Legal. Each row acts in place or pushes one page.
Log out at the bottom. Every existing row keeps its behaviour and identifier. P2 (Profile as a sheet from a header avatar)
should only have to change how `ProfileView` is presented.

## Acceptance criteria
1. Every pre-P1 `ProfileRow` and button has a home (unit test over signed-in, signed-out demo, signed-in demo, devices
   on and off).
2. Account deletion takes two taps from Profile, in two places (Account; Privacy and data → Your data). Destructive rows
   come last in their section and are confirmed.
3. Log out is the only button on the top page. Log out is also a row on Account. Same dialog, same D6 hold.
4. Devices and sync is one page whether or not `devices.setup` is on. It holds the status tile, last sync, Sync now (#151
   coordinator), device ID, Apple Health, the strength-to-Health toggle and Advanced (rescore, Demo data; catalogue and
   flags in Debug only).
5. Licences credits BLS 4.0 (CC BY 4.0).
6. Nutrition settings: Targets · Scoring · Data, same rows and the same visibility.
7. Unit tests and UI smoke pass. UI tests whose path into Profile changed are updated. Strings are in English and German,
   and `make lint` is clean.

## Owner and process
Codex drafts (`.codex-prompt.md`). ios-lead reviews every line, builds, tests and fixes. code-reviewer does one pass.

## Decisions
- **Demo data stays in Release** (under Advanced). The brief's "debug builds only" is read as covering the catalogue and
  feature flags. Reasons: `docs/APP_STORE.md` lists the Demo data toggle in Release as a requirement, and a signed-out
  demo user needs the toggle to leave the demo and log in.
- **Change password** keeps `canChangePassword`. That condition already needs email sign-in, which is off, so the row
  doesn't show.
- **How RYFT scores** is left out: the app has no "how it works" links to move. Open item for the user.
- **Analytics**: no new `screen_viewed` tokens in P1, so the allow list and the privacy text stay as they are. Devices and
  sync, Sync details, Notifications and Report a problem keep their existing tokens.
- Strings: en + de. `origin/main`'s CLAUDE.md says English and German, and so does the brief. The main checkout has an
  uncommitted "English only" edit, which isn't ours.

## Risks
- Dialogs raised from pushed pages: they are attached on `ProfileView`, outside the stack, through `ProfilePrompts`.
- The UI tests that walk into Profile (StoreSmoke, Devices, ProfileSubpages, DemoExit, SignedOut).
- Merging #151: this branch contains it. Merge #151 first, then merge main into this branch.
