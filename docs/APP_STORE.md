# App Store readiness — RYFT iOS

Audit: **2026-10-19** with **Xcode 27.1 (27A9275)** and the iOS 27.1 SDK. Sources:

- the App Review Guidelines
- developer.apple.com → Upcoming requirements
- the BundleResources privacy-manifest documentation (TN3181, TN3183, TN3184)
- HealthKit → Protecting user privacy
- App Store Connect → Accessibility Nutrition Labels

All were checked on the audit date, not from memory.

Status: **ok** = meets the requirement, **fix** = changed by the app in this pass,
**user** = only the account holder can do it (App Store Connect, Apple Developer,
Supabase, website).

## Current Apple requirements that apply

| Requirement | Since |
| --- | --- |
| Uploads must be built with **Xcode 26 or later** and an iOS 26 SDK | 2026-04-28 |
| Apps must target **iOS 13 or later** | 2026-09-09 |
| Approved reasons for required-reason APIs in the privacy manifest | 2024-05-01 |
| Answers to the **updated age-rating questions** | 2026-01-31 |
| EU **DSA trader status**, or the app isn't offered in the EU | 2025-02-17 |
| Accessibility Nutrition Labels: voluntary now, "mandatory eventually". Claim a feature only if *all* common tasks (first launch, login, primary features, settings) work with it | iOS 26 |

## 1. Privacy and data

| Requirement (guideline) | Status | Evidence |
| --- | --- | --- |
| Privacy manifest in the app target. `NSPrivacyTracking = false`, no tracking domains (5.1.2) | fix | `Ryft/PrivacyInfo.xcprivacy` |
| Collected data types, each linked to the user, not used for tracking, purpose App Functionality (5.1.1): Health, Fitness, Email Address, Name, User ID, **Device ID** (the per-install `device_id` sent with every sync), **Other User Content** (workout notes). No crash or diagnostics SDK | fix | `PrivacyInfo.xcprivacy` → `NSPrivacyCollectedDataTypes` |
| Required-reason APIs. App code uses only `UserDefaults` (`CA92.1`). No file timestamps, boot time, disk space or keyboards | fix | grep of `Ryft/`, `RyftWidgets/` |
| Packages. swift-crypto ships its own manifests. supabase-swift, swift-http-types, swift-clocks, swift-concurrency-extras, xctest-dynamic-overlay and swift-asn1 call no required-reason API, so they need none. The session is in the Keychain, not `UserDefaults`. Apple frameworks (SwiftData, HealthKit) are exempt | ok | grep of `SourcePackages/checkouts/*/Sources` |
| Xcode **Generate Privacy Report** on an archive lists exactly the declared types | user | Organizer → Archives → Generate Privacy Report (needs the signed archive) |
| `NSHealthShareUsageDescription` names the data and the purpose, and says no advertising (5.1.1(ii), 5.1.3(i)) | fix | `Info.plist`, `InfoPlist.xcstrings` (en, de) |
| `NSHealthUpdateUsageDescription` only if the app writes: it doesn't, so removed | fix | `Info.plist`; `requestAuthorization(toShare: [])` |
| No health data in iCloud, no `NSUbiquitous*`, no iCloud entitlement (5.1.3(ii)) | ok | `Ryft.entitlements`. The SwiftData store is local; ResponseCache is in Caches/ |
| HealthKit data never used for ads or marketing, never sold, only sent to the user's own RYFT account (5.1.2(vi), 5.1.3(i)) | ok | No ad or analytics SDK; `APIClient` talks only to `api.ryftapp.de` |
| Health permission requested in context. An explanation screen comes first, after sign-in, never on cold launch (5.1.1(iv), HIG HealthKit) | fix | `Features/Onboarding/HealthPermissionView.swift`; `RyftApp.bootstrap` |
| App fully usable when Health access is denied. Calm empty state with a way to the Health permissions (5.1.1(iv)) | fix | `HealthAccessHint` on Today, Sleep and Strain |
| Processors for the privacy policy: health data is processed by RYFT's own servers on AWS (eu-central-1) and by Supabase (EU) for authentication | user | privacy policy text (below) |
| Privacy policy linked in the app (5.1.1(i)): Profile → About, Welcome, Create account | fix | `ProfileView.about`, `WelcomeView`, `CreateAccountView` (in-app Safari) |
| Terms of Use in Profile → About | fix | same |
| Account deletion in the app, without contacting support (5.1.1(v)). Profile tab → **Delete account** → confirm (2 taps). Calls `DELETE /v1/me`; the platform revokes Apple with the code from `POST /v1/me/apple-authorization` | ok | `ProfileView.account`, `AuthService.deleteAccount`, `sendAppleAuthorization` |
| Export my data (GDPR art. 20; not an Apple rule): JSON of `/v1/me`, `/v1/days`, `/v1/workouts`, `/v1/sessions` via the share sheet | fix | `Features/Profile/DataExport.swift` |
| Sign in with Apple wherever email sign-in is offered (4.8: an equivalent privacy-preserving login) | ok | `WelcomeView` |
| Hide My Email relay addresses work: the email is shown, never required to be real. The name is taken only on the first authorisation. Only `.fullName, .email` are requested | ok | `AuthService.prepare`, `signInWithApple` |
| Email accounts: password reset, no lock-in | ok | `ForgotPasswordView`, `SetNewPasswordView` |
| No tracking, no ATT, no `NSUserTrackingUsageDescription`, no fingerprinting SDK | ok | `Info.plist`, package list |

## 2. Health claims and content

| Requirement (guideline) | Status | Evidence |
| --- | --- | --- |
| Wellness, not medical (1.4.1). No "diagnose", "detect", "treat", "illness" or "disease" in any string; insights read as observations | ok | grep of `Localizable.xcstrings`, `Features/`. Insight text comes from the platform (`SCORING.md`) |
| Disclaimer "RYFT is a wellness tool, not a medical device. Talk to a doctor about health concerns." in About and on Insights (1.4.1: remind users to check with a doctor) | fix | `ProfileView.about`, `InsightsView` |
| Scores are never called medically validated | ok | Copy in `ReadinessCopy`, `InsightsView` |
| Future "Healthspan / RYFT Age": the same wording review before it ships. No age-equivalent claim without a published methodology (1.4.1) | user | roadmap note |
| SpO₂ is shown from Apple Health (written by Garmin), not measured by the phone's sensors (1.4.1 example) | ok | `SampleType.spo2` |
| No placeholder, lorem ipsum, "beta", "coming soon" or broken features in Release (2.1(a)) | ok | grep. Every Train endpoint is served (`API.md` → Train) |
| Demo data toggle in Release: labelled "Demo data", shows a realistic sample history, never mixed with an account's data | ok | Profile → Data |

## 3. Build and project hygiene

| Requirement (guideline) | Status | Evidence |
| --- | --- | --- |
| Built with Xcode 26+ / iOS 26 SDK | ok | Xcode 27.1, iOS 27.1 SDK |
| Deployment target iOS 17 (≥ 13 required) | ok | `IPHONEOS_DEPLOYMENT_TARGET = 17.0` (app, widget, tests) |
| Release: no Developer section, no API key mode, no token / body / health-value logging; OSLog with privacy annotations | ok | `#if DEBUG` in `Settings`, `ProfileView`, `AuthService.staticBearer`. Logs carry only method, path, status and request ID, all `.public` |
| `-O`, dSYMs, Release strip | ok | Release: `SWIFT_OPTIMIZATION_LEVEL = -O`, `DEBUG_INFORMATION_FORMAT = dwarf-with-dsym` |
| `ITSAppUsesNonExemptEncryption = NO`: HTTPS (system TLS) only. SHA-256 is used for the Apple sign-in nonce and nothing is encrypted by the app, which is exempt | fix | `Info.plist` |
| App icon: one 1024 px asset, no alpha, dark and tinted variants | ok | `AppIcon.appiconset` (`sips`: `hasAlpha: no`) |
| Launch screen matches Welcome (Graphite) | fix | `UILaunchScreen.UIColorName = Graphite` |
| iPhone only (`TARGETED_DEVICE_FAMILY = 1`), portrait only. On iPad an iPhone-only app runs in compatibility mode, which has no orientation or multitasking requirements, so `UIRequiresFullScreen` doesn't apply | ok / user | build settings. Run once on an iPad (user) |
| Not offered on Mac (Designed for iPhone) or Vision Pro. HealthKit is missing there, and the app would be useless | fix | `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`, `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD = NO` |
| Background modes only for what's used: `fetch` (BGAppRefreshTask). `processing` is unused, so removed. HealthKit background delivery is an entitlement (2.5.4) | fix | `Info.plist` → `UIBackgroundModes` |
| Live Activities: Train ships in 1.0 (`API.md` → Train), so `NSSupportsLiveActivities` stays | ok | `Info.plist`, `RyftWidgetsExtension` |
| Capabilities: HealthKit (+ background delivery), Sign in with Apple, Associated Domains `applinks:ryftapp.de`. No Push until M7, no iCloud | fix | `Ryft.entitlements`. The app accepts `https://ryftapp.de/auth/callback`; `ryft://auth/callback` stays the redirect until the AASA file is live |
| App ID capabilities match the entitlements (app + `dev.timkrebs.ryft.RyftWidgets`) | user | Apple Developer → Identifiers (paid team) |
| Version `1.0.0`; the build number increases on every archive | fix | `MARKETING_VERSION = 1.0.0` (app + widget); `make archive` sets `CURRENT_PROJECT_VERSION` to `yyyyMMddHHmm` |
| `make archive` → `xcodebuild archive` + `-exportArchive` (app-store-connect, upload symbols) | fix | `Makefile`, `scripts/ExportOptions.plist` |
| Third-party licences screen (About → Licences) | fix | `Features/Profile/LicensesView.swift` |
| Satoshi licence: ITF Free Font License, which allows embedding in apps. It can't be committed to the repo, so archives check the fonts are present (otherwise SF Pro Rounded, said in the log) | ok / user | `make archive` font check. Confirm the FFL version at fontshare.com (user) |

## 4. Accessibility and HIG

| Requirement | Status | Evidence |
| --- | --- | --- |
| Tap targets ≥ 44 pt. Segmented pickers and filter chips were 36 pt, and the inline-message buttons were text-sized | fix | `SegmentedPicker`, `FilterChip`, `InlineMessage` |
| VoiceOver labels and values on rings, tiles, stage bars and set rows | ok | `ScoreRing`, `MetricTile`, `StageBar`, `SetRow` |
| Swift Charts: `accessibilityChartDescriptor` (Audio Graphs) on trends, e1RM and the workout heart rate | fix | `TrendChart`, `E1RMChart`, `WorkoutDetailView` |
| Colour never the only carrier of meaning: the recovery band gets a word ("High", "Moderate", "Low") | fix | `MetricTile` caption on Today |
| Text contrast ≥ 4.5:1 in both appearances. Before the fix: `TextTertiary` 2.7 (light) / 3.3 (dark); in light mode Accent 2.8, Warning 2.6, Alert 3.9 and AccentSecondary 3.5 | fix | Asset-catalog colours; white labels on teal in light mode (`OnAccent`) |
| Dynamic Type: text styles everywhere; rings keep fixed sizes, and text never clips | ok | `Typography.swift` (`relativeTo:`) |
| Reduce Motion: rings, counters, the pulsing dot and the summary celebration | ok | `accessibilityReduceMotion` checks |
| Standard navigation: tab bar, system back, pull to refresh, system share sheet | ok | `RootView`, `ScreenScaffold`, Export |
| Accessibility Nutrition Label answers | — | see below |

### Accessibility Nutrition Label (to enter in App Store Connect)

| Feature | Answer | Why |
| --- | --- | --- |
| VoiceOver | Yes | Every screen, including login and the live session, works with labels, values and actions; charts have audio graphs |
| Voice Control | Yes | All controls are standard buttons with visible or accessibility labels |
| Larger Text | Yes | Text styles scale up to AX sizes; rings cap their numbers but the same values appear as text |
| Dark Interface | Yes | Dark is the default; Welcome is always dark |
| Differentiate Without Color Alone | Yes | Bands, zones, sleep stages and severity have words or icons next to the colour |
| Sufficient Contrast | Yes | ≥ 4.5:1 for text after this pass (both appearances) |
| Reduced Motion | Yes | Animations off or instant under Reduce Motion |
| Captions / Audio Descriptions | Not applicable | No video or audio content |

## 5. Reliability

| Requirement (guideline) | Status | Evidence |
| --- | --- | --- |
| Usable with zero HealthKit samples: calibrating copy, empty states, no spinners that never stop, no error on first launch (2.1) | ok / fix | `HealthAccessHint`; `ReadinessCopy` calibrating; the unscored-day fixture |
| Reviewer demo account with 30 days of synthetic data. Credentials only in the App Review notes | user | `make smoke-supabase` seeding in `../plattform` |
| Network failure, 503 and offline: no crash | ok | `APIClient` status tests, `ConnectivityMonitor` |
| Sign-out during a sync doesn't crash: `token()` throws `.signedOut` and the sync stops with a message | ok | `SyncService.run`, `AuthService.token` |
| Memory: 90-day first sync, pages ≤ 20 000 samples. Record the Instruments peak | user | `HealthKitManager.pageSize = 20_000`; needs a device |
| Pre-submission UI smoke: Welcome → Log in (demo account) → each tab → Profile → Delete account → Cancel | fix | `RyftUITests/StoreSmokeUITests.swift` |
| Network Link Conditioner run (3G, 100 % loss) | user | device |

## 6. App Store Connect, TestFlight, submission (user)

1. **Paid Apple Developer Program team.** Switch `DEVELOPMENT_TEAM` in Xcode, then create
   these identifiers with matching capabilities:
   - App ID `dev.timkrebs.ryft`: HealthKit, Sign in with Apple, Associated Domains
   - App ID `dev.timkrebs.ryft.RyftWidgets`
2. **App record.**
   - Name **RYFT**
   - Subtitle, e.g. "Recovery, sleep & strain"
   - Primary category **Health & Fitness**; SKU; bundle ID `dev.timkrebs.ryft`
3. **Age rating.** Answer the updated questionnaire: "Medical or Treatment Information:
   None", no unrestricted web access (the in-app Safari only opens our own legal pages),
   no user-generated content shared with others. **Made for Kids: No.**
4. **App Privacy.** Answer exactly as `PrivacyInfo.xcprivacy`:
   - Health, Fitness, Email Address, Name, User ID, Device ID, Other User Content
   - all *linked to the user*, *not used for tracking*, purpose *App Functionality*
   - no third-party advertising, no analytics
5. **URLs.**
   - Privacy Policy `https://ryftapp.de/privacy`
   - Support `https://ryftapp.de/support`, with a contact email
   - Marketing `https://ryftapp.de`
6. **Privacy policy contents.** It must cover:
   - what is collected (the types above, and what comes from Apple Health) and why
   - processors: AWS eu-central-1 hosts the RYFT platform; Supabase (EU) handles sign-in
   - retention, and deletion: in the app via Delete account, which also revokes Sign in
     with Apple
   - GDPR rights (access, export via Export my data, rectification, erasure,
     objection) and the right to complain to a supervisory authority
   - contact
   - that RYFT is not a medical device
   - that Health data is never used for advertising or sold
7. **Terms of Use** at `https://ryftapp.de/terms`, with the same not-a-medical-device
   sentence.
8. **Universal links.** Serve
   `https://ryftapp.de/.well-known/apple-app-site-association` with `applinks` for
   `<TEAMID>.dev.timkrebs.ryft` on `/auth/*`. Then add `https://ryftapp.de/auth/callback`
   to Supabase's redirect URLs and switch `SupabaseConfig.redirectURL`. `ryft://` stays as
   the fallback.
9. **Screenshots.** 6.9" and 6.5", dark theme, English and German, generated from the demo
   account (`scripts/screenshots.sh`). Show the app in use, not the login (2.3.3).
   Promotional text, keywords, description: say that it integrates with Apple Health (2.5.1).
10. **App Review notes.**
    - the demo account email and password
    - "RYFT reads heart rate, HRV, resting HR, respiratory rate, SpO₂, VO₂ max, active
      energy, steps, sleep and workouts from Apple Health (written there by Garmin
      Connect). It computes recovery, strain and sleep scores in the user's RYFT account.
      HealthKit background delivery keeps the scores current after a night's sleep or a
      workout without opening the app."
    - that the demo account already has 30 days of data, because a review device has no
      Garmin history
11. **Export compliance.** `ITSAppUsesNonExemptEncryption = NO` is set, so no
    questionnaire per build.
12. **EU.** DSA trader status in App Store Connect → Business.
13. **TestFlight.** An internal group first, then an external group (beta review), with
    the same review notes.
14. **Accessibility Nutrition Labels.** Enter the answers from §4.
15. **Before submitting.**
    - archive with `make archive`
    - Organizer → Generate Privacy Report: must list exactly the §1 types
    - run the `StoreSmokeUITests` with the demo account
    - one run on an iPad (compatibility mode)
