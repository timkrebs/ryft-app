# A1 phase 2: review (2026-11-22, PR #137)

Two reviewers, scoped to the PR: code-reviewer and security-privacy-reviewer. Neither found a blocker.

## Code review
| # | Finding | Decision |
|---|---|---|
| 1 | `showsAnalyticsStep` required `!healthIntroDone`. That flag is per install, and `RootView` sets it to true when iOS already asked, so a second account on the phone was never asked. | **Fixed:** the condition is gone. "Before Health" now comes from RootView's case order. Test `aSecondAccountOnAPhoneWhereHealthWasAskedIsStillAsked`. |
| 2 | The ADR was wrong about the lifecycle: `Application Installed` fires at the first opt-in, and a mid-session start sends no `Opened`. | **Fixed** in the ADR. |
| 3 | The fence's redirect claim was unverified. | **Softened:** the system follows redirects, and PostHog ingestion doesn't redirect. The path check (privacy 2) narrows it anyway. |
| 4 | Setup and deletion run on the main actor. | **Kept:** a few small files, once per answer or config change. Noted in `PostHogSink`. |
| 5 | `APP_STORE.md` said "no boot time" next to 35F9.1. | **Fixed.** |

## Privacy review
| # | Finding | Decision |
|---|---|---|
| 1 | The manifest left out Device ID (the analytics install id) and Other Diagnostic Data (`error_shown`). | **Fixed:** the Analytics purpose is added to the existing entries, one per type, and they stay linked because of their App Functionality use. This goes beyond the brief's "Product Interaction" and is on the user's list. |
| 2 | The fence checked only the host, so `/flags` (`$device_id`) and push subscriptions would pass. | **Fixed:** only `https://eu.i.posthog.com/batch`, with no port, user or query. |
| 3 | The consent copy didn't mention lifecycle or device data, and had no policy link. | **Fixed** (ios-developer): the first point now covers both, and the step links the policy. |
| 4 | Conventions skill rule 4 is out of date. | `.claude/` isn't committed. The replacement sentence is in the PR's notes for the user. |
| note | Re-identification risk comes from timestamps in a small cohort, not from the kept keys. | For the user: limit who can see the PostHog project, and say in the policy that the data is never joined with RYFT accounts. |

The reviewers' "checked and sound" lists are in their reports: no code at launch, `beforeSend` sees every event, `close()` resets the id in memory only, and `with()` twice is safe after `close()`.
