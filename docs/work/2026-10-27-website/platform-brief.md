# ryftapp.de: `trackers.json` and the privacy policy (for the platform session, web-engineer)

The app session can't edit `plattform/`, so this is a hand-off. Everything it asks for is already in the app (on
`main`, mostly behind flags) and waits for the site. Read the linked app docs for detail; this file is the checklist.

## 1. Serve `https://ryftapp.de/trackers.json`

- **Source:** the app's canonical file `app/Content/trackers.json`, version `2026-10-23.1` (13 trackers). Copy it
  unchanged into `web/content/trackers/`. Schema and research notes:
  `app/docs/work/2026-10-22-tracker-setup/{design.md §2.3,trackers-research.md}`.
- **Serving:** `application/json`, a strong `ETag`, `Cache-Control: public, max-age=3600`, and a `304` on
  `If-None-Match`. The app fetches it at most once a day with one attempt, sends no account data, and
  falls back to its bundled copy on any error or invalid file.
- **Optional:** `/setup/<tracker>` pages rendered from the same file. Brand rule: no other wearable brand's vocabulary.
- **Done when:** `curl -sI https://ryftapp.de/trackers.json` shows `200`, the `ETag` and the JSON type, and the body
  equals the app file (`cmp`).

## 2. A new privacy-policy version

The current version is `2026-10-20` (`web/content/legal/{en,de}/privacy/2026-10-20.mdx`). Add `2026-10-27` (or the
publish date) in both languages and append it to `privacy-versions.json`. The app's consent gate (ADR 0008) then asks
everyone to agree again. Per R24 in the app's `docs/API_REQUESTS.md`, announce the bump before it applies, if the
platform supports that.

Add these points to the existing sections. They state facts; the wording is the web-engineer's and the user's:

**§3 What we process**
- **What you wear:** the trackers you pick in onboarding or Profile → Data → Devices & sync. The choice stays on the
  iPhone and is never sent. If `PATCH /v1/me` ever takes `trackers`, this line changes.
- **Activities and sleep you add by hand:** for an activity, the sport, start, end, moving time, distance, ascent and
  descent, perceived effort and a note; for a night, bedtime and wake time. They're stored and scored like Apple Health data, and you can edit or delete them.
- **Imported strength training:** you can import a CSV export from another training app. The file is read on the
  iPhone; only the resulting exercises, plans and workouts are sent, and each workout records which app it came from
  (`import_source`). An import not yet sent is kept on the iPhone for up to 30 days, then deleted.
- **Remembered exercise matches:** when you match an imported exercise name to a RYFT exercise, the iPhone remembers
  it for your next import. Matches stay on the iPhone, are deleted at sign-out or with "Clear remembered matches",
  and are part of "Export my data".
- **Problem reports:** if you send one, it includes the trackers you picked and the result codes of Check sync.

**§5 Who else processes data**
- **The tracker catalog:** once a day the app downloads `trackers.json` from ryftapp.de. Like any web request, this
  gives the site's host your IP address and the app's user agent. No account data is sent.
- **Setup guides:** "How to set up" links open the tracker vendor's own website, under that vendor's privacy policy.

**§6 How long we keep it**
- Unsent imports: up to 30 days on the iPhone. Activities, manual nights and imported workouts: like other health data,
  until you delete them or your account.

**Not yet:** routes, GPS recording and precise location (A3, U8 in `app/docs/work/2026-10-22-my-day-activities/design.md`).
They need their own version when `activities.recording` is about to turn on.

## 3. Also open for the platform (already filed; listed so nothing is lost)

- `app/docs/API_REQUESTS.md` → **Sync performance §2, HealthKit deletions.** **Now a confirmed bug** (2026-10-27): one
  Garmin run that Apple Health holds once shows 7 times in My Day, and the day reads "7 activities · 63.3 km". Garmin
  Connect rewrites its workouts in Apple Health with a new UUID. The old copy is deleted on the phone, but the platform
  keeps it, because `POST /v1/sync` can't carry deletions. The app has collected `deletedObjects` per account since
  that request and sends them as soon as the contract has `deleted`. Copies older than that collection need a one-off
  cleanup on the platform side (same user, source, activity, start and end).
- Tracker setup §5, Activities R1–R26, Training import T1–T13 (`POST /v1/train/import` unblocks the import's C2).
