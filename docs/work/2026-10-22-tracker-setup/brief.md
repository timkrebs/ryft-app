# RYFT iOS — baseline stuck at 0 (Garmin has no HRV in Apple Health) + "What do you wear?" setup & sync check — brief for `ios-lead`

Run: `claude --agent ios-lead` → "Run `CLAUDE_FOLLOWUP_TRACKER_SETUP.md`". The platform half is
`../plattform/CLAUDE_FOLLOWUP_BASELINE_WITHOUT_HRV.md` — it must land first for §1 to show real numbers; §2–§5 can
start right away. Owners: **debugger** (§0), **api-contract-keeper**, **ui-designer** → **ios-developer**,
**sync-engineer** (§4), **localization-editor**, **test-engineer**; reviewers per `docs/AGENT_FLEET.md`.

## The report

TestFlight, 2026-10-22 10:38, build `20261021.141128`, iPhone17,1, iOS 27.0.1:

> "The Baseline counter is not moving after 1 day. Please look into this issue."

Screenshot (Today): "Learning your baseline — 7 nights to go", gauge **Baselines 0 / 7**, "Scoring your latest data"
(spinner line), a hint "Nothing new from **Connect** since Wed 11:24 PM. Open the Connect app to sync it to Apple
Health.", tiles Sleep 6 h 28 m, **Recovery 74 % High**, Strain —. The user wears a **Garmin** and has ~90 days of history.

## Root cause (verify in §0, but this is the likely one)

- The platform counts baseline nights as `BaselineDays = min(lnHRVBase.N, rhrBase.N)` and marks a day
  `calibrating` while **either** HRV or RHR has fewer than 7 nights (`../plattform/backend/internal/scoring/compute.go:355`,
  `algorithms.go:170`).
- **Garmin Connect does not write HRV to Apple Health** (Garmin keeps HRV in its own app; third-party apps that read
  Apple Health document the same; Oura's HRV export is also reported as missing — verify both against the vendors'
  current docs). So `lnHRVBase.N` is 0 forever → `baseline_days` is 0 forever → Garmin users stay "calibrating" and
  never get Readiness, while Recovery is still computed from RHR + sleep (the 74 %). The counter will never move.
- Secondary issues on the same screen: the source is shown as "**Connect**" (HealthKit's source name) instead of
  "Garmin Connect"; "Scoring your latest data" stays up although nothing new arrived since 23:24 (the night hasn't
  reached Apple Health because Garmin Connect wasn't opened) — that's "waiting for your tracker", not "scoring".

## 0. Confirm (debugger)

- In the user's data: `User.sources` (kinds per source) — expect `hr`, `sleep`, `steps`, `workout`, maybe `resp`/`spo2`,
  **no `hrv`** for Garmin. Ask the user for Profile → Data sources (or `scripts/user.sh <id>` on the platform side).
- `GET /v1/days?from=…` for the last 14 days: `baseline_days` 0 throughout, `calibrating: true`, `hrv_ms: null`.
- Record the cause in `docs/STATUS.md` → Incidents. If it's something else, stop and report before building §1.

## 1. Show calibration and recovery honestly (after the platform change)

The platform will (see its brief): count baseline nights from resting heart rate (+ sleep), track HRV's baseline
separately, compute Recovery from the signals that exist, and say which ones were used. Mirror the new fields
(**api-contract-keeper**, from `API.md`'s changelog: expected `DailyScore.hrv_baseline_days`, `recovery_inputs`,
`User.sources[].kinds` already exists) and then:
- The baseline gauge counts the platform's `baseline_days` (now RHR-based) — for the user it should jump to 7/7
  after the rescore.
- Recovery and Readiness detail show **"Based on resting heart rate, sleep and breathing rate. Your tracker doesn't
  share HRV with Apple Health."** when `recovery_inputs` lacks `hrv`, with a link to the tracker's guide (§2).
- Never a counter that can't move: if a required signal has no source, say which and why instead of "n of 7".

## 2. "What do you wear?" — tracker setup (ui-designer → ios-developer)

A short, skippable step in onboarding **after About you, before Apple Health access**, and in Profile →
**Devices & sync** at any time.

**Step A — pick:** "What do you wear?" multi-select tiles (a watch *and* a ring is allowed): Apple Watch · Garmin ·
Oura · Polar · Suunto · COROS · Withings · Amazfit (Zepp) · Ultrahuman · Fitbit · Samsung Galaxy Watch · Other ·
"Just my iPhone". Use names only as data sources (brand rule: no comparisons, and the denylisted brand is not in the list
— it falls under "Other").

**Step B — per tracker, a setup card** with:
1. **What reaches RYFT** — a small capability row per signal: Heart rate · HRV · Resting HR · Sleep (stages) ·
   Breathing rate · SpO₂ · Workouts · Steps — ✓ / partial / ✗, and the resulting RYFT features ("Strain ✓, Sleep ✓,
   Recovery from resting heart rate and sleep — no HRV").
2. **Set it up** — numbered steps in the vendor's app (e.g. Garmin: Garmin Connect → More → Settings → Connected
   Apps → Apple Health → turn on all types) and in iOS (Settings → Health → Data Access & Devices → the vendor app →
   Turn On All). **Verify every step against the vendor's current help page** and store the URL + "checked" date with it.
3. **Keep it flowing** — the habits that make sync reliable, e.g. Garmin/Polar/COROS/Suunto only push to Apple Health
   when their app runs: enable Background App Refresh for it, keep it signed in, **open it each morning before RYFT**.
4. **Open <vendor app>** button (App Store link if not installed; don't guess private URL schemes) and "Show me again
   later".
5. Honest limits: Fitbit and Samsung don't write to Apple Health natively → "RYFT can't read <vendor> data on iPhone
   today" (no third-party bridge recommendations unless verified and privacy-reviewed); "Just my iPhone" → steps only,
   explain what stays empty.

**Content source, so guides can change without an app release:** the guides are data, not code —
`trackers.json` (id, display name, HealthKit bundle IDs and source names, capability matrix, setup steps en/de, habit
tips en/de, vendor help URL, `checked` date). The app bundles a copy and fetches the latest from
`https://ryftapp.de/trackers.json` (served by `../plattform/web`, cached, ETag) — file the request for the web side in
`docs/API_REQUESTS.md` (the web can also render `/setup/<tracker>` pages from the same file). Remote content is
validated against a schema; on failure use the bundled copy.

Store the selection locally per user and — if the platform accepts it (request in `docs/API_REQUESTS.md`:
`User.trackers: [string]` via `PATCH /v1/me`) — on the account, so support and `beta_report.sh` can see it.

## 3. Sync check — does data actually arrive? (sync-engineer + ios-developer)

Right after Health access, and in Profile → Devices & sync → **Check sync**:
- For each selected tracker, query HealthKit (no upload needed) for the newest sample per type **from that tracker's
  sources** (match bundle IDs / source names from `trackers.json`), last 48 h.
- Show a live checklist: "Heart rate — last 07:42 ✓", "Sleep — last night ✓", "HRV — not shared by Garmin Connect ✗
  (expected)", "Resting HR — waiting…". Distinguish **expected ✗** (the tracker doesn't share it) from **unexpected ✗**
  (it should, but nothing arrived → show the setup steps again, e.g. the Apple Health permission in the vendor app).
- Nothing at all from the tracker in 48 h → "No data from Garmin Connect yet. Open Garmin Connect and let it sync,
  then tap Check again."
- Also check RYFT's own Health permission per type (what's denied) and say which toggle to turn on.

## 4. Fix the screen's secondary issues (sync-engineer + ios-developer)

- **Friendly source names:** map HealthKit source bundle IDs to display names via `trackers.json` ("Connect" →
  "Garmin Connect", "Oura" → "Oura", etc.) everywhere: the stale-source hint, Data sources, Sync details.
- **Stale-source hint with the morning in mind:** if the newest sleep/HR sample from the user's tracker is older than
  the last wake-up window (e.g. no sample after 04:00 by 08:00), say "Your night hasn't reached Apple Health yet —
  open Garmin Connect to sync it." and **don't** show "Scoring your latest data" — that state is only for data RYFT has
  uploaded and the platform hasn't scored (`GET /v1/me/sync` → `pending`).
- "Scoring…" must end: if `pending` lasts beyond `expected_within_sec` × 3, switch to "Taking longer than usual" with
  Details, never an endless line.

## 5. Tests, strings, verification

- Tests: tracker selection persistence; `trackers.json` decode + schema validation + remote/bundled fallback; capability
  → feature text mapping; sync-check classification (expected vs unexpected missing) with a `MockHealthStore` that has
  Garmin-like sources (no HRV); source-name mapping; the Today state decision for "night not in Apple Health yet" vs
  "pending scoring"; calibration presentation when `recovery_inputs` lacks HRV.
- Strings en + de via localization-editor; the brand guard must stay green.
- Device (ask the user): onboarding with Garmin selected → setup card → Check sync shows HRV "expected ✗"; next morning
  without opening Garmin Connect → the night hint; after opening it → scores; after the platform rescore → baselines 7/7
  and Readiness visible.

## Ship

PRs: `fix: honest calibration and recovery inputs` (after the platform) · `feat: tracker setup and devices & sync` ·
`feat: sync check` · `fix: source names and the night-not-synced state` · `docs: tracker setup`. TestFlight notes en + de:
"Tell RYFT what you wear — it shows you how to set up the sync and checks that your data arrives. Garmin users get
Readiness without HRV." Needs-you: run the platform brief first; the rescore command it prints; device checks.
