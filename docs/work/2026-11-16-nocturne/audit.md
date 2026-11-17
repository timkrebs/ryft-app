# Nocturne audit: every user-reachable screen (2026-11-17)

Worktree `wt-sleep` at 6a90bfb (main + PR 1-3 + PR 4 shared components + finished Sleep Day). iPhone 17 Pro, iOS 27.2 simulator, dark only, 3x.
The screenshots named below (about 140, 3x) are kept in the lead's session scratchpad, not in the repo.
"hosted" = the view rendered in a real window by a scratch hosted test (screens demo mode and launch arguments cannot reach); the scratch tests were not committed.

Verdicts: A matches its mockup. B planned (PR 4/5). C consistent, no mockup. D off. E broken.
Cross-cutting findings that apply to every row marked "X1" or "X2":
- X1: teal (`Theme.accent` = recovery teal) is used as the general UI accent: filled primary buttons (`PrimaryButton`, 24 files; `TealButtonStyle`, 33 uses), links, toggles, checkmarks, icon tints. The brief says teal = recovery only, and the primary button is the light pill with a dark icon circle. `PillButton` is used nowhere outside the component catalog.
- X2: the old glass floating tab bar with icons and a teal active state is on every tab (brief: dot tab bar, Volt active dot). Planned for PR 5.

| Area | Screen | How reached | Screenshot | Verdict |
|---|---|---|---|---|
| Signed out | Welcome | `-demoMode NO` | auth-welcome.png | **D** (X1): value-line icons all teal (Sleep should be violet, Strain blue); "Create account" is a grey filled capsule, not an outline `PillButton`; "Log in" is a bare text button; Apple button is the white system capsule (fine, but unrelated to the pill spec). Lock-up and tagline are Nocturne. |
| Signed out | Welcome at AX3 | hosted | host-welcome-ax3.png | **E**: not scrollable, everything is squeezed into one screen; the privacy line truncates to "Your data is stored on th..." so the Privacy Policy link is gone. |
| Signed out | Welcome after session expiry, parked activities | `-RyftScreen welcome-parked` | dbg-welcome-parked.png | **D** (X1): same as Welcome plus an old teal-bordered notice and a grey "Delete from this iPhone" capsule. |
| Signed out | Log in | hosted | host-login.png, host-login-ax3.png | **D** (X1): left-aligned 26-pt-ish title is right, but fields are `surfaceRaised` at 60 %, disabled submit is a dim teal capsule. AX3 scrolls fine. |
| Signed out | Log in, error | hosted | host-login-error.png | **D** (X1): inline message is a bordered card (fine), button as above. |
| Signed out | Create account | hosted | host-create-account.png, host-create-account-ax3.png | **D** (X1) |
| Signed out | Reset password | hosted | host-forgot.png, host-forgot-ax3.png | **D** (X1) |
| Signed out | Check your inbox (confirm, reset) | hosted | host-check-inbox-confirm.png, host-check-inbox-reset.png | **D** (X1): teal envelope, teal "Open Mail", grey "Resend". |
| Signed out | Set new password (reset link sheet; also Profile → Change password) | hosted | host-set-password-recovery.png, host-set-password-change.png | **D** (X1) |
| Onboarding | Invite code | `-RyftScreen invite` | dbg-invite.png | **D** (X1): teal envelope glyph, teal paste chip, dim teal capsule. |
| Onboarding | Consent | `-RyftScreen consent` | dbg-consent.png | **D** (X1): teal hand glyph and teal row icons, teal link, teal checkbox/capsule. Long text screen, Light title is right. |
| Onboarding | About you (empty, saved) | `-RyftScreen aboutYou`, `aboutYouSaved` | dbg-aboutYou.png, dbg-aboutYouSaved.png | **D** (X1): teal glyph, wheel picker, full-width teal "Continue". |
| Onboarding | Apple Health intro | hosted | host-health-permission.png, host-health-permission-ax3.png | **D** (X1): teal heart-in-circle illustration, teal glyph rows, teal "Continue". AX3 wraps and scrolls. |
| Onboarding | What do you wear? | `-RyftScreen wear` | dbg-wear.png | **D** (X1, minor): chips on `surface` are fine; teal "Continue". |
| Onboarding | Set up your trackers | `-RyftScreen tracker-setup` | dbg-tracker-setup.png | **D** (X1, minor): teal "Done", teal check rows. |
| Onboarding | New-account hint sheet | `-RyftScreen accountHint` | dbg-accountHint.png | **D** (X1): teal glyph and teal "Use the other account". |
| Launch | Splash (while the session restores) | hosted | host-splash.png | **C**: mark on `background`. |
| Launch | Misconfigured build (Release only) | hosted | host-misconfigured.png | **C** (list is empty in the test, so it reads "It's missing ."). |
| Launch | Launch sequence, play | `-RyftLaunchSequence play` | launch-play-3.4.png, launch-play-5.0.png, launch-play-5.6.png, launch-play-6.2.png, launch-play-6.8.png, launch-play-7.6.png; sheets/launch.png, sheets/launch2.png | **A**: rings draw in metric colours with dots on the arc ends, the dots land in the logo positions, all colours go to `textPrimary`, "RYFT" tracks in, tagline "Engineered for peak." appears, cross-fade into Today. Timing was not checked frame by frame (a loaded Mac delayed the cold start by about 3 s). |
| Launch | Launch, Reduce Motion | same, Reduce Motion on | launch-reduced-2.8.png, launch-reduced-3.5.png; sheets/launchred.png | **A**: static lock-up with tagline, cross-fade to Today. |
| Tabs | Tab bar (all five tabs) | any tab | tab-*.png | **B** (X2, PR 5) |
| Tabs | Today | `-RyftTab today` | tab-today.png | T4.2 in progress, not graded |
| Tabs | Today states: importing, pending, calibrating, Garmin hint, error/offline fault | `-RyftScenario import/pending/calibrating/watch`, `-RyftFault` | today-importing.png, today-pending.png, today-calibrating.png, today-watch.png, today-fault-offline.png, today-fault-503.png; sheets/today1.png | T4.2 in progress, not graded (the fault launch only shows "Updating...", no error card: cached demo data) |
| Tabs | Today scroll: My Day card, Journal card, Train card, Trends | scrolling | today-scroll-0..4.png | T4.2 in progress |
| Tabs | My Day, full screen | `-RyftOpenMyDay 0` | myday-full.png | **C**: `surface` cards, circle back/add buttons, strain date strip still the old rings. |
| Tabs | My Day, add menu; Add activity; sport picker | taps | myday-add-menu.png, add-activity.png, add-activity-sport.png | **C** (X1): teal "Save", teal sport icons. |
| Tabs | My Day, no sleep recorded; Add sleep | `-RyftOpenMyDay 3 -RyftScenario missing-night` | myday-missing-night.png, add-sleep.png | **C** (X1) |
| Tabs | Activity detail | tap a row | activity-detail.png, activity-detail-2.png | **C**: grey "Edit", red "Delete". |
| Tabs | Sleep, Day | `-RyftTab sleep` | tab-sleep.png | **A**: header with circle buttons, dot numeral, ruler with Volt needle and need zone, violet hypnogram glow tile, 2x2 neutral tiles with dot row. Below the tiles, "Sleep need" is the old card (blue/yellow bar). Tab bar: X2. |
| Tabs | Sleep, Week and Month | `-RyftSleepMode week/month` | sleep-week.png, sleep-month.png; sheets/sleepmodes.png | **D**: old plain "Sleep / Last 7 nights" header (no circle buttons), Deep/Light/REM drawn in three blues (blue is the Strain colour), red delta text, old stat tiles. No mockup, no PR covers it. |
| Tabs | Sleep, Bedtime (planner) | `-RyftSleepMode plan` | sleep-plan.png | **D**: same old header; "Tonight" card, teal "Bedtime & wake" link, plain inputs. |
| Tabs | Sleep need sheet; Baseline sleep need editor | `-RyftScreen sleepNeed`, `baselineSleepNeed` | dbg-sleepNeed.png, dbg-baselineSleepNeed.png | **C** (X1) |
| Tabs | Bedtime & wake editor; Tonight card | `-RyftScreen bedtime`, `tonight` | dbg-bedtime.png, dbg-tonight.png | **C** (X1): teal toggles and checkmark. |
| Tabs | Strain | `-RyftTab strain` | tab-strain.png | **B** (PR 5): date-strip rings, plain ring gauge, five-hue zone bar (yellow, red). |
| Tabs | Strain, Train card, plans/history links, Activities | scrolling | strain-scroll-1..5.png; sheets/strain1.png | **B** (PR 5), X1: teal "Start workout", teal activity icons, teal strain chips (should be Strain blue). |
| Tabs | Workout detail (Run) | `-RyftOpenWorkout YES` | strain-workout.png | **B** (Strain family; PR 5 does not name it): red heart-rate line, green run icon, old stat tiles. |
| Tabs | Insights | `-RyftTab insights` | tab-insights.png, insights-scroll-*.png; sheets/ins.png | **B** (PR 5): title only (no 7 D / 30 D / 90 D segment), severity cards with red/yellow stripe, resting-HR chart in red. |
| Tabs | Insights, "Show the chart" | tap | insights-chart.png | **B** (PR 5) |
| Tabs | Profile | `-RyftTab profile` | tab-profile.png, profile-scroll-00..11.png; sheets/prof1.png, prof2.png | **B** (PR 5): long settings list, no avatar ring, no "Export data" pill, grey/red capsules. |
| Profile | Account when signed in: Log out, Delete account, Change password | hosted | host-profile-signedin.png | **C** (X1): grey capsules, red "Delete account". The confirmation dialogs are system sheets and could not be reached (needs a session). |
| Profile | Display → Hero numbers | scroll | prof-display.png, prof-display-ax3.png | **C**: system menu "Dots", teal. |
| Profile | About (lock-up, version, links) | scroll | prof-about.png, prof-about-ax3.png | **C** |
| Profile | Report a problem: form, details, sent, queued, rate limited, "What's included" | `-RyftScreen report-problem*` | prof-report.png, dbg-report-problem*.png; sheets/dbg4.png | **C** (X1) |
| Profile | Devices & sync; tracker card; Check sync | tap; `-RyftScreen devices/tracker-card/sync-check` | prof-devices.png, dbg-devices.png, dbg-tracker-card.png, dbg-sync-check.png; sheets/dbg5.png | **C** (X1): teal "Check sync", teal check rows. |
| Profile | Sync details | tap; `-RyftScreen syncDetails` | prof-syncdetails.png, dbg-syncDetails.png | **C** |
| Profile | Notifications | `-RyftScreen notifications` | dbg-notifications.png | **C** (the "being rolled out" state) |
| Profile | Journal → Behaviors to track | tap | prof-journal.png | **C** (X1): teal toggles. |
| Profile | Sign-in methods | `-RyftScreen signInMethods` | dbg-signInMethods.png | **C**: white system Apple button. |
| Profile | Licences | tap | prof-licences.png | **C** |
| Profile | Import training data (CSV import, step 1) | tap | prof-import-training.png | **C** (X1): teal "Choose files". Later steps not captured. |
| Profile | Export my data (share sheet) | tap | prof-export.png | **C** (system sheet, dark) |
| Profile | Baseline sleep need editor | tap | prof-sleepbase.png | **C** |
| Profile | Developer: Component catalog, Feature flags | Debug builds only | prof-catalog.png, prof-flags.png | not user-reachable (Release) |
| Train | Start workout sheet | tap Start workout | train-start-sheet.png | **C** (X1): the first option is a solid teal block. |
| Train | Live workout (list layout) | Start → From today's plan | train-session.png, train-session-2.png, train-session-set-checked.png; sheets/train1.png | **D** (X1): teal "Finish" capsule, teal target and last-time text, teal check. |
| Train | Live workout at AX3 | same, AX3 | ax-train-session-ax3.png, ax-train-start-sheet-ax3.png; sheets/ax1.png | **E**: "Finish" wraps to "Fini/sh", title truncates to "Uppe...", table headers break ("S/et", "Rep/s", "RP/E"); the start-sheet detail truncates ("~..."). |
| Train | Finish confirmation; Workout done summary | Finish | train-finish-confirm.png, train-summary.png | **C** (X1) |
| Train | My plans, plan detail, plan builder | tap | train-plans.png, train-plan-detail.png, host-plan-builder.png | **C** (X1) |
| Train | History, session detail, exercise page | tap | train-history.png, train-session-detail.png, host-exercise-detail.png | **C** (exercise page hosted) |
| Journal | Journal sheet (Today's Journal card → Edit) | hosted | host-journal-sheet.png | **C** (X1) |
| States | Sync status lines, stale, offline, action needed; inline error; setup card | hosted | host-status-lines.png; dbg-refresh-details-send.png | **C**: calm text rows, teal only on actions. Today's error Details sheet has a teal "Send to RYFT". |
| Widget | Readiness widget, Live Activities | not rendered | none | not verified (see below). Static check: `Brand` hexes match the Nocturne tokens, the widget gauge is the shared v3. |

## D and E, ranked by visibility

1. **Welcome** (every new user; E at AX3). Use `BrandLockup`, ring-legend or neutral icons in the value lines, `PillButton(.secondary)` for "Create account", the Apple button as is or as a light pill. At AX3: scroll view with the actions pinned, so the privacy line can wrap instead of truncate. A one-frame mockup is worth it: it is the first screen and has no board.
2. **Log in, Create account, Reset password, Check inbox, Set new password.** `ScreenHeader`-style Light title, fields on `surface`, `PillButton(.primary)` for submit, `PillButton(.secondary)` for the secondary action. No mockup needed once Welcome is drawn.
3. **Onboarding: invite, consent, about you, Apple Health, What do you wear, tracker setup, account hint.** Same buttons as 2; glyphs and illustrations in `textPrimary`/neutral (a teal heart in Apple Health reads as "recovery"); links `textPrimary` underlined. A mockup for the consent and Health intro pages is optional; the rest can follow the pattern.
4. **Train live workout** (daily use; E at AX3). Needs `CircleButton`/`PillButton` for Finish and a header that does not wrap at AX3; set-table headers need a fixed minimum width or an AX layout. Teal text to `textSecondary`. A mockup is worth it, because it is the most-used screen after the tabs.
5. **Sleep Week, Month and Bedtime.** Same header as Day (`CircleButton`s, centred title), stage bars in the Sleep violet family instead of blue, `GlowTile`/`DotRow` where Day uses them. Needs a decision first on whether T4.3 covers these; the board shows Day only.
6. **Cross-cutting X1 (teal as general accent)** touches every C row with a button. One decision resolves it: either `PrimaryButton` becomes `PillButton` and teal is only for recovery, or the brief names teal as the interactive accent.
7. **B items** (Strain, Insights, Profile, tab bar, Workout detail): planned for PR 5. Workout detail is not named in the plan; add it to PR 5.

## Not reached
- Log out, Delete account, Withdraw consent and Full re-sync confirmation dialogs: need a signed-in session; only the buttons were rendered (host-profile-signedin.png). Full re-sync is disabled in demo.
- Real sign-in errors from Supabase: not triggered, to avoid calls to the production project (the Debug config points at it). The error state was rendered with a staged message.
- Maximum heart rate editor, Insights "idea" hint, import flow steps 2-6, the live Strain/Insights empty and error states, Sleep pending/calibrating (no launch argument drives Sleep's states; the Sleep agent's previews cover them).
- Today's error card with a real failure: `-RyftFault` only produced "Updating..." on cached demo data.
- Widget on the home and lock screens, Live Activities, push banners, HealthKit permission sheet, Sign in with Apple: device only.
- Launch sequence frame-by-frame timing against the keyframes.
