# RYFT — App Store Connect metadata (v1.0)

Ready-to-paste product page texts in English (U.S.) and German, plus everything else App Store Connect asks
for. Limits checked by script (characters; keywords in **bytes** — German umlauts count 2). Keep this file the
source of truth; change it by PR and paste into App Store Connect.

Status of facts used here: features as shipped on `main` (2026-10-21). Don't add claims for unshipped work
(e.g. "every score explains itself" belongs to M4b).

---

## 1. App information (once per app)

| Field | Value |
| --- | --- |
| Name (≤ 30) | en: **RYFT: Recovery & Sleep** (22) · de: **RYFT: Erholung & Schlaf** (23) |
| Subtitle (≤ 30) | en: **Readiness from your own data** (28) · de: **Bereitschaft aus deinen Daten** (29) |
| Bundle ID | `dev.timkrebs.ryft` |
| SKU | `ryft-ios` |
| Primary language | English (U.S.); add German localisation |
| Primary category | Health & Fitness |
| Secondary category | Sports |
| Content rights | Contains no third-party content (only the user's own data) |
| Age rating | Complete the current questionnaire honestly (it includes medical/wellness questions; since 31 Jan 2026 updates are blocked until it is answered). RYFT: no user-generated content shared with others, no web browsing, no unrestricted chat, wellness information yes, no medical treatment advice. |
| Price | Free; no in-app purchases |
| Availability | Start with Germany/EU (data hosted in the EU); expand later |
| EU trader status (DSA) | Must be declared for EU distribution. **Trader** if this is or may become a business — then address, phone and email are shown publicly on the product page. **Non-trader** only for a purely private, non-commercial app. Decide deliberately; this is your legal call. |

## 2. Version information (per version, per localisation)

### Promotional text (≤ 170, editable without a new build)

**en (156):**
> One clear readiness score each morning, from the watch you already wear. Recovery, strain, sleep and strength training, built on your own Apple Health data.

**de (162):**
> Jeden Morgen ein klarer Bereitschaftswert – von der Uhr, die du schon trägst. Erholung, Belastung, Schlaf und Krafttraining aus deinen eigenen Apple-Health-Daten.

### Keywords (≤ 100 bytes, comma-separated, no spaces after commas)

Name and subtitle words are already indexed — don't repeat them. No competitor or device brand names
(Guideline 2.3.7).

- **en (98 bytes):** `hrv,strain,heart rate,training load,workout,tracker,fitness,resting pulse,hr zones,journal,vo2,nap`
- **de (100 bytes):** `hrv,belastung,herzfrequenz,training,workout,schlaftracker,fitness,ruhepuls,tagebuch,zonen,nickerchen`

### Description (≤ 4000, plain text)

**en:**

```
RYFT turns the data your watch or ring already writes to Apple Health into clear daily numbers: how ready you are, how hard you trained, and how well you slept.

EVERY MORNING, ONE NUMBER
Readiness combines your recovery and last night's sleep into a single score from 1 to 100, with a plain sentence about what it means for today.

RECOVERY
Heart rate variability, resting heart rate, respiratory rate and sleep, compared with your own 30-day baseline – not with an average stranger.

STRAIN
Day strain on a 0–21 scale from your heart-rate zones and training impulse, plus steps, active energy and every workout with its heart-rate curve.

SLEEP
Total sleep, stages, efficiency, consistency and naps. See how much sleep you need tonight – baseline, strain, sleep debt and naps – and get three bedtimes for the wake time you choose.

STRENGTH TRAINING
Build plans, log sets, reps and weight with a rest timer and Live Activity, track estimated one-rep max and personal records. Logged sessions count toward your strain.

JOURNAL AND INSIGHTS
Answer a few questions each morning – caffeine, alcohol, late meals, sauna and more – and after enough days RYFT shows how each one changes your recovery the next morning, with an honest confidence range. Insights flag what stands out in your trends.

YOUR DATA STAYS YOURS
- Works with Apple Health: RYFT reads heart rate, HRV, resting heart rate, respiratory rate, blood oxygen, VO2 max, sleep, workouts, steps and active energy. If you turn it on, it saves your strength workouts to Apple Health; it writes nothing else.
- Stored on servers in the EU, never sold, no ads, no tracking.
- Export everything or delete your account in the app at any time.

WHAT YOU NEED
An iPhone and any watch or ring that writes heart rate and sleep to Apple Health. Scores calibrate over your first 7 nights.

RYFT is a wellness app. It does not diagnose, treat or prevent any disease and is not a medical device. Talk to a doctor about health concerns.

Privacy policy: https://ryftapp.de/privacy
Terms of use: https://ryftapp.de/terms
```

**de:**

```
RYFT macht aus den Daten, die deine Uhr oder dein Ring bereits in Apple Health schreibt, klare Zahlen für jeden Tag: wie bereit du bist, wie hart du trainiert hast und wie gut du geschlafen hast.

JEDEN MORGEN EINE ZAHL
Die Bereitschaft verbindet deine Erholung und den Schlaf der letzten Nacht zu einem Wert von 1 bis 100 – mit einem klaren Satz dazu, was er für heute bedeutet.

ERHOLUNG
Herzfrequenzvariabilität, Ruhepuls, Atemfrequenz und Schlaf, verglichen mit deinem eigenen 30-Tage-Ausgangswert – nicht mit einem Durchschnitt fremder Menschen.

BELASTUNG
Die Tagesbelastung auf einer Skala von 0 bis 21 aus deinen Herzfrequenzzonen und dem Trainingsimpuls, dazu Schritte, aktive Energie und jedes Training mit seiner Herzfrequenzkurve.

SCHLAF
Gesamtschlaf, Schlafphasen, Effizienz, Regelmäßigkeit und Nickerchen. Sieh, wie viel Schlaf du heute Nacht brauchst – Grundbedarf, Belastung, Schlafschuld und Nickerchen – und erhalte drei Schlafenszeiten für deine Weckzeit.

KRAFTTRAINING
Erstelle Pläne, protokolliere Sätze, Wiederholungen und Gewicht mit Pausentimer und Live-Aktivität, verfolge dein geschätztes 1RM und deine Rekorde. Protokollierte Einheiten zählen zu deiner Belastung.

TAGEBUCH UND EINBLICKE
Beantworte morgens ein paar Fragen – Koffein, Alkohol, spätes Essen, Sauna und mehr – und nach genügend Tagen zeigt RYFT, wie jedes davon deine Erholung am nächsten Morgen verändert, mit einem ehrlichen Unsicherheitsbereich. Einblicke zeigen, was in deinen Verläufen auffällt.

DEINE DATEN BLEIBEN DEINE
- Funktioniert mit Apple Health: RYFT liest Herzfrequenz, HRV, Ruhepuls, Atemfrequenz, Blutsauerstoff, VO2max, Schlaf, Trainings, Schritte und aktive Energie. Wenn du es einschaltest, speichert RYFT deine Krafttrainings in Apple Health; sonst schreibt RYFT nichts.
- Gespeichert auf Servern in der EU, nie verkauft, keine Werbung, kein Tracking.
- Exportiere alles oder lösche dein Konto jederzeit in der App.

WAS DU BRAUCHST
Ein iPhone und eine Uhr oder einen Ring, die Herzfrequenz und Schlaf in Apple Health schreiben. Die Werte kalibrieren sich in deinen ersten 7 Nächten.

RYFT ist eine Wellness-App. Sie diagnostiziert, behandelt oder verhindert keine Krankheiten und ist kein Medizinprodukt. Sprich bei gesundheitlichen Fragen mit einer Ärztin oder einem Arzt.

Datenschutz: https://ryftapp.de/de/privacy
Nutzungsbedingungen: https://ryftapp.de/de/terms
```

### URLs and other version fields

| Field | Value |
| --- | --- |
| Support URL (required) | `https://ryftapp.de/support` (de: `https://ryftapp.de/de/support`) — must load, list a contact and how to delete the account |
| Marketing URL (optional) | `https://ryftapp.de` |
| Privacy Policy URL (required, App Privacy) | `https://ryftapp.de/privacy` — must be **published** (not the draft banner) before submission |
| Copyright | `2026 Tim Krebs` |
| What's New | not required for 1.0; from 1.0.1 on from `CHANGELOG.md` |
| Version | `1.0.0` (from `VERSION`); build number from `scripts/build-number.sh` |

## 3. Screenshots and previews

- **Required:** iPhone **6.9"** set, **1320 × 2868** portrait (1290 × 2796 also accepted), PNG/JPEG, RGB, no
  alpha, 1–10 per localisation. App Store Connect scales it down for smaller iPhones. iPhone-only app → no iPad
  set needed (keep "iPhone only" in the target).
- **Plan (6 shots, en + de, dark):** captions short and factual, numbers visible.
  1. Today — "One number for your day" / „Eine Zahl für deinen Tag"
  2. Recovery detail — "Measured against your own baseline" / „Verglichen mit deinem eigenen Ausgangswert"
  3. Sleep + need breakdown + planner — "Know how much sleep you need tonight" / „Wisse, wie viel Schlaf du heute brauchst"
  4. Strain + workout curve — "Strain from your heart-rate zones" / „Belastung aus deinen Herzfrequenzzonen"
  5. Train session — "Log sets, track records" / „Sätze protokollieren, Rekorde sehen"
  6. Journal impact — "See what changes your recovery" / „Sieh, was deine Erholung verändert"
- Real UI from demo mode, no device frames required, no other brands' devices or names, no medical claims in
  captions. `make screenshots` produces the raw captures; framing is a separate step.
- App preview video: optional; skip for 1.0.

## 4. App Privacy ("nutrition label")

Must match `PrivacyInfo.xcprivacy` and the code (security-privacy-reviewer checks). Based on today's app:

| Data type | Collected | Linked to user | Tracking | Purpose |
| --- | --- | --- | --- | --- |
| Health & Fitness → Health, Fitness | Yes | Yes | No | App Functionality |
| Contact Info → Email Address, Name | Yes | Yes | No | App Functionality |
| Identifiers → User ID | Yes | Yes | No | App Functionality |
| Identifiers → Device ID (install ID sent with sync) | Yes | Yes | No | App Functionality |
| User Content → Other (workout notes, journal answers, workout logs, feedback text) | Yes | Yes | No | App Functionality |
| Diagnostics → Other Diagnostic Data (Report a problem → "Include diagnostics": app version, device, iOS, locale, the last 20 requests without query strings and with their durations, per area (Today, History, Profile …) the last load time and the last error's status, code and request ID, sync phase and counts with day-precision dates, gates, flags; with tracker setup on, the tracker ids chosen, never device names, and the last Check sync: its day and, per tracker, a result code per data type (no values, times or source names)) | Yes, when the user sends a report with diagnostics on (the default) | Yes | No | App Functionality |
| Diagnostics → Crash Data | No | — | — | — |

Request durations are declared as Other Diagnostic Data, not Performance Data: they are network-diagnostic timings
that support reads next to a request's status and ID, while Apple's Performance Data means app performance such as
launch time, hang rate or energy use.

"Data Used to Track You": **none**. If any row changes, update the label and the privacy policy together.

## 5. App Review information

| Field | Value |
| --- | --- |
| Contact | Tim Krebs · timkrebs9@gmail.com · phone in `+49 …` format |
| Sign-in required | Yes — demo account `review@ryftapp.de`, password from Vault (`OPERATIONS.md` → demo account). Run the platform's `seed_demo.sh` right before submitting; the account must not expire and must pass the invite and consent gates without help. |
| Notes (≤ 4000 bytes) | below |

```
RYFT is a wellness app that reads heart rate, HRV, sleep and workouts from Apple Health and shows daily Readiness, Recovery, Strain and Sleep scores computed on our EU servers. It writes to Apple Health only if the user turns on "Save strength workouts to Apple Health" (Profile → Data, or the question after the first logged workout): one workout per logged strength session, no other data.

Demo account: the credentials above sign in with email and password. The account already holds 60 days of sample data, so every screen has content without a watch or Health data on the review device. Sign in with Apple also works; a new Apple account starts with an empty calibration state.

Health access: after sign-in RYFT explains why it asks for Apple Health access before showing the system prompt. Denying access keeps the app usable with the demo account's server data.

Account deletion: Profile > Account > Delete account removes all data on our servers and the sign-in (including revoking Sign in with Apple).

Data export: Profile > Privacy > Export my data.

Medical: RYFT is not a medical device and makes no diagnostic claims; a disclaimer is shown in About and on Insights.

Push notifications are optional and only asked for after the first successful sync.
```

## 6. Review-relevant guidelines (check before every submission)

- **2.1 App completeness:** no placeholder content, no crashes, demo account works, all URLs load.
  **The public App Store build must not be invite-only:** turn `BETA_GATE` off (or to `warn`) for the
  release, or Apple will reject an app ordinary users can't get into. TestFlight may stay gated.
- **2.3 Accurate metadata:** screenshots show the real app; no claims for unshipped features; no other app or
  brand names in keywords; name ≤ 30.
- **2.5.1 / HealthKit:** HealthKit use is stated in the description ("Works with Apple Health") and visible in
  the UI; Health data is not used for advertising or data mining and not stored in iCloud (5.1.3).
- **1.4.1 Physical harm:** wellness framing, no medical accuracy claims, disclaimer present.
- **4.8 Login services:** Sign in with Apple offered alongside email (done).
- **5.1.1 Privacy:** privacy policy linked in the app and in App Store Connect; consent before processing;
  account deletion in-app (done); purpose strings explain each permission.
- **5.1.3 Health data:** explicit consent, no sharing with third parties for ads, accurate App Privacy label.
- **Export compliance:** `ITSAppUsesNonExemptEncryption = NO` (only standard HTTPS) — already set.

## 7. Before you press "Submit for Review"

- [ ] Privacy policy, terms, support and Impressum published on ryftapp.de (no draft banner).
- [ ] Trader status declared; age rating questionnaire done.
- [ ] Demo account seeded and tested on a clean device; gates passable.
- [ ] Screenshots uploaded for en and de (6.9").
- [ ] App Privacy answers match `PrivacyInfo.xcprivacy`.
- [ ] Build from `release.yml`, processed, attached to version 1.0.0; release type "manually release";
      phased release on.
- [ ] `BETA_GATE` plan for launch day decided.

Sources: Apple, App Store Connect Help — Platform version information; App Review information; Product page;
Age rating update (Jul 2025); App Store Review Guidelines.
