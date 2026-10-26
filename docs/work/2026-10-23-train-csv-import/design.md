# Training import from CSV: design note (I1)

Ticket I1 of `plan.md`, by ios-architect, 2026-10-23. Requirements: `brief.md`; platform half: `platform-brief.md`;
screens: `ui.md` (in parallel). ADR 0007 holds what outlives this feature. Every format example here is **synthetic**.
Nothing from `local-samples/` is quoted.

## 0. What the files and the code say

| Source | Fact |
| --- | --- |
| Samples | UTF-8 with a BOM, CRLF, a final empty line. Every exercise block has a `#;KG;REPS` header, and set numbers restart per exercise. There are `-;-` rows, including an exercise whose every set is `-`. `+N` appears only on bodyweight-style exercises, with the same N on every set. 12 h times; `N min` and `h:mm hr`. Names can contain `-`. |
| `API.md` → Train (`origin/main`) | `load_type: bodyweight`: `weight_kg` is the *added* load, `Session.bodyweight_kg` the body weight. `completed_at: null` = planned, not done. `POST /v1/exercises` with the same id updates. `PUT /v1/plans/{id}` creates or replaces. `…/enroll` always starts at week 1, day 0. Other bodies ≤ 64 KiB. Rate limit: bursts of 60, then 10/s. |
| App | `TrainStore` is one main-context SwiftData container, wiped on sign-out (`TrainStore.swift:167`). `TrainSyncService` is a per-session op outbox. `PlanValidation` refuses `kg` without a value (`:69`). The app's bodyweight sets send `weight_kg: null`. Health saves happen only in `TrainCoordinator.save` (`:504`). `Info.plist` is a plain source file. |

## 1. Module layout and ownership

Pipeline: file → memory → `TrainImportReader` (`@concurrent`: detect, parse) → `ImportBundle` → `ExerciseMatcher` +
review → `ImportBuilder` (`@concurrent`: ids, prefill, duplicates) → Import tapped → `PendingImport` (SwiftData, per
account) → `TrainImportUploader` → platform.

```
Ryft/Train/Import/                    domain, no views
  Model/ImportBundle.swift  Formats/TrainImportFormat.swift  AlphaProgressionFormat.swift  AlphaProgressionTokens.swift  I2
  Parsing/LineReader.swift  CSVFields.swift  ImportScanners.swift                                    I2
  Mapping/ExerciseNormalizer.swift  ExerciseAliases.swift  ExerciseMatcher.swift  ImportMappingStore.swift   I3
  Build/ImportIDs.swift  ImportTimeResolver.swift  ImportBuilder.swift  DuplicateDetector.swift     I5
  Upload/TrainImportAPI.swift  PendingImport.swift  TrainImportUploader.swift                       I5
  Access/ImportFileAccess.swift                                                                     I4
Ryft/Features/Train/Import/           I4  TrainImportFlowModel (@MainActor @Observable), step views (ui.md)
Ryft/Resources/exercise-aliases.json  I3      Ryft/Preview/MockTrainImport.swift  I4/I5 (fake API, DEBUG sample literal)
RyftTests/Import/   RyftTests/Fixtures/Import/*.csv (synthetic, I2)
```

**Shared files:** one owner per region, and everything else is a new file. A1 rewrites Strain's activity list; the
import only touches `TrainRoute`.

| File | Region | Ticket |
| --- | --- | --- |
| `Environment/Seams.swift` | `FeatureFlag.trainImport = "train.import"`, compiled default off | I4 |
| `Environment/PlatformAPI.swift` | `:6` `PlatformAPI: …, TrainImportAPI`; `MockPlatformAPI.importTraining` through `enter("importTraining")` | I5 |
| `Train/Model/TrainStore.swift` | `schema` `:14`, `wipe()` `:167`: `ImportMapping` (I3), `PendingImport` (I5) | I3, I5 |
| `Features/Train/Plans/PlansView.swift` | the "New plan" button `:74–79` becomes a menu (New plan · Import from file) behind the flag, plus the flow's sheet | I4 |
| `Features/Profile/ProfileView.swift` | `data`: "Import training data" after Export `:447–452`, behind the flag | I4 |
| `App/RyftApp.swift` | `.onOpenURL` `:193` (file URLs first); app active and reconnect: `trainImport.resume()`; `onChange(of: auth.accountID)` `:117`: `trainImport.accountChanged()` | I4, I5 |
| `App/ScreenModels.swift` · `Navigation/DeepLinkRouter.swift` | `let trainImport: TrainImportUploader` · `openImport(_ files:)`, `takeImportFiles()`, in memory while signed out | I5 · I4 |
| `Features/Train/History/TrainHistoryView.swift` · `Info.plist` | `TrainRoute.importFlow` `:191` + destination · §9 | I4 |
| `Sync/SyncCoordinator.swift` | the days-changed trigger, shared with A2's `.activitySaved(days:)` (§7) | I5 |
| `docs/ARCHITECTURE.md` | seam row, flag gate, §3 models | I6 |

## 2. Frozen types (I2 owns them; I3 and I5 build on them)

**Changes from the brief:** times are a wall-clock `LocalDateTime` with no zone (ids and DST need it, and the zone
can change without reparsing). The file's 1-based numbers stay 1-based (`dayNumber`, `weekNumber`). `ImportedLoad`
replaces `weightKg` + `bodyweightModifier`, so impossible pairs can't exist. `isSkipped` is computed.
`ImportWarning.kind` is an enum without file text, so warnings localise, log and test safely. `SourceLine` lets later
stages warn with a line number.

```swift
struct ImportFormatID: RawRepresentable, Hashable, Codable, Sendable { let rawValue: String
    static let alphaProgression = ImportFormatID(rawValue: "alpha_progression") }  // = platform `source`; never renamed
enum ImportConfidence: Int, Comparable, Sendable { case none, weak, strong }
struct LocalDate: Hashable, Comparable, Sendable { var year, month, day: Int; var key: String }            // YYYY-MM-DD
struct LocalDateTime: Hashable, Comparable, Sendable { var date: LocalDate; var hour, minute: Int; var key: String } // …THH:mm
struct SourceLine: Hashable, Sendable { let file: Int; let line: Int }      // index of the picked file; 1-based line
enum WeightUnit: String, Codable, Sendable { case kg, lb }

struct ImportBundle: Equatable, Sendable {
    var format: ImportFormatID; var plans: [ImportedPlan]; var sessions: [ImportedSession]   // file order
    var warnings: [ImportWarning]; var suppressedWarnings: Int; var lineCount: Int
    func merging(_ other: ImportBundle) -> ImportBundle   // same start key in two files: kept once, .duplicateInFiles
}
struct ImportedPlan: Equatable, Sendable { var name: String; var weeks: Int?; var startDate: LocalDate?
    var days: [ImportedDay]; var source: SourceLine }
struct ImportedDay: Equatable, Sendable { var number: Int; var name: String; var exercises: [ImportedPlanExercise] }
struct ImportedPlanExercise: Equatable, Sendable { var order: Int; var name: String; var equipment: String?
    var sets: Int; var targetReps: ClosedRange<Int>? }
struct ImportedSession: Equatable, Sendable {
    struct PlanRef: Equatable, Sendable { var planName: String; var dayNumber: Int; var weekNumber: Int? }
    var title: String; var plan: PlanRef? /* nil: standalone */; var start: LocalDateTime; var durationMinutes: Int?
    var exercises: [ImportedSessionExercise]; var source: SourceLine }
struct ImportedSessionExercise: Equatable, Sendable { var order: Int; var name: String; var equipment: String?
    var targetReps: ClosedRange<Int>?; var unit: WeightUnit? /* nil: no table header */; var sets: [ImportedSet] }
struct ImportedSet: Equatable, Sendable {
    var ordinal: Int; var load: ImportedLoad?; var reps: Int?   // ordinal: 0-based row, `-` rows count; nil load: "-"
    var isSkipped: Bool { (reps ?? 0) == 0 } }
enum ImportedLoad: Equatable, Sendable { case weight(kg: Double), plus(kg: Double), minus(kg: Double) }  // 60 · +60 · -20
struct ImportWarning: Equatable, Sendable {
    let at: SourceLine; let kind: Kind
    enum Kind: Equatable, Sendable {
        case unrecognisedLine, lineTooLong, invalidText, outsideBlock, missingTableHeader(assumed: WeightUnit)   // I2
        case unsupportedColumns, unreadableNumber, implausibleValue, unreadableDate, unreadableDuration
        case meridiemConflict, duplicateInFiles, limitReached
        case nonexistentLocalTime, repeatedLocalTime, durationAssumed, overPlatformLimit, assistedLoad          // I5
    }
    var message: LocalizedStringResource { get } }        // en + de; a line number, never file text
enum ImportError: Error, Equatable, Sendable { case tooLarge(bytes: Int), unsupportedEncoding, notRecognised, mixedFormats, empty }
struct ImportLimits: Sendable {                            // tests shrink them
    var maxFileBytes = 8 << 20, maxLineBytes = 4_096, maxSessions = 10_000, maxPlans = 50
    var maxExercisesPerBlock = 200, maxSetsPerExercise = 200, maxWarnings = 200
    static let standard = ImportLimits() }
protocol TrainImportFormat: Sendable {
    var id: ImportFormatID { get }
    var displayName: LocalizedStringResource { get }       // "Alpha Progression": a data source, named factually
    func detect(_ head: Data) -> ImportConfidence           // ≤ the first 64 KiB; pure; never throws
    func parse(_ data: Data, limits: ImportLimits) throws -> ImportBundle }  // pure, sync; ImportError | CancellationError
enum TrainImportFormats { static let all: [any TrainImportFormat] = [AlphaProgressionFormat()]
    static func best(for head: Data) -> (any TrainImportFormat, ImportConfidence)? }   // highest; ties: list order
struct ImportFile: Sendable { let name: String; let data: Data }   // name: shown in step 2 only, never stored or logged
enum TrainImportReader {                                   // the flow's one entry; MainThread.assertOff inside
    @concurrent static func read(_ files: [ImportFile], limits: ImportLimits = .standard) async throws -> ImportBundle }
```

**Later formats** (named, not built): apps such as Strong, Hevy and FitNotes export comma-separated files with a header
row and one row per set. They join as one family: a `HeaderRowCSV` reader (RFC 4180), a per-app `ColumnMap` (date,
workout, exercise, equipment, set order, weight and unit, reps, duration, RPE, notes) with a header signature for
`detect`, and one shared fold into `ImportBundle`; nothing after the bundle changes.

## 3. The parser (I2)

`LineReader` is a `Sequence` over `Data`; it never builds an array of lines or one big `String`. Each line goes through
`CSVFields`, a classifier, and a block state machine (`top` / `plan(day?)` / `session(exercise?, table?)`).
**Classification never depends on blank lines.**

| Line | Recognised by (tokens below) | Valid in |
| --- | --- | --- |
| plan header | 2 fields: text whose last ` · ` part is `N <weeks>`, then a date | anywhere (starts a plan) |
| plan day · plan exercise | 1 field `<day> N[ · name]` · 3 fields `N. name · equipment`, `N <sets>`, `N[-–N] <reps>` | plan · plan day |
| session header | 3 fields: title, date and time, duration. `name · <day> N · <week> W · plan` is a plan session, anchored on the first such run (names may contain ` · `); otherwise standalone (`title · <standalone>` or plain) | anywhere (starts a session) |
| session exercise | 1 field `N. name[ · equipment][ · N <reps>]`: the last part is reps if it matches, the one before is equipment, the rest the name | session |
| table header | `#;<unit>;<reps>`. Other columns: `.unsupportedColumns`; rows skipped up to the next exercise | session exercise |
| set row | `idx;load;reps`, a fast path with no regex. Without a header: the file's last unit, else kg, with `.missingTableHeader` | session exercise |
| anything else, or the wrong state | `.unrecognisedLine` / `.outsideBlock`; skipped | — |

Week-to-week changes aren't validated: each session stands alone as history, and the plan comes only from plan headers.

**Tokens** are a data table (`AlphaProgressionTokens.swift`): case-insensitive, with an optional space after the
number. ✓ = seen in the sample; German is a guess until a German export exists (Q1).

| Token | en | de |
| --- | --- | --- |
| day · week · plan length | `Day` ✓ · `Week` ✓ · `week(s)` ✓ | `Tag` · `Woche` · `Woche(n)` |
| sets · reps | `set(s)` ✓ · `rep(s)` ✓, header `REPS` ✓ | `Satz`, `Sätze` · `Wdh`, `Wdh.`, `Wiederholungen`, `WDH` |
| standalone | `Standalone workout` ✓ | `Einzelnes Training`, `Freies Training` |
| duration | `N min` ✓, `h:mm hr` ✓, `N hr`, `N hr M min` (`mins`, `hrs`, `h`) | `Min`, `Min.`, `Minuten`, `Std`, `Std.`, `Stunde(n)` |
| clock | `h:mm am/pm` ✓ (`a.m.`) and 24 h. 12 am = 0, 12 pm = 12. `15:28 pm` → 15:28 with `.meridiemConflict` | 24 h |
| date · unit | `YYYY-MM-DD` ✓ · `KG` ✓, `LBS`, `LB` | `DD.MM.YYYY` · same |

**Numbers.** The field separator is `;`, so a comma inside a field is always a decimal comma. The scanner accepts
`[0-9]`, one separator and at most 3 decimals, and builds the `Double` itself (`Double(String)` would accept `1e309`).
Pounds: × 0.45359237, rounded to 0.01 kg. `60` · `72.5` · `72,5` → `.weight`; `+60` → `.plus`; `-20` (a `-` followed by
a digit) → `.minus`; `-`, empty or `–` → `nil` (not done). `1.234,5`, `7e2`, `nan`, `inf`, non-ASCII digits or more
than 9 digits → `.unreadableNumber`; over 1 000 kg (after lb), 1 000 reps or 24 h → `.implausibleValue`. Both drop the
set.

**File hygiene:** a UTF-8 BOM is skipped; a UTF-16/32 BOM or NUL bytes in the head give `.unsupportedEncoding`. LF,
CRLF and a lone CR all end a line, and a last line without one is read. Invalid UTF-8 decodes lossily (`.invalidText`).
`"…"` may contain `;` and `""`; an unclosed quote takes the rest of the line, and quotes never span lines. Trailing
empty fields (a trailing `;`) are ignored and fields are trimmed; the inner separator is U+00B7 with spaces. Lines over
4 KiB are skipped without buffering (`.lineTooLong`).

**Detection** reads the first 64 KiB, cut at a line end. `.strong`: a `#;<unit>;<reps>` header, or a plan header
followed by a plan exercise. `.weak`: ≥ 2 quoted fields with ` · ` and a set-row-shaped line but no header (parsed;
step 2 says some lines weren't recognised). `.none` otherwise, and always for a comma-separated header row as the first
line (≥ 3 alphabetic fields, no `;`) → "not a file RYFT can read yet". Formats mixed across picked files:
`.mixedFormats`.

**Time zone and DST** (`ImportTimeResolver(zone:)`, I5, pure). The zone is `TimeZone.current`, captured when the flow
starts and named in the preview. A wall-clock time that doesn't exist (spring change) moves to the later valid instant
(`.nonexistentLocalTime`); one that occurs twice (autumn) takes the earlier (`.repeatedLocalTime`), via
`Calendar.nextDate(after:matching:matchingPolicy: .nextTimePreservingSmallerComponents, repeatedTimePolicy: .first,
direction: .forward)` from local midnight, not `date(from:)`'s defaults. `ended_at = started_at + duration` in absolute
seconds. Ids never use the resolved instant (§6).

**Never crash:** `Ryft/Train/Import/` has no `!`, `try!`, `fatalError`, `precondition` or unchecked subscript; integers
come from ≤ 9 digits; every loop advances at least a byte or a line; every collection stops at its `ImportLimits` cap
(`.limitReached`); cancellation is checked every 1 024 lines; only whole-file refusals throw.

**Size cap: files over 8 MiB are refused,** before reading (`fileSizeKey`) and while reading (stop at cap + 1 byte).
At under 1 KB per workout in the sample, 8 MiB is about 9 000 workouts. File and bundle stay well under 100 MB on old
devices, and anything larger is almost certainly not one export.

## 4. Mapping (I3)

**Normalisation** (`ExerciseNormalizer`): one function for source names, library names and aliases.

| Step | Rule |
| --- | --- |
| Text | NFKC; `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)`; `ß` → `ss` |
| Punctuation · stop words | `- / ( ) , . ' ’ & +` → space, collapsed · en `with the a an on of and`, de `mit am an der die das und im zum` |
| Synonyms | from the alias file (`db` → `dumbbell`, `ohp` → `overhead press`, …) |
| Plurals (en, per token) | `-sses` → `-ss`; `-ches`/`-shes`/`-xes` drop `es`; `-ies` → `-y` (length > 4); `-s` dropped unless `-ss`/`-us`/`-is`. German plurals go through aliases |
| Key | `SourceExerciseKey(name: sorted unique tokens without equipment words, equipment: normalised token or "")` |

**Aliases** (`Ryft/Resources/exercise-aliases.json`, en + de, read once off the main actor) are curated from common
exercise vocabulary, **never from `local-samples/`**; reviewers reject a list that looks like one person's plan. They
point at platform slugs (stable for built-ins; I3 puts in the real ones). Unknown slugs are ignored and counted. Tests:
shape, idempotent normalisation, no key with the same equipment pointing at two slugs.

```json
{ "version": 1,
  "equipment": { "barbell": ["barbell", "langhantel"], "ez_bar": ["ez bar", "sz stange"], "dumbbell": ["dumbbell", "kurzhantel"], "cable": ["cable", "kabelzug"], "machine": ["machine", "maschine", "smith machine"], "bodyweight": ["bodyweight", "korpergewicht"], "kettlebell": ["kettlebell"] },
  "kinds": { "barbell": ["barbell"], "ez_bar": ["barbell"], "dumbbell": ["dumbbell"], "cable": ["cable"], "machine": ["machine"], "bodyweight": ["bodyweight"], "kettlebell": ["kettlebell"] },
  "synonyms": { "db": "dumbbell", "ohp": "overhead press" },
  "aliases": [ { "slug": "goblet-squat", "equipment": "kettlebell", "names": ["goblet squats", "goblet kniebeuge"] } ] }
```

**Matching** (`ExerciseMatcher`, pure): the first tier that hits wins. **The equipment filter is hard:** a candidate's
`kind` must be in `kinds[equipment]`; unknown equipment means no filter and lower confidence. Ties break by score, then
custom before built-in, then name, then id. Up to three runners-up become `alternatives`.

| Tier | Rule | Confidence | Review |
| --- | --- | --- | --- |
| remembered | this account + source + key chose an exercise that's still in the library | 1.0 | ✓ |
| exact · alias | the same key name · the alias key and its equipment; the equipment filter passes | 1.0 · 0.95 | ✓ |
| fuzzy | token Dice `2∣A∩B∣/(∣A∣+∣B∣)` ≥ **0.5** among candidates that pass the filter | the score (× 0.8 without known equipment) | "check": **never accepted without a tap, at any score** |
| none | nothing ≥ 0.5 | 0 | "new" |

```swift
struct SourceExerciseKey: Hashable, Codable, Sendable { let name: String; let equipment: String }
struct ExerciseMatch: Equatable, Sendable { let key: SourceExerciseKey; let exerciseID: UUID?; let tier: Tier?
    let confidence: Double; let alternatives: [UUID]
    enum Tier: String, Codable, Sendable { case remembered, exact, alias, fuzzy }
    var needsReview: Bool { tier == .fuzzy || exerciseID == nil } }
struct ExerciseMatcher: Sendable { init(library: [Exercise], aliases: ExerciseAliases, remembered: [SourceExerciseKey: UUID])
    func match(name: String, equipment: String?) -> ExerciseMatch }
enum BodyweightAnswer: String, Codable, Sendable { case addedWeight, bodyWeight, ignore }
```

**Remembered choices:** `@Model ImportMapping` in `TrainStore` (`account`, `source`, `key`, `exerciseId`,
`bodyweightRaw?`, `updatedAt`; upserted by account, source and key). Written when Import is tapped, never per tap, so an
abandoned flow changes nothing. Read through `ImportMappingStore`, filtered on `env.auth.accountID`; wiped by
`TrainStore.wipe()` at sign-out (demo has its own in-memory store).

**Custom exercises** ("new") get a derived id (§6), so a retried flow updates the same one. `kind` comes from the
equipment (else `machine`); `load_type` is `bodyweight` for bodyweight equipment or `+N` sets, else `weight`; the name
is ≤ 80 characters; the user picks `primary_muscles`. They go up first, one `POST /v1/exercises` at a time.

## 5. Bodyweight `+N`

Asked **once per source exercise** that has `.plus` sets, and remembered. The default answer is "body weight" when N is
the same on every set and within 30–300 kg; otherwise "added weight".

| Matched `load_type` | Answer | Set | Session `bodyweight_kg` |
| --- | --- | --- | --- |
| `bodyweight` | added weight | `weight_kg = N` | unchanged |
| `bodyweight` | body weight (offered for 30 ≤ N ≤ 300) | `weight_kg = null`, as the app's own sets | `N`. With several different N in a session, the most common wins (ties: the first) |
| `bodyweight` | ignore | `weight_kg = null` | unchanged |
| `weight` | two answers: "N kg is the weight" (`addedWeight`) or ignore | `weight_kg = N` / `null` | unchanged |
| `time`, `distance` | not asked | the load is dropped, reps kept | — |

A `weight` match against `+N` happens only by the user's pick (the equipment filter keeps bodyweight sources on
bodyweight exercises); the mapping row then says the file logs it as bodyweight. `.minus` imports as reps only
(`.assistedLoad`). What doesn't fit: T3, T4, T11 (§13).

## 6. Ids and duplicates (I5; ADR 0007)

**UUIDv5:** CryptoKit SHA-1, version 5, RFC 9562 variant. The namespace is `aed18370-8351-4f38-9f14-af711a508076`
(`ImportIDs.namespace`, a `uuid_t` literal, so no force unwrap). Names are UTF-8 with fields joined by U+001F;
`src` = `ImportFormatID.rawValue`; keys are normalised as in §4.

| Id | Namespace | Name |
| --- | --- | --- |
| account | `namespace` | `account␟<accountID>` (Supabase user id, lowercased; `demo` in demo mode) |
| custom exercise · plan | account | `exercise␟src␟key.name␟key.equipment` · `plan␟src␟normalised plan name␟startDate.key or ""` |
| plan day · plan exercise | plan · plan day | `day␟<dayNumber>` · `exercise␟key.name␟key.equipment␟<occurrence of the key in the day>` |
| session | account | `session␟src␟start.key␟<occurrence of that start key, oldest first>` |
| session exercise · set | session · session exercise | `exercise␟key.name␟key.equipment␟<occurrence>` · `set␟<ordinal>` (`-` rows keep theirs) |

**Why:** no exercise order in any key, so a reorder changes `position`, not ids. The account is in every key, so two
accounts never collide (a `409` on plans). Wall-clock session keys, so importing again in another zone doesn't
duplicate. No title or duration, so a renamed day isn't a new session. A plan keeps its id while name and start date do.

**Existing ids are skipped by the app.** Before the preview it reads `GET /v1/plans` (`mine`), `GET /v1/sessions` over
the import's range (180-day chunks, as `DataExport`) and the library. A session whose derived id exists is "already
imported" and **not sent**: a re-import sends nothing, and a newer export only the new workouts (the platform's
idempotency still covers lost answers). An existing plan keeps RYFT's copy by default (it may have been edited), with
"Replace with the file's version" as an option.

**Duplicates** (`DuplicateDetector`, pure): against sessions that aren't imports (the server list minus derived ids,
plus `TrainStore.completedSessions()` not yet uploaded), the same local day of `start` in the import zone and
`∣I ∩ E∣ / max(∣I∣, ∣E∣)` ≥ 0.7 over distinct RYFT exercise ids with ≥ 1 performed set → "Looks like a session you
already logged", skipped by default (`max`: a short session logged in RYFT can't hide a longer import). Server sessions'
exercises come from `GET /v1/sessions/{id}`, only for days that have both. Offline at the preview: the job is saved
with `duplicatesChecked = false`, the uploader runs the same check before the first session batch, and the result
screen offers "Import these too".

**"Skip"** (duplicate, already imported, outside the range, or deselected): never sent, and nothing is written on the
server. The id is still derived, so "import anyway", now or later, stays idempotent.

## 7. Upload (I5; the live request after C2)

**The job** is a `@Model PendingImport` in `TrainStore` (`schema` + `wipe()`), at most one per account, created only
when Import is tapped (before that everything is in memory in the flow model, so plan.md's "survives an app restart"
applies from that tap). Deleted when nothing is `pending` and the result was seen, on Discard, after 30 days (purged
on app active), or at sign-out.

| Field | Content |
| --- | --- |
| `id` `account` `source` `createdAt` `timeZoneID` `duplicatesChecked` | |
| `payload` (`.externalStorage`) | `ImportUploadPlan` JSON (custom `Exercise`s, `Plan`s, `TrainSession`s oldest first, `enrolPlanID?`, skip counts). Built and encoded by `@concurrent ImportBuilder.build`, written once, decoded off the main actor on resume |
| `progress` | `[UUID: ItemState]` JSON (`pending`, `done(created/unchanged/updated)`, `rejected(reason, requestID)`, `blocked(by:)`, `attempts`), rewritten after each request |
| `sessionsPerRequest` | 50, halved after a `413` |

**Order:** custom exercises (one `POST /v1/exercises` at a time) → plans (≤ 5 per request, in the first requests) →
sessions, oldest first → `POST /v1/plans/{id}/enroll` if its plan is `done` (replacing an active enrolment was confirmed
in flow step 3). **Packing** is greedy: ≤ 50 sessions and a **measured** body ≤ 1 MiB − 16 KiB, encoded `@concurrent`
(`MainThread.assertOff`); the seam takes `Data`, like `sync(encoded:)`. A session too big alone gets
`.overPlatformLimit`. An item that refers to a rejected custom exercise is `blocked`; a session whose plan was rejected
or skipped is sent without `plan_day_id` / `plan_exercise_id`.

**Results.** One request at a time. Retry classes come from `TrainSyncService.isRetryable`.

| Answer | Items |
| --- | --- |
| 2xx `created` / `unchanged` / `updated` | `done` |
| 2xx `rejected` | `rejected(reason, request ID)`. Not retried automatically; listed on the result screen, where Retry sends them again |
| 2xx without the item in `results` | stays `pending`; after 3 such answers, `rejected(no answer)` |
| transport, 408, 5xx, 429, 401 after `APIClient`'s refresh, 403 with a gate | all stay `pending`. `Retry-After` (≤ 60 s, `env.clock`) is waited out only while the flow is open; otherwise the next trigger resumes |
| 413 · other 4xx for the whole request | halve `sessionsPerRequest` and resend · that request's items are `rejected` with the request ID, and the upload goes on |
| the stub before C2 (`notPublished`) | `pending`, shown as "not available yet" |

| Concern | Rule |
| --- | --- |
| Rate limits | imports run one at a time per user, a batch counts as one request, and the `POST`s go one by one, so bursts of 60 and 10/s are never reached |
| Triggers | Import, Retry, app active, reconnect, sign-in. A request in flight finishes under `beginBackgroundTask`; there is no `BGProcessingTask`. **Flag off** (the kill switch): nothing is sent and the job waits |
| Never another account | each request checks `job.account == env.auth.accountID`; a `Generation` (account counter + `TrainStore.epoch`, as in `TrainSyncService`) drops late answers; sign-out wipes the job |
| After the last session batch | `TrainLibrary.refresh()` and `invalidateHistories()`; the server's custom exercises go to `store.cache(exercises:)`; one `SyncCoordinator` run with the imported days (A2's `.activitySaved(days:)`, renamed `.daysChanged(days:)` by whichever PR lands second): it waits for scoring (T7), then makes one ranged read |

**The seam and the fake before C2.** The draft lives in `Upload/TrainImportAPI.swift`, **not** in `Models.swift`, so
the mirror check keeps matching API.md. C2 moves the reconciled shapes into `Models.swift`, adds
`APIClient+TrainImport.swift` and fixtures, and deletes the draft. Until then the live `APIClient` throws
`notPublished` and sends nothing. `MockTrainImportSource` (demo, previews, tests) upserts by id, answers `unchanged`
for identical content, fails on a script (`failNext`, `rejectIDs`) and lists imported sessions in `sessions(from:to:)`.
Demo's `remoteConfig` turns `train.import` on.

```swift
protocol TrainImportAPI {   /// POST /v1/train/import (draft until C2); `body` is an encoded TrainImportRequest
    func importTraining(encoded body: Data) async throws -> TrainImportResponse }
struct TrainImportRequest: Encodable, Sendable { let source: ImportFormatID; let plans: [Plan]; let sessions: [TrainSession] }
struct TrainImportResponse: Decodable, Sendable { let results: [TrainImportItemResult] }
struct TrainImportItemResult: Decodable, Sendable { let kind: Kind; let id: UUID; let status: Status; let reason: String?
    enum Kind: String, Decodable, Sendable { case plan, session, unknown }          // lenient
    enum Status: String, Decodable, Sendable { case created, unchanged, updated, rejected } }
struct ImportUploadPlan: Codable, Sendable { var exercises: [Exercise]; var plans: [Plan]; var sessions: [TrainSession]
    var enrolPlanID: UUID?; var skipped: ImportSkipCounts }
@MainActor @Observable final class TrainImportUploader {
    init(env: AppEnvironment, store: TrainStore, library: TrainLibrary, coordinator: SyncCoordinator?)
    private(set) var status: ImportJobStatus?      // counts per state, phase, last error and request ID
    func start(_ plan: ImportUploadPlan, source: ImportFormatID, zone: TimeZone, duplicatesChecked: Bool) async
    func resume() async; func retryRejected() async; func discard(); func accountChanged() }
```

**Why not `TrainSyncService`:** its queue is a debounced op per session (`PUT`, `…/complete`, `DELETE`, 409 merge) on
`LocalSession`, with the summary sheet and the Health save. The import is one job row, one batch endpoint and skipped
existing ids, and **never** touches `LocalSession`, the outbox or Apple Health. Shared: `isRetryable`, the `Generation`
pattern, the connectivity and app-active triggers.

## 8. Plan, enrolment, "last time" (I5 builder; preview in I4)

| RYFT field | From |
| --- | --- |
| `name` · `weeks` | the plan name (editable in step 5, ≤ 80) · `N weeks` when 1–52, else `nil` (repeats) |
| `days_per_week` | the number of days. Over 7: the plan can't be imported (the reason is shown); history still can |
| `goal` · `progression` | `.general` · `.linear`, as `Plan.blank()` (editable later in the builder) |
| `PlanDay` · `PlanExercise` | `week: nil`, `day_index = number − 1`, `name` · `position` = file order, `sets` (1–20), `reps_min…reps_max` from the target (1–100), `rest_sec = SessionFactory.defaultRest(for:)` |
| target, `weight` exercise | with history: `kg` = the **heaviest performed set of the most recent imported session with this exercise** (the same plan day first). Without history: `rpe` 8, the builder's default. `PlanValidation` refuses `kg` without a value, and RPE shows no weight, which is the brief's "leave empty" |
| target, bodyweight exercise | `bodyweight`, `target_value: null` (API.md; T11) |

**Sessions** (`TrainSession`, `status: completed`): `title` = the day or workout name (≤ 120); `started_at` from the
resolver; `ended_at = started_at + duration`, or + 60 min with `.durationAssumed` when the file has none. Skipped sets
aren't sent (counted only, T2). The k-th of n performed sets (in exercise, then row order) gets `completed_at = start +
duration × (k+1)/n`, whole seconds, and `updated_at = completed_at`, so a re-send is identical (T10). `is_warmup` is
false; `rpe`, `notes` and `device_id` are empty. Over 50 exercises or 50 sets per exercise (the platform's limits),
the rest is dropped with `.overPlatformLimit`. Imported sessions never enter `LocalSession`, so no Health save.

Every built plan must pass `PlanValidation.issues(in:)`, otherwise its toggle is off with the reason. A session that
names a plan in the file gets `plan_day_id`, and `plan_exercise_id` by key and occurrence (several plans of that name:
the one whose start ≤ the session date < start + weeks), so the platform's `last_time` and `target_kg` work from the
imported history. "Make this my active plan" enrols at week 1, day 0; "from the file's start date" and "continue where I
am" need T8 and stay hidden until then.

## 9. "Open in" and file access (I4)

**`Info.plist`: add exactly these keys.** No capability, entitlement or build setting is needed. The PR edits the
file (it's a source file); the user checks it (§14).

```xml
<key>CFBundleDocumentTypes</key>
<array><dict>
  <key>CFBundleTypeName</key><string>CSV document</string>
  <key>CFBundleTypeRole</key><string>Viewer</string>
  <key>LSHandlerRank</key><string>Alternate</string>
  <key>LSItemContentTypes</key><array><string>public.comma-separated-values-text</string></array>
</dict></array>
<key>LSSupportsOpeningDocumentsInPlace</key><true/>
```

**Opening in place (YES):** Files hands over the original as a security-scoped URL instead of a copy in the backed-up
`Documents/Inbox`; without the key Xcode warns. **`Alternate`:** RYFT never claims to be the default CSV app. **CSV
only:** declaring plain text would put RYFT on every `.txt`; `.fileImporter` still takes `[.commaSeparatedText,
.plainText]`, multi-select. **Not added:** `UTImportedTypeDeclarations` (system type), `UIFileSharingEnabled`,
`UISupportsDocumentBrowser`.

**Reading** (`ImportFileAccess.load(_ urls:limits:)`, `@concurrent`), per URL: `startAccessingSecurityScopedResource()`
(stop in `defer`) → refuse if `fileSizeKey` is over the cap → coordinated read (`NSFileCoordinator`, `.withoutChanges`;
downloads from iCloud) through `FileHandle`, at most cap + 1 bytes, **into memory** → delete the URL if it is inside our
container (an Inbox or `tmp` copy, e.g. from Mail). Never `write(to:)`, SwiftData, UserDefaults or state restoration for
the bytes; no file timestamps (they would need a Required Reason entry in `PrivacyInfo.xcprivacy`).

**Routing:** `.onOpenURL` checks `url.isFileURL` first. Flag off: a calm sheet ("not available on this account yet"),
nothing read. Flag on: load → `router.openImport(files)` opens Strain with `.importFlow` → the flow calls
`router.takeImportFiles()`. Signed out: the files wait in memory until sign-in, like `pending` links, and die with the
process. `TrainRoute` stays `Hashable`; bytes never travel through navigation.

## 10. Privacy and logging

| Data | Where | How long | Deleted by |
| --- | --- | --- | --- |
| The file · the bundle, matches and answers | memory (flow model, router) | until the flow ends · until Import or Cancel | the flow or process ending; Inbox copies at once |
| Upload job (exercise ids, plan, titles, times, weights, reps) | SwiftData `PendingImport`, per account | until done and seen; at most 30 days | completion, Discard, the purge, sign-out |
| Remembered choices (normalised source name and equipment → exercise id, bodyweight answer) | SwiftData `ImportMapping`, per account | until sign-out or account deletion | `TrainStore.wipe` |
| Imported plans, sessions, custom exercises | the platform | the account's life | the user, `DELETE /v1/me` |

**Logs and diagnostics** (`Logger` category `import`) contain only counts, warning kinds, item states, durations and
request IDs (`.public`), never names, dates, weights or line text; line text appears only on screen in the flow, read
from memory. **Export:** `DataExport` already includes `/v1/sessions`, so imported sessions are exported (labelled once
T1 lands). Plans and custom exercises aren't exported today, imported or not (an older gap); remembered choices aren't
(Q4).

## 11. Tests (brief §5)

**Synthetic fixtures** (`RyftTests/Fixtures/Import/`; invented plan names, generic exercise names):

| Fixture | Covers |
| --- | --- |
| `ap-plans.csv` · `ap-workouts.csv` | BOM, CRLF, weeks and a date, 2 days, a hyphenated name, a rep range · 3 standalone and 3 plan sessions, `min` and `h:mm hr`, 12 h, `-` rows, an exercise with every set `-`, `+N` on a bodyweight exercise, decimal points, a week-4 session that drops an exercise |
| `ap-workouts-de.csv` · `-lbs.csv` · `-edge.csv` | decimal comma, `Min.`/`Std.`, 24 h, `Tag`/`Woche`, LF, no BOM · an `LBS` header · a missing table header, unknown columns, junk lines, a trailing `;`, a quoted `;`, an unclosed quote, `15:28 pm`, the Europe/Berlin DST gap and repeat (2026-03-29 and 2026-10-25, 02:30), blocks without blank lines |
| `ap-workouts-plus1.csv` · `header-row.csv` | `ap-workouts.csv` plus one newer workout · a comma-separated header-row file |

| Ticket | Suites |
| --- | --- |
| I2 | `AlphaProgressionParserTests` (each fixture → counts, sets, loads, warning kinds and lines); `ImportScannerTests` (tables for numbers, dates, durations, tokens, en + de); `LineReaderTests` (BOM, CRLF, CR, the last line, a 4 KiB line, invalid UTF-8, UTF-16 refused); `ImportDetectionTests` (`header-row.csv` → `.none`); `ImportFuzzTests`; `MainThread.assertOff` in `TrainImportReader.read` |
| I3 | `ExerciseNormalizerTests` (a rule table); `ExerciseAliasesTests` (shape, idempotent, unique); `ExerciseMatcherTests` (each tier, the equipment filter, fuzzy never ✓ even at 0.99, ties, remembered beats exact, an archived remembered id is ignored); `ImportMappingStoreTests` (per account, upsert, wipe) |
| I4 | `TrainImportFlowModelTests` (every step and guard; the bodyweight question once per exercise with options by `load_type`; the zone line; flag off; opened files and the signed-out wait); `ImportFileAccessTests` (the cap before and during the read; the Inbox copy deleted); `ImportUITests` (demo with the DEBUG sample: the result counts) |
| I5 | `ImportIDsTests` (RFC 9562 vector v5(DNS, `www.example.com`) = `2ed6657d-e927-568b-95e1-2665a8aea6a2`; same input, same ids; `-plus1` adds exactly one id; a reorder or a zone change keeps ids; two accounts differ); `ImportTimeResolverTests` (DST); `ImportBuilderTests` (§5 and §8, `PlanValidation` passes, deterministic `completed_at`/`updated_at`, titles ≤ 120); `DuplicateDetectorTests` (0.69 vs 0.70, the max denominator, derived ids excluded); `ImportBatcherTests` (50, 5, measured bytes, 413 halving); `TrainImportUploaderTests` (order, resume after a reload, per-item results, rejected not retried, blocked, `Retry-After` on `TestClock`, an account switch drops answers, never another account's job, the stub → "not available", nothing with the flag off, no `LocalSession` and no Health save) |
| C2 | the mirror's fixture-decoding tests from API.md |

**Fuzz** (`ImportFuzzTests`, I2 with test-engineer): a seeded `SplitMix64`, 500 seeds per base fixture, each applying
1–8 mutations (delete, duplicate, swap or join lines; truncate at a random byte; insert `;` `"` `·` CR, NUL, invalid
UTF-8 or U+FFFD; put `9999999999999`, `1e309`, `nan`, `-0`, `+`, `,,` or Arabic-Indic digits in place of a number; flip
BOM or CRLF; add a 64 KiB line; drop all blank lines). Each case asserts: it returns or throws only `ImportError`;
warning lines lie in 1…`lineCount`, sorted and capped; sessions ≤ 3-field lines; the same bytes give an equal bundle.
**No wall clock:** `ParseStats.steps` (lines visited + fields split) must stay ≤ 4 × lines + 16, so quadratic work
fails as a count. Each seed is printed before its case.

**Manual (the user):** his files, the result screen's counts, and the e1RM of two lifts.

## 12. What could go wrong

| Risk | Mitigation |
| --- | --- |
| German tokens differ · a wrong match files history under the wrong exercise | tokens are data and unknown lines only warn (Q1) · fuzzy needs a tap; ✓ only for remembered, exact or alias |
| **Open (user): does Alpha Progression export the wall clock a workout was recorded at, or re-render every time in the phone's current zone?** Ids use the file's wall clock (ADR 0007). If the app re-renders, an export made after a time-zone change (travel, a move) shifts every time by the zone difference: the re-import's ids differ and the whole history comes back as new, not as "already imported" | ask the user to compare two exports of one workout made in different zones; if times move, key sessions on the day plus the order within the day instead (a new ADR amendment and a migration of nothing: no import has shipped) |
| The id recipe changes and history duplicates · a big history blocks the main actor | ADR 0007 freezes it, `ImportIDsTests` pins vectors · parse, build and encode are `@concurrent` (`MainThread.assertOff`) |
| Personal data in the public repo · Open-in while dark | synthetic fixtures, curated aliases, review of every fixture, doc and PR body · the flag-off sheet (Q3) |

## 13. API requests: wording for `docs/API_REQUESTS.md` → "Training import (open, 2026-10-23)"

| # | Request |
| --- | --- |
| T1 | **Origin belongs to the endpoint.** Every session in `POST /v1/train/import` is an import, so the request carries no per-session `origin`. `Session` and `SessionSummary` responses carry `origin` (`app` \| `import`) and `import_source` (string?), so history can label them. |
| T2 | **No `skipped` flag is needed.** The app doesn't send sets that weren't done; it counts them on the device. If the platform wants them anyway, `completed_at: null` already means "planned, not done". |
| T3 | **Bodyweight keeps today's convention.** For `load_type: bodyweight`, `weight_kg` is the added load and `Session.bodyweight_kg` the body weight; no `bodyweight` / `added_kg` set fields. Please confirm that `weight_kg: null` and `0` mean the same for a bodyweight set. |
| T4 | **Assisted sets.** Files can log assistance as a negative load (`-20`). `weight_kg` is clamped to 0–500, so the app imports reps only. Is a negative added load, or an `assist_kg`, planned? |
| T5 | **Order within a request.** Plans are stored before the same request's sessions, so `plan_day_id` / `plan_exercise_id` may point into the batch. Are these ids validated (`422` when unknown)? |
| T6 | **Imported sessions never move an enrolment,** even with the active plan's `plan_day_id`, and send no `SESSION_SCORED` or `PR` push. |
| T7 | **The rescore answer.** The response carries `days_touched` and `scoring.expected_within_sec`, as `SyncResponse` does. Those days stay in `GET /v1/me/sync` → `pending_days` until rescored, and the silent refresh push is sent for them. |
| T8 | **Enrolling where the user is.** `POST /v1/plans/{id}/enroll` takes an optional `{ "started_at": timestamp?, "current_week": int?, "current_day_index": int? }` (defaults: now, 1, 0). Until then the app offers only "start today". |
| T9 | **Limits under Conventions.** The 1 MiB body limit of `POST /v1/train/import`; ≤ 50 sessions and ≤ 5 plans per request; the status when a second import starts while one is running (`429` with `Retry-After`, please). |
| T10 | **"Identical content"** for the no-op is compared without server fields (`updated_at`, scoring). The app derives `completed_at` and `updated_at` from the session's start and duration, so sending a session again gives `unchanged`. |
| T11 | **Bodyweight plan targets.** API.md says `target_value` is `null` for `target_kind: bodyweight`, but the plan builder accepts an added load there (`PlanValidation.swift:70`). Which is right? The import sends `null`. |
| T12 | **Archived custom exercises.** Does `POST /v1/exercises` with an archived custom exercise's id un-archive it? |

## 14. For the lead

| # | Question |
| --- | --- |
| Q1 | A German export, only to confirm the German tokens (the user checks its structure locally). |
| Q2 | ui.md should show: the zone line in the preview; the bodyweight options by `load_type` (§5); the offline duplicate note (§6); a job still uploading when a new import starts; warnings as line numbers without file text; the flag-off Open-in sheet. |
| Q3 | Info.plist can't follow a remote flag. Accept RYFT in Open-in on every build with the keys, or add the keys in the PR that turns the flag on? |
| Q4 | (security-privacy-reviewer) Should remembered choices be part of "Export my data"? |

**User step** (no capability, entitlement or build-setting change): in Xcode → target → Info → Document Types, check
"CSV document" (`public.comma-separated-values-text`, Viewer, Alternate) and "Supports opening documents in place" =
YES; then, on a device, share a `.csv` from Files and check that RYFT is offered.
