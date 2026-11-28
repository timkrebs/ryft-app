# P2 review (2026-11-28)

## Lead's behaviour review of Codex's draft
- **Presenters under the Profile sheet** (blocking for flag on): Review consent, a gate's step and Profile → Data → Import
  present from `RootView`, the sheet's parent, so they couldn't show over the sheet. Fixed: `importPresentations` and the
  new `onboardingGateSheet` take `active:`; the root's step aside while `showsProfile`, and the Profile sheet hosts them.
- **Tab bar glyph**: the Nocturne bar draws a dot per tab; a Volt `fork.knife` for Nutrition tripped `check-accent-use`
  (a new Volt mark). Reverted to the dot.
- **German wording**: Codex added contextual keys for Journal ("Journal") and Add sleep ("Schlaf hinzufügen"); the app
  already says "Tagebuch" and "Schlaf erfassen". Reused the existing keys.
- The UI test wasn't in a plan: added `StructureV2UITests` to UISmoke.

## code-reviewer (one pass): flag off == main confirmed; should-fix for flag on, all fixed
1. Quick log → Log meal `reselect`ed Nutrition, dropping a meal being edited → no reselect; the diary opens the editor
   only when none is open and no draft waits.
2. A Live Activity/Siri resume while Profile is up set `train.live` under the sheet, never shown → `liveSessionCover(active:)`,
   hosted by the Profile sheet meanwhile.
3. Clean-up on the tabs' `onDisappear` could close Profile under a cover → removed; the sheet and a waiting link are
   forgotten with the account (`forgetsAccountState`).
4. Import's Open plan/history landed behind the sheet → `showStrain`/`openRoute` close Profile first.
5. A link closed Profile with a gate or the import over it → `DeepLinkRouter.holdsProfile` keeps it; the link waits for
   Done. Unit-tested.
- Nits fixed: an auth callback no longer closes Profile (tested); `profile_sheet` sent once per presentation.
- Nit kept: the avatar's Sync now sends `homescreen_top_right` from every tab (plan decision: same control, same place).
