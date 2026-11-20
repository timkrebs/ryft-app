# security-privacy-reviewer memory (RYFT app)

- [account-switch-invariants.md](account-switch-invariants.md): where account/demo switches are handled, the
  AccountBinding pattern, APIClient epoch retries, Journal/plan caches demo split (closed a819ff5), Bedtime & wake schedule per accountID in Demo (open S).
- [widget-privacy.md](widget-privacy.md): snapshot contents/protection, WidgetConcealment, gallery, Live Activity
  redaction status, notification placeholders.

Review history:
- 2026-11-19 PR 6 C (feat/nocturne-pr6-settings @ 9c0eef4): S1 Notifications save queue sends A's change as B;
  S2 (pre-existing) JournalStore cross-account; N: gallery real data, Live Activity VoiceOver combine, SIWA link w/o reauth.
- 2026-11-19 PR 6 C fix round 6c8 (feat/nocturne-6c8 @ e20bf95): S1 closed, S2 closed for accounts; open item
  (Journal docs shared Demo/account) ranked S; test gaps N (no hold for putJournal/journal(day)/impact; no sign-out-only
  or Demo-off Notifications test).
- 2026-11-19 PR 6 C re-check (wt-6c @ a819ff5, e20bf95..a819ff5): Journal/plan S-1 CLOSED; new S Bedtime & wake schedule +
  records per accountID shared with Demo (pre-existing #23); N: sheet side binding, planner async forget/wiring untested,
  no cross-switch late-answer or launch-in-Demo tests, SleepPlanner wake carries over, docs lack account tag.
