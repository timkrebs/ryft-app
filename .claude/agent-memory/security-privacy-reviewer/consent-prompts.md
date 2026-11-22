---
name: consent-prompts
description: Invariants and where-to-look for the analytics opt-in prompt and the push pre-prompt (checked on the Nocturne gate, 2026-11-21)
type: project
---
Analytics opt-in (Ryft/Features/Profile/AnalyticsOptInSheet.swift):
- View = OnboardingScreen(showsLockup:false, dismissible default true -> grabber visible) + GroupedCard of 4 OnboardingPoint
  ("What is counted", "What is not", "Your ID", "Where it goes") + footnote + two PillButton(.secondary). Pinned below AX1,
  inline from AX1. Share first, Don't share second. Ids analytics.share / analytics.decline.
- Swipe = decline lives in the private AnalyticsOptInPrompt modifier (same file): onDismiss -> setOptIn(false) only if
  !withdrawn && optIn == nil && showsPrompt. Re-check that block on every change; check no interactiveDismissDisabled.
- Phase 1: Analytics.showsPrompt requires sink.canSend; NoopSink and PostHogSink stub both return false -> nobody sees it.
- Tests: RyftTests/Analytics/AnalyticsPromptTests.swift (model, swipeCountsAsDecline), NocturneGateSweepHostedTests.swift
  D2 block (equal outline pills, order, identifiers, pinned/inline). No "anonymous" in user-facing strings (code comments in
  Analytics.swift/AnalyticsSink.swift still say it; not user-facing).
- Copy source: docs/work/2026-11-20-analytics/ui.md + review.md (title without "anonymous"; ID is pseudonymous).

Push pre-prompt: Ryft/Push/PushPrePromptCard.swift `PushAskButtons` (Allow = primary PillButton, Not now = LaterButton,
quiet text 44 pt). Used by PushPrePromptCard and TodayView ImportCard. Allow -> TodayViewModel.enablePush -> PushRegistrar.accept
-> notifier.requestAuthorization (PushRegistrar.swift ~108). "Allow" label on a custom pre-alert is pre-existing (HIG prefers
a neutral "Continue").

Headers: SubpageHeader deleted (gate DG-6). SubpageScaffold .close -> SheetHeader(onClose: action.handler) pinned; .back ->
PushedHeader(onBack: handler). `.perform` closures (SetNewPassword cancel, Import cancel-asks) covered by
NocturneFoundationHostedTests.headerActions. No privacySensitive anywhere in the app target (only widgets).
