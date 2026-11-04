# Data quality: plan

Brief: `brief.md` (a copy of `CLAUDE_FOLLOWUP_DATA_QUALITY.md`). The platform half is
`../plattform/CLAUDE_FOLLOWUP_DATA_QUALITY.md` (Q1–Q5). Lead: ios-lead. Started 2026-10-31 from `origin/main` 69ca9ad.

**Gates, checked 2026-10-31 (plattform `origin/main` 7f0f8db).** `API.md` has none of the changelog entries
"Deletions and HealthKit ids", "Workout duplicates" or "Coverage and provisional scores", and no `sources[].samples_7d`.
`trackers.json` with a `sync` field isn't served yet either. So D1 and D2 get design notes now and no code, and nothing is
mirrored ahead of the contract (CLAUDE.md: "do not invent fields"). D3 and D4 ship first.

## Tickets

| # | Ticket | Owner | Branch · PR title | Depends on |
| --- | --- | --- | --- | --- |
| A | Architecture note: D1 drain and capability gate, D4 source detection seam, D3b refresh paths (`architecture.md`) | ios-architect | (doc) | — |
| B | Design note: D3 hint button, D4 Sources screen and pre-selection, D2 provisional / coverage / provenance (`design.md`) | ui-designer | (doc) | — |
| C | D3b audit: is `.pending` reached on every refresh path (pull-to-refresh, background delivery, foreground return, import)? (`d3b-audit.md`) | sync-engineer (read-only) | (doc) | — |
| T1 | D3a: the staleness line becomes a button that opens the tracker's app; `sync` read from `trackers.json` when present; the scheme from a compiled table (decision 3, ADR 0012), listed in `LSApplicationQueriesSchemes` | ios-developer | `feat/tracker-sync-hint` · `today: tracker sync hint opens the app` | A, B §D3 |
| T2 | D3b: the fix the audit finds, with a view-model test per refresh path (no PR if the audit finds every path covered and the tests already exist) | owner of the file the audit names | `fix/today-pending-every-path` · `today: pending on every refresh path` | C |
| T3 | D4: detection in `Health/` (HKSourceQuery + 7-day counts per type, a seam for demo and the simulator); the Sources screen; the wizard pre-selects; warning chips | sync-engineer (detection), ios-developer (screen, wizard) | `feat/detected-sources` · `setup: detected sources` | A §D4, B §D4 |
| T4 | D1: HealthKit ids on samples and sleep segments; `PendingDeletions` drains into `SyncRequest.deleted` | api-contract-keeper (mirror), sync-engineer | `feat/sync-deletions` · `sync: HealthKit ids and deletions` | **changelog "Deletions and HealthKit ids"**, A §D1 |
| T5 | D2: `DailyScore.coverage`; provisional on Today and the widget; the ≥ 5-point "Updated" line; the coverage explain line | api-contract-keeper (mirror), ios-developer | `feat/provisional-scores` · `today: provisional scores and coverage` | **changelog "Coverage and provisional scores"**, B §D2 |
| T6 | D2: the provenance line under the tiles, tap → Sources | ios-developer | `feat/source-provenance` · `today: source provenance` | T3, T5 |

Every ticket with strings: localization-editor (en + de). Every ticket with behaviour: test-engineer from the acceptance
criteria below. Reviewers: code-reviewer always; security-privacy-reviewer for T1 (URL schemes, Info.plist), T3
(HealthKit reads), T4 (sync write path); ui-validator for T1, T3, T5, T6; performance-profiler for T3 (HealthKit queries
at screen open) and T4 (sync).

## Acceptance criteria

**T1 (D3a)**
- When the tracker's `trackers.json` entry has a `sync` text in the screen's language, the staleness line uses it;
  otherwise the line's current text stays.
- The line is a button when the tracker has an app URL scheme that `canOpenURL` accepts: it opens the app. Otherwise it
  keeps today's App Store page action. An Apple device keeps no button.
- Every scheme in the catalog is listed in `LSApplicationQueriesSchemes`, and a test fails if one is missing.
- The URL builder is unit-tested (scheme → URL, no scheme, malformed scheme refused).
- en + de; VoiceOver names the action ("Open Garmin Connect").

**T2 (D3b)**
- A view-model test per path (pull-to-refresh, background delivery, foreground return, the import) proves the hero
  shows `.pending` while the mock `GET /v1/me/sync` lists today in `pending_days` after a sync that touched today.

**T3 (D4)**
- Sources screen: one row per source seen in the last 7 days for the types RYFT reads, with its display name
  (`TrackerCatalog.displayName`), a known icon by bundle id, and type chips ("HR · Sleep · Steps").
- Warning chip when a tracker picked in setup wrote nothing in 7 days, or writes heart rate but no HRV (copy per brief).
- The wizard's "What do you wear?" step pre-selects what is detected; the user confirms.
- Counts: `User.sources[].samples_7d` when present (not yet in the contract: the seam only), HealthKit's otherwise.
- Simulator test with seeded HealthKit data: a Garmin-like bundle with HR and sleep and no HRV → the warning chip.
- No per-metric pinning UI (the seam is in the design note only).

**T4 (D1)** and **T5/T6 (D2)**: as in the brief, refined by `architecture.md` §D1 and `design.md` §D2 once the gates
open.

## Lead decisions

1. **No code for D1 and D2 before the changelog.** Design notes now, so the work starts the day the entries appear.
   I re-check `API.md` before each phase and at the close.
2. **Shared files are sequenced.** `Localizable.xcstrings`: T1's strings land first, and T3 merges `main` before its
   strings go in. `TodayViewModel.swift` holds both `WatchSyncHint` (T1) and the pending logic (T2), so T2 waits for T1 to
   merge if both change it. `Info.plist` belongs to T1 only.
3. **URL schemes are compiled, never read from the catalog (amends ADR 0002 rule 4).** ADR 0002 rules out schemes,
   `canOpenURL` and `LSApplicationQueriesSchemes`. The concern behind it is that a compromised remote `trackers.json`
   could redirect users. The brief wants the hint to open the tracker's app. Both hold if:
   - the scheme per tracker id is a **compiled** table, like `help_url`'s host allowlist, and every entry is in
     `LSApplicationQueriesSchemes`;
   - the remote file can't add or change a scheme; the catalog gets no `url_scheme` field;
   - the app opens a scheme only when `canOpenURL` accepts it, and falls back to today's App Store page otherwise. A wrong
     or unverified scheme then costs nothing.
   The schemes (`garminconnect`, `oura`, …) are unverified until a device check (Needs you). ios-architect records this
   as an ADR amending 0002.
4. **`sync` is a plain-text catalog field** (optional, en + de complete, the same text rules as `habits`). It goes into
   the app's schema and the bundled `Content/trackers.json` now, for trackers whose verified `habits` already say how
   they sync. The served copy picks it up when the web side next publishes the file.
5. **Design answers (design.md "Decisions that need the lead"):**
   1. **No 70 % dimming.** It can't be told from pending (0.6, breathing) and fails 3:1 (2.21:1 in light mode). The
      provisional gauge stays full strength with a dashed centre ring, which the brief allows ("its provisional
      treatment"). It needs a provisional flag in the shared `OrbitGaugeMode`, built in T5.
   2. **Wizard order stays (option a).** "What do you wear?" runs before Apple Health access, so a first run detects
      nothing. Pre-selection applies in Devices & sync → Edit and after a reinstall. The setup step offers "Also found
      Oura. Add it?" once something is detected. Moving the step changes the onboarding funnel; that is the user's call,
      not this brief's.
   3. See decisions 3 and 4.
   4. **The "no HRV" note is neutral** (`minus.circle`), because the user can't fix it. "Nothing in 7 days" stays amber.
   5. **The "no HRV" wording comes from detection**, not from `recovery_inputs`, which isn't in the contract:
      - "…recovery uses resting heart rate and sleep" only when that source wrote resting HR in the 7 days;
      - otherwise the catalog's `limits` sentence alone.
   6. **The "Based on" sheet** (medium detent, from the caption line) is the explain surface; there is no sheet today.
   7. **Durations use the shipped `Fmt.duration`** ("2h 50m").
   8. **Sources replaces "Seen in Apple Health",** so that view goes from 30 to 7 days, as the brief asks.
   9. **No new `SignalChip`:** `SourceBadge(glyph: nil)`, one component fewer.
6. **D1 needs a remote flag** (`architecture.md` §D1.1–1.2, ADR 0011).
   - **Why:** ingest decodes `POST /v1/sync` with `DisallowUnknownFields`, so a `deleted` or a record `id` sent before its
     deploy is a `400` on every page, forever.
   - **What the app does:** it sends the new fields only while `sync.deletions` (in `GET /v1/config`) is on, and falls
     back to the old shape on a `400`.
   - **What the platform must add:** the flag. That request goes into `API_REQUESTS.md` → Sync and performance §2 in the
     docs PR, so it reaches the platform before its Q1 ships.
7. **Answers to architecture.md's open questions:**
   - **Q3:** routing unchanged (decision 5.2).
   - **Q4:** yes. The "not received yet" note works now from `User.sources[].kinds`, which shows nothing it can't prove.
   - **Q5:** acceptable. Presence, chips and last-seen show at once. The count line appears once the tally covers 7 days;
     the brief says "a count per type is enough".
   - **Q7:** the first-sync orphan sweep is a follow-up after T4, not in T4.
   - **Q1, Q2, Q6:** for the platform, in `API_REQUESTS.md`.
   - **Q8:** a device check during T4.
8. **D3b has one owner** (`architecture.md` §D3b), and T2 is a single sync-engineer ticket. The pending record lives in
   `SyncService`, written only by the coordinator's `awaiting` / `scored` steps, and read through one pure function by
   Today and the widget. Its one-line `TodayViewModel.swift` change merges after T1.
9. **T3's order of work:**
   - Detection (`Health/SourceDetection.swift`, new) starts in parallel with T2.
   - The tally hook in `SyncService.swift` waits until T2 is merged, so there is one writer per file. Until then the count
     is nil, as the design allows.
   - The screen and the wizard (ios-developer) follow on the same branch once the types exist.
