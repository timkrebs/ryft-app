# security-privacy-reviewer memory (RYFT app)

- [account-switch-invariants.md](account-switch-invariants.md): where account/demo switches are handled, the
  AccountBinding pattern, APIClient epoch retries, JournalStore demo/account shared docs (open).
- [widget-privacy.md](widget-privacy.md): snapshot contents/protection, WidgetConcealment, gallery, Live Activity
  redaction status, notification placeholders.

Review history:
- 2026-11-19 PR 6 C (feat/nocturne-pr6-settings @ 9c0eef4): S1 Notifications save queue sends A's change as B;
  S2 (pre-existing) JournalStore cross-account; N: gallery real data, Live Activity VoiceOver combine, SIWA link w/o reauth.
- 2026-11-19 PR 6 C fix round 6c8 (feat/nocturne-6c8 @ e20bf95): S1 closed, S2 closed for accounts; open item
  (Journal docs shared Demo/account) ranked S; test gaps N (no hold for putJournal/journal(day)/impact; no sign-out-only
  or Demo-off Notifications test).
