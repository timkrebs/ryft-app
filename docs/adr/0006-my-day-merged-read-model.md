# 0006 — My Day is a merged read model: the platform's items plus local overlays, computed on read

- Status: proposed (2026-10-22, My Day and activities, `docs/work/2026-10-22-my-day-activities/design.md` §2.5, §7)
- Deciders: ios-lead, on ios-architect's proposal; the read path (R1) also needs the platform architect
- Applies to: `Ryft/Features/MyDay/MyDayAssembler.swift`, `MyDayViewModel.swift`, `Persistence/Repository.swift`
  (`ReadResource.activities`), `Features/Strain/StrainViewModel.swift` (activities list),
  `Ryft/Activities/ActivityStore.swift`

## Context

My Day lists one day's sleep, tracker workouts, Train sessions, and activities the user recorded or added. Each row
has strain once scored, its sources, and merged rows when the platform combined a RYFT activity with a tracker
workout.

**Those facts have different owners:**
- **The platform:**
  - sleep, workouts and sessions (`GET /v1/days/{day}`, cached in `CachedDay`, ADR 0001's read path);
  - activities with strain, scoring state, merges and HR source (`GET /v1/activities`, contract pending).
- **The device:** activities and manual sleep not yet confirmed (ADR 0004), Train sessions not yet synced, and
  edits and deletions in flight.

**Constraints:**
- **The endpoint is undecided.** The platform brief leaves open between extending `GET /v1/days/{day}` and a new
  `GET /v1/my-day/{day}`.
- **Strain merges on its own.** Strain already merges workouts with Train sessions in its view model
  (`StrainViewModel.activities`).
- **Offline-first.** Views read only from caches (ARCHITECTURE §3), and nothing may be stored twice.

## Decision

1. **One pure function builds the list.** `MyDayAssembler.items(_ input:, catalog:, now:) -> [MyDayItem]`.
   - **Input:** the platform's layer (the cached `DayDetail` plus the cached activities of that day, or the
     platform's own items once they exist) and the local layer (snapshots of unconfirmed or tombstoned rows, local
     sessions, a pending manual sleep).
   - **Output:** rows, never persisted. The view model computes them from caches on each render, memoised per
     Repository revision.
2. **The local layer overlays the platform's by id:**
   - an unconfirmed local edit wins until confirmed, and keeps the last strain the platform reported;
   - a tombstone hides the item;
   - local-only items are added.
3. **Merges are only what the platform reports.**
   - An activity's `merged_with` hides that workout's row and adds its source badge. The strain is the activity's,
     from the better heart-rate source.
   - The app never predicts a merge from overlap. Until the platform answers, both rows show, and the activity's
     carries the pending dot.
4. **Source names** come from the tracker catalogue (`TrackerCatalog.displayName`, the tracker-setup work).
5. **The read path:**
   - **Now:** `GET /v1/days/{day}` (existing) plus `GET /v1/activities?from&to` for the day, through `ReadScheduler`
     as `ReadResource.activities`. It's cached as `CachedDocument "activities.<day>"`, with the day's TTLs and
     refreshed for `days_touched`.
   - **Recommended to the platform (R1):** extend `GET /v1/days/{day}` additively with the day's activities, merge
     ids and sleep origin. My Day then *is* Today's read: no second resource, already refreshed by every sync, silent
     push and pull. `.activities` then leaves My Day's path.
   - **If `GET /v1/my-day/{day}` is chosen instead:** `ReadResource.myDay` takes `.activities`' place. The assembler's
     platform layer switches input; the overlay rules and the rows stay.
6. **Strain's activity list uses the same assembler** (without the sleep row). Its own merge is deleted, and RYFT
   activities appear there too.

## Consequences

**Good:**
- **One owner per fact.** The platform owns scores and merges; the device owns what it hasn't delivered yet. The
  list is derived, so it can't drift from either.
- **Works before the contract.** Sleep, workouts and sessions come from today's day detail; activities come from the
  fake, then the real read.
- **The endpoint decision changes one input type.** Rows, tests and UI don't change.
- **Pure and table-tested.** Every rule is a case in `MyDayAssemblerTests`.
- **Less code.** One merge for My Day and Strain instead of two.

**Costs:**
- **An extra request.** Until R1 lands as a day-detail extension, Today makes one more scheduled read (activities)
  per refresh of a stale day.
- **Brief double rows.** A RYFT activity and a tracker workout show as two rows until the platform merges them
  (seconds to minutes after the tracker's sync).
- **A per-render merge.** The assembler runs on every render of the card. It's small (a handful of items) and
  memoised per revision.

**Rejected alternatives:**
- **Storing the merged list** (a `CachedMyDay` table). Two owners for the same rows, and invalidation for every local
  edit and every platform answer.
- **Merging overlaps on the client** with the platform's rule (same family, ≥ 60 %). It duplicates scoring logic the
  platform owns, can disagree with it (HR source choice, families), and the phone computes no scores.
- **Waiting for `GET /v1/my-day/{day}` before shipping My Day.** It blocks a feature whose main inputs exist today.
- **Separate lists per type** (sleep card, workouts card, activities card). That's not what the brief asks for, and
  it doesn't answer "what happened today".
