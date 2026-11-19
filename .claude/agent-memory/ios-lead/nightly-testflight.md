---
name: nightly-testflight
description: Every merge to main ships to TestFlight Internal with the next nightly (late, ~07:40–09:00 UTC); the user wants a build to carry a whole feature set, so time merges; signing works again since 2026-11-17
metadata:
  type: feedback
---

**Every merge to `main` goes to TestFlight Internal with the next nightly.** It runs on its own, with no step in
between: `nightly.yml` builds whenever `main` changed since the last `build/*` tag. Its cron says 01:00 UTC, but GitHub
starts it late, between about 07:40 and 09:00 UTC.

The user wants a TestFlight build to carry a **complete feature set**, not half of one. On 2026-11-17 he said: "Ich
würde mit dem Nightly gerne warten bis PR4 auch komplett durch ist. damit wir den usern die beste experience bieten
können". That message came too late: Nocturne PR 3 (#114) had already shipped alone as `build/20261117.085425`.

**Why:** a merge ships automatically, and the user only finds out afterwards. So a staged UI series (like the five
Nocturne PRs) has to be timed by me.

**How to apply:**
- Before a merge in the middle of a series, tell the user it ships with the next nightly and ask whether it should wait.
- Prefer merging the last parts of a set on the same day, after the nightly has run.
- If the user wants to hold a whole set, offer `gh workflow disable nightly.yml` and re-enabling it afterwards. Don't
  do it without asking: it's his repo setting.
- A manual `gh workflow run nightly.yml` is his call too.

**Signing history:** archives failed from 2026-11-05 to 11-16 on the certificate limit and an unsigned PLA. The user
deleted certificates on 11-16, and the 11-17 run uploaded fine. If an archive goes red again with "maximum number of
certificates" or "PLA", only the Account Holder (the user) can fix it on developer.apple.com.

See [[headless-permission-preflight]].
