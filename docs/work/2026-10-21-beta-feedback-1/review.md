# Beta feedback 1 — review log

## T1 `sleep: editable sleep need everywhere`

**code-reviewer** (no blockers; 5 should fix, 4 nits) — all addressed:
- Birth-year failures were invisible in Profile → shown beside the picker (`birthYearError`).
- Save and rescore could overlap (a save during the rescore was reported as rescored) → one at a
  time (`isBusy`), buttons disabled across, tested.
- A failed rescore lost its request ID → `rescoreDetails`, shown with Details.
- The form's draft only set on appear (stale after a refusal; defaults before the account
  loaded) → follows the saved value until edited, resets after every save.
- Test gaps → 500 failure, refused "go back", birth-year failure, save during rescore, failed
  rescore, the mock keeping each change.
- Nits: dead `updateUser`, unused environment and init parameter removed; the demo platform now
  keeps each patch (it reset to the mock user); VoiceOver hint says what happens ("Opens the
  editor"); the number animates (Reduce Motion respected).

**ui-validator** (1 blocker, 3 should fix, 3 nits):
- Blocker, About you at AX3: title and value fought for the line → stacked at accessibility
  sizes (the screen already scrolls). Re-checked at AX3.
- Editor at AX3: −/+ now scale with text (`@ScaledMetric`); the title scales instead of truncating.
- Not changed: the disabled Save pill (system toolbar style), Birth year staying a menu picker
  (it is a picker), caption contrast (existing token; a design-token change is out of scope).
