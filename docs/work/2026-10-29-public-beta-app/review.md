# Review — PR #71 (minimum age 16, External notes)

Cross-repo plan: `../docs/work/2026-10-29-public-beta/plan.md`.

## code-reviewer
- Should fix, fixed: the new-account lists in `TESTFLIGHT.md` and `TESTFLIGHT_NOTES.md` skipped "What do you wear?"
  (`devices.setup`).
- Should fix, fixed: Profile's picker went blank for a year saved under the old rule (− 13). The saved year now stays
  listed (test in `birthYearSetsTheEstimateAndManualCanGoBack`).
- Nit, left: `MockDataSource.patchMe` checks against `.now`, not the injected clock. No test or preview is affected.
- Nit, to the platform: which time zone "this year" means in the − 16 check (first hour of 1 January, Berlin vs UTC).
  In STATUS → Open.
- Confirmed: no 13 or 1920 left except Apple's breathing-rate fact; `nonisolated static` is fine; the catalog
  edit is surgical; labels in the notes match the catalog; the demo seed consents and sets 1990.

## ui-validator
- Not run: launching the simulator was refused (Bash permission), and so was `scripts/screenshots.sh`. From the code,
  the consent line wraps (`fixedSize`), VoiceOver reads it as plain text, and it sits 20 pt below the points (the
  screen's spacing). It still needs a look in the `Consent · dark` / `· light` previews.
