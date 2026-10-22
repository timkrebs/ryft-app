# 0005 — Route privacy is enforced on the device: opt-in routes, privacy zones trimmed before the disk and before anything leaves, no coordinates in logs

- Status: proposed (2026-10-22, My Day and activities, `docs/work/2026-10-22-my-day-activities/design.md` §8);
  revised the same day after the security and privacy review (B1, B3, S1, S5, S6, S7 and the nits);
  security-privacy-reviewer must sign off
- Deciders: ios-lead, on ios-architect's proposal; security-privacy-reviewer
- Applies to: `Ryft/Activities/Recording/RouteTrimmer.swift` (`PrivacyZone`, `RouteTrimmer`),
  `Recording/ActivityRecorder.swift`, `ActivityVault.swift`, `PrivacyZoneStore.swift`, `ActivityPayload.swift`,
  `ActivityHealthExport.swift`, `Features/Profile/DataExport.swift`, `Persistence/Repository.swift`,
  `Recording/Sources.swift` (`LocationFix`), `Recording/RecordingDiagnostics.swift`, `Ryft/PrivacyInfo.xcprivacy`,
  `Ryft/Info.plist`

## Context

A GPS route is location data, which is personal data under GDPR. Repeated routes reveal where someone lives and
works, and when they're away.

**The brief requires:**
- routes opt-in per activity, and as a setting;
- distance and pace without uploading a route;
- privacy zones that trim 200–500 m around user-chosen places before upload and before any export;
- routes deleted with the activity and the account, and included in "Export my data";
- never logged.

**The platform expects** routes "already trimmed by privacy zones on the device".

**Where routes leave the phone or rest on it:** the upload, Apple Health, the export file, cached reads,
diagnostics, and the store itself (backups, SQLite free pages).

**The review found three gaps in trimming only at send time:**
- zones kept in a document that the wipe deletes, so routes uploaded after an expiry went untrimmed (B1);
- a mutable radius with a fixed offset, which could leave the place outside its circle (B3);
- an untrimmed route at rest (S1).

## Decision

1. **Routes are opt-in per activity.**
   - The pre-start toggle defaults to the account's setting.
   - The setting is unset until the first GPS Start, where the choice is asked once and remembered.
2. **Without the route, no coordinate is written to disk.**
   - Distance, pace, splits and elevation are computed on the device. The checkpointed `profile` holds time,
     distance, altitude and speed only, and the recording header holds no coordinate (tested).
   - A resume after a kill then can't bridge the gap.
3. **Privacy zones live only on the device:**
   - 1–5 places, each with a radius of 200, 300, 400 or 500 m;
   - stored as `LocalPrivacyZone` rows: per account, sealed with the account's zone key, parked with the activities
     on expiry, deleted with the account;
   - never a `CachedDocument`;
   - never uploaded, exported or logged.
4. **Zones are immutable and edits draw a new offset.**
   - `PrivacyZone.make(name:place:radiusM:)` draws a secret offset, uniform over the disc of radius `radiusM −
     100 m`, from the system CSPRNG. The circle that trims isn't centred on the place, and the place stays at least
     100 m inside it.
   - Changing the place or the radius makes a new zone; a rename keeps the offset.
   - A property test pins the invariant through edits.
5. **Trimming happens twice:**
   - **At each checkpoint:** the recorder drops every in-zone point before a route chunk is encoded and sealed. No
     in-zone point ever reaches the disk.
   - **At every exit path:** upload, Apple Health, export and the detail map of an unconfirmed activity trim again
     with the account's current zones. A zone added later applies to everything not yet uploaded.

   Routes already on the platform aren't changed: the platform never learns the zones.
6. **The withhold rule.** A row recorded with zones, in an account that now has none, doesn't attach its route
   automatically. The activity uploads without it and asks the user to review: add the zones again, send it as
   recorded (it was trimmed then), or remove it.
7. **What leaves the phone is minimal:**
   - **Upload:** a polyline of latitude and longitude only, simplified at ≥ 3 m, with no altitude or timestamps.
   - **Apple Health:** the same trimming, with the timestamps HealthKit requires.
   - **Reads:** list and day reads never carry `route` or `hr_samples`. If they do, they're stripped before caching.
     The detail screen fetches a route on demand and keeps it in memory only.
8. **At rest:**
   - route and heart-rate chunks and zones are sealed with AES-GCM keys kept in the Keychain as
     `AfterFirstUnlockThisDeviceOnly`;
   - deleting a key (at confirmation, discard, wipe, or after 30 days unconfirmed for the route) makes the data
     unreadable everywhere it lingers.
9. **Export:**
   - the file contains trimmed routes, `hr_samples`, splits, manual sleep and unconfirmed rows, never zones;
   - it's deleted when the share sheet closes, and any leftover is deleted at launch.
10. **Apple Health on delete:**
    - deleting an activity deletes RYFT's own Health workout and route (by external UUID, our source only);
    - deleting the account leaves the user's Health copies, and the confirmation says so.
11. **No coordinates anywhere outside the route path:**
    - **Not logged:** no log call, signpost, diagnostics line, error string, or `fatalError` / `precondition` /
      `assert` message contains one.
    - **Redacted types:** location types implement `CustomStringConvertible`, `CustomDebugStringConvertible` and
      `CustomReflectable` with redacted output (tested). Store and Keychain errors are logged by domain and code.
    - **Grep:** reviews grep for `latitude`, `longitude`, `coordinate`, `CLLocation` and `CLLocationCoordinate2D`.
12. **Declarations:**
    - When In Use only, no `NSLocationAlways…`;
    - temporary full accuracy only for a recording;
    - `PrivacyInfo.xcprivacy` declares Precise Location, linked, App Functionality, and its diagnostics comment names
      the recording line;
    - the privacy policy (new version, re-consent) and the App Store privacy answers are updated before
      `activities.recording` turns on;
    - `UIBackgroundModes` → `location` ships only in that release.

## Consequences

**Good:**
- **Minimal by construction.** No in-zone point is ever stored, sent, exported or saved to Health. That doesn't
  depend on a server promise or on the zones surviving a wipe.
- **The platform never stores the places users hide.**
- **Recoverable without leaking.** A lost zone set withholds the route instead of leaking it.
- **Bounded rest.** Data at rest is sealed and time-limited, and a backup or free page can't be read after the key
  is gone.
- **Reviewable.** Trimming lives in one function, used at the disk and at every exit, so a forgotten path is visible
  in review.

**Costs:**
- **No retroactive trimming.** Changing zones doesn't fix routes already uploaded. The user has to delete those
  activities to remove them.
- **Lost gap bridging.** Route-off recordings lose it after a kill, and so does a run killed inside a zone.
- **Chords.** Until the API takes segments, a mid-route pass draws a straight chord through a zone (inside the
  circle).
- **The summary shows the trimmed route,** not the full one: the full one never existed on disk.
- **Keychain work.** Keychain management and its failure mode: a failing Keychain costs the route, never the
  activity.
- **Not exported.** Zones aren't in the export. That's deliberate, and the export screen says so.

**Rejected alternatives:**
- **Trimming only at send time** (the first version). An untrimmed route at rest, and an untrimmed upload after an
  expiry wiped the zones (B1).
- **Trimming on the server.** The server would have to store the zones, which means storing the users' homes.
- **Trimming only the first and last N metres.** A run past home mid-route leaks it, and a fixed distance makes the
  start point easy to reconstruct from several runs.
- **Fuzzing or snapping coordinates.** It degrades the route and the distance, and averaging many runs undoes it.
- **A mutable radius with a fixed offset.** Shrinking the radius could leave the place outside the circle (B3).
- **Caching routes from list reads.** It keeps location data around for no screen that needs it (S5).
- **Deleting Health copies on account deletion.** It erases Fitness history the user asked for. Deleting one
  activity is a correction; deleting the account isn't a request to erase Health.
