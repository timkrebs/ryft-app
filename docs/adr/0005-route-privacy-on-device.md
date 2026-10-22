# 0005 — Route privacy is enforced on the device: opt-in routes, privacy zones trimmed before anything leaves, no coordinates in logs

- Status: proposed (2026-10-22, My Day and activities, `docs/work/2026-10-22-my-day-activities/design.md` §8);
  security-privacy-reviewer must sign off
- Deciders: ios-lead, on ios-architect's proposal; security-privacy-reviewer
- Applies to: `Ryft/Activities/PrivacyZones.swift`, `ActivityPayload.swift`, `ActivityHealthExport.swift`,
  `Features/Profile/DataExport.swift`, `Recording/Sources.swift` (`LocationFix`), `Recording/TrackCodec.swift`,
  `Recording/RecordingDiagnostics.swift`, `Ryft/PrivacyInfo.xcprivacy`, `Ryft/Info.plist`

## Context

A GPS route is location data, which is personal data under GDPR. Repeated routes reveal where someone lives and
works, and when they're away.

**The brief requires:**
- routes opt-in per activity, and as a setting;
- distance and pace without uploading a route;
- privacy zones that trim 200–500 m around user-chosen places before upload and before any export;
- routes deleted with the activity and the account, and included in "Export my data";
- never logged.

**The platform:**
- stores routes in a separate table so they can be excluded and purged;
- expects routes "already trimmed by privacy zones on the device".

**Where routes leave the phone:** the upload, Apple Health (an export to another app), "Export my data", and
diagnostics.

## Decision

1. **Routes are opt-in per activity.**
   - The pre-start toggle defaults to the account's setting.
   - The setting is unset until the first GPS Start, where the choice is asked once and remembered (lead's question
     Q3).
2. **Without the route, no coordinate is written to disk.**
   - Distance, pace, splits and elevation are computed on the device. The checkpointed `profile` holds time,
     distance, altitude and speed only.
   - A resume after a kill then can't bridge the gap.
   - Nothing is uploaded, exported or saved to Apple Health as a route.
3. **Privacy zones live only on the device:**
   - 1–5 places, each with a radius of 200, 300, 400 or 500 m;
   - stored per account (`CachedDocument activities.privacyZones`), wiped on sign-out;
   - never uploaded, exported or logged.

   Each zone carries a **secret random centre offset**, generated once. Its length is at most the radius minus
   100 m, so the circle that trims isn't centred on the place, and the place stays at least 100 m inside it.
4. **Trimming:**
   - **What's dropped:** every route point inside any zone, anywhere on the route, not only at its ends.
   - **Where:** at send time, in the one function that builds the upload (`ActivityPayload.make`), in the Apple
     Health save, and in the export. A zone added later applies to everything not yet uploaded.
   - **What isn't changed:** routes already on the platform. The platform never learns the zones, and the setting
     says so.
   - **Segments:** until the API takes segments (request R5), the remaining segments are joined. A mid-route pass then
     shows as a chord across the circle.
5. **Raw coordinates are short-lived.** They leave the phone's disk once the platform has confirmed the trimmed route
   and Apple Health (if on) has its copy (ADR 0004).
6. **No coordinates anywhere outside the route path:**
   - **Not logged:** no `Logger` call (public or private), signpost, diagnostics line, Report a problem payload or
     error string contains one.
   - **Redacted descriptions:** `LocationFix`, `RoutePoint`, `Coordinate` and `PrivacyZone` print only an
     accuracy. A unit test asserts that their descriptions contain no coordinate digits.
   - **Counts only:** diagnostics carry counts and accuracies.
7. **Declarations:**
   - When In Use only; no `NSLocationAlways…` key;
   - temporary full accuracy only for a recording;
   - `PrivacyInfo.xcprivacy` declares Precise Location, linked to the user, for App Functionality;
   - the privacy policy and the App Store privacy answers are updated before `activities.recording` turns on.

## Consequences

**Good:**
- **Minimal by construction.** What leaves the phone is trimmed and opt-in, and that doesn't depend on a server
  promise.
- **The platform never stores the places users hide**, so a breach or a bug there can't reveal them.
- **One trimming function on every path out.** It's easy to review and test, and a forgotten path is visible in
  code review.
- **Zones apply retroactively** to anything still pending.

**Costs:**
- **No retroactive trimming.** Changing zones doesn't fix routes already uploaded. The user has to delete those
  activities to remove them.
- **Lost gap bridging.** Route-off recordings lose it after a kill.
- **Chords.** Until R5, a mid-route pass draws a straight chord through a zone (inside the circle, so the place isn't
  revealed).
- **Not exported.** Zones aren't in the export. That's deliberate, and the export screen says so.
- **A shared trimmer.** The Apple Health save and the export depend on it, so A6 and the export work wait for A5.

**Rejected alternatives:**
- **Trimming on the server.** The server would have to store the zones, which means storing the users' homes.
- **Trimming only the first and last N metres.** A run past home mid-route leaks it, and a fixed distance makes the
  start point easy to reconstruct from several runs.
- **Fuzzing or snapping coordinates.** It degrades the route and the distance, and averaging many runs undoes it.
- **Uploading untrimmed and hiding zones in the UI only.** The data would still be stored and exported.
- **A route on by default without asking.** That contradicts "opt-in" and data protection by default.
