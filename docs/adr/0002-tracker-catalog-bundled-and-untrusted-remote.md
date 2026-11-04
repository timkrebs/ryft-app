# 0002 — The tracker catalog: a generated bundled copy, and remote content treated as untrusted

- Status: proposed (2026-10-22, tracker setup, `docs/work/2026-10-22-tracker-setup/design.md` §2)
- Amended: 2026-10-31. Rule 4's scheme clause is amended by 0012 (`0012-tracker-app-schemes-compiled.md`).
- Deciders: ios-lead, on ios-architect's proposal
- Applies to: `Content/trackers.json`, `scripts/trackers.py`, `Makefile`, `Ryft/Health/HealthKitManager+Status.swift`,
  `Ryft/Environment/Seams.swift`, `Ryft/Environment/AppEnvironment.swift`

## Context

**What the catalog is.** RYFT is getting a tracker catalog, `trackers.json`. For each tracker (Apple Watch, Garmin,
Oura, … Other, Just my iPhone) it holds:
- the HealthKit identity of its sources: bundle IDs, prefixes, source names, device models;
- which signals reach Apple Health (`yes`, `partial`, `no` or `unverified`);
- setup steps, habits and limits in English and German;
- a vendor help page and the date it was checked.

**Who uses it:**
- Today's source names and its "your night hasn't reached Apple Health" hint;
- onboarding's "What do you wear?" step and the setup cards;
- Profile → Devices & sync;
- the sync check.

**What constrains it:**
- **Vendor facts change.** Research on 2026-10-22 corrected the brief on Garmin (no HRV, no resting HR,
  foreground-only), Fitbit (now writes natively) and the iOS permission path. Guides must be fixable without an app
  release, so the latest copy comes from `https://ryftapp.de/trackers.json` (served by `plattform/web`).
- **The app needs a copy that always works:** offline, on first launch, in previews, unit tests and demo mode.
- **`Ryft/` is a classic Xcode group.** A new file there, a JSON resource included, needs a pbxproj change that only
  the user can make in Xcode.
- **The remote file is on another host than the API, and it's unauthenticated.**
  - `APIClient` adds a bearer token, refreshes on `401` and reports gates. None of that belongs to a static web file.
  - ADR 0001's `ReadScheduler` is the retry layer for platform reads, with the platform's rate limits.
- **Remote text is shown to users and may carry links.** A compromised or careless deploy must not be able to send
  users to arbitrary sites, inject markup, spoof Apple devices, or put the denylisted brand into the product. Today the
  brand rule is enforced only by an agent hook, not by `make lint`.

## Decision

1. **The canonical file is `Content/trackers.json`** in this repo. It starts from the research draft
   (`trackers.draft.json`), with schema changes listed in the design note:
   - localized `{en, de}` text from v1;
   - `version`, `form`, `health_access`;
   - store URLs built by the app.

   Once `plattform/web` publishes the file, the web's content becomes canonical, and this file is a snapshot refreshed
   before each release.
2. **The bundled copy is a generated Swift literal.** `scripts/trackers.py --write` (`make trackers`) writes the JSON
   into a marked region at the end of `Ryft/Health/HealthKitManager+Status.swift`.
   - `scripts/trackers.py --check` runs in `make lint`, and so in CI. It fails when:
     - the region and the JSON differ;
     - an en/de pair is incomplete;
     - an id is duplicated;
     - text matches the brand pattern;
     - a `checked` date is older than 180 days.
   - The full validation lives once, in Swift (`TrackerCatalog.decode`). A unit test proves the bundled literal
     passes it.
3. **The remote fetch is a seam of its own, outside the platform's read pipeline.**
   - `ContentSource` (`WebContentSource` live, `MockContentSource` for tests, previews and demo) fetches
     `https://ryftapp.de/trackers.json`:
     - with no auth and no cookies;
     - with an ephemeral session;
     - with same-host redirects only;
     - with at most 256 KiB read;
     - with `If-None-Match`.
   - `TrackerCatalogStore` (`env.catalogStore`) makes **one attempt** when the copy is due:
     - 24 h after the last 200 or 304, or 1 h after a failure;
     - on app active after the first frame, or when a tracker screen opens;
     - never in the background, offline or in demo mode.
   - There is no retry loop. The next due time is the retry. It doesn't go through `ReadScheduler` or
     `RequestBudget`: ADR 0001 governs platform reads, and this is neither the platform nor frequent.
4. **Remote content is untrusted.** A copy is used only when it passes every rule:
   - **Structure:** ≤ 256 KiB; `schema_version == 1`; ids `^[a-z][a-z0-9_]{1,31}$`, unique, with `iphone` and `other`
     present; closed enums; en and de complete; length and count caps.
   - **Text:** plain only. Reject `<`, `>`, `](`, `://`, `www.`, Unicode control and format characters (bidi
     overrides, zero-width), and the denylisted brand pattern. It is rendered with `Text(verbatim:)`, never as
     Markdown, `LocalizedStringKey` or HTML.
   - **Links:**
     - The only navigable URL is `help_url`: `https`, no user info, no port, and the host on a **compiled** allowlist
       for that tracker id, or `ryftapp.de`. Anything else is dropped and the text kept.
     - App Store links are built from the numeric `app_store_id` (`https://apps.apple.com/app/id<n>`).
     - No URL schemes, no `canOpenURL`, no `LSApplicationQueriesSchemes`.
   - **Identity:** `com.apple.` bundle IDs and prefixes only for `apple_watch` and `iphone`; a bundle ID belongs to one
     tracker; prefixes match at a dot boundary.
   - **Versions:** the newest valid `version` wins against the bundled copy and the cache, so an older valid file
     can't roll content back.
   - **No remote images.**
5. **A failure never shows.** The last valid copy (cache or bundle) stays; the reason is recorded for Sync details and
   Copy diagnostics. The cache is a `CachedDocument` (`content.trackers`) and is wiped with the store on sign-out.

## Consequences

**Good:**
- Guides and capability facts can be corrected without a release. A bad remote file costs a fallback, never a broken
  screen.
- One validator, used three ways: on the bundled copy in tests, on the cache at launch, and on every download.
- Previews, unit tests, demo mode and the UI tests are deterministic and offline, with the same compiled copy.
- No user step is needed before the first ticket starts.
- The brand rule gets an automated check for this content: in `make lint`, and at runtime for remote copies.
- The catalog's network path can't be confused with the platform's: no token leaves the app for the web host, and
  ADR 0001's guarantees are untouched.

**Costs:**
- About 60 KB of generated literal in the binary, and a generated region in PR diffs.
- A Python step in `make lint`.
- The catalog's types live in a file whose name (`HealthKitManager+Status.swift`) doesn't say so, until `Ryft/` is a
  synchronized folder.
- A new vendor domain for help links needs an app release: the allowlist is compiled on purpose.
- The cache is per-store, so it's dropped on sign-out and fetched again.
- Two copies of the content exist until the web ships: this repo's file and the web's. The release checklist must pull
  the web's copy before each release.

**Follow-ups:**
- When the user converts `Ryft/` to a synchronized folder, replace the generated literal with a JSON resource in
  `Ryft/Resources/`, delete the generator and its lint step, and move the catalog types into their own file.
- `scripts/trackers.py --pull` and a `docs/RELEASING.md` step to snapshot the web's file.
- The platform documents schema v1 next to `API.md`, so the web and the app validate the same rules.

**Rejected alternatives:**
- **Ask the user to add `trackers.json` as an Xcode resource now.** It's the right end state, but it blocks the first
  ticket on a Needs-you step, and a resource can silently miss its target membership. Revisit with the folder
  conversion.
- **No bundled copy, remote only.** The first launch, offline users and tests would have no catalog, and onboarding
  would depend on the website being up.
- **Fetch through `PlatformAPI` / `APIClient` and `ReadScheduler`.**
  - It would send the bearer token to the web host, apply `401` and gate semantics to a static file, spend the
    platform's request budget, and retry a daily download as if a user were waiting.
  - The catalog also isn't part of `API.md`; mirroring it in `Models.swift` would blur that file's rule.
- **Content with links or Markdown** (vendor-supplied store URLs, `open_url` deep links, rich text). A compromised
  file could then redirect users or inject markup. Store URLs from content would also pin a storefront (the research
  draft had `/us/`).
- **Strings in `Localizable.xcstrings`.** The guides are structured data per tracker and must change without a
  release; xcstrings is compiled.
