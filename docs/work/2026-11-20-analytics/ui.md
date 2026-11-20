# Analytics opt-in: the prompt and the Profile row (ui-designer, 2026-11-20)

Lead's decision: this copy replaces design.md §14/§15's draft copy ("Share usage data"). The structure of design.md
(sheet on RootView's tabs, `AnalyticsOptInRow` in `ProfileView.privacy`) stands.

## Prompt (`AnalyticsOptInSheet`)
- **Presentation:** a sheet over the tabs, not an onboarding step (it isn't a gate). Shown once, after `reachedTabs()`,
  only when no gate sheet, Health explanation or active workout is up; otherwise it waits (not marked answered).
- **Dismissal:** a swipe down counts as "Don't share" and is recorded.
- **Layout:** `OnboardingScreen(symbol: "chart.bar", …)`, accent only on the symbol; four `ConsentPoint`s (make it
  internal); the footnote; two buttons. Text in `Theme.textPrimary`, `textSecondary`, `textTertiary`.
- **Buttons:** two `PrimaryButton(style: .secondary)`, same size and style, stacked; neither accent-filled.
- **Title:** "Share anonymous usage analytics?"
- **Body:** "This is separate from your health-data consent. It stays off unless you say yes."
- **Points:**
  - "Which screens and features are used, onboarding progress, and errors shown, with their status codes."
  - "No health data, scores, sleep or workout details, names or free text."
  - "A random ID for this install. Never your account or email."
  - "Not used for tracking or ads. Sent to PostHog, in the EU."
- **Footnote:** "Change this any time in Profile → Privacy."
- **Buttons:** "Share usage analytics" / "Don't share".
- **Never shown:** flag off, analytics unavailable, demo, already answered, a sink that can't send.
- **VoiceOver:** focus starts on the title (header trait); then body, the four points (each one combined element),
  footnote, the two buttons. The symbol is hidden.
- **AX5:** everything scrolls; buttons inline after the footnote, not pinned; labels wrap (`fixedSize` vertical),
  nothing truncates; tap targets ≥ 44 pt.
- **Motion:** the system sheet only.

## Profile row (`AnalyticsOptInRow`)
- **Where:** `ProfileView.privacy`, between the consent block and the "Privacy Policy" link; one inserted line (PR #127
  restyles Profile). Hidden unless `showsToggle`.
- **Pattern:** a Demo-data-style `Toggle`, `.tint(Theme.accent)`, identifier `profile.analytics`.
- **Label:** "Share usage analytics".
- **Caption** (`textTertiary`): "Screens used and errors shown. No health data. Turning it off stops sending now and
  resets your random ID."
- **On toggle:** the system switch animation only; no dialog.
- **VoiceOver hint:** "Anonymous. Turning it off resets your random ID."

## Previews
"Analytics prompt · dark", "Analytics prompt · AX5", "Analytics prompt · AX3", "Profile · Privacy · analytics off ·
dark", "Profile · Privacy · analytics on · dark", "Profile · Privacy · flag off · dark" (row absent).
