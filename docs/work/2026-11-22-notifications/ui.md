# Notifications: UI and copy (N1)

Ticket N1 of `plan.md`. Contract: `design.md` §1 (kinds K1–K7, hint H, row states, content rules), §4 journal, §5
not syncing, §7 categories and taps, §8 preferences; ADR 0024; NT1 in `docs/API_REQUESTS.md`. Written against the
current page (`NotificationSettingsView`, `NotificationSettingsViewModel`), Bedtime & wake's reminder rows
(`SleepPlannerView`), Devices & sync, and Today's `SyncStatusLineView`. Spec only: no Swift here. The ios-developer
builds it in N4; the sync-engineer takes the notification texts of §5 for N3; the localization-editor checks all copy.

Drafts (HTML with the Nocturne tokens, system font as a stand-in for Satoshi; they show hierarchy and copy, not pixels):
`shots/draft-a.png` (allowed: server route, no habits, quiet-hours note), `shots/draft-b.png` (denied + rolling out, not
asked, rolling out), `shots/draft-c.png` (lock screen, Devices & sync hint, Today line). Sources: `shots/mock-*.html`.

The app is dark only (ADR 0016). "Dark and light" in the role brief is answered by dark only; every preview is dark.

**Conventions of this file.** Every number-and-unit pair in a string below (and `%` after a number) is joined by a real
no-break space, U+00A0, which looks like a plain space here; where the string is a format, the same applies to its
`%lld` and `%@` neighbours. House style for the catalog is the English text as the key, so the "Id" column is a handle
for this spec and for the string's `comment:`; the notification texts of §5 get symbolic keys (like the server's
`loc-key`s), so a future extension or the platform can share them.

**Times and plurals.** A clock time in a string is never typed. It is a `%@` filled with `Date.FormatStyle(date: .omitted, time: .shortened)` (the chip's own format), so it reads "9:00 PM" or "21:00" by locale. The space before AM/PM is the locale's own: U+202F NARROW NO-BREAK SPACE (checked with Foundation, en_US). The app neither adds nor replaces it. A spoken number that varies takes a plural (§2.6).

---

## 0. What changes, and why (read this first)

| # | Change | Reason |
| --- | --- | --- |
| 1 | The page has five groups: **Morning, Training, Sleep, Sync, Quiet hours**. It keeps its scaffold (`SubpageScaffold`, one `PushedHeader`, `GroupedCard`s, the pinned bar, `InlineMessage` notices). | The brief; `plan.md` decision 1. Nothing new is invented in the component set. |
| 2 | **Permission is the page's, not the flag's.** The permission notice and the pinned Allow or Open Settings show in every mode, because local rows (journal, bedtime, not syncing) need iOS permission whether or not `push.enabled` is on. | Lead decision 2: local kinds don't wait for the flag. |
| 3 | **Rolling out is per row.** The old page hid every switch and listed four read-only rows under "You'll get". Now only server rows (K1, K3, K4, K5) are read-only, each with the trailing value "Rolling out". K2 and K7 are live. The notice above says so ("Some notifications are being rolled out"). | A page-wide "rolling out" would now be false: three kinds work. |
| 4 | **Renames:** K4 "Workout scored" becomes **"Strength session scored"**; K7 "No new data" becomes **"Not syncing"**. K1 keeps "Morning score" (design.md calls it "Your day is ready"; see §10, conflict 1). | K3 (Activity scored) is a workout too, and two rows with "workout" in their name can't be told apart. K7 now also covers a phone that can't sync, which "No new data" doesn't describe. |
| 5 | **Quiet hours' sentence is rewritten.** "Nothing arrives in this window; the morning score waits until it ends." is no longer true: the journal reminder waits, workout alerts are skipped, and bedtime and wake are exempt. | ADR 0024 §4 says the page has to say this in one line. |
| 6 | Everything else stays where it is: group order of the old page (categories, then quiet hours), the From and Until chips, the pinned bar, the failure notice under its group, the 35 % rule while a save is in flight (server rows only, see §2.9). | No reason to move it. |

---

## 1. The page

### 1.1 Purpose and hierarchy

**Purpose:** choose what RYFT may tell the user, and when not to. **The eye sees:**
1. the **notice** if there is one (permission, then rollout), because it explains why a switch below may do nothing;
2. the **Morning** group's first switch and the reminder's time chip (the one thing here that is a number);
3. the rest as a scannable list: group title, row title, one grey sentence.

One accent per screen: there is none on this page. Switches are `.ryft` (ink), chips are `surfaceRaised` capsules, the only
colour is `warning` on the glyph of a notice where the user has something to fix (§4, H refreshOff). Teal stays with the
recovery score (L27).

### 1.2 Structure (top to bottom)

```
PushedHeader "Notifications"                        (SubpageScaffold, as today)
[notice: permission]        only notAsked or denied
[notice: rollout]           only while push.enabled is off
Morning                     GroupTitle
  Morning score             K1   switch | "Rolling out"
  Journal reminder          K2   switch            (hidden: journal not live)
  Remind me at   9:00 AM    K2's time row          (only while K2 is on)
  [note row]                K2: noHabits or quiet-hours move
Training
  Activity scored           K3   switch | "Rolling out"   (hidden until the key exists)
  Strength session scored   K4   switch | "Rolling out"
  Records                   K5   switch | "Rolling out"
Sleep                                                (hidden while sleep.planner is off)
  Bedtime reminder  30 min >   K6  link row to Bedtime & wake
Sync
  Not syncing               K7   switch (live in every mode)
  footer
Quiet hours
  Pause at night            switch
  From / Until              chips (only while on)
  footer
[failure notice]            under its group, as today
pinned bar                  "Allow notifications" | "Open Settings" | none
```

Group spacing is `GroupedListSpec.groupSpacing` (18), as today. A group whose rows are all hidden is not drawn, title
included (Sleep, and Morning is never empty because K1 is always there).

### 1.3 Page-level states

Three permission states, which decide the notice and the pinned bar; independent of rollout (a fourth axis, §1.4).
"Allowed" means iOS authorization is `authorized`. `provisional` counts as **not asked**, as Bedtime & wake does
(design.md §1.2): the page asks again, and the pinned button says so.

| State | Trigger | Notice (top) | Pinned bar | Switches |
| --- | --- | --- | --- | --- |
| **notAsked** | iOS status `notDetermined` or `provisional` | `InlineMessage`, `bell`, neutral, `readsAsOne`, `announces: false`: "RYFT hasn't asked to send notifications yet." Caption (new): "Nothing below reaches you until you allow it." | `PillButton` "Allow notifications" (`bell`), calls `model.allow()` | Live, choices kept. Turning a **local** row on (K2, K7) from off also asks iOS (same call as the pinned button) after it stores the choice; refused, the page becomes denied and the choice stays on. |
| **denied** | iOS status `denied` | `bell.slash`: "Notifications are off in iOS Settings". Caption (as today): "Your choices below are kept for when you turn notifications back on." | `PillButton` "Open Settings" (link-out glyph) to `UIApplication.openNotificationSettingsURLString` | Live, choices kept. No per-row refusal: the notice is the one reason, and nothing arrives until the user allows. |
| **allowed** | `authorized` | none | none | Live |

Both permission notices keep today's identifiers (`notifications.notAsked`, `notifications.denied`, `notifications.allow`,
`notifications.openSettings`). The notice never has a button of its own: the pinned bar is the page's one action.

### 1.4 Rollout (a separate axis from permission)

`push.enabled` off for the account:

- Notice, `bell`, neutral, `readsAsOne`, `announces: false`: **"Some notifications are being rolled out"**. Caption:
  **"Rows that say Rolling out get a switch when they reach your account. The others work now."**
  It sits under the permission notice when both show (permission blocks everything, so it goes first).
- K1, K3, K4, K5 become `GroupedRow.value` rows (title, detail as today, trailing value **"Rolling out"** in
  `textTertiary`), not interactive, VoiceOver reads "Morning score, Rolling out" and then the detail. No switch is drawn, so
  nothing looks on while nothing can be sent. The stored choices are kept and shown again once the flag arrives
  (`FlagStore.applyPending` when the page appears, as today).
- K2, K6, K7 and Quiet hours are unaffected. (Quiet hours is a server preference, but `PATCH /v1/me/notifications` works
  whatever the flag, as K7's switch already relies on.)

### 1.5 Row state matrix

| Row | rolling out | notAsked | denied | allowed | other states |
| --- | --- | --- | --- | --- | --- |
| K1 Morning score | read-only, "Rolling out" | switch | switch | switch | |
| K2 Journal reminder | never | switch | switch | switch | off (no time row); `noHabits`; time in quiet hours; **hidden** while the journal isn't live (also while `availability == .unknown`: no placeholder, it appears with the fade of §7) |
| K3 Activity scored | read-only, "Rolling out" | switch | switch | switch | **hidden** until `ACTIVITY_SCORED` is a key in the cached `categories` |
| K4 Strength session scored | read-only | switch | switch | switch | |
| K5 Records | read-only | switch | switch | switch | |
| K6 Bedtime reminder | never | link row | link row | link row | values Off, "30 min", Waiting; **hidden** while `sleep.planner` is off |
| K7 Not syncing | switch, live | switch | switch | switch | detail by route: `.server`, `.thisIPhone`, `.off` |
| Quiet hours | switch, chips | same | same | same | |

K6 is a link row to a page that has its own permission handling (its own refused notice), so on this page it says nothing
about iOS: the page notice covers it.

---

## 2. Rows

All rows are `GroupedRow`s in `GroupedCard`s. Row title 15 pt `textPrimary`, detail 12 pt `textTertiary`, never truncated,
the row grows (`GroupedListSpec`). Strings are final English drafts; ids are handles (§ conventions).

### 2.1 K1 Morning score (server)

| Id | Text |
| --- | --- |
| `notifications.k1.title` (exists) | Morning score |
| `notifications.k1.detail` (exists, kept) | When today's recovery is scored after a night's sleep, once a day. |
| `notifications.rollingOut.value` (new, shared by K1, K3, K4, K5) | Rolling out |

States: switch (`GroupedRow.toggle`, identifier `notifications.MORNING_SCORE`), or the read-only value row while rolling out.

### 2.2 K2 Journal reminder (local)

Switch row, then, while it is on, **the time row** (§3), then at most one note row.

| Id | Text | When |
| --- | --- | --- |
| `notifications.k2.title` | Journal reminder | always |
| `notifications.k2.detail` | Asks about yesterday, if you haven't answered yet. | always (the time is in the row below, not repeated here) |
| `notifications.k2.timeLabel` | Remind me at | time row's label |
| `notifications.k2.noHabits` | No habits chosen yet, so nothing is sent. | **noHabits**: switch on, `enabledBehaviors` empty. Neutral note row (glyph `checklist`), as Bedtime & wake's `ScheduleNoticeRow` with the link below it |
| `notifications.k2.noHabits.action` | Choose habits | link under the note; pushes Profile → Journal (`ProfileRoute.journal`); hint "Opens the Journal page in Profile" (exists in `JournalViews`: reuse the string unchanged) |
| `notifications.k2.quiet` | Quiet hours end at %@, so it arrives then. | the chosen time is inside quiet hours; `%@` the window's end (the locale's time: "7:00 AM" in en_US, "07:00" in 24-hour locales; the space comes from the locale, §0 conventions). Neutral note row, glyph `moon`. Not shown with `noHabits` (nothing would arrive) |

- `noHabits` keeps the switch and the time row: a preference the user may set before choosing habits; the note says why
  nothing is sent. Choosing habits starts the reminder with no further step.
- **Off:** the switch is off, the time row and notes are gone, nothing else changes.
- **Not live:** the whole row, its time row and notes are absent. There is no placeholder: the journal isn't something this
  account has, so there is nothing to explain on this page.
- **notAsked, denied:** the row looks as in allowed; the page notice and pinned bar are the reason and the action (§1.3).
- The switch writes `JournalReminderSettings` at once (no network, no pending state, never disabled by a server save in flight).

### 2.3 K3 Activity scored (server, hidden until the key exists)

| Id | Text |
| --- | --- |
| `notifications.k3.title` | Activity scored |
| `notifications.k3.detail` | When a workout from Apple Health, such as one from your watch, is scored. Up to three a day. |

NT1's rules in one sentence: a workout synced from Apple Health, scored, not during quiet hours (skipped), at most three
a day. Switch identifier `notifications.ACTIVITY_SCORED`. Never PATCHed before the key exists (NT1), so the row is absent,
not disabled, before then.

### 2.4 K4 Strength session scored (server)

| Id | Text |
| --- | --- |
| `notifications.k4.title` (renamed from "Workout scored") | Strength session scored |
| `notifications.k4.detail` (exists, kept) | When a logged strength session is scored, the first one each day. |

### 2.5 K5 Records (server)

| Id | Text |
| --- | --- |
| `notifications.k5.title` (exists) | Records |
| `notifications.k5.detail` (changed: names K4's new title) | When a session sets a record, if Strength session scored is off. |

### 2.6 K6 Bedtime reminder (local, set in Bedtime & wake)

A link row (`GroupedRow.push(…, route:)` to Bedtime & wake, the same destination Profile's row opens), chevron, trailing
**value** short, **detail** the sentence. This splits design.md's value strings in two so the trailing value never squeezes
the title (a 21-character value beside a 16-character title wraps both at 390 pt) and the number stays the eye's first
stop (draft-a, A1).

| State | Trigger | Value | Detail | VoiceOver value (spoken, whole) |
| --- | --- | --- | --- | --- |
| Off | no schedule, or `reminderOn` false | Off | Turn it on in Bedtime & wake. | Off |
| On | `reminderOn`, plan known | 30 min (`windDownMin`) | Before bedtime. Change it in Bedtime & wake. | 30 minutes before bedtime |
| Waiting | `reminderOn` and `BedtimePlanner.remindersWaiting` | Waiting | Reminders resume once RYFT has tonight's plan. (exists in Bedtime & wake: reuse) | Waiting for tonight's plan |
| Hidden | `sleep.planner` off | – | – | – |

| Id | Text |
| --- | --- |
| `notifications.k6.title` | Bedtime reminder (exists: reuse) |
| `notifications.k6.off` | Off (exists: reuse) |
| `notifications.k6.off.detail` | Turn it on in Bedtime & wake. (new) |
| `notifications.k6.on.value` | %lld min (new key; the existing key with the same text has a plain space, not touched here) |
| `notifications.k6.on.detail` | Before bedtime. Change it in Bedtime & wake. |
| `notifications.k6.on.spoken` | VoiceOver value, plural: one "%lld minute before bedtime", other "%lld minutes before bedtime" (new) |
| `notifications.k6.waiting` | Waiting (exists: reuse) |
| `notifications.k6.waiting.detail` | Reminders resume once RYFT has tonight's plan. (exists: reuse) |
| `notifications.k6.waiting.spoken` | Waiting for tonight's plan (new, VoiceOver value) |
| `notifications.k6.hint` | Opens Bedtime & wake (new) |

The spoken value differs from the visible one (design.md's "N min before bedtime", "Waiting for tonight's plan"), so N4
needs `.accessibilityValue` on this row; `GroupedRow.push` reads value then detail by default, which is also acceptable
("30 min, Before bedtime. Change it in Bedtime & wake") and is the fallback if the override is not worth a parameter.
The wake-up alarm has no row here (design.md §1.1); Bedtime & wake owns it.

### 2.7 K7 Not syncing (server and local, one switch)

| Id | Text | Route |
| --- | --- | --- |
| `notifications.k7.title` (renamed from "No new data") | Not syncing | all |
| `notifications.k7.detail.server` (changed: the two hours are locale-formatted) | When no heart rate or steps arrived for 20 hours, between %@ and %@. | `.server` |
| `notifications.k7.detail.thisIPhone` | When RYFT couldn't sync for 20 hours, between %@ and %@. | `.thisIPhone` |
| `notifications.k7.detail.off` | You won't be told when syncing stops. | `.off` (the switch is off) |
| `notifications.k7.footer` | Closing RYFT from the app switcher can stop background sync until you open it again. | group footer, always |

- The switch is `categories.SYNC_STALE`; one switch for both paths (ADR 0024 §5). The detail follows
  `SyncStaleRoute`; the user never chooses a route and the page never names "server" or "this iPhone".
- Live in every mode (rolling out included).
- The footer is the page's one line about force-quit. It says the cause in the user's words ("the app switcher"), not iOS
  jargon, and matches the local notification's body (§5.2) so the page and the notification explain the same thing.
- The two hours follow the clock setting (lead decision, 2026-11-22). The key carries them as `%@` and `%@`: the window's start and end on the user's calendar, each formatted with `Date.FormatStyle(date: .omitted, time: .shortened)`. That reads "9:00 AM" and "9:00 PM" in en_US and "09:00" and "21:00" in 24-hour locales. Sequential `%@`s, as `String(localized:)` writes two interpolations; English is the only language, so no argument order changes. The window is the platform's rule, not a time the user set, so it is shown in the user's clock, not the platform's.

### 2.8 Quiet hours

| Id | Text |
| --- | --- |
| `notifications.quiet.title` (exists) | Quiet hours (group title) |
| `notifications.quiet.row` (exists) | Pause at night |
| `notifications.quiet.detail` (changed: "Nothing arrives" was not true, since bedtime and the wake alarm still come) | The morning score and the journal reminder wait until quiet hours end. Workout alerts are skipped. |
| `notifications.quiet.from`, `.until` (exist) | From · Until |
| `notifications.quiet.footer` (changed, adds the second sentence) | Times are local. Equal From and Until turn quiet hours off; a From later than Until spans midnight. The bedtime reminder and the wake-up alarm still come at their times. |

From and Until stay `ValueChipRow(role: .row)` with the system compact picker (1-minute steps: the platform takes any
`HH:MM`), disabled at 35 % while a save is in flight, as today. "Not syncing" is not listed: it only fires between 09:00
and 21:00 anyway.

### 2.9 In-flight and failure (unchanged, scoped)

The 35 % and disabled rule while a PATCH is on its way applies to **server** rows, the quiet-hours switch and its chips.
K2's switch and time chip, K6 and the permission controls never wait for it. A refused or offline change goes back and the
notice goes under its group, as today (`notice(failure)`); there is no new failure copy.

---

## 3. The journal reminder's time row

**Row:** `ValueChipRow(Text("Remind me at"), role: .row)` holding one `ValueChip(…, date:, displayedComponents: .hourAndMinute)`,
inside the Morning card directly under K2, drawn only while K2 is on. This is the pattern of Quiet hours' From and Until
and Bedtime & wake's days, so there is nothing new to learn.

- **Default 09:00.** The chip shows it in the locale's clock: "9:00 AM" or "09:00". Stored as minutes after midnight
  (540); a reset account shows 09:00 again.
- **Steps of 15 minutes.** The picker offers :00, :15, :30, :45 only.
  - **Problem:** SwiftUI's `DatePicker` has no minute interval, so today's `ValueChip` can't do it. Use a `UIDatePicker`
    (`.compact`, `datePickerMode = .time`, `minuteInterval = 15`) behind the chip in a `UIViewRepresentable`, with the same
    trick as `ValueChip`: transparent (`colorMultiply(.clear)`), as big as the chip, tinted `textPrimary`, labelled by the
    row's title. This is a new parameter of `ValueChip` (`minuteInterval: Int = 1`; the existing callers are unchanged), in
    `Design/FormField.swift`, with dark and AX3 previews.
  - **Fallback** if the compact UIKit picker misbehaves in a presented popover: a medium sheet (`SheetFrame`, grabber, the
    sheet header "Remind me at", a wheel with `minuteInterval = 15`, "Done" in the header). Same value, same row. Do **not**
    ship the SwiftUI picker with a snap-to-15 after the fact: the wheel would show 9:07 and then jump.
- **Saved as it changes**, no Save button, no network, no pending state (design.md §8). The scheduler follows (debounced).
- A stored value off the 15-minute grid (cannot be produced by this picker) is shown as stored; the next edit snaps.
- **In quiet hours** the note row `notifications.k2.quiet` appears under the chip (§2.2). It is a sentence, not a warning:
  nothing is wrong, the reminder simply arrives later.
- At AX1 and above the label goes above the chip (`ValueChipRow` does this itself).

---

## 4. The hint H

### 4.1 Devices & sync (the full hint)

**Where:** `DevicesAndSyncView`, a notice at the **top of the page**, above "Your trackers", 18 below it to the first group
(the page's other notices live at the top too). It exists only while it holds: no placeholder, no "all good" line. One notice
at a time; precedence `refreshOff`, then `restricted`, then `lowPower`. Same in all placements (pushed, sheet).

`InlineMessage`, `announces: false` (it is part of the page), `readsAsOne: false` (its action must stay reachable),
identifier `devices.background`.

| State | Trigger (`BackgroundAvailability`) | Glyph · severity | Message | Caption | Action |
| --- | --- | --- | --- | --- | --- |
| **refreshOff** | `refreshStatus == .denied` | `arrow.triangle.2.circlepath` · **attention** (`warning`: the user can fix it) | Background App Refresh is off for RYFT | RYFT may not sync while it's closed. Turn it on in iOS Settings, or open RYFT to sync. | text link **Open Settings** to `UIApplication.openSettingsURLString` (the app's page, where the switch is); `InlineMessage.action` |
| **restricted** | `refreshStatus == .restricted` | same glyph · neutral | Background App Refresh is restricted on this iPhone | Screen Time or a device profile limits it, so RYFT may not sync while it's closed. Open RYFT to sync. | none (the user can't change it from here) |
| **lowPower** | `isLowPowerMode` and refresh otherwise `.available` (design.md §5.3; device check D2) | `battery.25percent` · neutral | Low Power Mode is on | iOS pauses background refresh while it's on, so RYFT may sync less often. Background refresh resumes when you turn Low Power Mode off. | none; transient |
| **none** | everything available | nothing is drawn | | | |

| Ids | |
| --- | --- |
| `devices.hint.refreshOff`, `.refreshOff.caption`, `.openSettings` | the three strings above ("Open Settings" exists: reuse) |
| `devices.hint.restricted`, `.restricted.caption` | |
| `devices.hint.lowPower`, `.lowPower.caption` | |

"May not sync", not "can't": whether HealthKit background delivery still wakes the app with refresh off is not known
(design.md §5.4, device check D3), and the copy must stay true either way. It says what the user can do (turn it on, or open
RYFT) and never blames them.

- Returning from iOS Settings: `BackgroundAvailability` is observable; the notice fades out when refresh turns on (§7).
- Sheet placement (Devices & sync opened from Today): same notice under the sheet header.
- Low Power Mode needs no action and is gone as soon as it is off; no announcement.

### 4.2 Today (a line inside the existing sync status, and nothing else)

**Which view:** `SyncStatusLineView`, drawn by `TodayView.intro(_:)` (`Ryft/Features/Today/TodayView.swift`, under the
sub-line, when `model.hasDataSource`), whose line comes from `TodayViewModel.syncLine` → `TodayStates.line(…)`
(`TodayViewModel.swift`). No card, no banner, no second row.

**Rule.** A new `SyncLine` case (suggested name `.backgroundOff(since: Date, restricted: Bool)`) replaces the idle
`.upToDate` line when **all** hold: H is `refreshOff` or `restricted` (never `lowPower`); `Settings.lastSync` is more than 20 h
old (not nil: before a first sync Today has its own states); and no higher line applies (`actionNeeded`, `issue`,
`offline`, `paused`, `stale`, `waitingForUnlock` and the active lines keep priority: the cause that is happening now wins).

| Id | Text |
| --- | --- |
| `today.syncLine.backgroundOff` | Last sync %@ · Background App Refresh is off |
| `today.syncLine.backgroundRestricted` | Last sync %@ · Background App Refresh is restricted |

`%@` is `SyncLine.dataTime` ("Yesterday 14:05", "Tue 14:05", then the date), never relative, so "stale data shows its date".
Glyph `clock` (as `.stale`), 12 pt caption, `textSecondary` (it needs a look, like `.issue`/`.stale`, not `warning`).

**Tap:** Devices & sync as a sheet (`DevicesAndSyncView(placement: .sheet)`, the page that holds H and its Open Settings),
as the calibration note's Devices & sync link does (`CalibrationLinkSheet`); not Sync details. VoiceOver: "Last sync Tue 14:05. Background App Refresh is off.", hint "Opens Devices & sync". The line goes at once when the condition stops
holding (a sync lands, or the user turns refresh on).

**Be honest about how rare this is (see §10, call 1).** Today starts a sync when it opens, so "last sync over 20 h" holds
only while that first sync hasn't finished, or when it can't run. The first case is covered (an active line outranks this
one), so the line shows in practice when the app is open, the phone is online and unlocked but the upload didn't happen, which
is exactly when the user should be told why. It is the one place Today says anything about this, and it never becomes
permanent. If it proves noisy or empty in the beta, drop the line; Devices & sync and the notifications carry the hint.

---

## 5. The copy of each notification

All English only. Titles carry no health value and no habit name. Health values appear only where they already do (K1,
K4, K5, K3's strain, K6's need), in the body, which iOS hides with previews off. The platform's `MORNING_SCORE_TITLE` carries the score in its title: see §10, call 4. Every body puts what matters first (the
lock screen collapses to about two lines). No other wearable brand's name or vocabulary. No count of hours in a text built when the request is scheduled ("X hours ago", "20 hours"): it can fire many hours later (quiet hours, the 1 h hysteresis), so a fixed number would be wrong. "Yesterday" in the journal's title is right, because its request is keyed to the day it asks about (§5.1). "About three days" (§5.2) is the only other count, and it holds from 72 h on.

### 5.1 Local: journal reminder (`JOURNAL_REMINDER`)

| Key | Text |
| --- | --- |
| `JOURNAL_REMINDER_TITLE` | How was yesterday? |
| `JOURNAL_REMINDER_BODY` | A few taps, and RYFT shows how your habits change the morning after. |

The title is the question Today's journal card already asks and the body is that card's sentence ("A few taps, and RYFT
shows how your habits change the morning after."): one voice, and no habit name or value anywhere. "Yesterday" is always
right: the id is keyed by the asked day, it fires the morning after, and a quiet-hours move only slides it within that day.
Delivered ones from earlier days must not linger (note for N3, §10).

### 5.2 Local: not syncing (`SYNC_STALE`, local path)

| Key | When | Text |
| --- | --- | --- |
| `SYNC_STALE_LOCAL_1_TITLE` | `sync.stale.1`, 20 h after the last sync, 09:00–21:00 | Your data hasn't synced |
| `SYNC_STALE_LOCAL_1_BODY` | | Open RYFT to bring it up to date. Closing RYFT from the app switcher can stop background sync. |
| `SYNC_STALE_LOCAL_2_TITLE` | `sync.stale.2`, 72 h | Your data is still behind |
| `SYNC_STALE_LOCAL_2_BODY` | | It's been about three days since RYFT last synced. Open RYFT to catch up on your scores. |

No hour count and no clock time: `.1` can fire 19 h to about 30 h after the last sync, and `.2` 71 h or more, so "about
three days" is the only number that is always true. The titles do not repeat the app name (iOS prints it above) and differ
from the platform's own `SYNC_STALE_TITLE` ("No new data"): that one is about data from the watch not arriving, this one is
about RYFT itself not having synced; the user never gets both for one gap (ADR 0024 §5.2).

### 5.3 Local: bedtime (`BEDTIME`), unchanged

| Text | |
| --- | --- |
| Title | Wind down |
| Body | In bed by %@ for your full %@. / In bed by %@ for %lld % of your need: %@. |

Exactly as `BedtimePlanner` writes it today (its `%` already has the no-break space). Not touched.

### 5.4 Server: quoted from NT1 for K3 (`ACTIVITY_SCORED`)

| Key | en |
| --- | --- |
| `ACTIVITY_SCORED_TITLE` | %@ scored |
| `ACTIVITY_SCORED_TITLE_UNTITLED` | Activity scored |
| `ACTIVITY_SCORED_BODY` | Strain %1$@ · %2$@ |

Examples: "Run scored", "Strain 12.8 · 56 min". Decided by the lead (§10, call 3; NT1 in `API_REQUESTS.md` now says it): the untitled title is "Activity scored", not `SESSION_SCORED_TITLE_UNTITLED`'s "Workout scored", so K3 and K4 read differently on the lock screen. The duration argument carries U+00A0 before "min" and "h". The other server texts (`MORNING_SCORE_*`, `SESSION_SCORED_*`, `PR_*`,
`SYNC_STALE_*`) are API.md's and are not changed here.

### 5.5 Placeholders (`hiddenPreviewsBodyPlaceholder`), every category

With previews hidden iOS shows neither title nor body, only this text under the app name (design.md §1.3, correcting plan.md
decision 6), so each one must make sense alone, say what kind it is, and carry no value, name or number. No category sets
`.hiddenPreviewsShowTitle`.

| Category | Key | Text |
| --- | --- | --- |
| `MORNING_SCORE` | `HIDDEN_PREVIEW_MORNING_SCORE` | Your morning score is ready |
| `ACTIVITY_SCORED` | `HIDDEN_PREVIEW_ACTIVITY_SCORED` | Activity scored |
| `SESSION_SCORED` | `HIDDEN_PREVIEW_SESSION_SCORED` | Strength session scored |
| `PR` | `HIDDEN_PREVIEW_PR` | New record |
| `SYNC_STALE` (both paths) | `HIDDEN_PREVIEW_SYNC_STALE` | Your data may be behind |
| `JOURNAL_REMINDER` | `HIDDEN_PREVIEW_JOURNAL_REMINDER` | Journal reminder |
| `BEDTIME` | exists: "Bedtime reminder" | Bedtime reminder (unchanged) |

`ACTIVITY_SCORED` is registered with the others now (design.md §6), so its placeholder ships before the platform sends it.
A test worth having (N5): every placeholder, and every local title, contains no digit.

### 5.6 Taps, actions, presentation

No actions on any category (design.md §7.1: the tap already does the one thing each kind is for). Nothing to word. Local
`SYNC_STALE` is not shown while RYFT is open (it is moved), so its text is never read over the app.

---

## 6. Copy index (page and hints)

New or changed strings only; unchanged ones keep their catalog entries. "Exists" = already in `Localizable.xcstrings`.

| Id | Text | Status |
| --- | --- | --- |
| `notifications.notAsked.caption` | Nothing below reaches you until you allow it. | new |
| `notifications.rollingOut.message` | Some notifications are being rolled out | changed ("Notifications are being rolled out") |
| `notifications.rollingOut.caption` | Rows that say Rolling out get a switch when they reach your account. The others work now. | changed ("We'll let you know here when notifications reach your account.") |
| `notifications.rollingOut.value` | Rolling out | new |
| `notifications.group.morning` · `.training` · `.sleep` · `.sync` | Morning · Training · Sleep · Sync | Morning and Sync new; Training and Sleep exist (reuse). "Notify me about" and "You'll get" go |
| `notifications.k2.*` | §2.2 | new |
| `notifications.k3.*` | §2.3 | new |
| `notifications.k4.title` | Strength session scored | new key; the row title "Workout scored" goes |
| `notifications.k5.detail` | When a session sets a record, if Strength session scored is off. | changed |
| `notifications.k6.*` | §2.6 | new |
| `notifications.k7.title`, `.detail.thisIPhone`, `.detail.off`, `.footer` | §2.7 | new; title renamed ("No new data" row title goes). `.detail.server` changed (the two hours) |
| `notifications.quiet.detail`, `.footer` | §2.8 | changed |
| `devices.hint.*` | §4.1 | new |
| `today.syncLine.backgroundOff`, `.backgroundRestricted` | §4.2 | new |
| `JOURNAL_REMINDER_*`, `SYNC_STALE_LOCAL_*`, `HIDDEN_PREVIEW_*` | §5 | new |

Reused as they are (same English, so the same text): "Choose habits", "Opens the Journal page in Profile", "Off", "Waiting", "Reminders resume once RYFT has tonight's plan.", "Bedtime reminder", "Last sync". The notification keys are symbolic (§5) and carry the same English.

Unchanged: "Notifications", "Allow notifications", "Open Settings", "RYFT hasn't asked to send notifications yet.",
"Notifications are off in iOS Settings", "Your choices below are kept for when you turn notifications back on.", the K1 and
K4 details, "Quiet hours", "Pause at night", "From", "Until". Retired: "Notify me about", "You'll get", "Workout scored" (as a
row title), "No new data" (as a row title), "Morning score"'s old group.

---

## 7. Interactions and motion

- **Switch:** as `RyftToggleStyle` today. Server and quiet-hours switches mark themselves pending while their PATCH is on its
  way (the existing `change(_:get:set:)`). Local switches (K2) apply at once.
- **Time row:** appears under K2 when it turns on, goes when it turns off. Fade plus height, `Theme.Motion.quick`
  (250 ms ease-out). Same for the K2 note rows and for K2's first appearance once the journal's availability is known.
  The notices (permission, rollout, H) fade in and out with the same curve.
- **Reduce Motion:** `Theme.Motion.respecting(reduceMotion)`: every one of the above is instant. No pulse, no spinner
  anywhere on this page (pending is the 35 % dimming, not an animation).
- **K6:** a normal push; the back button returns here with the value read fresh (Bedtime & wake may have changed it).
- **Pinned bar and Open Settings:** as today. Returning from iOS Settings re-reads permission (`push.refresh()` on app
  active); the notice and the bar change without animation under Reduce Motion, fade otherwise.
- **The picker:** the system's own presentation; no custom motion.
- Haptics: none new.

---

## 8. Accessibility

### 8.1 VoiceOver, in reading order

Order is the visual order: notices, then each group (title is a header, so the rotor jumps between groups), then the pinned
bar last.

| Element | Label | Value | Hint / trait |
| --- | --- | --- | --- |
| Permission notice | the message, then the caption (one element, `readsAsOne`) | | static text |
| Rollout notice | the message, then the caption | | static text |
| Group title | "Morning" etc. | | header |
| K1 / K3 / K4 / K5 switch | the row title | On / Off | the detail sentence as hint; switch |
| Rolling-out row | the row title | "Rolling out" | the detail; static text (no button, no switch) |
| K2 switch | Journal reminder | On / Off | "Asks about yesterday, if you haven't answered yet." |
| K2 time row | **Journal reminder time** | the time, "9:00 AM" | adjustable (the date picker's own, in 15-minute steps); hint "Opens the time picker" |
| K2 note rows | the sentence; for noHabits the link follows as its own element "Choose habits", link trait, hint "Opens the Journal page" | | static text |
| K6 | Bedtime reminder | "Off" / "30 minutes before bedtime" / "Waiting for tonight's plan" | button; hint "Opens Bedtime & wake" |
| K7 switch | Not syncing | On / Off | the detail for the current route |
| Quiet hours switch | Pause at night | On / Off | the detail |
| From, Until | From, Until | the time | adjustable (date picker) |
| Sync footer, quiet footer | read in place after their group | | static text |
| Pinned bar | Allow notifications / Open Settings | | button; Open Settings hint "Opens outside the app" |
| H notice (Devices & sync) | message, then caption, then the action | | refreshOff's action: link, hint "Opens outside the app" |
| Today's line | "Last sync Tue 14:05. Background App Refresh is off." | | button, "Opens Devices & sync" |

- The time spoken is the locale's clock; the visible chip is hidden from VoiceOver (it is drawn text over the picker) as
  `ValueChip` already does, so the time is read once, from the picker.
- A switch that flips and is refused (a server PATCH fails) goes back; the notice is announced by its own element
  appearing, as today (`InlineMessage` for failures keeps `announces: true`).
- When the page becomes `denied` after an Allow tap, VoiceOver gets one announcement (the notice's message), through the
  notice's own `announces` (set `true` for that transition only; at page load they stay `false`).
- Contrast: all text is `textPrimary` (≥ 15:1), `textSecondary` or `textTertiary` on `surface`; `textTertiary` (48 %)
  is used only for secondary detail, as everywhere in Nocturne. The one coloured glyph (`warning`) is never alone: the
  message says it.
- Touch targets: rows ≥ 46 pt; the notice's action 44 pt (`InlineMessage`); the time chip's picker as big as its chip, 34 pt
  high chip inside a 56 pt row.

### 8.2 Dynamic Type

- **Default to XXXL:** as drawn (draft-a). Row titles wrap and the row grows; nothing is truncated; no fixed heights.
- **AX1 and above:** rows stack. A trailing value ("Rolling out", "Off", "30 min", "Waiting") goes **under the title and the
  detail**, left-aligned (`GroupedRowText` does it from AX1). The switch stays trailing (it is 51 pt wide and never wraps); the
  text beside it wraps to the remaining width. The time row stacks: label above, chip under it at the leading edge
  (`ValueChipRow`). Note rows: glyph, then the sentence wrapping; the link on its own line. Notices wrap; their action goes
  under the caption. The pinned pill grows with its text.
- **AX3** is the supported ceiling of the app (conventions rule 8) and must look right in the shipped previews; **AX5** must
  not clip, overlap or hide the last group behind the pinned bar. Group titles stop growing at AX3 (`GroupTitle` caps them),
  everything else keeps growing; at AX5 the page is long and scrolls, and the bottom inset is the pinned bar's height so the
  last footer stays reachable. Check AX5 in a preview, with the pinned bar present (notAsked or denied), since that is the
  tallest case.
- Quiet hours' From and Until, K2's time row: always stacked at AX1+, as today's From and Until.

### 8.3 Reduced motion, Bold, contrast

Reduce Motion: §7. Bold Text: the system's, nothing custom. Increase Contrast: the tokens' own. The app is dark only.

---

## 9. Previews N4 must ship

Dark only, synthetic data only (the `AppState.preview` mock user, `MockNotifier`, `MockJournal`, a mock
`BackgroundAvailability`, mock bedtime schedule; no real names, times or habits beyond the mock). One `#Preview` each, named
as below. Page previews wrap `NavigationStack { NotificationSettingsView() }` as today.

**Notifications page** (`NotificationSettingsView.swift`):

| # | Name | State |
| --- | --- | --- |
| P1 | allowed · server route | everything on, K3 present, bedtime on 30 min, journal 9:00 |
| P2 | allowed · no K3 | `categories` without `ACTIVITY_SCORED` |
| P3 | allowed · this iPhone | push not registered: K7 detail `.thisIPhone` |
| P4 | allowed · not syncing off | K7 `.off` |
| P5 | allowed · journal off | no time row |
| P6 | allowed · no habits | `noHabits` note with its link |
| P7 | allowed · quiet hours | quiet hours on, journal 06:30: the moon note |
| P8 | allowed · journal not live | K2 and its rows absent |
| P9 | allowed · bedtime off | K6 Off |
| P10 | allowed · bedtime waiting | K6 Waiting |
| P11 | allowed · no sleep planner | Sleep group absent |
| P12 | not asked | notice, caption, pinned Allow |
| P13 | denied | notice, caption, pinned Open Settings |
| P14 | rolling out | read-only K1, K3, K4, K5 with "Rolling out"; K2, K6, K7 live |
| P15 | rolling out · denied | both notices, in order, pinned Open Settings |
| P16 | rolling out · not asked | both notices, pinned Allow |
| P17 | save failed | an existing failure notice under Training, and one under Quiet hours (kept from today's states) |
| P18 | AX3 · allowed | the default page |
| P19 | AX3 · journal states | `noHabits` and the quiet-hours note |
| P20 | AX3 · rolling out · denied | tallest top, pinned bar |
| P21 | AX5 · rolling out · denied | must not clip |

**Devices & sync** (`DevicesAndSyncView.swift`): D1 background · refreshOff, D2 · restricted, D3 · lowPower (none is the
page's existing previews), D4 refreshOff at AX3.

**Today's line** (`StatusViews.swift`, beside the existing `SyncStatusLineView` boards): T1 `.backgroundOff`, T2
`.backgroundRestricted`, T3 either at AX3 (leading alignment, as Today uses it).

**Design primitive:** `ValueChip` with `minuteInterval: 15` in dark and AX3 (`FormField.swift`).

Notification text is not a SwiftUI preview. The check that stands in for one is a unit test over the strings of §5 (titles,
bodies, placeholders present in the catalog; none of the local titles and placeholders contains a digit).

---

## 10. Conflicts, calls and notes

### Conflicts with `design.md` §1 (none blocks)

1. **K1's row name.** §1.1 names it "Your day is ready"; the page already says "Morning score" and the group is "Morning".
   I kept "Morning score" (shipped, short, matches the notification's "Recovery %"). "Your day is ready" is used where it
   fits better: nowhere on the page; the lock-screen placeholder is "Your morning score is ready".
2. **K6's value strings.** §1.2 gives the value as "Off", "N min before bedtime", "Waiting for tonight's plan". Drawn as one
   trailing value that wraps the title. I split it: short value (Off, 30 min, Waiting) plus a detail line, and the full
   strings are the VoiceOver value (§2.6). Same information.
3. **Page-level permission.** §1.2 lists `notAsked` and `denied` for server rows under the flag; §8 says `mode` splits. The
   page does the split: permission is independent of rollout (§1.3, §1.4). Not a contradiction, but it changes today's page,
   where permission only showed with the flag on.
4. **§1.2's quiet-hours line** ("the row says the bedtime reminder and the wake alarm still come") is the footer's second
   sentence (§2.8), not the row's detail, because the detail already carries the K2 and K3–K5 rules.
5. **H on Today** (§1.2): "once the last sync is more than 20 h old" holds only briefly, because Today syncs when it opens.
   Specified as written, with the caveat of §4.2.
6. **Local rows and `notAsked`.** §1.2: "turning it on asks iOS". K2's default is on, so in `notAsked` its switch is already on
   and the pinned Allow is the way to ask; turning it off and on again also asks (§1.3). Said so that N4 builds both.

### Calls that need the user (2 and 3 decided by the lead on 2026-11-22; 1 and 4 to 6 open)

1. **Keep Today's hint line?** (§4.2.) Recommendation: ship it with the Devices & sync hint; it is one `SyncLine` case, and
   drop it if the beta shows it empty. The alternative is Devices & sync alone.
2. **Rename "Workout scored" to "Strength session scored"** (K4's row title). A shipped label changes; the reason is K3. The
   notification text (`SESSION_SCORED_TITLE`, the platform's) is unchanged.
3. **NT1's untitled title (decided, 2026-11-22).** It was `ACTIVITY_SCORED_TITLE_UNTITLED` = "Workout scored" = `SESSION_SCORED_TITLE_UNTITLED`. It is now "Activity scored", which matches the row and the placeholder; `API_REQUESTS.md` (NT1) carries it. The platform builds it from that text.
4. **The score in the morning title (open).** The platform's `MORNING_SCORE_TITLE` is "Recovery %@" with "82%" (API.md, push section), so the lock-screen title carries a health value. §5 says titles carry none, and design.md §1.3 names the same case. Options: the platform moves the score to the body (its `MORNING_SCORE_BODY_*` already carries the state) and the title becomes "Your morning score"; or the rule is relaxed for this one title, which iOS hides with previews off. Recommendation: move it. Needs the contract keeper.
5. **Quiet hours on K4 and K5 (open).** §2.8 says workout alerts are skipped, which is NT1's rule for K3. K4 and K5 are workout alerts too, but design.md §1.2 puts K1–K5 under quiet hours without saying held or skipped. Confirm "skipped" for K4 and K5 (the copy says so), or say "wait" instead for them.
6. **"A few taps" and "shows how your habits change" (open).** "A few taps" holds for a day of yes-or-no habits (a tap each); a count or a time takes more. "RYFT shows how your habits change the morning after" needs a few days of answers: the Insights empty state says "Log a few days in the journal to see how your habits change the morning after." Kept as written, because it is the journal card's own sentence. If you want it true from the first day: "…shows how your habits change the morning after, once you have a few days."

### For the sync-engineer (N3)

- Texts of §5.1, §5.2 and §5.5 are final, static (no argument), English only (§5.3 is unchanged and keeps its arguments): `String(localized: "JOURNAL_REMINDER_TITLE")` etc.
  `thread-id` = the category. No health value, no relative time, so a request can sit pending for days and still be true.
- A delivered `journal.<day>` stays in Notification Center if unanswered; the next morning's says "yesterday" about a
  different day. Each pass on app-active should also remove delivered `journal.*` whose asked day is not yesterday
  (cheap: the delivered list is read only on app-active, and design.md's `answered(journalDay:)` already removes by id).
- Local `SYNC_STALE` bodies contain no time, so the 1 h hysteresis needs no body rebuild.

### For N4 and the localization-editor

- `ValueChip(minuteInterval:)` is the only new primitive (§3); everything else is existing components.
- The two hours of K7's detail follow the clock (§2.7, decided by the lead); the key takes them as `%@` and `%@`.
- The existing Bedtime & wake string "{n} min" (`SleepPlannerView.minutes`) uses a plain space, against the no-break rule;
  not touched here, flagged.
- A new account with push already allowed gets a journal reminder at 09:00 it never asked for in this app version (Q1,
  accepted). The first one explains itself (§5.1), and `CHANGELOG.md` should say it. No in-app announcement is specified.

---

## 11. Copy review notes (localization-editor, 2026-11-22)

- **Brands:** none named as a comparison; "Apple Health" only as the data source (K3's detail, factual). "Your watch" is generic.
- **Placeholders and local titles:** no digit, no value, no name, no habit (§5.1, §5.2, §5.5). Checked by hand; N5's test should keep it that way.
- **Plurals:** only the K6 spoken value varies with a number. Every other number in a string is a fixed setting or a fixed rule.
- **Units:** every number and unit in the copy takes U+00A0 (§0 conventions). Clock times are locale-formatted; their space is the locale's.
- **Existing keys:** the Notifications page keeps its keys where the English is unchanged; the changed and new ones are marked in §6.
