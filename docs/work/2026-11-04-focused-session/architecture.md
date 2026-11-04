# D2: SessionController and the session screen's structure (Focused layout)

> Lead resolutions L5 and L15–L21 in `plan.md` override this note where they differ (flag instead of a compiled default,
> no swipe to delete in Focused, ✓ on an empty row, German copy, T4's cut).

Owner: ios-architect. Inputs: `brief.md`, `plan.md` (L1 to L14 win over the brief), `design.md` (D1), the session code on
`origin/main` 0b6069b, ADR 0009. Lasting part: ADR 0013. Synthetic values only.

## The decisions

| # | Question | Decision | Rejected |
| --- | --- | --- | --- |
| 1 | Where the page lives | `LocalSession.currentExerciseID: UUID?`, optional, not on `wire`, written with `store.save()` only (as `restEndsAt` is) | A per-session entry in `Settings` |
| 2 | Page API | One owner (the attribute), resolved by `pageExerciseID`. `jump(to:)` for the user, `follow(_:)` for the planner, one funnel `showPage(_:)`. **`SessionAdvance.swift` changes by zero lines.** `collapse` and friends stay computed and go unread | A layout branch in `fireAdvance`; a controller-side `pageIndex` |
| 3 | `activeSet` | Pure `SessionPage.activeSet(in:tapped:warmupsExpanded:)`. `tappedSet: UUID?` and `expandedWarmups: Set<UUID>` are controller state | Page `@State` (measured: lost on a round trip) |
| 4 | "Next:" vs a folded warm-up | Folded warm-ups leave the planner's *input* in Focused; `activeSet(in:)` picks the row, working sets count from 1 | A new parameter in `SessionAdvance.next`; a second definition of next |
| 5 | Keypad across pages | Invariant: an open keypad's set is on the current page. `showPage` closes it otherwise; nothing to flush | Blocking swipes while the keypad is open |
| 6 | Container | `TabView(.page)` behind `SessionPager.swift`, the one file that knows the container. **Measured on iOS 27 only** | Paging `ScrollView` + `.scrollPosition(id:)` |
| 7 | Manual rest | `startRest(for:seconds:)`; `startRest(after:)` calls it for its last step | Reusing `startRest(after:)` (its guards are about what follows a check) |
| 8 | View split | `SessionView` stays the host and keeps everything shared; `FocusedSessionView` replaces only the list part. `train.sessionLayout` lives in `Settings`, the controller gets a closure | A `ListSessionView` move; the layout as controller state |

**Swipe to delete does not survive a pager** (§6). This overturns D1 §2.5 and §8, which asked this note to confirm it.

## 1. Where the current page lives

**`var currentExerciseID: UUID?` on `LocalSession`.**

| | Stored attribute (chosen) | Per-session entry in `Settings` |
| --- | --- | --- |
| Opens the shipped store | Additive, optional: lightweight migration, the fourth of its kind after `uploadedTo`, `account`, `deletedExerciseIDs` | No schema risk |
| Lifetime | Goes with the row: discard, `TrainStore.wipe()`, cascade | Needs its own clearing on finish, discard, `clearPerUserState`, and a sweep for keys a kill left behind |
| Seam | `SessionController` already has the row and the store, tests already use `TrainStore(inMemory:)` | Needs `Settings` injected into the controller |
| One owner | Yes | A second store with the session's id as a foreign key |

**Does the shipped store open it?** `TrainStore` has no versioned schema; inference runs at open. If it failed, the
`catch` in `TrainStore.init` would fall back to an in-memory store and the user's local sessions would seem to vanish,
so this is checked, not assumed:
- **Checked by:** `TrainOutboxSchemaUpgradeTests` (old models on disk, opened by name with the whole `TrainStore.schema`).
  T1 adds `currentExerciseID == nil` after the upgrade and a write and read of it.
- **Measured for this note:** a replica with every stored attribute of `LocalSession`, `LocalSessionExercise` and
  `LocalSet` as on main, on disk with an in-progress session and one set, then reopened with the new attribute: opened on
  disk, one session, one set, status kept, attribute nil; a write kept `updatedAt`; the value survived a reopen.

**No wire, no merge, no `updatedAt`, no upload:**
- `wire` lists its fields by name, so the attribute is not on it. `SessionMerge` works on `TrainSession` and cannot see
  it. `LocalSession.apply` assigns named fields and doesn't name it.
- `updatedAt` and the outbox are written only by `sessionChanged` and `finish`. Nothing observes store saves (no
  `didSave` hook in the app). A page change calls neither. `persistRest` is the precedent.
- Pinned by a test: after `jump`, `follow`, `pinPage`, `store.pendingOps()` is empty and `updatedAt` is unchanged.

**Lifetime.**
- Survives a relaunch and a rebuild: it's on the row. A rebuild is routine, not only a kill: `close()` sets `live = nil`,
  so minimise and reopen builds a new controller.
- Never cleared. The id stays on the completed row, unread (`activeSession()` fetches in progress only, and `apply` never
  moves a session back), and goes with the row. Clearing in `finish()` would run the fallback and flip the page behind the
  Finish spinner, which can wait 10 s on the screen. Clearing at the summary's Done would be undone by the re-pin 15 ms
  later and would move the stored page during the dismissal.
- `pinPage()` writes only while the session is underway (`isUnderway`). The cover's last `onChange` arrives after `live`
  is nil: after Discard it would write to the deleted row.

**Fallback.** `SessionPage.resolve(stored:in:)` returns:
1. `stored` while that row exists;
2. else the first exercise with an open working set (`SessionAdvance.next(after: nil, in:)`);
3. else the last exercise; `nil` with none.

Rows only leave through `remove` and Undo, and those move the page themselves (§2), so `resolve` is for what those can't
see: `nil` from a session started before this build or in List, and an id List's `remove` left behind.

A nil attribute must be pinned, or `resolve` would move the page by itself as sets get checked: `FocusedSessionView` calls
`pinPage()` on appear, which writes the resolved id with no side effect.

## 2. The API

```swift
// SessionPage.swift: pure, no SwiftData, tested like SessionAdvance
enum SessionPage {
    static func resolve(stored: UUID?, in exercises: [SessionAdvance.ExerciseState]) -> UUID?
    static func neighbour(of id: UUID, in order: [UUID]) -> UUID?          // the next, else the previous, else nil
    static func activeSet(in ex: SessionAdvance.ExerciseState, tapped: UUID?, warmupsExpanded: Bool) -> UUID?
}

// SessionController+Page.swift
var pageExerciseID: UUID? { get }                // resolved; the pager's and the strip's only source
var pageExercise: LocalSessionExercise? { get }
func jump(to exerciseID: UUID)                   // the user: swipe, strip tap, strip adjust, the + tile
func follow(_ request: AdvanceRequest)           // the planner: what the view does with `advance`
func pinPage()                                   // on appear and when the page changes, while underway
func showPage(_ id: UUID?)                       // the funnel: every page change, internal for +Replace
```

```swift
func jump(to id: UUID) {
    guard id != pageExerciseID, exercises.contains(where: { $0.id == id }) else { return }
    userScrolled()                               // the existing 3 s stamp, on `clock`
    showPage(id)
}
func showPage(_ id: UUID?) {
    guard layout == .focused, id != session.currentExerciseID else { return }   // List never writes it
    if let focused = focusedSet, focused.exercise.id != id { focus = nil }
    tappedSet = nil
    session.currentExerciseID = id
    store.save()
}
```

| Trigger | Entry | 3 s stamp | Animated |
| --- | --- | --- | --- |
| Finger on the pager (any drag, 10 pt) | `userScrolled()` | yes, from the first event | - |
| Swipe (selection write) | `jump(to:)` | yes | the finger |
| Strip tap, strip adjust, `+` tile | `jump(to:)` in `withAnimation` | yes | `Theme.Motion.respecting` |
| `.advance(to:)` | `follow` in `withAnimation` | **no** | `Theme.Motion.respecting` |
| `.allDone` | `follow`: no page change (L1) | no | - |
| Replace, split, on page X | `showPage(row Y)` in `replace` | no | instant |
| Undo | `showPage(X)` before `edit` | no | instant |
| Remove on its own page | `showPage(neighbour)`, **before** the delete | no | instant |

**How `.advance` drives it.** The controller stays layout-free: `fireAdvance` publishes `advance` as today. List scrolls;
`FocusedSessionView` calls `withAnimation(motion) { controller.follow(request) }` on `advance?.id`. `follow` takes only
`to.exerciseID`. The controller doesn't know Reduce Motion, and it shouldn't (design.md §7 of beta feedback 2).

**Why echoes can't stamp.** A superset flips the page after every set (A1, B1, A2). If a programmatic move stamped the
window, the second flip would stay. `jump` returns early when the id already is the page, so an echo is harmless; a
programmatic move sets the attribute first. Test: two flips inside 3 s both happen.

**What the layout does to the collapse machinery: nothing, on purpose.** `collapse`, `collapsed`, `carriedCollapse`,
`userExpanded` and `pruneCollapsed` keep running; no Focused view reads `isCollapsed`, and `expand` is never called, so
`userExpanded` stays empty. That is L1's "ignored". A branch would add a state to test and would lose the collapse if
the layout changes mid-session.

**The manual window.** `Input.lastManualScroll` and `manualScrollWindow` are reused as they are, on the injected clock.
A vertical drag on a page counts too, as in List: the reporter sits on the pager and fires for both axes (measured).
`ManualScrollReporter`'s iOS 18 branch (`onScrollPhaseChange`) can't see a `TabView`, so the pager uses a plain
`simultaneousGesture(DragGesture(minimumDistance: 10))`, which is its iOS 17 branch.

`AdvanceRequest` and `SessionAdvance.Step` don't change either: `.advance` still carries `collapse`, and Focused ignores it.

## 3. `activeSet`

```swift
static func activeSet(in ex: ExerciseState, tapped: UUID?, warmupsExpanded: Bool) -> UUID? {
    let shown = ex.sets.filter { !$0.isWarmup || warmupsExpanded }
    if let tapped, shown.contains(where: { $0.id == tapped && !$0.isCompleted }) { return tapped }
    if warmupsExpanded, let warmup = ex.sets.first(where: { $0.isWarmup && !$0.isCompleted }) { return warmup.id }
    return ex.sets.first { !$0.isWarmup && !$0.isCompleted }?.id
}
```

That is L6 in order. `controller.activeSet(in: ex)` feeds it `Self.states(of: [ex])`, the unfiltered states, one call per
page, so neighbours render correctly during a swipe. `nil` means no open row, and the page shows no active row.

**The override.** `tappedSet: UUID?`, one slot, observed, not persisted.

| Event | Effect |
| --- | --- |
| Tap on an upcoming row, `edit` on a field (`nextField` included) | set to that set: the active row follows the keypad |
| Uncheck | set to that set: "unchecking makes it active again" (brief, test list) |
| Check, any set | cleared, so an uncheck can't bring back an old tap |
| Page change (`showPage`) | cleared |
| Delete, or a server copy completes it | ignored by the pure rule (open and shown only). Ids aren't reused while the page lives: a split's restored sets come back with a page change |
| Fold | cleared when it is a warm-up of that exercise, so unfolding doesn't resurrect it |
| Rebuild, relaunch | gone: the first open set. Nothing is lost, no data was ever involved |

**Warm-up group.** `expandedWarmups: Set<UUID>`, exercise ids, observed, per controller, not persisted.
- Starts empty: folded (L6). Survives a page change because it isn't on the page. A rebuild refolds.
- `setWarmups(expanded:for:)` toggles it, then calls `refreshActivity()`, since "Next:" can change. No `edited()`: folding
  changes no set (L6) and uploads nothing.
- **Auto-fold** in `toggleCheck`: after a check of a warm-up, when the exercise has no open warm-up left. The empty set in
  List makes it a no-op there, so there is no layout branch.
- `toggleWarmup` on a working row in Focused inserts the id first, or the row would vanish under the thumb.
- `addWarmup(to:)` (`addSet` + `toggleWarmup`, D1 §2.4) does the same. The new set gets the last `setIndex`; `ghost` counts
  working sets only and the group renders above the table, so that is safe.
- `SessionFactory` creates no warm-ups: they exist only because a user marked them, so the demo plan never shows the pill.

## 4. `nextUp` / `nextLabel()` against a folded warm-up

**The planner stays; its input changes.** In Focused, a folded group's warm-ups are left out of the states it sees:

```swift
func isFolded(_ ex: LocalSessionExercise) -> Bool { layout == .focused && !expandedWarmups.contains(ex.id) }
func plannerStates(of list: [LocalSessionExercise]) -> [SessionAdvance.ExerciseState]   // states(of:) minus folded warm-ups
```

`advanceStates` and `nextOpenSet` use it. In List `isFolded` is always false, so the states are byte-identical, and with
them `nextLabel()`, `currentSetID` and the Live Activity's text. Reading `SessionAdvance` for each consumer:
- `isFinished`, `isAllDone`, `isOutOfOrder` read working sets only, so they don't change. A checked warm-up stays out of
  order either way (`firstIndex` in the working sets is nil), so the auto-fold before the delay's end changes nothing.
- `next` can't offer what it can't see, and `open` needs an open working set anyway.

**Then, in Focused only:**
1. **The planner picks the exercise, `activeSet(in:)` picks the row.** `nextOpenSet` maps the ref back and swaps the set,
   so a tapped row on the next exercise's page is what "Next:" names.
2. **Numbering follows the table:** a working set is "set n of m" among working sets, the same key. An open warm-up
   (group expanded) is "\(name) · warm-up n of m", a new key.
3. **No check yet in this controller:** `nextUp` falls back to the page, not the top
   (`ex?.id ?? lastCheckedExercise ?? focusedPage`), so a relaunch on page 3 doesn't name exercise 1. On a superset this
   offers the partner first: a coin toss either way, and one line is the right price.

A swipe doesn't change "Next:". It stays bound to the last check (L1, one definition). After peeking at another page the
pill still names the set you left, which is true.

**Focused's Live Activity** uses the same `nextLabel()`, so it matches the pill. `layout` is passed in `init`, because
`init` calls `nextLabel()` before the coordinator could wire a property.

## 5. The keypad across pages

**Invariant: `focus != nil` means the focused set is on the current page.** `showPage` is the only place that enforces it.

| Event | Keypad | Why it's safe |
| --- | --- | --- |
| Swipe or strip tap | closes | `commitBuffer` runs on every key, so there is nothing to flush. "82." is already stored as 82; `buffer` goes stale but is only read with `focus`, and `edit` reloads it |
| Auto-advance | never reached with an open keypad | `keypadOpen` gives `.stay`. A check closes the keypad first (Focused closes it on any check, the brief's "closes if open"; List keeps `focus?.setID == set.id`) |
| `beginReplace` | closes, `focusBeforeReplace` keeps it | The sheet is hosted above the pages (§8) and holds the exercise id, so a page move under it can't hit the wrong row |
| Replace in place | stays closed, page unchanged | Same row, same set ids |
| Replace, split | closes, page goes to the new row **if it was on X** | X holds only done sets now. On another page it stays |
| Undo | page goes to X, always, then `edit` restores the field | The toast is screen-wide, so Undo can come from any page. Landing on what came back is one rule, and it makes `edit` safe. A keypad open on page C closes first |
| `remove` of the current page | closes, page goes to the neighbour | `showPage` runs before the delete, while `focusedSet` still finds the row |
| `remove` elsewhere | nothing | Reachable only from a stale dialog; focus is on the current page by the invariant |
| `nextField` | stays on the page | In Focused it skips folded warm-ups: `addWarmup` puts them at the highest index, so today's rule would focus a hidden row |

`showPage` doesn't touch `undo`: a page change is no edit, so the window keeps running and the hold stays. The toast lives
above the pages: its `onDisappear` commits, so on a page a swipe would commit the replace.

## 6. The paging container: `TabView(.page)`

**Measured, not guessed.** A throwaway app: 14 pages (8 rows with `SetRow`'s gesture, 8 last-time rows, a vertical
`ScrollView` each), the page in a SwiftData `@Model`, driven by XCUITest drags on a private iPhone 17 Pro simulator,
iOS 27.0, deployment target 17.0.

| Criterion | `TabView(.page)` | Paging `ScrollView`, `LazyHStack`, `.scrollPosition(id:)` |
| --- | --- | --- |
| Relaunch on page 6 | opens there | opens there |
| Insert before current; first moved to end | stays on its page | stays on its page |
| **Current moved to end** | **follows the id** | **shows the neighbour, binding still says the old id**; needs `scrollTo` on an order change (that fixed it) |
| Remove current, then Undo | neighbour, then back | neighbour, then back |
| Jump with Reduce Motion (`withAnimation(nil)`, plain set) | instant, only the target appears | instant, target and both neighbours appear |
| Animated jump over 4 pages | walks through them, 0.3 s | the same |
| Binding writes per programmatic move | 0 | 1 echo |
| Binding writes per swipe | 1 | 1, plus 1 echo on the first drag |
| When a swipe writes | at the 50 % point, finger down, about 1.2 s before the lift in a slow drag | the same |
| 30 % drag, released | no write, springs back | the same |
| Nested vertical scroll, 35° diagonal | inner scrolls, page stays | the same |
| Programmatic move while a finger holds a drag | the program takes over, the drag is lost | the same |
| `DragGesture(10)` on the pager | fires for both axes | the same |
| Pad height change, rotation | page stays | the same |
| Pages' rows in the accessibility tree | **current only** | current and 1 to 2 neighbours (eager `HStack`: all 14) |
| Footprint: start, all pages seen, back at first | 30.6, 35.8, 37.8 MB | 33.1, 41.2, 51.3 MB (eager: 63.4 throughout) |
| Mounted pages after a full pass | 14, then 8 | 7, then 12 |
| `@State` on a page after a round trip | lost | lost (eager keeps it, at double the memory) |

`context.save()` of the page, both containers, n = 58: median 1.0 ms, p95 8.3 ms, max 10.0 ms.

**Choice: `TabView(.page)`.** It wins or ties every row: no reorder fix, no echo, the smaller tree for VoiceOver, less
memory. The plan's fears don't show on iOS 27: it does hold pages (14 after a full pass) but with no cost, and it neither
fights the nested scroll nor shifts its selection.

**Not measured, and the risk that remains:**
- **iOS 17.** Only iOS 27 runtimes are installed, and CI runs the newest runtime only. Both containers carry this risk.
- **VoiceOver itself.** The tree is a proxy; ui-validator runs the checklist (L11).
- **The real store.** The save above is one model; the real file is bigger. If a device hitches at the 50 % point, drop
  the `save()` in `showPage` and save in `pause()` instead.

So `SessionPager.swift` is the only file that knows the container. Its contract is `pages: [UUID]`, `selection: Binding<UUID?>`
and a page builder. Going to the `ScrollView` is that one file plus `scrollTo` on an order change.

```swift
TabView(selection: Binding(get: { controller.pageExerciseID },
                           set: { if let id = $0 { controller.jump(to: id) } })) { … .tag(Optional(ex.id)) }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .simultaneousGesture(DragGesture(minimumDistance: 10).onChanged { _ in controller.userScrolled() })
```

**A swipe writes at 50 %, not at the lift**, on both containers, and iOS 17 has no settle signal for either. So the page
flips, the keypad closes and the strip moves at the halfway point. That is what the eye sees, and a drag back simply
jumps back, at the cost of a second save. Accepted.

**Swipe to delete dies in a pager** (D1 §8 asked). The positive control, the same row with no pager, fired on all 4 drags
and reached the full reveal.

| Row gesture, inside either pager | Row swipe | Page swipe from a row | Vertical scroll from a row |
| --- | --- | --- | --- |
| `simultaneousGesture`, 16 pt (today's) | **0 of 4** | works | as in List (not driven from a row here) |
| `highPriorityGesture`, 16 pt | **0 of 4** | works | not driven |
| `highPriorityGesture`, 5 pt | 4 of 4 | **dead** (left drags; the page stayed) | **dead** (1 drag per container) |

Right drags weren't driven; a 5 pt high-priority gesture claims any drag that starts on the row, so I expect them to die
too. D1's split (left on a row belongs to the row, right pages) isn't available from SwiftUI on iOS 17. A row-level
`UIPanGestureRecognizer` shim could do it; rows fill the page, so it would make paging depend on where the thumb lands, and
it is the kind of layer we don't add. **So in Focused `SetRow(swipeToDelete: false)`: a left swipe pages.** Delete stays
in the row's context menu and the VoiceOver action, with the confirmation. That is a visible loss against List; whether
it needs a visible affordance is D1's call.

## 7. Manual rest start

```swift
/// The idle pill's sheet: rest for `ex`, no set checked. `seconds` is the sheet's value (D1 §4c), else its rest.
func startRest(for ex: LocalSessionExercise, seconds: Int? = nil) {
    rest.start(seconds: seconds ?? ex.restSec, now: .now)
    followRest()
    persistRest(exercise: ex.name)
}
```

`startRest(after:)` keeps its guards and calls this for its last three lines, so a rest has one definition. It sets no
`lastCheckedExercise`, no `setsChecked`, no advance and no `tappedSet` (D1 §2.7: it doesn't change the active set).
`persistRest` writes only `restEndsAt` and `restTotal` and sends the Live Activity; no upload.

- It stays on `.now`, not the clock: the ticker compares `endsAt` with `.now`, and a second time base would break the
  timer. Rest not being on the seam is existing debt, and T3 is not where to pay it.
- `restSec == 0` leaves the timer idle (`RestTimer.start`), so the sheet disables Start at 0:00.
- A later check replaces a manual rest, and a superset's `skipRest` ends it, like any rest.
- No pill and no entry point with no exercises or while `isAllDone` (D1 §2.5), which keeps "no rest after the last set".

## 8. How `SessionView` splits

`SessionView` stays what `RyftApp` presents and keeps everything both layouts share. Only the list part moves, into a
`listContent` computed property, text unchanged, so the diff is a move and List can't change.

```
SessionView (host, unchanged modifiers)            shared
├─ header                                          shared
├─ T1, T2: RestBar (pinned)   T3: List only        RestBar stays for List (L2)
├─ layout == .list    → listContent                moved, unchanged
│  layout == .focused → FocusedSessionView
│     ├─ offline banner, ExerciseStrip
│     ├─ SessionPager → ExercisePage per exercise
│     ├─ SessionToastOverlay                       the same view; a stack row, on the screen, never on a page
│     └─ T3: RestPill
└─ NumberPad                                       shared
   sheets, confirmations, keep-awake, sensory feedback, scene phase: shared, on SessionView
```

| File | Holds | Doesn't hold |
| --- | --- | --- |
| `SessionView.swift` | Header, sheets (add, reorder, plates, history, summary), finish and discard dialogs, keypad, keep-awake, haptics, pause | Anything per page |
| `FocusedSessionView.swift` | Strip + pager + toast + pill, `onChange(advance?.id)`, `pinPage`, VoiceOver focus and announcements, **the per-exercise sheets and the remove dialog** | Layout of a page |
| `SessionPager.swift` | The container and the drag reporter (§6) | Everything else |
| `ExerciseStrip.swift` | Tiles, `+`, long press, the adjustable element, centring | State: reads `pageExerciseID`, writes `jump(to:)` |
| `ExercisePage.swift` | Title, chips, notes, warm-up group, table, Add set, all-done footer, last-time card; its own `ScrollViewReader` for the focused row | Sheets |
| `ExerciseMenuItems.swift` | The `…` items, moved out of `ExerciseCard`, one order for both (ui.md §1) | |
| `RestPill.swift`, `RestSheet.swift` | T3 | |

**Why per-exercise sheets go up a level.** Pages lose their state on a round trip (measured), and the 0.6 s delay can move
the page while a sheet opens. `@State exerciseSheet: ExerciseSheet?` (`.replace(id)`, `.targets(id)`, `.notes(id)`,
`.rest(id)`) on `FocusedSessionView`, reached through closures. `ExerciseCard` keeps its own: List doesn't change.
`SetRow`'s delete dialog stays on the row: losing it to a page change deletes nothing.

**Toast and pill are stack rows, not `safeAreaInset`.** An inset through `TabView` wasn't measured, and height changes
were (the pad): the pager keeps its page. The geometry is D1's; the page just ends above them, so the 64 pt margin in
D1 §2.7 isn't needed.

**Rows.** `SetRow` gets `swipeToDelete: Bool = true` (T1) and `rowState: FocusedRowState? = nil` (T2). One struct: the
gesture, the accessibility actions and the identifiers stay shared, and deleting the nil path later is the removal.
`number` counts working sets in Focused, so `set.<position>.<number>` matches in sessions with no warm-ups, like the
demo plan's.

**`train.sessionLayout`.**

```swift
enum SessionLayout: String { case list, focused }                 // Settings.swift, next to Appearance
var sessionLayout: SessionLayout                                  // didSet writes "train.sessionLayout"
sessionLayout = defaults.string(forKey: "train.sessionLayout").flatMap(SessionLayout.init(rawValue:)) ?? .list
```

`-train.sessionLayout focused` works because launch arguments reach `defaults`, as `-appearance dark` already does. T5
flips `?? .list` and adds the picker. A device preference, like `train.jumpToNext`: it stays on log-out. The coordinator
holds `sessionLayout: @MainActor () -> SessionLayout = { Settings.shared.sessionLayout }`, as it holds `jumpToNext`, and
passes it to `SessionController.init(…, layout:)` as a value, default `.list`, so no existing test or preview changes.
`SessionView` reads `controller.layout`; Observation tracks `Settings`, and there is one owner.

## 9. What could go wrong

| Failure | What happens | Covered by |
| --- | --- | --- |
| **Swipe starts inside the 0.6 s** | A programmatic move with a finger down takes over the drag (measured), so the reporter is not optional: it stamps on the first drag event, the planner says `.stay` | Reporter on the pager; `lastManualScroll` test at 2.9 and 3.1 s |
| **Strip tap inside the 0.6 s** | `jump` stamps; `.stay` at fire time, as the input is built then | Controller test |
| **Swipe during the animated move** | The drag interrupts; the selection write differs from the page; `jump` corrects it | `SessionPager` contract; device run |
| **Echo counted as manual** | The next superset flip would stay. `jump` returns on the same id; `TabView` wrote 0 on programmatic moves | Test: two flips in 3 s |
| **A stale `advance`** | The view performs it on its next update, so a row can go in between; `follow` checks the row exists | Test |
| **Server merge mid-session** | `apply` and `SessionMerge` upsert and never remove, so the page's row can't vanish. New rows append (insert keeps the page, measured); new positions reorder (the page follows the id, measured). A set completed by a copy leaves `activeSet` on its own (derived) | Tests with a 409 fixture |
| **Replace split, then Undo from another page** | Undo lands on X, §5 | Tests, both kinds, with and without focus |
| **Hold + page change** | The page writes nothing the hold cares about; `showPage` never calls `sessionChanged` | The no-upload test, inside an undo window |
| **Session restored after a kill** | Page from the row, or nil pinned on appear. Rest restores as today. `tappedSet`, `expandedWarmups`, `lastCheckedExercise` are gone: groups folded, first open row, "Next:" from the page | Rebuild test: new controller on the same row |
| **Minimise inside the 0.6 s** | The old controller goes (weak `self`), no jump: the reopened screen stays on the finished page. Harmless, one swipe | Accepted |
| **Migrated session, `nil` page** | `resolve`, then `pinPage` | Schema test + rebuild test |
| **Page removed while in List** | The stored id dangles; `resolve` on the next Focused open | Pure tests |
| **Layout changes mid-session** (T5: Profile is reachable, the session is minimisable) | The reopen builds a controller on the new closure. List wrote no page, so the stored one can be stale but valid | Accepted |
| **One exercise** | One page; `.stay` until `.allDone`; strip still shown | Tests |
| **Empty session** | `pageExerciseID` nil, no pager: D1's empty page and `+`. `add` returns the row and `jump` shows it. Removing the last exercise lands here | Tests; `TabView` isn't built with zero pages |
| **Superset flip after each set** | Programmatic, no stamp, instant under Reduce Motion, no rest inside a round (`startRest(after:)`). With the keypad open: `.stay`. VoiceOver focus moves with each flip, after the move | Tests; ui-validator |
| **Superset + a manual swipe** | Swipe to B, check B1 within 3 s: `.stay`, as the brief says. The user swipes back by hand. A cost of the rule | Accepted |
| **Sheet opens inside the 0.6 s** | The page moves under it; the sheet holds the id | Sheets above the pages (§8) |
| **Save at the 50 % point** | Up to 10 ms on the main actor mid-drag (measured, simulator) | Device run; §6 has the fallback |
| **iOS 17 behaves differently** | Unmeasured | `SessionPager` swap; see the open point below |

## 10. Change list

Everything in `Ryft/` unless noted. New files need no project edit (synchronized folders).

**T1, `feat/focused-session-layout`:**
1. `App/Settings.swift`: `SessionLayout`, `sessionLayout`.
2. `Train/Model/LocalSession.swift`: `currentExerciseID`, with a comment saying it is local only.
3. `RyftTests/TrainOutboxSchemaUpgradeTests.swift`: the attribute opens nil, writes and reads.
4. `Features/Train/Session/SessionPage.swift` (new): `resolve`, `neighbour`.
5. `Features/Train/Session/SessionController.swift`: `init(…, layout:)`; `tappedSet`, `expandedWarmups` next to the
   jump-to-next block; `add` returns the row; `remove` calls `showPage` first; the auto-fold in `toggleCheck`.
6. `Features/Train/Session/SessionController+Page.swift` (new): §2, plus `isFolded`, `setWarmups(expanded:for:)`, `addWarmup(to:)`.
7. `Features/Train/Session/SessionController+Advance.swift`: `plannerStates`, used by `advanceStates` and `nextOpenSet`.
8. `Features/Train/Session/SessionController+Replace.swift`: `showPage` in `replace` (split) and `undoReplace`.
9. `Features/Train/TrainCoordinator.swift`: `sessionLayout`, `open()`.
10. `Features/Train/Session/ExerciseCard.swift`: `SetRow.swipeToDelete`; `menuItems` moves to `ExerciseMenuItems.swift` (new).
11. `Features/Train/Session/SessionView.swift`: `listContent`, the switch, a `SessionActions` value for the shared sheets.
12. New in `Features/Train/Session/`: `SessionPager.swift`, `ExerciseStrip.swift`, `ExercisePage.swift`,
    `FocusedSessionView.swift`, with Previews dark and light.
13. `RyftTests/SessionPageTests.swift` (new), `RyftTests/SessionFocusedPageTests.swift` (new),
    `RyftUITests/FocusedSessionUITests.swift` (new, `-train.sessionLayout focused`).

**T2, `feat/focused-active-set`:**
1. `Features/Train/Session/SessionPage.swift`: `activeSet`.
2. `Features/Train/Session/SessionController+Page.swift`: `activeSet(in:)`, `activate(_:)`.
3. `Features/Train/Session/SessionController.swift`: in `toggleCheck` the override and Focused's keypad close; in `edit` the
   override; in `nextField` skip folded warm-ups; in `nextLabel` Focused's numbering and the warm-up key.
4. `Features/Train/Session/SessionController+Advance.swift`: the row swap in `nextOpenSet`; `nextUp`'s page fallback.
5. `Features/Train/Session/ExerciseCard.swift`: `SetRow.rowState`.
6. `Features/Train/Session/FocusedSessionView.swift`: `onChange(advance?.id)` → `follow`, VoiceOver focus, the announcements.
7. `Features/Train/Session/ExercisePage.swift`: row states, `AllSetsDoneCard` footer, scroll to the footer on `.allDone`.
8. `RyftTests/SessionActiveSetTests.swift` (new), `RyftTests/SessionFocusedAdvanceTests.swift` (new);
   `RyftUITests/FocusedSessionUITests.swift` gets the auto-advance run.
9. `Resources/Localizable.xcstrings`: the warm-up "Next:" key, en and de.

**T3, `feat/focused-rest-pill`:**
1. `Features/Train/Session/SessionController.swift`: `startRest(for:seconds:)`; `startRest(after:)` calls it.
2. `Features/Train/Session/RestPill.swift`, `RestSheet.swift` (new), reusing `RestBar.nextLine`, previews dark and light.
3. `Features/Train/Session/SessionView.swift`: the `RestBar` block goes under `layout == .list`.
4. `Features/Train/Session/FocusedSessionView.swift`: the pill row; `ExercisePage.swift`: the Rest chip's sheet.
5. `RyftTests/SessionManualRestTests.swift` (new); the UI test's pill step.
6. `Resources/Localizable.xcstrings`.

## Test strategy

Everything with `TestClock` and `TrainStore(inMemory:)`, `layout: .focused`, as in `SessionAutoAdvanceTests`.

- **Pure tables:** `resolve` (present, nil, gone, all done, empty), `neighbour`, `activeSet` (every row of L6 and §3).
- **No upload:** after `jump`, `follow`, `pinPage`, folding and `startRest(for:)`, `updatedAt` and `pendingOps()` are unchanged,
  inside an undo window too.
- **The window:** a stay at 2.9 s and a move at 3.1 s after `jump`; `follow` doesn't stamp; two superset flips inside 3 s.
- **Rebuild:** a new controller on the same session lands on the page; folded and without an override.
- **Replace and Undo:** split moves the page only if it was on X; Undo from another page lands on X with its focus back.
- **Remove:** the neighbour in the middle and at the end; the last one gives nil; focus closes.
- **`nextLabel`:** folded warm-up skipped; expanded named; working numbering; a tapped row named.
- **List is untouched:** with the default `layout`, `nextLabel`, `currentSetID` and `advanceStates` match, warm-ups included;
  `showPage` writes nothing. The existing `SessionNextUpTests`, `SessionAutoAdvanceTests` and `SessionReplaceTests` run unchanged.
- **Manual rest:** the rest runs and `restEndsAt` is set; no check counted, no advance, no `tappedSet`, no outbox entry.

## Open points

- **iOS 17 (needs the user).** No iOS 17 runtime here or in CI, so the pager has no run on the deployment target. T1 needs
  one run on iOS 17 (a device, or a runtime the user installs) of: restore, swipe, jump, reorder, remove, Undo. Otherwise it
  goes in `docs/STATUS.md` as unverified. I'd do it before the flip in T5, not after.
- **L5 against `app/CLAUDE.md`.** The rule there is "ships dark behind a remote flag (`GET /v1/config`)". L5 ships it dark
  behind a compiled default, so the design is fine until T5, but the flip has no remote way back; only the picker. If the
  lead wants one, it's one line: the coordinator's `sessionLayout` closure can ask a `FeatureFlag`. Nothing else moves.
- **D1 §3.1, the check on an empty active row** (asked of this note, the lead decides). Feasible without touching
  `toggleCheck`: a small `checkActive(_:in:)` in T2 opens the keypad on the first empty field when the row has no value and
  no ghost, for `.weight` and `.bodyweight` only; time and distance rows have no field to open until T6. The VoiceOver
  "Check off" action stays `toggleCheck`.
- **D1 to change:** §2.5, §5.3 and §8 on swipe to delete (§6 here). §3.1 row 6: an unchecked set is active, whatever its
  position (brief; L6, an uncheck is a tap). §2.7: the 64 pt margin goes (§8 here).
- **Found on the way, left alone so List doesn't change:** `remove` leaves `focus` set when the keypad is on that exercise, so
  in List the pad stays up with a dead target. `focusBeforeReplace` survives a cancelled sheet; Undo's `x.sets` lookup
  makes that harmless.
