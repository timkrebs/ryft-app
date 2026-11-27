---
name: Nocturne gate part 2 pass (9c820f3) driver notes
description: What gate 2 needed beyond gate 1: sim locale, AX naming, system-UI drivers, Files picker trick, findings
type: reference
---
- AX naming: x = accessibility-extra-large = AX3, y = accessibility-extra-extra-extra-large = AX5 (gate-1 shot letters). I once mislabelled y as AX3.
- A fresh `simctl create` sim has AppleLocale en_US@rg=dezzzz (host region); fix with plutil on Devices/<udid>/data/Library/Preferences/.GlobalPreferences.plist (AppleLocale en_US, AppleLanguages ["en-US"]) while shut down.
- Launch screen samples as 090C0B (sim rounds the asset) then the first app frame 0A0C0B: 1/255, no visible step. Tight `simctl io screenshot` loop right after `launch` works; scratchpad/uiv-gate2/px (swift CGContext sampler).
- Driver additions (ZZValUITests): tapdate:<datepicker id>, longpress, tapany:<label|id>, tapalert. `list` aborts inside out-of-process pickers (snapshot index error): don't use list there.
- Files picker multi-select: copy CSVs into Devices/<udid>/data/Containers/Shared/AppGroup/<group.com.apple.FileProvider.LocalStorage>/File Provider Storage/, reboot sim, tapany:Browse > On My iPhone > tap files. The selection badge is system blue with a white check (visible; not the app tint).
- Demo is signed out: no Log out / Delete account; alerts reachable: Discard this import (import step 3 > Close, needs -uiTestImportFiles), Delete this activity (activityDetail.menu > Delete). Export: profile.export -> share sheet.
- Add sleep: `-RyftTab today -RyftOpenMyDay 3 -RyftScenario missing-night`, tap myday.addSleep. Import card: `-RyftScenario import`. Reorder: start workout, tapbutton "Reorder exercises" (the list button; session.more menu item did not open it). Exercise history: tapbutton "Options for Bench press" > History.
- Live-workout scenes leave an active session: run `xcrun simctl uninstall/install` (fresh.sh) between them or train.start is missing. A fresh install also brought the Today coach marks back despite -coachMarks.today.done YES in one run.
- Findings (pre-existing, not part 2): StageRow at AX5 splits "20%" into "20" + "%" and "Awake" into "Awak/e"; first-run coach callout overflows the screen top at AX3/AX5 ("Your readiness" title off-screen).
