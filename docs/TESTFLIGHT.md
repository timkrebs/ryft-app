# TestFlight — beta for friends

How the beta gets from Xcode to 5–10 friends on external TestFlight, and past Beta App
Review. The per-build "What to test" texts are in `docs/TESTFLIGHT_NOTES.md`; CI's
nightly and weekly uploads are described in `docs/CI.md`.

Before the first external build, the platform must be live:
- the Beta deploy: consent, invite gate, the demo account and the legal pages
  (`../plattform/CLAUDE_FOLLOWUP_BETA.md`)
- `https://ryftapp.de/privacy` published, not just a draft

## 1. Archive and upload

**Build numbers.** Every build, from `make archive` or from CI, is numbered by
`scripts/build-number.sh` with the UTC build time, `yyyyMMdd.HHmmss`. Numbers therefore
only go up, and both paths can be mixed freely.

**Option A, Terminal:** `make archive` (Release, version from `VERSION`, build number
from `scripts/build-number.sh`). It checks the fonts and `make lint` (including `check-entitlements`)
first. Then upload `build/export/Ryft.ipa` with Organizer → Distribute App, or with
`xcrun altool --upload-app -f build/export/Ryft.ipa -t ios` and an API key.

**Option B, Xcode:**
1. Product → Archive, with the Ryft scheme and *Any iOS Device*. First set
   **Build** (General tab) to the output of `sh scripts/build-number.sh` on **both** the
   Ryft and RyftWidgetsExtension targets: each target sets its own value, and App Store
   Connect rejects an extension whose build differs from the app's. Without this, the
   archive carries `1` and the upload is rejected. `make archive` passes the number to
   every target by itself, so prefer it.
2. Organizer → Distribute App → App Store Connect → Upload.
3. Keep automatic signing. The export re-signs `aps-environment` as `production`.

Wait for "Processing" to finish in App Store Connect → TestFlight (usually 5–15 min).
Export compliance is answered by `ITSAppUsesNonExemptEncryption = NO` in `Info.plist`,
so no question appears.

## 2. Internal test first (your phone)

1. TestFlight → **Internal Testing** → add yourself to a group (App Store Connect users
   only; no review needed).
2. Install from the TestFlight app. This is a production-signed build:
   - push goes through **production** APNs
   - the Debug-only Developer section doesn't exist
3. Check on that build:
   - **Fresh install:** sign up with an invite code → consent → about you → Health → the
     first import → Today calibrating.
   - **Production push:**
     - The registration logs once to the console (`dev.timkrebs.ryft`, category `push`):
       `push registration env=production`. The same `env` is in Report a problem →
       diagnostics.
     - On the platform, check that `POST /v1/devices/{id}/push` stored `production`.
     - Then send a test push with the platform runbook (`OPERATIONS.md` → Push → test
       push) and confirm it arrives.
   - **Feedback:** Report a problem once, including the two-finger long-press, which is
     TestFlight only.

## 3. External group "Friends"

1. TestFlight → **External Testing** → **+** → group **Friends**.
2. Add the build. The first build of a version goes to **Beta App Review**, which takes
   about a day; later builds of the same version usually pass at once.
3. Turn on **Public Link** and send it to friends together with an **invite code**
   (`../plattform` `OPERATIONS.md` → Invite codes; one code per person, or one code with
   `max_uses`). Without a code the app stops at "Invite code".
4. The tester limit and the link can be changed later. Each build **expires after 90
   days**, so upload a new one before then.

## 4. App Store Connect fields (TestFlight → Test Information)

| Field | Value |
| --- | --- |
| Beta App Description | see below |
| Feedback Email | the address you read (e.g. `beta@ryftapp.de`) |
| Marketing URL | `https://ryftapp.de` |
| Privacy Policy URL | `https://ryftapp.de/privacy` |
| Sign-in required | **yes**: user name `review@ryftapp.de`, password from Vault (`seed_demo.sh`). Enter it **only here**, never in the repo. Run `seed_demo.sh` before every submission, so the 60 days of data are fresh. |
| Review Notes | see below |
| What to Test | from `docs/TESTFLIGHT_NOTES.md`, for the build |

### Beta App Description (en)

> RYFT turns what your watch or ring writes to Apple Health into three daily numbers:
> recovery, strain and sleep, each scored against your own baseline. This beta is for a
> small group of friends. Install, enter your invite code, and wear your device to bed.
> Scores sharpen over the first week. Feedback: Profile → Report a problem, or
> TestFlight's screenshot feedback.

### Review Notes (en)

> RYFT is a wellness app. It reads heart rate, HRV, resting heart rate, sleep,
> workouts, steps and energy from Apple Health. It never writes to Apple Health. It sends
> the data to the RYFT platform (EU), which calculates recovery, strain and sleep scores.
> Full scores need a watch or ring that writes heart rate and sleep to Apple Health. With
> an iPhone alone, the app shows steps and explains what is missing.
>
> **Demo account:** use the sign-in details above (email). The account already has 60
> days of data, so Today, Sleep, Strain, Train and Insights all show scores. It has beta
> access and consent on file, so the invite code and consent steps do not appear for it.
> New accounts see both.
>
> Sign in with Apple and email/password both work.
>
> **Account deletion:** Profile → Delete account. It erases all data on the platform and
> the sign-in, and revokes the Apple grant.
>
> **Notifications** are optional and asked for only after the first sync.
>
> RYFT is not a medical device; the app says so on Insights and in Profile → About.

## 5. Every new build

1. Raise the build number. `make archive` does it, so does CI. Keep the version at
   `1.0.0` during the beta.
2. Add an entry to `docs/TESTFLIGHT_NOTES.md` (en + de) and paste it into What to Test.
3. Upload, wait for processing, add the build to **Internal**, check it, then add it to
   **Friends**.
