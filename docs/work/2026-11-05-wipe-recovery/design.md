# Sign-out wipe recovery: what happens when a wipe fails or the app dies during one

**Status:** decided, not built. U1 to U3 are answered in §8; U4 and U5 stay open.

Follow-up to #93 (`train: a sign-out deletes session rows one by one`). Designed against `fix/train-wipe-objects`, head
`a669d5b`, not `main`. Values are synthetic. Line numbers are that commit's.

**Sources.** "Proved" means a probe in one of the two security-privacy reviews of #93 (Review 1 on `4ba42a7`, Review 2 on
`cbb6351`), on the iOS 27 simulator. "Read" means from the code. "Assumed" means nobody has checked it. Nothing here has
run on iOS 17 or a device.

## 1. Goal

A wipe that fails or is killed finishes by itself, before any account's data shows, and it can't take a later account's
work. Four outcomes:

1. Account B never sees or uploads a row of account A.
2. A wipe that was started always ends, at the latest on the next launch.
3. A session expiry's parked rows survive recovery, and their 30-day limit never restarts.
4. What the app and the policy say about deletion is true, including the failure cases.

Not a goal: moving the wipe off the main actor, or scoping every read model by account.

## 2. Facts that shape the design

- **The read models have no owner.** `purge(notBelongingTo:)` covers only activities, nights and chunks. `LocalSession`
  and the `Cached*` tables have no account column, so a session published over a failed wipe reads A's rows (Read).
- **A failed wipe poisons the context.** Object deletes stay pending, and the next `save()` by anyone lands them or fails
  with them (Proved). In-process retries are unreliable, and B's rows can sit in the same transaction.
- **A wipe isn't atomic.** Batch deletes commit at once, and object deletes land in the final save. A kill in between
  leaves caches gone and sessions intact (Proved).
- **The SDK drops the Keychain session before `apply(nil)` runs** (`AuthService.swift:601-603`). After a kill, `apply` sees
  no session and does nothing (Read).
- **UserDefaults is the wrong place for a crash marker.** The tracker catalog's guard says so
  (`TrackerCatalogStore.mark`, `Seams.swift:578`).
- **`auth.lastUserID` has readers that assume it's the signed-in user:** the HealthKit anchor keys and the export choice
  (`HealthKitManager.swift:81`, `TrainCoordinator.swift:479`).
- **A live store's bytes outlast the wipe.** Deleted values stay in `Train.store-wal`, and `secure_delete` is FAST, not
  full (Proved). Persistent history is never pruned, and it holds row counts and timestamps but no values (Proved).
- **SwiftData copies an app-container store into an empty group container when it opens** (`OrphanedStoreCleanup`). A
  naive file delete can bring an old store back.

## 3. Options

| | A. Retry the object wipe at launch | B. Scope every table by account | **C. Write-ahead debt, gate, replace the files (chosen)** |
|---|---|---|---|
| Kill | Resumes | Rows stay, hidden | Resumes |
| A permanent refusal (iOS 17 batch delete, full disk, trigger) | Fails on every launch | Hidden, never deleted | File delete doesn't depend on the delete that failed |
| Main thread at launch | Seconds, watchdog risk | None | Milliseconds |
| WAL, free pages, history | Stay | Stay | Gone |
| Parked rows | Kept | Kept | Kept: this path keeps the object wipe |
| Cost | Small | A migration of 12 tables, every read and write touched, no versioned schema | Small: one file, one launch step, one guard in `apply` |

C needs the object wipe only for an expiry, which A alone would already do. B is rejected: its cost is highest, and hidden
rows are still undeleted.

## 4. States and transitions

### Types

```swift
/// `AuthService.Wipe` becomes Codable, and gains `since` and `storeOnly`.
struct OwedWipe: Codable, Equatable {
    var wipe: AuthService.Wipe    // reason, account, `since`; `Wipe.parking` stays the one derivation
    var since: Date { wipe.since } // the first begin; stamped as `parkedAt`, starts the 30-day bound
    var deviceStepsDone = false   // set after the first pass, so a retry runs only the store step
    var scrubOnly = false         // the wipe succeeded; only file residue is left (W7)
}

@MainActor final class WipeLedger {
    init(file: URL?)              // Application Support/account-wipe.json; tests pass a temp folder; nil is memory only
    var entry: OwedWipe? { get }  // memory first: a full disk can't lose it during this run
    func begin(_ wipe: AuthService.Wipe, at: Date)   // merges, see below
    func update(_ change: (inout OwedWipe) -> Void)
    func clear()
}
```

- **Writes:** atomic, `.completeFileProtectionUntilFirstUserAuthentication`, the same class as the Keychain session.
- **`since` lives in `Wipe`** (W1), so `OwedWipe.since` reads it, a retry runs `entry.wipe` as it stands, and I4 needs no
  second copy. W1 also stores `storeOnly`, because W1 builds write the file W2 reads. Nothing sets it before W2.
- **Reading the format:** a missing `storeOnly`, `deviceStepsDone` or `scrubOnly` reads as false. `since` is required.
- **Merging `begin`:** the earliest `since` stays. Anything that doesn't park the same account narrows the entry to no
  parking: a different account, a nil reason, or the same account's `.user` or deletion. A deletion's reason always
  replaces the entry's, for W5's notice. It never widens back. The entry keeps its first account, and a wipe already asked
  for runs as asked: only the date comes from the entry, and only when the entry parks the same account.
- **An entry that can't be read:** no action, and the file stays. Before the first unlock the store is in memory anyway.
  `entry` reads the file again while memory is empty, so it's found after the unlock.
- **Seam:** the file URL is enough. No protocol, because nothing else implements it. `AuthService.shared` is the only
  service with a real file: nil is the default, so previews and tests can't reach the live one.
- **Debug API-key mode** keeps its own unledgered wipe.

### Invariants

- **I1.** While an entry that isn't `scrubOnly` exists, no new session is published, except the entry's own account signing
  in again, which ends the entry. The leaving session stays published only until its own `apply(nil)`, inside the same
  sign-out.
- **I2.** The entry is written before the first destructive step and before the SDK drops the session. Only a wipe that
  returned true removes it, with one exception: the entry's own account signing in ends it, and until W3 that's with no
  attempt, so W1 changes no sign-in. A stored session restored at launch isn't a sign-in: the entry survives it.
- **I3.** `auth.lastUserID` means only "whose data the store holds". The debt lives only in the ledger.
- **I4.** A retry parks with `at: since`.
- **I5.** Nothing writes to the widget while a debt exists.

```mermaid
stateDiagram-v2
    [*] --> Clean
    Clean --> Owed: session ends, or another account signs in (entry first)
    Owed --> Clean: wipe true, a parking wipe
    Owed --> Scrub: wipe true, no parking (W7)
    Owed --> Owed: wipe false, or kill
    Owed --> Clean: the same account signs in, after one attempt (W3; no attempt before it)
    Scrub --> Clean: next launch signed out, files replaced
    Scrub --> Clean: any session published
```

### At launch

The store step runs in `static let TrainStore.shared`, before the container opens, so every route to the store passes it.
`AuthService.init` runs first and narrows the entry when it reads another account's stored session. `AppEnvironment.live`
passes `auth: .shared` ahead of `TrainStore.shared` (Read). If that order ever flips, the launch falls back to the object
wipe and the gate, and the next launch converges.

| Entry | Stored session | Before the store opens | After |
|---|---|---|---|
| none | any | nothing | as today |
| owed, no parking | none | replace files | run the wipe, clear, signed out |
| owed, no parking | another account | replace files | run the wipe, clear, publish it |
| owed, no parking | the entry's account | replace files | sign-out was interrupted: run the wipe, clear, `client.signOut()`, signed out |
| owed, parking, within 30 days | none | nothing | object wipe after the first frame, `at: since` |
| owed, parking, within 30 days | the entry's account | nothing | same, and `client.signOut()`; not published |
| owed, parking | another account | narrowed, replace files | run the wipe, clear, publish it |
| owed, parking, past `since + 30 days` | any | narrowed, replace files | as the matching no-parking row |
| `scrubOnly` | none | replace files | clear |
| `scrubOnly` | any | nothing | clear |

- **Replace files** means removing `Train.store`, `-wal`, `-shm` and `.Train_SUPPORT` at the configuration's URL, then
  the app-container orphan through `OrphanedStoreCleanup.run`, reusing its names and `decide`.
- **The wipe always runs after a replace.** If a file couldn't be removed, or SwiftData copied an orphan back, the object
  wipe still catches it, and the entry clears only on true.
- **If the wipe still fails,** the gate below applies.
- **The retry** also runs from the nightly compaction beside `deleteExpiredParked`, so a background-only run can reach it.

### At sign-in (`apply`, the one chokepoint)

| Entry and owner | Action |
|---|---|
| Neither, or both are this account | publish |
| Another account in the entry or `lastUserID` | `begin`, wipe with no parking. True: clear and publish. False: **hold** |
| The entry's own account signs in | one attempt with the entry's parking, then clear, publish either way. The rows are its own, and keeping the entry would let a later launch take its live work |

**Hold** means B's publish is skipped: `apply` returns before `session`, `accountChanges` and the hooks change for B, and the
phase becomes `signedOut`. If A is still published (a deep link signing B in over A), A's session ends first, hooks
included, so a wiped account never stays on screen. `accountID` is then nil, so sync, uploads, flags and reads stay idle
(Read). The SDK keeps B's session in the Keychain, so
the next launch publishes B without another login. Welcome shows the reason through `errorMessage`. No new phase or
screen. Later SDK events for B re-enter `apply`, so a retry that succeeds publishes B.

## 5. Decisions

The labels need a note: **`docs/STATUS.md` has no S-numbers.** They come from the two reviews, and each review has its own
S1 to S4. The brief's S1 is STATUS's first bullet, which is Review 2's S2. Rather than guess, both sets are covered below.

| Item | Decision | Reason | Ticket |
|---|---|---|---|
| **S1, two owners** (STATUS bullet 1, R2-S2) | Split it. `lastUserID` is the owner, the ledger is the debt. One entry, not a list | I1 means a second account can't accrue a debt while one is open, so a list has nothing to hold | W1, W3 |
| **R2-S1**, the kept key destroys B's work | Fixed by I1 | B has no rows while a debt exists, so a recovery can't take any | W3 |
| **R2-S3**, wipes on every launch | Fixed by the file replace, plus `deviceStepsDone` | A permanent refusal ends on the next launch, and retries stop repeating the anchor reset and the 90-day backfill. This also removes STATUS's iOS 17 loop | W2 |
| **R2-S4**, the notice claims too much | `wipeLeaving` returns the result. On false, Welcome says what's still on the iPhone, for deletion and for a user sign-out. A resumed deletion shows its notice again from the entry | The server half is true, the device half wasn't, and the notice lived only in memory | W5 |
| **R1-S2**, kill mid-wipe | Fixed by I2. A resume reruns every step | Each step is idempotent (Read) | W1, W2 |
| **R1-S3**, log text | Done at `save()`. Other `localizedDescription` sites **deferred** to a separate cleanup | Not a wipe matter, and none was analysed | none |
| **R1-S4**, never-saved rows | See that row below | | W6 |
| **Launch-time marker** | A file in Application Support, written ahead. **Deliberately no inference** from "`lastUserID` set, no session" | A Keychain miss before the first unlock looks identical and would wipe a signed-in user. The price is a window of milliseconds on an SDK-driven expiry, where the data stays until another account's sign-in wipes it | W1, W2 |
| **Sign-in over a failed wipe** | Hold: no session is published until the wipe returns true | Failing closed is the only option that needs no account column. iOS has no supported relaunch, and `TrainStore.container` is a `let` that the whole graph holds | W3 |
| **No-parking chunks outside 30 days** | A retry parks with `at: since`, and past `since + 30 days` the entry narrows to a replace | That bounds rows that carry no `parkedAt`. Exposure today is nil: `Ryft/` constructs no `ActivityTrackChunk` (Read) | W1, W2 |
| **`CachedDay` republished** | `Repository.publishWidget` removes the file instead of writing while a debt exists. `ReadinessSnapshot.clear()` moves ahead of the store wipe | The path is `forgetActivityState` → `tonightBedtime = nil` → `publishWidget` → `widgetFacts` reads the row the wipe left (Read). `session` is still A during `onWipe`, so `isSignedIn` can't guard it, and the ledger can | W4 |
| **Live Activity** | `signOut` awaits an `endNow()` before the SDK call. At launch, `endAll(except:)` keeps nothing unless the app has an account and no debt | `end()` is a main-actor `Task`, so moving it ahead of a synchronous wipe changes nothing. The SDK-driven expiry stays synchronous and relies on launch. If the app is never reopened, ActivityKit ends it (assumed, 8 to 12 h) | W4 |
| **Never-saved rows before A3b** | Before the final save, delete `context.insertedModelsArray` rows of wiped types, keeping what parking keeps. Must merge before A3b | Today's only route is an earlier failed save (Read). Proved on 4 tables, so the batch-only list is wider than activities. It becomes sensitive when A3b adds chunks | W6 |
| **WAL and history** | After a no-parking wipe, the entry stays as `scrubOnly`, and the next signed-out launch replaces the files | A replace is the only step that removes WAL, free pages and history together, and it reuses W2. An in-process A→B switch and an expiry keep this residue (§7) | W7 |
| **Backups** | Excluded (§8, U2): `Train.store` and the ledger leave device backups in W7 | `readiness.json` is excluded "never in a device backup" (`Repository.swift:808`), but `CachedDay` holds the same scores in a store that the activities design §2.4 says is backed up. No wipe reaches an existing backup | W8 |
| **Policy wording** | See §8 | The current text says "at once" and "then deleted" | W8 |
| **Remote flag** | None | Recovery runs before `/v1/config` and while signed out, and a privacy fix shouldn't be switchable off | |

"Deleted" then means, in order:

| Moment | State |
|---|---|
| Wipe returned true | Unreachable through the app, values still in the WAL |
| Next signed-out launch | Files gone. Per-file keys go with them (assumed, Apple's platform documentation) |
| Backups taken earlier | Unchanged, until the user replaces them |

## 6. Tickets

Each is one PR on a branch from `main`, after #93 merges. **W2 and W3 must ship in the same build:** W2 alone leaves B
published over a failure, and W3 alone promises a reopen that can't help. W1 to W3, W6 and W7 get a
security-privacy-reviewer pass. Tests extend `StoreOnDisk` and `WipingAuth`, whose `relaunch` is the kill. `refuseDeletes`
is the failure.

| # | Title | Owner | Depends on |
|---|---|---|---|
| W1 | `auth: a wipe is written down before it starts` | sync-engineer | #93 |
| W2 | `train: an owed wipe finishes before the store opens` | sync-engineer | W1 |
| W3 | `auth: no session over an owed wipe` | ios-developer, localization-editor | W2 |
| W4 | `today: nothing of a leaving account on the lock screen` | ios-developer | W1 |
| W5 | `auth: the notice says what's left on this iPhone` | ios-developer, localization-editor | W1 |
| W6 | `train: a wipe takes rows never saved` | sync-engineer | #93 |
| W7 | `train: a sign-out replaces the store's files` | sync-engineer | W2 |
| W8 | `docs: ADR 0016, architecture, status` | ios-architect | W3, U1, U2 |

**W1.** `WipeLedger`, `OwedWipe`, a Codable `Wipe`, `begin` in `signOut` before `client.signOut()` and in `apply` before each
wipe. `TrainStore.wipe(_: Wipe)` is the one call and passes `wipe.since`. The kept-id code stays until W3. The entry's own
account signing in ends the entry with no wipe, except a session restored at launch (I2).
- The mock client sees an entry on disk with reason and account when `signOut()` is called, for all three endings.
- True clears the entry. False keeps it, surviving a new `WipeLedger` on the same file.
- Merge: the earliest `since` stays, another account removes parking, and nothing widens it back.
- An unwritable file keeps the entry in memory for the run.
- A retry stamps `parkedAt == since`, and an already parked row keeps its older date.

**W2.** `StoreReset.run(entry:store:orphans:now:)`, pure on a folder like `OrphanedStoreCleanup.run`, called from
`TrainStore.shared`. The launch table in `AuthService.init`. Setting `Wipe.storeOnly`. After a resume, `.task` calls
`screens.bedtime.accountChanged()`, because a kill leaves A's reminders and alarms scheduled and nil → nil fires no
`onChange`.

W2 must also handle what W1 builds leave. A kill between `begin` and the SDK's Keychain delete publishes the account again
and keeps the entry, so that account can work over an entry for weeks, and its rows are then live, not interrupted. The
launch table's "the entry's account" rows read as a fresh interruption and would sign it out and replace the files. Resolve
this before the first W2 build: a deletion's entry must still resume, and a stale `.user` or expiry entry must not take
live work. Until then such an entry dates a later parking of the same account early (§7).
- An entry of each reason with a stored session of its own account, written by a W1 build and aged, takes the path chosen
  above, and a deletion's rows go.
- With an entry and all 18 tables full, a relaunch leaves every table at 0 and no entry, for each ending.
- With `refuseDeletes` still in the file, the relaunch still ends clean: the replace beats the trigger.
- No entry: the store's bytes are unchanged. An undecodable entry: no replace, and the file stays.
- Parking: no replace, the parked row and its chunk survive, and `parkedAt == since`. At `since + 30 days + 1 s` a replace
  runs. A clock behind `since` doesn't expire it.
- With an app-container copy present, neither store holds a row after the relaunch.
- With `wipeLocalData` always false over three launches, the device steps ran once.
- A resume after a successful replace does no object deletes (`ModelContext.didSave` is empty).
- Bedtime: after a resume, the mock notifier has no pending reminder of A.

**W3.** Hold in `apply`, a throwing path so `logIn`, `signUp` and `handle` report failure. The same-account rule, which
replaces W1's clear with no attempt. The interrupted sign-out. Remove the kept-id branch (`:742-743`) and the `wiped` guard
(`:703`). Rewrite `aRefusedWipeAtSignInIsTriedAgainAtTheNextLaunch`.

The same-account rule must not trust the entry's account alone. Neither route is new with W1:
- **Rows of another account.** A's wipe fails, B is published, B's sign-out dies after `begin`, and A signs in: the entry
  still names A, and A would read B's rows.
- **A deleted account.** A's `accountDeleted(background: true)` wipe fails, and A signs in while the removal runs: a
  deletion's entry isn't a return.

Tests:
- B over a refused wipe: `accountID == nil`, `accountChanges` unchanged, no hook ran, `logIn` is false, the message shows,
  and `client.currentSession` is still B.
- Then a relaunch: B is published, every table is at 0, and `lastUserID` is B.
- B over a published A with a refused wipe: `accountID == nil`, and A's hooks ran.
- Review 2's sequence (A fails, B fails, relaunch healthy, B signs in) leaves no row of A.
- A refresh event while held publishes nothing unless the wipe then returns true.
- Same account: one attempt, published either way, no entry, and no wipe on the next launch.
- Entry A with stored A: not published, and `client.signOut()` ran once.
- While signed in, `AccountScope.current` always equals `accountID`.
- `make lint`: strings in en and de.

**W4.** The guard in `publishWidget`, the reorder in `wipeSharedLocalData`, `endNow()`, and a pure
`keptLiveActivity(active:hasAccount:owed:)`.
- A refused `CachedDay`, then `tonightBedtime = nil`: `readiness.json` is absent.
- The `readiness.json` file is removed before the store step (a refused store still leaves it absent).
- `endNow()` ran before `client.signOut()`.
- `keptLiveActivity` is table-tested, and demo data keeps its activity.
- By hand on a device: kill during a sign-out with a workout live, reopen, the lock screen shows nothing.

**W5.** `wipeLeaving` returns Bool. A variant per ending with a failed wipe, and the notice restored on a resume.
- Each of `.user`, `.accountDeleted(background: true)` and `(false)` with a refused wipe shows its variant, and with a
  healthy wipe shows today's text.
- A kill during a deletion's wipe shows the deletion notice after the relaunch.

**W6.** One step before the final save.
- For every `WipedTable` and both parkings, a row inserted and not saved is at 0 in the file afterwards.
- Unsaved parked rows still survive (`aSessionExpiryKeepsParkedRowsWithTheirUnsavedChanges` stays green).

**W7.** `scrubOnly` after a no-parking success.
- A synthetic marker string is in `-wal` before the relaunch (the control), and in no file under the store's folder after.
- A→B in one process: no replace, and B's rows survive a relaunch.
- An expiry never sets `scrubOnly`.
- History holds no rows of A after a replace.

**W8.** ADR 0016, `docs/ARCHITECTURE.md` (`:208`), STATUS. A brief to platform-lead through head-architect for the policy
text, since the app never edits `../plattform`.
- ADR accepted, and the policy version named in STATUS.

## 7. Risks

- **The replace is the only code that deletes a live store.** Only a real `begin` can arm it, it never runs on an unreadable
  entry, and with parking it runs only past the limit. Mutation-test the guard.
- **A wrong "same account" reading** signs a user out. That's an annoyance and it fails safe.
- **Stuck on Welcome.** If the files can't be removed and the wipe keeps failing, B stays held. The message says to reopen,
  which won't help here; deleting the app should (assumed). No path to it was found, so no extra screen.
- **`ModelConfiguration.url` before opening, and the replace itself, are unverified on iOS 17.** STATUS's iOS 17 run stays
  a release gate.
- **Residue that stays:** an in-process A→B switch leaves A's values in the WAL and free pages of B's store, and A's row
  counts in history. An expiry keeps them until the account returns or the parked rows expire. Reachable only with file
  access. Accepted, and said in the policy text.
- **The main thread still blocks during a wipe:** 3.4 s for 44,500 rows in Debug, and an expiry's retry does too. A kill
  during it is now safe, but a progress line can't render meanwhile. Measure on a device (performance-profiler). Moving it
  off the main actor is its own design.
- **A debt that survives a launch dates a later parking early.** W1 keeps an entry when a stored session is restored, or a
  deletion killed before the Keychain delete would be forgotten. A later expiry of that account then parks at the entry's
  `since`, so the row expires sooner than 30 days after that expiry. Accepted: it's bounded, shorter retention is the safe
  direction, and W2 resolves the entry at launch. `aDebtThatSurvivedALaunchDatesTheNextParking` pins it.
- **Review 1's N1:** `wipe` hit a SwiftData fatal error under an artificial limit. It's now a kill with an entry on disk, so
  a launch replace recovers it. Not reproduced at a realistic limit.
- **An upgrade from a #93 build** with key A and B signed in wipes once more, taking B's unsent work, as #93 would. This only
  matters if #93 reaches testers before W3.

## 8. What needs the user

**Decided by the user on 2026-11-05.** The questions below stay as asked, for the record.

- **U1:** the policy wording is confirmed, including the 30-day limit exception (item 2). Item 4 drops its last sentence, about backups, because of U2.
- **U1 item 5:** one new policy version, released with the build that ships this wipe recovery, bundling any other pending policy lines. So there is one re-consent prompt.
- **U2:** `Train.store` is excluded from device backups, and the ledger with it. W7 takes this. It reverses the activities design §2.4.
- **U3:** the hold and the copy are approved as written.
- **U4, U5:** not decisions. They are runs on the user's hardware and stay open.

**U1. Privacy policy.** Wording is yours as controller, and I'm not giving legal advice. The current version,
`2026-10-26`, says of an unsent import that it "is kept on your iPhone for up to 30 days and then deleted; signing out or
deleting your account removes it at once" (§3, same in `TESTFLIGHT_NOTES.md:139`). §6 covers only the servers, and nothing
describes data on the iPhone or parked activities. Please confirm each:

1. **"At once" no longer holds without exception.** Proposed: "signing out or deleting your account removes it from your
   iPhone, normally at once; if RYFT can't finish or is closed, it finishes the next time you open RYFT."
2. **The 30-day limit exception.** Limits on the iPhone run only while RYFT runs. Proposed: "These limits are applied by the
   app. If you don't open RYFT, the data stays on your iPhone until RYFT next runs or you delete the app." Deleting the app
   removing the App Group container is assumed, and is a device check before this ships.
3. **Parked activities, before `activities.manual` turns on.** Proposed for §6: "If your session ends without you signing
   out, activities and sleep entries not yet sent stay on your iPhone for up to 30 days so you can sign in and send them.
   Another account signing in removes them."
4. **Residue.** Proposed: "Deleted data can remain in unused parts of the app's storage until RYFT next starts while signed
   out, or when you switch accounts without closing RYFT, until that space is reused. It's not visible in the app. Device
   backups you made earlier keep their copy until you replace them." The last sentence depends on U2.
5. **Version.** §11 means a new version asks everyone to consent again, and uploads hold until they do (ADR 0008). Ship it
   alone, or with the next planned policy change? Items 1 and 2 are inaccurate today in the failure case only.

German follows once the English is confirmed.

**U2. Should `Train.store` stay in device backups?** Excluding it, on the group's `Application Support` folder, is about one
line, and it makes "never in a device backup" true for scores. The cost is that unsent workouts and parked activities don't
survive a restore to a new iPhone, and it reverses the activities design §2.4. I recommend excluding it. If you agree, W7 takes it, the
ledger is excluded too, and sentence 4 drops its backup clause. Whether App Group containers are backed up at all is
assumed, and is a device check.

**U3. The held sign-in's copy and behaviour.** B is told: "RYFT couldn't finish removing the previous account from this
iPhone. Close RYFT and open it again to continue." Is a held login acceptable, given the alternative is B seeing A's data?

**U4. The iOS 17 run.** No such runtime is on this Mac. `TrainStoreWipeTests` must run once on iOS 17 before the next
External build, with or without this work.

**U5. Device checks:** kill during a sign-out with a workout live, a real full disk, and a backup restore after a sign-out.

## 9. Draft ADR

```markdown
# 0016 — An account wipe is a debt written down first, and no session is published over it

- Status: proposed (2026-11-05)
- Deciders: ios-lead, on ios-architect's proposal
- Applies to: `WipeLedger`, `AuthService.apply`, `TrainStore.shared`, `StoreReset`

## Context

The read models and logged sessions have no account column, so one store holds one account's data, and the wipe is what
separates accounts. A wipe can be refused or killed, it isn't atomic, and the SDK drops the session before it starts. #93
made it report failure, but the only record was the last user's id, which also means "whose data this is" to the HealthKit
anchors. One id can't say both, and a retry at launch took the next account's unsent work.

## Decision

1. **A wipe is recorded before it starts.** A file, written atomically before the first destructive step and before the SDK
   drops the session, removed when a wipe returned true or its own account signs in (decision 3). Not UserDefaults: it may
   not reach the disk before a crash.
2. **`auth.lastUserID` only says whose data the store holds.** The debt lives only in the ledger.
3. **No session is published over a debt,** except the entry's own account returning, which ends it after one attempt. A
   sign-in held this way changes no account state, and the SDK keeps its session for the next launch.
4. **Recovery replaces the store's files before the container opens,** then runs the wipe. A session expiry keeps the
   object wipe, because its parked rows are the only copy of unsent work, until `since + 30 days`.
5. **The first attempt's time is the parking time,** so a retry never restarts the limit.
6. **Nothing infers a debt** from a missing session. A Keychain miss before the first unlock looks the same.
7. **A no-parking wipe leaves a scrub:** the next launch signed out replaces the files.
8. **No remote flag.** Recovery runs before `/v1/config` and while signed out.

## Consequences

**Good:**
- A permanent refusal ends on the next launch, on any iOS version.
- A launch recovery costs milliseconds.
- WAL, free pages and history go with the files.
- A later account's work can't be taken by a retry.

**Costs:**
- A rare sign-in is held until the app is reopened.
- A second piece of launch-critical state to keep in step with `TrainStore.shared`.
- The only code that deletes a live store: it must stay behind the ledger.
- An in-process account switch, and an expiry, keep file residue.

**Rules:**
- A new table needs no change here, but it must stay wipeable by `WipedTable`.
- Anything writing a lock-screen surface checks the ledger.
- An account column on the read models would make decision 3 removable; it's not planned.
```
