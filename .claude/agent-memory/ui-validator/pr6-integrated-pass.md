---
name: PR 6 integrated pass (ecca568) driver notes
description: What worked and what bit when driving the whole PR 6 app (A+B+C) with the ZZVal driver
type: reference
---
- simctl sizes: AX3 = `accessibility-extra-large`, AX5 = `accessibility-extra-extra-extra-large` (the latter is NOT AX3).
- Montage tool: scratchpad/montage.swift (`montage out.png maxHeightPx in1.png ...`, scaled 50 %); no PIL/ImageMagick on this Mac.
- Never rewrite a scenes shell script while it runs (python in-place write broke it mid-run; `sed -i ''` is safe: new inode).
- Strain tab: `reveal:` stops when the element is "hittable" behind the tab bar; use `scrollto:` (frame between y 100..745) for rows under the Train pill (train.plans, train.history).
- Handy ids: train.start / train.start.today / session.finish / set.0.1 (tapin 0.96,0.5 checks it) / session.restPill / plans.current -> plan.copy opens the builder / history.row.* / sessionDetail.exercise.* / myday.card, myday.view (launch `-RyftOpenMyDay 0`) / myday.add -> myday.add.activity / journal.card -> journal.save / profile.journal -> journal.add.
- `-RyftScreen welcome-parked|invite|consent|aboutYou|aboutYouSaved|accountHint|wear|tracker-setup|report-problem|...` gives A without a server; plain Welcome needs `-demoMode NO` (driver env VAL_DEMO=NO). Don't submit Log in: Debug.xcconfig = production Supabase.
- Demo My Day has a night, so `myday.add.sleep` does not exist (Add sleep not reachable in demo; needs the missing-night state).
- AX3 runs are ~2.5 min each on the loaded Mac (huge accessibility tree); default ~1 min.
- Busy a11y ("In progress") has hosted tests already: RyftTests/BusyKeepsTitleTests, BedtimeNocturneTests; run them instead of driving a spinner.
