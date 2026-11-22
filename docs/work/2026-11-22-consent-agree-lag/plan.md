# Consent: Agree and continue lags — plan (ios-lead, 2026-11-22)

## Brief (the user, 2026-11-22)
A new user ticks the consent box and taps "Agree and continue"; the next screen comes 3–4 s later.

## Findings
- **The debugger's trace:** after the consent `204` the step waits for the slowest of `/v1/me`, `/v1/config` and `/v1/me/sync`, the user's SwiftData commit and an optional tz `PATCH`. Mock latency: 250 ms per request gives 0.5 s; one slow read gives its own time.
- **The user's device diagnostics** (not kept in the repo): those reads answer in 0.1–0.3 s with no transport errors. The POST itself was already out of the 20-entry ring, so the time is in the POST (cold connection on the default session, the `503` loop) or in the store commit.
- **Two latent bugs on the path** (design §1, §4.4–4.5):
  - the platform's 10 s status cache can record a stale `consent_required` and keep the step on screen;
  - a failed re-check after the `204` leaves the user on the consent screen with no word.

## Lead decisions
- **The design note (`design.md`) is accepted:** D1–D9, rules R1–R4, tests T1–T11.
- **One PR, not two:**
  - Measurement (D7) and the fix go in separate commits, measurement first.
  - Why: a separate measurement PR would need a nightly and a fresh new-user sign-in before the fix could ship, and that costs the user more than the "before" number is worth. The line still ships, so the "after" number is visible on his phone.
- **Q1 (invite re-check):** not here. It is a follow-up, logged in STATUS.
- **Q2 (platform):** request the fresh `gate` (D8, §9), filed in `docs/API_REQUESTS.md` by this PR. The app's R2 works either way.
- **Q3:** yes. The shared fail-fast helper (D6) uses `readUserBack(since:)` for both agree's and #134's "ask again", if it stays a small change. Otherwise it is a follow-up.
- **Q4:** a `503` on Agree is said, the fail-fast way, with the same calm words as other "RYFT is busy" cases. Nobody waits 5 s on an unlabelled spinner.
- **Q5:** the localization-editor words `consentUnansweredMessage` and the `503` line.
- **ADR 0025** is written by ios-architect with this PR.

## Tickets

| # | Ticket | Owner | Acceptance |
|---|---|---|---|
| C1 | The agree line, `Signposts.onboarding`, App Attest and `503` intervals (§6) | ios-developer | T11; the line in Copy diagnostics and Report a problem |
| C2 | Agreement record, `missing` vs `gate`, re-read via `readUserBack(since:)`, R2 in both status doors, failed re-read, `Flight` (§4.1–4.7) | ios-developer | T1–T7, T9, T10; Devices & sync says Paused, not Action needed |
| C3 | The POST on the fail-fast helper shared with #134's withdrawal, with "ask again" (§4.8) | ios-developer | T8; #134's tests unchanged |
| C4 | ADR 0025; `docs/API_REQUESTS.md` (§9); STATUS; CHANGELOG | ios-architect, lead | — |
| C5 | Words: `consentUnansweredMessage`, the `503` line | localization-editor | catalog, targeted edit |

**Reviews:**
- code-reviewer;
- **security-privacy-reviewer** (consent and the upload gate, ADR 0008);
- ui-validator only if the consent screen's look changes (it shouldn't).

**PR title:** `onboarding: Agree and continue moves on when RYFT has the consent`
