# 0012 — The tracker hint opens the tracker's app through a compiled scheme table

- Status: Accepted (2026-10-31, data quality D3a, `docs/work/2026-10-31-data-quality/plan.md` lead decisions 3 and 4,
  `docs/work/2026-10-31-data-quality/design.md` §D3)
- Deciders: ios-lead; recorded by ios-architect
- Amends: ADR 0002 rule 4, "Links", its clause "No URL schemes, no `canOpenURL`, no `LSApplicationQueriesSchemes`".
  The rest of ADR 0002 stays in force.
- Applies to: `Ryft/Health/HealthKitManager+Status.swift` (`CatalogValidator`'s compiled tables, the `sync` field),
  `Ryft/Info.plist` (`LSApplicationQueriesSchemes`), `Ryft/Features/Today/TodayViewModel.swift` (`WatchSyncHint`),
  `Ryft/Features/Today/TodayView.swift` (`WatchSyncHintCard`), `Content/trackers.json`, `scripts/trackers.py`

## Context

- **What the hint does today.** When a tracker's data stops reaching Apple Health, Today shows "Nothing new from
  Garmin Connect since …". Its one action is "Garmin Connect in the App Store", built from the tracker's
  `app_store_id`. On that page, iOS shows "Open" when the app is installed, so reaching the app takes two taps and a
  detour.
- **What the brief wants.** For most vendor apps, opening the app is the fix: Garmin Connect writes to Apple Health
  only while it is open. So the data-quality brief (D3) asks for a button that opens the app, and for a catalog
  sentence saying how the tracker syncs.
- **Why ADR 0002 ruled schemes out.** The tracker-setup design dropped `open_url` from the catalog schema
  (`docs/work/2026-10-22-tracker-setup/design.md` §0.4 and §2.5, "Store or scheme tricks"). The reason was that a
  compromised or careless deploy of the remote `trackers.json` must not be able to send users anywhere. A scheme read
  from content would give that file a way to launch any app, or any deep link inside one.
- **The pattern that already answers it.** Since 0002, the catalog keeps what matters for safety in compiled tables
  that content can repeat but never change:
  - `helpHosts` and `helpPaths` for help links;
  - `storeIDs` for App Store ids;
  - `integrations`;
  - `knownBundles`.

  A scheme table fits that list.
- **iOS rules for checking a scheme:**
  - `canOpenURL` answers `true` only for schemes listed in `LSApplicationQueriesSchemes`. For any other scheme it
    returns `false`.
  - Apps linked on iOS 15 or later get at most 50 entries. Entries beyond that are ignored.
  - The list already holds one entry, `x-apple-health` (`HealthLinks`, onboarding and Profile). That entry is RYFT's
    own, not catalog content.
  - `open` works without the list. The list only controls whether the app may ask before opening.
- **The schemes aren't verified.** The brief names `garminconnect://` and `oura://`, and no one has checked them on a
  device yet. The other vendors have only candidates.

## Decision

1. **A compiled table maps tracker id → URL scheme.**
   - It lives next to `storeIDs` in `CatalogValidator`, only for `integration: vendorApp` trackers.
   - A tracker without a candidate scheme has no entry and keeps the App Store action.
   - `apple_watch`, `iphone`, `samsung_galaxy_watch` and `other` never get an entry (design.md §D3.3, states 3 and 4).
2. **Every entry is listed in `LSApplicationQueriesSchemes`, and a unit test pins the two lists together.** The test
   reads the bundle's Info.plist and passes only if all of these hold:
   - The plist list equals the table's schemes plus a short, named set of RYFT's own entries (today
     `x-apple-health`). A scheme missing from the plist would silently fail `canOpenURL`, and an extra one is an
     unexplained query.
   - The list has at most 50 entries.
   - Every scheme matches `^[a-z][a-z0-9+.-]{1,31}$`.
   - No scheme is `http`, `https`, RYFT's own `ryft`, or a system scheme (`tel`, `sms`, `mailto`, `facetime`, any
     `x-apple-` entry).
3. **The remote catalog can't add or change a scheme.**
   - The schema has no `url_scheme` field, and `CatalogValidator.knownKeys` doesn't learn one. A remote copy that
     carries it is treated like any unknown key and ignored.
   - A unit test proves that such a copy changes no hint's action.
   - `scripts/trackers.py --check` fails if `url_scheme` appears in `Content/trackers.json`, so no one adds it to the
     canonical file thinking it works.
4. **The URL is the bare scheme, checked first.**
   - The app builds exactly `<scheme>://`, with no host, path, query or user data. A pure builder turns the scheme
     into that URL and returns `nil` for anything malformed.
   - The hint offers "Open {app}" only when `canOpenURL` accepts that URL.
   - If it doesn't, or if `open` reports failure, the hint opens the App Store page built from the compiled
     `app_store_id` (`https://apps.apple.com/app/id<n>`), as it does today. The failure is silent and shows no error
     (design.md §D3.3, state 2).
   - Every surface other than Today's hint keeps the App Store action until a ticket changes it under these rules.
5. **The check goes through a seam, not `UIApplication.shared`.**
   - The hint gets the `canOpenURL` check as an injected `(URL) -> Bool`. In the app, demo mode and the simulator it is the real
     `canOpenURL` (harmless: the answer is kept nowhere); tests and previews inject a fake.
   - The check runs on the main actor when the hint is built. The answer isn't cached across foregrounds, because the
     user may install or remove the app in between.
6. **The new `sync` field is plain text under rule 4's text rules.**
   - It is optional, and when present it is `{en, de}` with both languages complete.
   - It has the same length cap as a `habits` item.
   - The validator rejects it if it contains `<`, `>`, `](`, `://`, `www.`, Unicode Cc or Cf characters, or the brand
     pattern.
   - It is rendered with `Text(verbatim:)` only.
   - It is additive and older builds ignore unknown keys, so `schema_version` stays 1.
   - The bundled `Content/trackers.json` gets `sync` now, for trackers whose verified `habits` already say how they
     sync (lead decision 4).
7. **The schemes stay unverified until a device check (Needs you).**
   - Each scheme is checked on a device with the vendor's app installed and again without it.
   - A scheme that fails is removed from the table and the plist in one change, and that tracker keeps the App Store
     action.
   - The check gates the External beta and App Store builds that contain the table. It doesn't gate merging, because
     a scheme that no installed app registers costs only the fallback.

## Consequences

**Good:**
- A common morning problem gets a one-tap fix: open the app that writes to Apple Health, then come back. Returning
  to the foreground already runs sync and the refresh path (design.md §D3.7).
- The threat that 0002 guarded against stays closed:
  - nothing a remote file says can make RYFT launch an app or a deep link;
  - the worst a hostile `trackers.json` can do to this button is change its `sync` sentence, under the same text
    rules as every other remote string, or add a bundle id or source name to a tracker's identity, so another source's
    quiet hint offers that tracker's compiled scheme or store page. It can never introduce a scheme or a URL.
- A wrong or missing scheme degrades to the behaviour the app ships today.
- One more compiled table follows the pattern of `helpHosts` and `storeIDs`, with no new mechanism.

**Privacy:**
- `canOpenURL` tells RYFT whether an app is installed, but only for the schemes in the plist, so the 50-entry cap is
  also the cap on what RYFT can learn this way.
- The app asks only for the tracker the hint is about. That hint exists because the tracker's data already reached
  Apple Health, so the answer adds little that RYFT didn't know.
- The answer stays in memory. It isn't logged, persisted, put in Copy diagnostics or Sync details, or sent to the
  platform. The App Privacy answers don't change.
- The opened URL carries no data.

**App Review:**
- Review watches for query lists that look like app discovery. RYFT's list is about ten entries:
  - one per supported tracker app, each behind a visible button with a matching label;
  - `x-apple-health`.
- Opening another app's bare scheme is an ordinary integration and needs no entitlement.
- Follow-up: `docs/APP_STORE.md` §10 (App Review notes) gets one sentence saying that the queried schemes open the
  companion app whose data has stopped arriving in Apple Health (the source the hint is about, not the tracker
  picked in setup), and that RYFT records nothing about them.

**Costs:**
- A new tracker app, or a vendor that changes its scheme, needs an app release. This is the same cost as a new help
  host, and it is intended.
- Each scheme needs a device check, which is a user step per vendor, and must be checked again when a vendor renames
  its app.
- There are two lists, the table and the plist, held together by a test.
- Comments that cite ADR 0002 for "no URL schemes" (the setup card in `StatusViews.swift`, Profile's tracker detail)
  stay true for their surfaces. T1 updates any comment that the hint's change makes wrong.

**What could go wrong:**
- **Another installed app claims the same scheme.** iOS doesn't say which app owns a custom scheme, so a squatting app
  could be opened instead of the tracker's.
  - The harm is small: the URL is bare, no data leaves RYFT, and the user sees the wrong app.
  - A release fixes it. The device check makes this unlikely for the listed vendors.
- **A wrong scheme ships.** Nothing can remove a compiled entry without a release. If that is ever needed faster, a
  remote kill switch for the button is the tool (a `today.*` flag in `GET /v1/config`). It isn't part of this
  decision, because the fallback is the shipped behaviour.
- **The list approaches 50 entries.** The test fails before iOS starts ignoring entries. At that point, the trackers
  without much use lose their entry and keep the App Store action.

**Rejected alternatives:**
- **Schemes from the catalog** (a `url_scheme` or `open_url` field in `trackers.json`). Rejected for the reason 0002
  gave:
  - A compromised or careless file could redirect the button. With `open`, which needs no plist entry, it could
    point at any scheme: `tel:`, `sms:`, `facetime:`, or a deep link with parameters inside another app.
  - Requiring `canOpenURL` would limit it to the plist's schemes. Those schemes have to be compiled anyway, so the
    field would add nothing except the power to swap one tracker's app for another's.
- **Universal links to vendor domains** (an `https` URL that opens the vendor's app when the vendor's site claims
  that path, opened with `universalLinksOnly`).
  - Gains:
    - no plist entries;
    - no `canOpenURL`;
    - the vendor's AASA, not RYFT, decides which app opens.
  - Rejected for now:
    - RYFT can't see or verify which paths each vendor claims, and many companion apps claim none for "open the
      app";
    - vendors change the AASA without notice;
    - SwiftUI's `openURL` has no `universalLinksOnly` option, so the hint would need `UIApplication` directly;
    - each URL would also have to pass the compiled host allowlist.
  - Revisit per vendor if a scheme fails the device check and the vendor documents a universal link.
- **The App Store page only** (today's behaviour, 0002 as written).
  - It has no privacy surface, no review question and no table to maintain.
  - But it turns the hint's one fix into a store detour every time. Users read the store page as "install", not
    "open and sync".
  - It remains the fallback, so this decision costs nothing where a scheme can't be used.
