# Refresh resilience: UI spec (D2)

> **Errata 2 (lead, after review):** row B for a long history without HRV/RHR shows today's readiness + the
> `needsVitals` note (fallback "n of 7 nights with heart-rate data"); the German tile caption is "kalibriert noch";
> the delta shows only in row A; while the error card is shown, the status line reads "Couldn't load today · Details" and
> scrolls to it; the Report a problem disclosure lists exactly the allow-listed diagnostics (no install ID). "App too old"
> stays unshipped.

> **Errata (lead, after D1 `design.md`):** the decision is `TodayPresentation.decide` (`TodayState` is the API mirror of
> `SyncStatus.today`); `design.md` §7's table is authoritative. Row D needs a *scored* today that says `calibrating`
> (never an unknown/unscored one, which is row C), and requires `vitals ≥ 7`. Preview 7 uses a scored row without
> readiness (`computed_at` set, `readiness: nil`, `calibrating: true`, `scoring_state: scored`). Row B adds a
> `GaugeNote` ("Baselines need heart-rate variability and resting heart rate from nights with your watch.") when
> history has ≥ 7 scored days but < 7 with HRV and RHR. "App too old" isn't shipped (no API signal).

Brief: `CLAUDE_FOLLOWUP_REFRESH_RESILIENCE.md` §1–§4. Plan: `plan.md` T1 (7–9), T2, T3.
Spec only. Implementers: T1 (status line, error card, Sync details), T2 (Today hero, tiles, Trends delta),
T3 (Report a problem). Everything below uses `Theme`, `Typography` and existing components; "new" items name the
existing file they go into (classic groups: no new files).

## 0. Principles for these states
1. One screen, one truth. The sentence under the greeting, the gauge, the tiles and every note describe the **same
   day**. Whenever a block shows a day other than today, it carries that day's date next to it.
2. Dimmed means "not today's". Dimmed value = `Theme.textTertiary`; its date or label = `Theme.textSecondary`
   (the date carries the information, so it must reach 4.5:1; the dimmed number alone is decorative-adjacent and
   always has its date and a spoken "not scored yet" beside it).
3. Staleness is a time ("Showing data from 14:05"), never a mood. Pending is an outline. Calibrating is progress.
4. A failure is quiet until it lasts. Under the threshold nothing changes on screen except the status line's
   normal progression. One accent per screen: Teal stays on the gauge arc / the one action; notes are
   `textSecondary`, errors are never red (red is the Alert band colour of a score).
5. Honest copy, no other wearable's vocabulary. German is du-form; German terms follow the shipped catalogue
   (Baselines = "Ausgangswerte", readiness = "Bereitschaft", sync = "Sync").

Reading order of Today, top to bottom: header, greeting, sentence, **status line**, gauge (+ note), raw night
(pending only), tiles, other cards, Trends, **error card** (only past the threshold). The eye lands on the
gauge number first, the status line second.

---

## 1. Today hero: one row per case

`TodayPresentation.decide(...)` returns the whole row; the view reads nothing else. "Latest scored day" = newest day with
a readiness; it is today in rows A/B, an earlier day in rows C/D.

| Row | Sentence (callout, `textSecondary`) | Gauge | Tiles | Note / extra card |
| --- | --- | --- | --- | --- |
| **A** scored, not calibrating | `ReadinessCopy.sentence` (shipped) | `MetricGauge` readiness `.large`, delta "vs 7 d" only when `vsSevenDayMean` is non-nil | today's values, band word under Recovery | none |
| **B** scored, calibrating (`baseline_days` of the latest scored day < 7, history really short) | "Your baselines are still forming." | `BaselineGauge(nights: baseline_days)` | today's values; caption slot of **all three** tiles reads "calibrating" (`textTertiary`), replacing the Recovery band word | none |
| **C** not scored yet (pending / waiting_for_sleep / `computed_at` zero) | shipped: "Last night hasn't reached RYFT yet." / "Yesterday's readiness, until last night is scored." / "Your night is being scored." | `PendingGauge` (shipped): outline, yesterday's readiness dimmed, its date inside | the **latest scored day's** values, **dimmed**, caption = that day's date ("Yesterday", "Tue 20 Oct", via `Fmt.dayTitle`) in `textSecondary`; Recovery's band word is **not** shown | `RawNightCard` (shipped) between gauge and tiles: last night from Apple Health, labelled "not scored yet". Never "0 of 7" |
| **D** platform says calibrating but ≥ 7 scored days in history | "Readiness from {date}, while your baselines are recalculated." (just "Readiness is back soon." if the day is today: not needed, see below) | `MetricGauge` readiness `.large` of the latest scored day, **no delta**, gauge title stays "Overall readiness" | that day's values; dimmed + date caption if the day is not today, normal if it is today | **"Recalculating" note** under the gauge, see §1.4 |
| **E** nothing scored ever | shipped: "Your history is on its way." | `ImportCard` (shipped, "Setting up RYFT") | hidden (shipped: tiles hidden while importing) | none |

Unknown (`DailyScore.empty`, no row at all) is its own case and never maps to B: with a scored history it falls to
C or D by `scoring_state`; with none it is E. Tiles in an unknown state show `Fmt.placeholder` ("—") with no
caption (shipped look).

### 1.1 Layout and tokens (all rows)
- Greeting `title`/`textPrimary`; sentence `callout`/`textSecondary`; status line directly below (§2). Spacing and
  `Theme.Metrics.sectionSpacing` unchanged.
- Gauge: keep shipped sizes (160 pt dial, 6 pt stroke, `ryftNumber(46)`), Teal arc only in A and D; B's filled
  segments Teal, empty `surfaceRaised`; C's outline `textTertiary` hairlines; the dimmed number `textTertiary`.
- Tiles: `MetricTile` on `Theme.surface`, `tileRadius` 16. Dimmed tile: value `textTertiary`, icon tint at
  opacity 0.5, caption `textSecondary`. No border, no badge: dimming plus a date is the whole message.
- Tile order and sizes unchanged; at AX sizes tiles stack vertically (shipped) and the date caption wraps to
  its own line, never truncates.

### 1.2 Per-row detail

**A, scored.** Shipped. Delta label: only with a 7-day line (§4).

**B, calibrating.** Shipped gauge. Tiles keep today's values (they come from the same scored row) with the caption
"calibrating" so the user knows the Recovery band word would be provisional. Gauge caption "Baselines · n of 7
nights" uses the `baseline_days` of the latest scored day. VoiceOver per tile: "Recovery, 75 percent, calibrating".

**C, not scored yet** (the screenshot's case). From top: sentence, status line "Scoring your night", outline
gauge with yesterday's number (e.g. 76) and "Yesterday" under it, title "Scoring your night…", detail
"Usually ready within 20 s.", `RawNightCard` "Last night · From Apple Health · not scored yet · 7h 17m asleep",
then tiles: Sleep "7h 10m", Recovery "75 %", Strain "0.9", each dimmed with "Yesterday" below.
How the two sleep figures differ is stated, not hidden: tiles carry yesterday's scored sleep and a date; the raw card
carries last night's Apple Health total and says "not scored yet". Waiting-for-sleep variant: same, raw card absent
(no night has arrived), title "Waiting for last night's sleep".
When the score lands: values un-dim and roll (`numericText`), captions change to the band word, existing haptic.

**D, recalculating.** The gauge shows the latest scored day's readiness with its band colour and arc (it is a real
score), but without the delta (the baseline under it is being rebuilt). Note sits directly under the gauge, in the
band/delta line's place:

    [arrow.triangle.2.circlepath]  Recalculating your baselines

`caption`, `textSecondary`, SF Symbol static (no spin, it is not progress). If the day shown is not today, the
gauge's title row stays and the day is stated in the sentence ("Readiness from Tue 20 Oct, ...") and as the tile
caption; the note is the same. The note is a plain line, not a card: this is a platform hiccup, not an
action. Disappears with the standard cross-fade when the platform's `calibrating` goes false. No action.
VoiceOver on gauge: "Overall readiness, 80 of 100, High. Recalculating your baselines. From Tuesday 20 October."

**E, nothing scored ever.** Shipped `ImportCard` and `ImportRow`; unchanged by this brief.

### 1.3 Motion
- Row change: cross-fade 250 ms (`Theme.Motion.quick`; the shipped hero transition uses `standard` 0.4: switch it
  to `quick`). Reduced motion: no animation, instant swap.
- Dim to normal on landing: opacity + `numericText` ≤ 250 ms; reduced motion: instant, no digit roll (shipped
  `MetricTile` already does this).
- Pending outline breathing is shipped; reduced motion: static.

### 1.4 VoiceOver and Dynamic Type
- Gauge and tiles keep one element each. Dimmed tiles speak the day and the state: "Sleep, 7 hours 10 minutes,
  Yesterday, not today's score" (en); "Schlaf, 7 Stunden 10 Minuten, gestern, nicht der Wert von heute" (de).
  Visible caption "Yesterday" is the same word, no extra visible label.
- Order: greeting + sentence (one element, shipped), status line, gauge, note (read as part of the gauge value
  in D), raw night, tiles.
- AX sizes: dial stays 160 pt (shipped; its centre text has `minimumScaleFactor`), the title/detail lines under
  the dial wrap freely; the note wraps to two lines and centres. Tiles stack.
- Light and dark both: dimmed number is `textTertiary` in either; verify the light-mode value against Mist
  background (flag in review, see Open questions).

### 1.5 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| sentence B | Your baselines are still forming. | Deine Ausgangswerte entstehen noch. |
| tile caption B | calibrating | kalibriert |
| note D | Recalculating your baselines | Ausgangswerte werden neu berechnet |
| sentence D, other day | Readiness from %@, while your baselines are recalculated. | Bereitschaft vom %@, bis deine Ausgangswerte neu berechnet sind. |
| sentence D, today | Your baselines are being recalculated. | Deine Ausgangswerte werden neu berechnet. |
| a11y tile dimmed | %@, %@, not today's score | %@, %@, nicht der Wert von heute |
| a11y tile calibrating | %@, calibrating | %@, kalibriert noch |

### 1.6 Preview entries (`TodayView.swift`, each in dark, light, de, AX3)
Mock inputs build on `TodayScenario`; add the cases as scenarios so previews, UI tests and screenshots share them.
1. `Today · A scored`: `.preview()` (today scored, `baseline_days` 30, `calibrating` false, 7-day line).
2. `Today · B calibrating`: `.preview(scenario: .calibrating)` (`baselineDays` 3, tiles from the same row).
3. `Today · C pending`: `.pending` extended: history with scored yesterday (readiness 76, recovery 75, sleep
   430 min, strain 0.9), today `nil`, status `pending`, raw night 437 min.
4. `Today · C waiting for sleep`: as 3 with status `waiting_for_sleep`, no raw night.
5. `Today · C pending, no previous`: scored history empty except import done: gauge "—", tiles "—".
6. `Today · D recalculating`: today `calibrating: true, baseline_days: 0, readiness 80`, history 30 scored days.
7. `Today · D recalculating, yesterday`: as 6 with today unscored-but-calibrating row; tiles dimmed with date.
8. `Today · E first import`: shipped `.importing`.
9. `Today · AX3` of rows B, C, D (`.environment(\.dynamicTypeSize, .accessibility3)`).
Component preview `MetricTile · states` (dim, calibrating caption, normal) in `MetricTile.swift`: dark/light,
en/de, AX3.

### 1.7 New or changed components
- `MetricTile` (Design/MetricTile.swift): add `isDimmed: Bool = false` (value `textTertiary`, icon opacity 0.5,
  caption forced to `textSecondary`) and let `caption` carry the date or "calibrating". No other change.
- `GaugeNote` (Design/MetricGauge.swift): icon + `caption` text, `textSecondary`, centred, wraps. Used by row D.
- `MetricGauge` already hides the delta when `delta == nil`; row D passes `nil`.

---

## 2. Status line (`SyncStatusLineView`)

Always present under the sentence; `caption`, centred, SF Symbol + text (shipped). Colour `textSecondary` while
something is active, `textTertiary` when idle; the only accent is an action (`Theme.accent`).

### 2.1 States (priority, first wins)
| # | Line | Symbol | Trigger | Tap |
| --- | --- | --- | --- | --- |
| 1 | Action needed: enter your invite code / agree to the privacy policy | `hand.raised` | gate (shipped) | opens gate screen |
| 2 | Offline — will sync when back | `wifi.slash` | no connectivity (never an error, never stale-styled) | opens Sync details |
| 3 | Waiting for you to unlock your iPhone | `lock` | shipped | none |
| 4 | Syncing · heart rate (also "· sleep") | `heart.text.square` / `arrow.up.circle` | engine reading/uploading (shipped, add the "Syncing ·" prefix) | Sync details |
| 5 | Scoring your night / Scoring your latest data | `waveform.path.ecg` | awaiting scores (shipped) | Sync details |
| 6 | Updating… | `arrow.triangle.2.circlepath` | refresh reads in flight (shipped) | Sync details |
| 7 | **Showing data from 14:05 · Try again** | `clock` | idle, no request in flight, and the data is older than its threshold (today 2 h, history 24 h) after a refresh that did not succeed | text: Sync details; "Try again": retry |
| 8 | Health sync paused | `exclamationmark.circle` | upload failed (shipped) | Sync details |
| 9 | Up to date · 2 min ago | `checkmark.circle` | idle and fresh | Sync details |

Rules:
- "Time" for 9 and 7 is the **`day` resource's `fetchedAt`** (what the hero is made from), not the last attempt.
  Same day: "14:05"; yesterday: "Yesterday 14:05"; older: "Tue 14:05" then date. Never a relative time in 7.
- Row 7 only appears when idle. During any refresh the line shows 4/5/6 and 7 is suppressed, so a retry never
  shows "Updating…" next to a stale claim.
- When the calm error card (§3) is on screen, 7 drops "Try again" (the card owns it) and only reads
  "Showing data from 14:05"; one retry button on screen, not two.
- Under the threshold, failed reads change nothing: the line reads 9, with the time of the last good `day` read.

### 2.2 Progression during pull-to-refresh (no spinner plus error)
1. Pull. The system refresh control shows while the cheap part runs. The `refreshable` closure returns as soon as
   `today` and `GET /v1/me/sync` have answered, or after 3 s, whichever is first (T1 criteria 5). The native
   control is then gone and the line carries the rest. No custom spinner anywhere.
2. Line: "Syncing · sleep" (reading/uploading per engine) -> "Scoring your night" (only if a night is pending, else
   "Updating…") -> "Up to date · just now".
3. Each line stays at least 600 ms so it can be read (debounce, not animation), then cross-fades.
4. A failure inside a refresh is silent: retried, then falls back to cache, line ends at 9 (under threshold) or 7
   (past it). Never 9 immediately followed by an error card; the card appears only through §3's rule, and at the
   same moment the line has become 7 without "Try again".
5. Cancelling (view identity change) is never shown: the line goes back to whatever is true.

### 2.3 Tap targets
- The line is one element with min height 44 pt. 1–6, 8, 9: tap = Sync details (sheet with its own
  NavigationStack and "Done"; shipped screen). 1: gate screen (shipped).
- 7: two targets in one row: the text part opens Sync details; "Try again" (Teal, `caption` medium) is its own
  button, min 44 pt tall, `.contentShape(Rectangle())`, runs `refresh()`. Pressing it switches the line to 4/5/6
  at once; no spinner in the button.
- At AX sizes 7 stacks: text on line 1, "Try again" on line 2, both centred, no line limit (shipped `lineLimit(2)`
  becomes unlimited at AX).

### 2.4 Motion
Text change cross-fades 250 ms (`Theme.Motion.quick`); symbol pulse while active (shipped) stops under Reduce
Motion; reduced: text swaps instantly.

### 2.5 VoiceOver
One element for text, and "Try again" as a second element after it (state 7). Labels: "Up to date, 2 minutes ago";
"Syncing, heart rate"; "Scoring your night"; "Offline. Will sync when back"; "Showing data from 14:05" with
hint "Opens sync details"; button "Try again" with hint "Tries to load your data again". Status changes post an
`.announcement` only for 7 and for the return to 9 after a manual "Try again"; the other transitions stay silent
(they would chatter).

### 2.6 Copy
| Key | en | de |
| --- | --- | --- |
| line 7 | Showing data from %@ | Zeigt Daten von %@ |
| line 7 action | Try again (existing) | Erneut versuchen (existing) |
| line 4 prefix | Syncing · %@ | Synchronisiere · %@ |
| a11y 7 hint | Opens sync details | Öffnet die Sync-Details |
| a11y retry hint | Tries to load your data again | Versucht erneut, deine Daten zu laden |
Existing and unchanged: Up to date · %@, Offline — will sync when back, Scoring your night, Updating…, Health sync paused.
Visible combined form: "Showing data from 14:05 · Try again" / "Zeigt Daten von 14:05 · Erneut versuchen".
(`%@` stream name reuses `SyncActivity` text: "heart rate | Herzfrequenz".)

### 2.7 Previews (`StatusViews.swift`, extend "Sync status line")
Add `SyncLine.stale(since: Date, offersRetry: Bool)`. Entries: `.stale today 14:05, retry`, `.stale yesterday 22:10,
retry`, `.stale no retry (card visible)`, `.reading(.sleep)` with "Syncing ·", plus the shipped ones. Dark/light,
en/de, AX3 (retry on its own line).

---

## 3. The calm error card and its Details sheet

### 3.1 When (T1 criterion 7, restated for the view)
Card only if (a) same resource failed >= 3 times in a row **and** what's on screen is older than its threshold
(today 2 h, history 24 h), or (b) an error the user can act on. Offline never shows it. It replaces today's
"Couldn't refresh just now — showing your last loaded data." (the string is removed).

### 3.2 Layout (`InlineMessage` extended, `StatusViews.swift`)
Shipped container: `Theme.surface` at 60 %, `tileRadius` 16, hairline `separator` border, padding 14, last item
on Today. Content, top to bottom:
1. Symbol (`textSecondary`, 15 pt medium) + **reason**, `callout`, `textSecondary`: one plain sentence for the class.
2. **Data age**, `caption`, `textTertiary`, monospaced digits: "Showing data from 14:05".
3. Buttons row: **Try again** (`Theme.accent`, `callout`) and **Details** (`textSecondary`), each min height 44,
   18 pt apart. At AX sizes they stack, 44 pt min each, full width tappable.
Under Try again no spinner: while retrying the label reads "Trying again…", button disabled, card stays. On
success the card fades out (250 ms; reduced: removed instantly) and the line becomes "Up to date · just now".
If it fails again the card stays, the age line stays, nothing flashes.
"Details" opens the Details sheet (3.4), not the inline monospaced toggle (the inline toggle stays for
other `InlineMessage` uses without a request).

### 3.3 Reasons per class
| Class | Trigger | Reason (en) | Action | Symbol |
| --- | --- | --- | --- | --- |
| Server busy | `429`, `503`, `5xx` after retries | RYFT is busy right now. Your data is safe; try again in a moment. | Try again | `clock.arrow.circlepath` |
| Can't reach RYFT | transport error or timeout, device online | RYFT can't be reached right now. Your connection looks fine, so this isn't on your side. | Try again | `wifi.exclamationmark` |
| Something unexpected | other `4xx`/decoding on a resource | Part of your data couldn't be loaded. The details help us find out why. | Try again, and Details emphasised (Teal "Send to RYFT" inside) | `exclamationmark.circle` |
| Signed out | final `401` | You're signed out, so new data can't load. | **Sign in** (replaces Try again) | `person.crop.circle.badge.exclamationmark` |
| App too old | server says the app version is too old (see Open questions) | This version of RYFT is too old to load new data. Update it to continue. | **Update** (opens the App Store page) | `arrow.down.app` |
| Gate | `403 invite_required` / `consent_required` | not this card: shipped "Action needed: ..." status line and card (`.actionNeeded`) | Enter code / Review | `hand.raised` |
| Health sync paused | upload failed | shipped `.syncPaused` message (unchanged), now also with Details | Try again | `heart.text.square` |
The card is not for offline (line 2 says it), not for `Retry-After` waits under the threshold (shipped
"catching up, retrying in 12 s" notice stays only while a retry is actually pending).

### 3.4 Details sheet (`RefreshDetailsSheet`, `StatusViews.swift`)
Sheet, detents `.medium` and `.large`, drag indicator visible, own `NavigationStack`, title "Details" (inline), "Done"
in the toolbar. Background `Theme.background`, one `Card`, rows via `StatRow` (label `callout`/`textSecondary`, value
`body`/`textPrimary`, monospaced digits). At AX sizes value goes under the label (like `SettingRowLabel`).

| Row | Value | Note |
| --- | --- | --- |
| What failed | Today (resource name, §6) | |
| HTTP status | 503 | "—" for transport/timeout, with the word under it ("No response") |
| Code | `consent_required` / "—" | monospaced |
| Request ID | `01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c` | monospaced `caption`, `textSelection(.enabled)`, **copy button** (`doc.on.doc`, 44 pt) at the row's end; shows "Copied" with a check for 1.5 s; exactly as received, never shortened. If absent: "Not available" and a caption "A proxy answered before RYFT did." |
| Time | 14:07:12 | time of the last failed attempt |
| Showing data from | 14:05 | |
| Failed in a row | 3 | |
Below the card: **Send to RYFT** (`PrimaryButton`, `.primary`, Teal; the only accent on the sheet) and **Copy details**
(`.secondary`; copies the rows as plain text, no health data). Caption under them: "Sends this and the last 20 requests.
No health values." "Send to RYFT" pushes **Report a problem** (§5.5) onto the sheet's stack.
Motion: sheet default; "Copied" swap instant under Reduce Motion. VoiceOver: card is read row by row ("Request ID,
01a14ffa, ..."): the ID's value is spoken in groups; a custom action "Copy request ID" on the row. Focus lands on
the title. Sheet works in dark and light, AX3 scrolls.

### 3.5 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| busy | RYFT is busy right now. Your data is safe; try again in a moment. | RYFT ist gerade ausgelastet. Deine Daten sind sicher, versuch es gleich noch einmal. |
| unreachable | RYFT can't be reached right now. Your connection looks fine, so this isn't on your side. | RYFT ist gerade nicht erreichbar. Deine Verbindung scheint in Ordnung zu sein, es liegt also nicht an dir. |
| unexpected | Part of your data couldn't be loaded. The details help us find out why. | Ein Teil deiner Daten konnte nicht geladen werden. Die Details helfen uns, die Ursache zu finden. |
| signed out | You're signed out, so new data can't load. | Du bist abgemeldet, deshalb können keine neuen Daten geladen werden. |
| signed out action | Sign in | Anmelden |
| too old | This version of RYFT is too old to load new data. Update it to continue. | Diese Version von RYFT ist zu alt, um neue Daten zu laden. Aktualisiere sie, um fortzufahren. |
| too old action | Update | Aktualisieren |
| age | Showing data from %@ | Zeigt Daten von %@ |
| retrying | Trying again… | Neuer Versuch … |
| sheet title | Details | Details (existing) |
| rows | What failed / HTTP status / Code / Request ID / Time / Showing data from / Failed in a row | Betroffen / HTTP-Status / Code / Anfrage-ID / Zeit / Zeigt Daten von / Fehlversuche in Folge |
| no response | No response | Keine Antwort |
| no id | Not available | Nicht verfügbar |
| proxy note | A proxy answered before RYFT did. | Ein Proxy hat geantwortet, bevor RYFT es konnte. |
| copy id a11y | Copy request ID | Anfrage-ID kopieren |
| copy details | Copy details | Details kopieren |
| send | Send to RYFT | An RYFT senden |
| send caption | Sends this and the last 20 requests. No health values. | Sendet dies und die letzten 20 Anfragen. Keine Gesundheitswerte. |

### 3.6 Previews (`StatusViews.swift`)
`Error card · busy`, `· unreachable`, `· unexpected`, `· signed out`, `· app too old`, `· retrying` (disabled
label), `Details sheet · with ID`, `Details sheet · no ID`. Each dark/light, en/de, AX3. Mock age 14:05, 3 failures,
request ID `01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c`.

---

## 4. Trends card delta

- With a 7-day line and a non-nil `vsSevenDayMean`: delta shows as shipped ("▲ +4 · vs 7 d").
- Delta nil (fewer than 2 valued points, or no prior day in the window): **nothing renders**, neither value nor
  "vs 7 d" nor spacing (shipped `DeltaLabel` already returns empty; `ChartHeader`'s `HStack` must not leave a gap
  or reserve height, check at AX where it is a `VStack`).
- Flat change (< 2 %): the shipped label prints "—" followed by "vs 7 d", which reads as a missing value and is very
  likely what the screenshot shows (80 against a ~80 mean). New wording: **"Steady vs 7 d"** (`textSecondary`),
  with "No change" as the spoken form (shipped). See Open questions: this changes `DeltaLabel`'s documented
  behaviour.
- Fewer than 2 points: card body says "Not enough data yet" (shipped), header and delta hidden.
- Gauge delta follows the same rule (rows A only; none in B, C, D).
Copy: "Steady" | "Stabil" (flat), "vs 7 d" | "ggü. 7 Tg." (existing).
Previews (`DeltaLabel.swift`, `TrendChart.swift`): `delta up`, `delta down`, `flat -> Steady`, `nil -> hidden`
(assert zero height), `one point`; dark/light, en/de, AX3.

---

## 5. Profile -> Report a problem

### 5.1 Entry points
- Profile -> About: first row, **Report a problem** (symbol `exclamationmark.bubble`, chevron, `SettingRowLabel`);
  value shows "1 waiting to send" in `textSecondary` while a report is queued.
- Details sheet -> Send to RYFT (5.5).
Pushed screen (same style as Sync details): `ScrollView`, `ProfileSection` cards, title "Report a problem" inline.

### 5.2 Layout, top to bottom (compose state)
1. **Message** section: label "Message" (`ryftLabelStyle`), `TextEditor` in `Theme.surfaceRaised`, radius 16, padding
   12, min height 140, `body`. Placeholder (`textTertiary`): "What happened? What did you expect?" Character count
   "3 912 / 4000" appears only above 3 500 (`caption`, `textTertiary`, `warning` at 4 000).
   Helper under it (`caption`/`textTertiary`): "Please don't type health values you'd rather keep private."
2. **Category** section: four single-choice rows (radio list, 44 pt each, check in Teal on the chosen one, hairline
   dividers), values from `FeedbackCategory`: `bug` "Something's broken", `idea` "An idea", `data` "My numbers look
   wrong", `other` "Something else". Default `other` from Profile (the API default), `bug` from the error card.
3. **Diagnostics** section: row "Include diagnostics" + `Toggle` (`tint` Teal), **on** by default. Under it a
   `DisclosureGroup` "What's included" (collapsed). Expanded, `caption`/`textSecondary`, bullet rows:
   - App version and build
   - Device model and iOS version
   - The last 20 requests: method, path, status, error code, request ID, duration
   - Per resource: when it was loaded, last error
   - Sync state, account gates and feature flags
   then a closing line in `textPrimary`: "No health values. Nothing from Apple Health, no scores, no sleep or heart
   data." When the toggle is off the disclosure collapses and reads "Nothing is attached except your message."
   Optional (not required): a "See exactly what's sent" link opening a read-only monospaced preview sheet of the JSON.
4. **Send** (`PrimaryButton`, Teal): disabled while the message is empty. Under it, `caption`/`textTertiary`:
   "Reports are limited to 10 a day."
Keyboard: the editor is first responder only when opened from the error card (message prefilled, caret at the end).
Toolbar above the keyboard: "Done" dismisses it. Scroll interactively dismisses.

### 5.3 Pre-filled state (from Details)
Category `bug`; message prefilled with "Refreshing Today didn't work." (resource name filled in; editable); a
context chip at the top, `caption`, `surfaceRaised`, hairline: "About: Today · 503 · request 01a14ffa…" (request IDs
attached to `request_ids`, not only inside diagnostics); diagnostics on. Back returns to Details.

### 5.4 Result states (replace the form in place; cross-fade 250 ms, reduced: instant)
| State | Trigger | Visual | Copy (en) | Action |
| --- | --- | --- | --- | --- |
| Sending | Send tapped | Send label becomes "Sending…", disabled, form fields disabled; no spinner | Sending… | none |
| **Sent** | `204` | `checkmark.circle` 40 pt `Theme.accent`, headline, callout | Thanks, your report reached RYFT. | Done (pops) |
| **Queued offline** | offline, or `5xx`/timeout | `clock` 40 pt `textSecondary` | Saved. It will be sent as soon as you're back online. You can close the app. | Done; Profile row shows "1 waiting to send" |
| **Rate limited** | `429` (10 a day) | stays on the form; `InlineMessage` at the top, `clock` symbol, message kept; Send disabled | You've reached today's limit of 10 reports. Your message is kept; try again tomorrow. | Copy message (so it isn't lost) |
| Too long | > 4000 characters | count turns `warning`, Send disabled | (count only) | edit |
| Failed to queue | disk error | `InlineMessage` | Couldn't save your report. Copy it and try again later. | Copy message |
Honest-state rule: a queued report is never shown as sent. Haptic: `.success` only for Sent.
VoiceOver: result headline is focused on appearance and announced; the form order is message, category (radio group,
"selected" trait), toggle, disclosure, Send. The disclosure's rows read as a list.
AX3: all rows full width, radio rows wrap, Send full width, editor keeps min height and grows; nothing truncates.

### 5.5 Copy (en | de)
| Key | en | de |
| --- | --- | --- |
| row | Report a problem | Problem melden |
| row value | %lld waiting to send | %lld warten auf Versand |
| section | Message | Nachricht |
| placeholder | What happened? What did you expect? | Was ist passiert? Was hast du erwartet? |
| helper | Please don't type health values you'd rather keep private. | Bitte gib keine Gesundheitswerte ein, die du lieber für dich behalten möchtest. |
| category | Category | Kategorie |
| bug / idea / data / other | Something's broken / An idea / My numbers look wrong / Something else | Etwas funktioniert nicht / Eine Idee / Meine Werte wirken falsch / Etwas anderes |
| toggle | Include diagnostics | Diagnose anhängen |
| disclosure | What's included | Was enthalten ist |
| items | App version and build / Device model and iOS version / The last 20 requests: method, path, status, error code, request ID, duration / Per resource: when it was loaded, last error / Sync state, account gates and feature flags | App-Version und Build / Gerätemodell und iOS-Version / Die letzten 20 Anfragen: Methode, Pfad, Status, Fehlercode, Anfrage-ID, Dauer / Pro Datenquelle: wann geladen, letzter Fehler / Sync-Status, Konto-Freigaben und Feature-Flags |
| no health | No health values. Nothing from Apple Health, no scores, no sleep or heart data. | Keine Gesundheitswerte. Nichts aus Apple Health, keine Scores, keine Schlaf- oder Herzdaten. |
| off | Nothing is attached except your message. | Außer deiner Nachricht wird nichts angehängt. |
| limit note | Reports are limited to 10 a day. | Pro Tag sind 10 Meldungen möglich. |
| send | Send | Senden |
| sending | Sending… | Wird gesendet … |
| sent | Thanks, your report reached RYFT. | Danke, deine Meldung ist bei RYFT angekommen. |
| queued | Saved. It will be sent as soon as you're back online. You can close the app. | Gespeichert. Sie wird gesendet, sobald du wieder online bist. Du kannst die App schließen. |
| rate | You've reached today's limit of 10 reports. Your message is kept; try again tomorrow. | Du hast das Tageslimit von 10 Meldungen erreicht. Deine Nachricht bleibt erhalten, versuch es morgen noch einmal. |
| copy message | Copy message | Nachricht kopieren |
| save failed | Couldn't save your report. Copy it and try again later. | Deine Meldung konnte nicht gespeichert werden. Kopiere sie und versuch es später erneut. |
| count | %lld / 4000 | %lld / 4000 |
| chip | About: %@ · %@ · request %@ | Betrifft: %@ · %@ · Anfrage %@ |
| prefill | Refreshing %@ didn't work. | Das Laden von %@ hat nicht geklappt. |

### 5.6 Previews (`ProfileView.swift`)
`Report · empty`, `· filled`, `· from Details (prefilled)`, `· diagnostics off`, `· disclosure open`, `· sending`,
`· sent`, `· queued`, `· rate limited`, `· over limit`; dark/light, en/de, AX3 for empty, disclosure open and sent.
Profile row preview with and without "1 waiting to send".

---

## 6. Sync details addition (`SyncDetailsView`)

New section between **Engine** and **Streams**: "Loaded data" (uploads are Streams; this is what the app reads).
`ProfileSection` card, one row per resource, same row pattern as Streams:

    Today                                     14:05
    OK · loaded 14:05
    Profile                                   13:58
    503 · 12 s ago · 3 failed in a row

- Line 1: resource name (`callout`, `textPrimary`), fetched time right (`callout`, monospaced, `textSecondary`);
  "Not loaded yet" when never.
- Line 2 (`caption`): last error as "status · code · time" in `textSecondary`; with >= 3 consecutive failures
  it is `Theme.warning` and appends "· 3 failed in a row"; with 1 or 2: `textSecondary` and "· 1 failed";
  none: "No errors" in `textTertiary`. The request ID is not repeated here (it is in Last requests).
- Resources: Today, History, Profile, Sync status, Trends, Insights, Journal, Remote settings, Train.
- Row element is combined for VoiceOver: "Profile, loaded 13:58, last error 503, 3 failed in a row".
- AX: time moves under the name, like `SettingRowLabel`; no truncation.
- **Copy diagnostics** includes the same rows, one line each (`resource | fetched_at | last_error status code request_id
  at | consecutive_failures`), no health values.
Motion: none (static list); values update in place, reduced-motion irrelevant.

| Key | en | de |
| --- | --- | --- |
| section | Loaded data | Geladene Daten |
| names | Today / History / Profile / Sync status / Trends / Insights / Journal / Remote settings / Train | Heute / Verlauf / Profil / Sync-Status / Trends / Einblicke / Tagebuch / Konfiguration / Training |
| never | Not loaded yet | Noch nicht geladen |
| ok | No errors | Keine Fehler |
| failed n | %lld failed in a row | %lld Fehlversuche in Folge |
| loaded | loaded %@ | geladen %@ |
Previews (`ProfileView.swift`): `Sync details · loaded data`: all fine, one with 1 failure, one with 3 failures,
one never loaded; dark/light, en/de, AX3.

---

## 7. Accessibility and Dynamic Type summary
- Every state above: VoiceOver text specified, no information by colour alone (dimming always has a date, warning
  colour always has words, the delta keeps arrow/sign).
- AX1-AX3: tiles stack, lines wrap, buttons stack and stay 44 pt, sheets scroll, no `lineLimit` on explanatory text.
- Reduced motion: all fades become instant swaps, pulses and the outline breathing stop, digit rolls off.
- Contrast: body text `textSecondary` on `surface`/`background` >= 4.5:1 in both modes; `textTertiary` only for
  non-essential text (placeholders, counts, dimmed numbers that carry a date).
- Localization: all strings via `Localizable.xcstrings` en + de; plural-aware keys (`%lld failed in a row`,
  `%lld waiting to send`) need variations.

## 8. Open questions (also in the hand-back)
1. Platform signal for "app too old": `API.md` defines none. The card class stays in the spec but cannot ship until
   the platform gives a code or status (`docs/API_REQUESTS.md`); until then, no such card.
2. Flat delta wording (4): changes the shipped "—" convention.
3. Feedback size: the plan says body <= 64 KiB, `API.md` says `diagnostics` <= 32 KiB; `FeedbackPost.diagnostics` is
   `[String: String]`, so the 20 requests and per-resource list must be encoded as strings.
4. Two sleep figures in row C (yesterday's scored sleep in the tile and last night's raw Apple Health sleep in the
   card): spec keeps both as the brief says, separated by the date and the "not scored yet" label.
5. Light-mode contrast of `textTertiary` dimmed numbers; verify in review.
