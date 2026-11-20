# security-privacy-reviewer memory (RYFT app)

- [account-switch-invariants.md](account-switch-invariants.md): where account/demo switches are handled, the
  AccountBinding pattern, APIClient epoch retries, Journal/plan caches demo split (closed a819ff5), Bedtime & wake demo
  shelf (closed round 3), TrainLibrary unbound reads + unstructured Try again, busy-rule once-only guarantees.
- [train-reads-binding.md](train-reads-binding.md): TrainLibrary `Client`/`fetch` binding guard (S-1 fix, R1), which
  reads bypass ReadScheduler, Demo switch clear (`demoModeChanged`), process-lived TrainTodayViewModel gap, App Attest surface.
- [widget-privacy.md](widget-privacy.md): snapshot contents/protection, WidgetConcealment, gallery, Live Activity
  redaction status, notification placeholders.

Review history:
- 2026-11-19 PR 6 C (feat/nocturne-pr6-settings @ 9c0eef4): S1 Notifications save queue sends A's change as B;
  S2 (pre-existing) JournalStore cross-account; N: gallery real data, Live Activity VoiceOver combine, SIWA link w/o reauth.
- 2026-11-19 PR 6 C fix round 6c8 (feat/nocturne-6c8 @ e20bf95): S1 closed, S2 closed for accounts; open item
  (Journal docs shared Demo/account) ranked S; test gaps N.
- 2026-11-19 PR 6 C re-check (wt-6c @ a819ff5): Journal/plan S-1 CLOSED; new S Bedtime & wake per accountID shared with Demo.
- 2026-11-20 PR 6 combined (feat/nocturne-pr6 @ bd795ed, B never reviewed before): 0 B, 1 S (Train History / exercise
  page Try again -> unbound TrainLibrary reads land after sign-out/Demo switch), N: Train memory not reset on Demo switch
  (ADR 0019), journal sheet display after switch, onboarding perform() no re-entrancy guard, request-ID copy general
  pasteboard. S-1/S-2/Notifications S1 hold. No plist/entitlements/xcprivacy/APP_STORE change.
- 2026-11-20 PR 6 re-verify after R1/R2 + #128 (wt-rev @ a0bd5c2): S-1 (Train) CLOSED, N-2/N-3/N-4 CLOSED, N-1 partly
  (ADR 0019 rest). New S: TrainTodayViewModel (ScreenModels, process-lived) keeps A's lastSession/activePlan for B's Start
  sheet (no forgetter). New N: TrainLibrary.error/errorDetails + pausedKey written after await unbound, not cleared by
  wipe/demoModeChanged; withdrawConsent shares perform's !isWorking guard (silent drop). #128: only entitlements change,
  check-entitlements 7 keys ok, no token/key-ID logging in PR 6.
