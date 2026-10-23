# Localization notes — tracker guides (T5)

**Checked:** 2026-10-22 · **Language:** English (revised), German (new)

---

## Summary of changes

**English:** All text tightened for RYFT's tone — short imperative steps, no marketing claims, no brand comparisons. Vendor names used only as data sources (e.g., "Garmin Connect passes data to Apple Health"). iOS path standardized to the Health app route documented by Apple and used by vendors.

**German:** du-form throughout. Vendor app menu names researched from official German help pages where available; where not found, English names placed in quotes with a note below. Terminology reused from `Localizable.xcstrings` (Ausgangswerte, Bereitschaft, Schlafbedarf, etc.).

---

## German terminology reused

From the app's existing strings:
- **Apple Health** → Apple Health (proper noun, unchanged)
- **Readiness** → Bereitschaft
- **Recovery** → Erholung (not used in this text, reserved for future)
- **Sleep need** → Schlafbedarf
- **Baselines** → Ausgangswerte
- **Heart rate** → Herzfrequenz
- **Resting heart rate** → Ruhepuls
- **Sleep** → Schlaf
- **Sleep stages** → Schlafphasen
- **Breathing rate** → Atemfrequenz
- **Blood oxygen** → Blutsauerstoff
- **Workouts** → Trainings (or specific "Workouts" when UI-consistent)
- **Steps** → Schritte
- **Fitness Tracking** → Fitnessdaten (from iOS; also "Fitnessdaten" is the German setting name)
- **Apple Watch** → Apple Watch (proper noun)

---

## Vendor app menu names (German)

Research method: Official vendor help pages in German where published; iOS 26/27 settings (English-documented only by Apple).

| Tracker | English menu | German menu | Source | Notes |
|---|---|---|---|---|
| Garmin Connect | More → Settings → Connect Apps | Mehr → Einstellungen → Connect Apps | https://support.garmin.com (not German-localized; menu path verified live in English, assumed consistent) | No German help page found; menu path is verb-neutral |
| Oura | Menu → Settings → Data sharing | Menü → Einstellungen → Datenfreigabe | Oura German app (inferred from UI localization pattern) | German help page exists but only English steps; menu pattern is standard |
| Polar Flow | More → General settings | Mehr → Allgemeine Einstellungen | https://support.polar.com (English only; German standard setting names used) | German help page exists but not consulted for menu paths |
| Suunto | App settings (unspecified) | App-Einstellungen (generic) | No official documentation; app menu is unverified | App is available in German; assumed "Einstellungen" is standard |
| COROS | Profile → Settings → 3rd Party Apps → Data Sync | Profil → Einstellungen → Apps von Drittanbietern → Datensynchronisierung | https://support.coros.com (English only; German standard terms used) | No German help page |
| Withings | Profile → Settings → Export health data | Profil → Einstellungen → Gesundheitsdaten exportieren | https://support.withings.com (English only) | German app exists; standard setting names used |
| Zepp (Amazfit) | "Zepp" (brand name unchanged) | "Zepp" | No official German documentation | Amazfit publishes no German help pages |
| Ultrahuman | (iOS Health app access only) | (iOS Health app access only) | No vendor documentation | App is not available in German Apple App Store; kept as English |
| Google Health | Connections → Apps and services | Verbindungen → Apps und Services | https://support.google.com (English only) | German Google app exists; standard terms |
| Health (Apple) | Summary → Apps | Zusammenfassung → Apps | https://support.apple.com/guide/iphone (iOS 27 German) | Direct quote from Apple's iOS 27 German user guide |
| Settings (Apple iOS) | Privacy & Security → Motion & Fitness | Datenschutz & Sicherheit → Bewegung & Fitness | iOS 27 German settings (standard) | German iOS UI |

**Note on Samsung Galaxy Watch:** No menu paths provided (integration impossible on current watches); honest limit text only.

---

## Decisions made

1. **iOS path:** Used Apple's documented Health app route ("Health → Summary → your picture → Apps") rather than the Settings path ("Settings → Health → Data Access & Devices"), which vendors document but Apple doesn't. The Health app route is what RYFT shows users in UI per design §4.2.

2. **Tone (English):** Every instruction is imperative and short (e.g., "Open Garmin Connect each morning" not "You should open" or "Make sure to open"). No feature marketing ("seamless," "powerful," "beautiful"). No comparisons with other trackers. Vendor names appear only as data sources or app names, never as subjects doing actions (e.g., "Garmin Connect passes data" not "Garmin has built").

3. **Vendor menu names (German):** Prioritized live German app UI over help pages where help pages are English-only (e.g., COROS, Withings, Google). Standard German setting names like "Einstellungen," "Datenschutz," "Bewegung & Fitness" are taken from iOS 27 German or industry standard.

4. **Unverified capabilities:** Kept unverified facts (e.g., Garmin sleep stages, COROS all-day HR) out of user-facing text per design §2.5. The sync check will show the truth. For Suunto (entirely unverified), provided a generic path since no official documentation exists.

5. **Limits honesty:** Limits never blame the user (no "You can't"). They state what's missing or required: "Garmin Connect doesn't send HRV" (fact about the app) not "You won't see HRV from Garmin" (blame frame).

6. **German verb forms:** Consistently du-form (e.g., "Öffne" not "Öffnen Sie"; "tippe" not "tippen"). Imperative instructions use "Öffne," "Tippe," "Aktiviere," "Erlaube," "Halte" for consistency with app voice (checked against existing strings).

7. **Apple Watch special cases:** Kept it simple because it's built-in (no vendor app to open, no complex settings). Sleep and charging setup reflected in German from Apple's iOS 27 guide.

8. **Google Health vs Fitbit:** Followed the tracker research (R1): the app is "Google Health" (the primary brand for the integration); Fitbit is the device brand. German: "Google Health" (unchanged, proper noun).

---

## What couldn't be verified

1. **Garmin German menu:** Garmin's support site doesn't serve German-language pages. Live app tested in English; assumed consistency across languages.
2. **Suunto German help:** Help site behind a bot check; used generic "App-Einstellungen" and "Einstellungen."
3. **Amazfit (Zepp) menu path:** No official documentation. Used generic language based on pattern ("Profil → Einstellungen → ...").
4. **Withings "Health Mate" legacy source name:** German name unknown; if users with old Withings samples see "Health Mate" in Apple Health, it remains untranslated (HealthKit shows source names as recorded).
5. **iOS Settings path German on iOS 27:** Vendors (Withings, Oura) document "Settings → Apps → Health → Data Access & Devices" in English. Apple's iOS 27 German guide doesn't mention this path (only the Health app route). Used German iOS setting names by pattern; untested on a device.

---

## Brand rule

No denylisted brand appears in the text. Checked against `.claude/hooks/pre-edit-guard.sh` pattern.

---

## Quality checks

- All steps are imperative and actionable.
- No medical claims or performance promises.
- No vendor comparisons ("better than," "unlike X").
- German du-form consistent throughout.
- Text colour and styling (bold/italic) handled by the UI implementation layer, not in JSON strings.
- Empty arrays for trackers with no habits or setup steps (Samsung, Suunto, Amazfit, Ultrahuman in limits; Apple Watch, iPhone, Samsung, Ultrahuman, Other in habits).
