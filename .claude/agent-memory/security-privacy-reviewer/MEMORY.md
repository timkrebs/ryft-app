# security-privacy-reviewer memory (RYFT app)

- [account-switch-invariants.md](account-switch-invariants.md): where account/demo switches are handled, the
  AccountBinding pattern, APIClient epoch retries, Journal/plan caches demo split (closed a819ff5), Bedtime & wake demo
  shelf (closed round 3), TrainLibrary unbound reads + unstructured Try again, busy-rule once-only guarantees.
- [train-reads-binding.md](train-reads-binding.md): TrainLibrary `Client`/`fetch` binding guard (S-1 fix, R1; send guard +
  owner keys R4), reads bypassing ReadScheduler, Demo switch clear, TrainTodayViewModel forget (R4), ADR 0019 residue, App Attest.
- [consent-prompts.md](consent-prompts.md): analytics opt-in sheet + swipe=decline modifier, phase-1 no-op gate,
  push pre-prompt wiring, header .perform routing after SubpageHeader's deletion.
- [withdrawal-hold.md](withdrawal-hold.md): consent withdrawal lifecycle, Flight/turn, transport timeouts, the D6 hold (F2) and its
  gaps (Send first, offline minutes, auth-driven silent ends).
- [consent-agree-lag.md](consent-agree-lag.md): ADR 0025 agreement record, gate ignores it, R2 10 s status rule, agree line
  and APIClient/onboarding signposts; verified paths and the day-segment signpost finding.
- [local-notifications.md](local-notifications.md): ReminderScheduler (ADR 0024) owner/wipe/in-flight model, placeholders,
  PushPresentation, the N3 gaps (no off switch pre-N4, withdrawal, expiry push residue, wake foreground).
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
- 2026-11-20 PR 6 R4 close-out (wt-rev @ 145c91a): S-A, N-A, N-C, code S1 CLOSED; N-B closed as scoped. 0 B, 0 S. New N:
  inviteCode survives account change (R4O late-success skip widened it; test overwrites the field); waiting/sent withdrawal
  ends without a word on sign-out or Demo flip. Nit: onboarding error + request ID under Privacy survive the Demo flip.
  No logging/pasteboard/URL/entitlement/xcprivacy change; APP_STORE.md:67 Demo line now 'open' (accurate).
- 2026-11-21 Nocturne gate part 1 (feat/nocturne-gate @ 7fa1b6f): 0 B, 0 S. Analytics prompt equal/ordered/swipe=decline,
  sink still no-op, ids kept; push Allow/Not now same actions, no earlier request; headers keep .perform (cancel/asks);
  flags view #if DEBUG. Nits: CHANGELOG line 116 says 'the analytics question' w/o 'not active yet' (becomes What's New);
  Report a problem Done|Send row puts Send where the keyboard's Done was (diagnostics default on); 'Allow' on push pre-alert
  (pre-existing). No plist/entitlements/xcprivacy/logging/defaults/network change.
- 2026-11-21 F2 withdrawal hold + Train failure words (fix/withdrawal-hold @ f93387e): 0 B, 3 S (Send first logs out mid-
  withdrawal; offline hold ~5 min via waitsForConnectivity; auth-driven silent ends, follow-up), nits: DEBUG API key/URL not
  held, seam in Release (inert), hold outlasts confirmation by the re-check, CHANGELOG 'seconds'. Train offline split clean.
- 2026-11-22 F2 re-verify (wt-f2 @ dc5d882): S-1, S-2, N-1..N-4 CLOSED; S-3 open (follow-up). New nits: a timed-out DELETE may
  have been processed (app says 'No connection…', shows Given; safe direction, idempotent retry); no re-check after NoAnswer.
- 2026-11-22 F2 round 3 (wt-f2 @ 467db54, #134): 'arrived' path, deferred .consent, Log out busy/withdraw guard all fine; nits:
  'may still have arrived' also for errors that sent nothing (TLS, cannot connect, token SDK); request ID dropped for 408/2xx.
- 2026-11-22 consent agree lag (wt-dbg fix/consent-agree-lag 9f0d00d..6d3bb2b): 0 B, 1 S (APIClient attempt signposts .public
  route keeps day strings, every round trip), nits: startSync while a withdrawal's DELETE is out (other order than T9), ADR 0025
  dec. 3 wording (gate opens at 204 if cached user has V), agreement can't settle when the clock was ahead. Gate/R2/fail-fast sound.
- 2026-11-22 N3 local notifications (wt-n3 @ 0d9b463): 1 B (merge gate: journal + local fallback default-on with no in-app
  switch pre-N4), S: fallback after consent withdrawal; expiry leaves push reg, A's alerts survive to B (owner check pending-only);
  wake.* silenced in foreground; journal off reset by wipes. Nits: signed-out = mismatch for server alerts, authCallback via tap,
  requestedJournalDay across accounts, BG journal GET when denied, CHANGELOG 'never another account's data' overclaim.
  Account/in-flight/placeholders/logging/deep-link parsing sound. No plist/entitlement/xcprivacy/APP_STORE change.
