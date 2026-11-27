---
name: Gate G6: the screenshots
description: Re-shooting docs/screenshots with scripts/screenshots.sh — fresh sims inherit the Mac's German region, coach marks on Today, which old names map to which token, files with no producer
metadata:
  type: project
---
G6 (2026-11-22, feat/nocturne-gate-2 in wt-g4): the light and German shots went (105 files), the dark English ones
were re-shot with `scripts/screenshots.sh` on an own simulator.

**Why:** the app is dark only (ADR 0016) and English only; `docs/screenshots` must hold only dark English shots on
synthetic data ("Alex Doe", alex@example.com, "Alex's iPhone").

**How to apply / traps:**
- `grep -- -de` over the folder also hits `-details`, `-devices`, `-detail`: the brief's "67 -de" was 57 German
  plus 10 false matches. Match `-de(-|\.)` and `-light(-|\.)`.
- A **fresh** `simctl create` sim is *not* plain en_US on this Mac: `AppleLocale en_US@rg=dezzzz` (the Mac's German
  region), AppleLanguages `(en-US, de-US)`. Shots then read "12,4", "9.412", "22. Nov". Check with
  `simctl spawn <udid> defaults read -g AppleLocale`; set `defaults write -g AppleLocale -string en_US` on the own
  sim only, then shut it down so the boot re-reads it.
- The script doesn't pass `-coachMarks.today.done YES`; a fresh install shows Today's coach marks. Write the key into
  the **app container's** plist (needs the app installed, sim booted):
  `simctl spawn <udid> defaults write "$(simctl get_app_container <udid> dev.timkrebs.ryft data)/Library/Preferences/dev.timkrebs.ryft" coachMarks.today.done -bool YES`.
  `defaults write dev.timkrebs.ryft …` without the path lands in the sim's global domain, which the app never reads.
- The script names files `<token>-dark.png`. Hand-renamed old names and their tokens: today-row-a = `today`,
  row-b = `calibrating`, row-b-note = `needsVitals`, row-b-note-baselines = `needsVitalsBaselines`, row-c = `pending`,
  row-c-waiting = `waitingForSleep`, row-c-no-previous = `pendingNoPrevious`, row-d = `recalculating`,
  row-d-yesterday = `recalculatingYesterday`, row-e = `import` (PR #28's table); today-night-gap/scoring-slow-dark-en =
  `nightGap`/`scoringSlow`; onboarding-{consent,invite,sign-in-methods}-dark-en = `consent`/`invite`/`signInMethods`.
- No producer in the script (it routes unknown tokens to `-RyftTab`): welcome*, create-account, log-in, setup,
  sleep-week, workout, today-offline, refresh-429, sync-check-*, sync-setup-*, tracker-*, train-* (preview captures,
  1030x1500 with a black dot top right, pre-Nocturne teal). `tracker-devices-dark-en-AX3.png` shows "Tim's Apple
  Watch" / "Tim's iPhone" (real name) and a live status bar.
- The shared-Mac gate (load5 < 200, < 3 xcodebuild, no booted "RYFT CI") as a scratchpad runner that waits in 60 s steps
  and then runs the script, in the background (`scratchpad/g6-run.sh`). The build into `build/DerivedData` took ~2 min.
- Never wait with `while pgrep -f "<pattern>"` in a Bash/Monitor command: the shell's own `zsh -c` line contains the
  pattern, so it matches itself and never ends. Wait on a PID, or on the background job's notification.
- Nocturne shots are 2-6x larger PNGs than the old ones at the same pixels and format (8-bit RGBA): the gradient cards,
  the orbit's dotted rings and the dot-matrix digits compress badly (Today ~1 MB, Tonight 150 KB -> 980 KB). The brief
  said report, don't resize.
- Same names, so a re-shot duplicate (today = row-a, import = row-e, pending = row-c, calibrating = row-b) is a `cp`.
