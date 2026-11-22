---
name: Notification copy (N1 review)
description: Facts checked while reviewing the notifications page and local notification copy (2026-11-22). Read before writing time, unit or notification copy.
type: project
---
- Locale clock: `Date.FormatStyle(date: .omitted, time: .shortened)` in en_US puts U+202F (narrow no-break space) before PM, not U+00A0. Checked with Foundation on this Mac. en_GB gives "21:00" with no space. Never claim the chip uses U+00A0.
- Units in copy take U+00A0 (`30 min`, `20 hours`, `%lld %`). Clock times come from the locale and are not typed.
- Existing keys, reuse as-is: "Off", "Waiting", "Bedtime reminder", "Choose habits", "Opens the Journal page in Profile" (not "Opens the Journal page"), "Reminders resume once RYFT has tonight's plan.", "How was yesterday?", "Last sync", "Devices & sync", "Opens outside the app", "Wind down".
- Existing `%lld min` has a plain space; left alone (flagged), not used by the notifications page.
- Platform `MORNING_SCORE_TITLE` = "Recovery %@" with the score in the title (API.md). Conflicts with the no-value-in-title rule; open with the lead.
- Force-quit: BG refresh and silent push don't run until reopened (documented). HealthKit background delivery is undocumented (device check D3), so "can stop background sync" is the honest wording.
- "A few taps" is true for yes/no habits; "RYFT shows how your habits change" needs days of answers (Insights empty state: "Log a few days in the journal…").
- Journal title "How was yesterday?" stays relative on purpose: the request is keyed to the day it asks about. Counts of hours are not allowed in scheduled text.
- Quiet hours copy: never say "Nothing arrives" (bedtime and the wake alarm still come).
