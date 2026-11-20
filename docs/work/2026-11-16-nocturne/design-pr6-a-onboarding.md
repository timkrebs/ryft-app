# Nocturne PR 6, area A — signed out and onboarding (T6A.1)

Status: **draft for the user's approval (L28)**. Nothing here is built. Inputs: `brief.md`, `plan.md` (L27–L30), `design.md`
(PR 2 components, P2-8 form tokens, PR 4 conventions), `audit.md`, the PR 5 board numbers (`pr5-boards.md`, kept in the lead's scratchpad), the `ryft-app-conventions` skill.
Scope is layout and look: no model, sync, API or auth-flow change, no new strings in the catalog (§9 proposes copy; the
localization-editor finalises it). Dark only, English only. Synthetic data only ("Alex Doe", alex@example.com, 1990).

Conventions as in PR 4: boards and drafts are 390 × 844, content is **350 pt** (20 pt sides), CSS px = pt, "ink" is
`Theme.textPrimary`, ink 0.62 = `textSecondary`, 0.55 / 0.48 = `textTertiary` (value text at 0.55 where the board says so),
gaps are measured from the bottom of the element above. The top of the content is the safe-area top (D4-1); the draft
renders draw a 62 pt status area and a 34 pt home area only so they read like a phone.

Draft renders (not in the repo; kept in the lead's scratchpad, 3x, dark, 390 × 844):
`/private/tmp/claude-501/-Users-tim-krebs-Development-Projects-ryft-app/6c6f1e78-44f0-4400-b13c-ddf23bb79e65/scratchpad/pr6-drafts/a/`
(`a-<nn>-<screen>[-state].png`, list in §12). They are composed from `PillButton`, `CircleButton`, `WordmarkLockup`,
`BrandLockup`, `RyftMark`, the real Sign in with Apple button and prototypes of the primitives in §3, in a scratch hosted
test that is not committed.

---

## 1. What this covers

Named in the brief: Welcome, Log in, Create account, Reset password, Check inbox, Set new password, Sign in with Apple,
invite code, consent, About you, Apple Health, What do you wear, tracker setup, the account hint, splash, the
misconfigured-build screen, and the shared status/error banners and sheets those flows use.

**Found in the audit and the code, beyond the list** (all specified below):

| # | Screen or state | Where | Section |
|---|---|---|---|
| B1 | Welcome after a session expiry: the "You were signed out" notice | `WelcomeView.actions` (`auth.signOutNotice`) | A-1 |
| B2 | Welcome with parked activities: notice, "Delete from this iPhone", its confirmation dialog | `ParkedActivitiesNotice` | A-1 |
| B3 | Welcome with a file waiting ("Your file is ready. Sign in to continue.") | `RootView.importSignInNote`, a safe-area inset over Welcome | A-1 |
| B4 | Welcome, build without Supabase values (key banner, actions dimmed) | `SupabaseConfig.problem` | A-1 |
| B5 | Developer: use an API key (Debug only, not user-reachable in Release) | `WelcomeView` `#if DEBUG` | A-1 (unchanged) |
| B6 | Invite code and consent **as sheets over the tabs** (after the first run), not only full screen | `RootView.tabBar` `.sheet(item: sheetStep)` | A-7, A-8 |
| B7 | Set new password opened from Profile → Change password (same view, `.change`) | `SetNewPasswordView(mode:)` | A-6 |
| B8 | The Safari sheet behind every legal link (`SafariView` tints the bar's controls teal) | `Design/SafariView.swift` | A-16 |
| B9 | `HealthAccessHint` ("No Health data yet", teal "Open Health") and `HealthWriteAccessHint`: Today and Profile states that live in the onboarding file | `HealthPermissionView.swift` | A-16 |
| B10 | The embedded Check sync under the tracker cards, and Profile → Devices & sync, which share `TrackerSetupCard`, `CheckRow`, `NumberedStep` | `StatusViews.swift`, `ProfileView.swift` | A-12 (tokens only; layout is area C's) |
| B11 | Today's error card and its Details sheet (`RefreshIssueCard`, `RefreshDetailsSheet`) and the sync status line's teal actions | `StatusViews.swift` | A-16 |
| B12 | The editors opened from About you's saved rows (maximum heart rate, baseline sleep need) | `bodySettingSheet` | A-9 (opens area C's sheets) |
| B13 | The system sheets and dialogs this flow reaches: Sign in with Apple, the HealthKit permission sheet, the parked-delete confirmation | system | listed, not designed |

Not in scope and left to others: Today's `SetupCard` ("Connect RYFT", Today), `SyncStatusLineView` layout (T4.2),
`SignInMethodsView` (area C; it sits in `AuthComponents.swift` today, §10 moves it), `TrackerPickerSheet` (area C),
`TrackerCheckView` layout (area C).

## 2. Grammar for this area

The shared grammar of the PR 5/6 boards (L27 and the boards' numbers), applied to forms and steps. Every number is a token or
a named constant on its component.

| # | Rule |
|---|---|
| G1 | **Teal is recovery only (L27).** No teal anywhere in area A except the Recovery legend mark on Welcome. Links, checkmarks, toggles, glyphs, the paste chip, the Safari bar: `textPrimary` (or `textSecondary` for quiet ones). Volt: not used in this area. |
| G2 | **Primary action** = `PillButton(.primary)`: light fill, dark 40 pt icon circle, 52 high. **Secondary** = `PillButton(.secondary)` outline. **Quiet third action** ("Not now", "Skip", "Show me again later") = a 44 pt high text button, `Font.ryft(.body)`, `textSecondary`, centred. **Link** = underlined text in `textPrimary` (inline links in a small caption: `textSecondary`), never colour alone. |
| G3 | **Screen header**: 40 high, title 26 pt Light, tracking −0.01 em. Pushed screens: a 40 pt `CircleButton` (`chevron.left`, "Back") then 12 pt then the title. Sheets: the title, a `CircleButton` (`xmark`, "Cancel") at the trailing edge. First-run onboarding steps: `WordmarkLockup()` (mark 26, wordmark 15) leading, no title in the row; the step's title is the first block under it. |
| G4 | **Forms are grouped cards** (`surface`, radius `Theme.Metrics.neutralTileRadius` 22) with hairlines ink 0.06 between rows. A **field row** carries a label, so it is **56 high** (label 13 pt `label` at `textSecondary`, 2 below it the value 16 pt `body` in `textPrimary`; padding 8 / 16); a **list row** (About you's saved values) is **46 high**, padding 0 / 16, value at ink 0.55. Group titles 13 pt at ink 0.55, 8 above their card. See D6A-1. |
| G5 | **Focus** is the system caret plus, in the focused row, the label turning `textPrimary` and a 2 × 28 pt `textPrimary` bar, capsule, inset 6 from the card's leading edge. No fill: a 6 % fill is 1.15:1 against `surface` and tells nobody anything (D6A-8). |
| G6 | **Banners and errors** (shared `InlineMessage`, restyled once, §3): `surface` fill, radius 22, no stroke, padding 14 / 16, a 16 pt glyph centred in a 24 pt column (so stacked banners start their sentences on one line) and the sentence in `textPrimary` (15 pt), caption `textSecondary`, text buttons below ("Try again" Medium in `textPrimary`, underlined at 35 % as C §2.6's text link, as is a plain action; "Details" `textSecondary`). Errors are **neutral**, no coral: the glyph and the words carry the state (D6A-9). One banner per screen, 12 below the form, 12 above the primary. |
| G7 | **Busy**: the pill keeps its place, its title becomes the progressive form ("Logging in…") and its arrow circle shows a small `ProgressView`; it is not dimmed, it is not tappable; the form stays visible. No full-screen spinner anywhere in this area. Marked *shared, to reconcile with T5.0* (§3, `PillButton` busy). **Disabled** = the existing 35 % pill. |
| G8 | **Destructive**: nothing in area A needs a destructive pill. "Delete from this iPhone" is an outline pill/text button; the red appears only in the system confirmation dialog's `.destructive` button. So no destructive proposal is made here. |
| G9 | **Metric colours** appear only where a metric is named and nothing is measured: the three Welcome value lines (§A-1). No glow tile, no numeral, no ruler, no dot row in this area. |
| G10 | **Motion**: ≤ 250 ms (`Theme.Motion.quick`), none under Reduce Motion. Banners fade in (`quick`). Step changes cross-fade with `quick` (today 0.4 s in `OnboardingFlowView` and 0.3 s `easeInOut` in `RootView`, the latter ignoring Reduce Motion; D6A-11). |
| G11 | **Padding** 20 on both sides (350 content), `maxWidth` 480 centred on wide windows. Auth and onboarding use 24 and 28 today (D6A-5). |

## 3. Shared primitives requested

Nothing here is a one-off variant. Owner of all of them: **T6A.2** (§11). "Also needed by" names the other PR 5/6 areas that I
expect to ask for the same thing; whoever lands first creates it, the others rebase.

| Primitive | File | What | Why not an existing component | Also needed by |
|---|---|---|---|---|
| `FormGroup`, `FormRow` | `Design/FormGroup.swift` (new) | The grouped field card of G4: `FormGroup { FormRow(...); FormRow(...) }`; a row = label + a `TextField`/`SecureField`/content slot + optional trailing view; the focus bar of G5; the hairlines; `isInvalid`-free (errors are banners). Constants `FormGroupSpec.rowMinHeight = 56`, `hairlineOpacity = 0.06`, `focusBar = 2 × 28`, `focusInset = 6`, padding `8 / 16`. At AX sizes the trailing view moves under the value. | `AuthTextField` / `PasswordField` (grey `surfaceRaised` 60 % fields, radius 12) are the old look and live in `AuthComponents.swift` | Profile sheets with fields (C), Add activity / Add sleep (B), Report a problem (C) |
| `ListGroup`, `ListRow` | `Design/ListGroup.swift` (new) | The board's grouped list: card radius 22, rows min 46, padding 0 / 16, value at ink 0.55, optional caption line (12 pt, `textTertiary`), optional chevron (`chevron.right` 12 pt, `textTertiary`), group title above. `Theme.Metrics` gets `listRowHeight = 46`. | None; the Profile list (PR 5) draws the same thing. **If PR 5's ticket lands it first, T6A.2 uses it as is.** | Profile main list (PR 5), Profile subpages (C), Devices & sync (C) |
| `PillButton` busy | `Design/PillButton.swift` | `PillButton(…, isBusy: Bool = false)`: primary shows a `ProgressView(.small)` (tint `textPrimary`) in the 40 pt circle instead of the arrow, not dimmed; secondary shows its (changed) title, not dimmed. Taps ignored while busy; VoiceOver value "Busy". **Shared, to reconcile with T5.0**, which has to give `PrimaryButton`'s `busy` a home when it retires it. | `PillButton` says "no busy state: the caller disables and changes the title"; that dims the pill to 35 % mid-request, which reads as a failure | everything T5.0 migrates |
| `LinkText` | `Design/LinkText.swift` (new) | A localized Markdown string drawn as `Text` with its link runs underlined (`underlineStyle = .single`) and tinted `textSecondary` or `textPrimary`; the existing `safariSheet` `OpenURLAction` keeps routing the links; the Links rotor still reaches them. | `Text("… [Privacy Policy](…)")` cannot be underlined by a modifier; link colour alone fails 1.4.1 | Create account, Welcome, Profile footers (C) |
| `LinkButton` | `Design/LinkText.swift` | A 44 pt high underlined `textPrimary` button, `Font.ryft(.callout)`, optional trailing `arrow.up.right` (11 pt, `textTertiary`, joined to the last word with a no-break space so it never wraps alone); trait `.isLink`. | Consent's "Read the privacy policy" and Health's "Privacy Policy" are teal `Button`s | Profile (C) |
| `PinnedBar`, `TextActionButton` | `Design/PinnedBar.swift` (new; today private to `HealthPermissionView.swift` as `PinnedBar` and `LaterButton`) | The bar under a long step: padding 12 / 20 / 4 (top / sides / bottom), `background`, 1 pt `Theme.separator` rule on top (the tab bar's rule), content centred, `maxWidth` 480; the 44 pt text action of G2. Same numbers as today. | Already exists, private | Add sheets (B/C) |
| `LegendMark` | `Design/LegendMark.swift` (new) | The Welcome value line's mark: a 28 pt ring (track ink 0.16, 1.5 pt) with a 2.5 pt round arc over 62 % in the metric colour and the gauge's end dot (r 3.5, 1.5 pt `background` ring). 28 pt at the default size, `@ScaledMetric(relativeTo: .headline)` capped at 44; `accessibilityHidden`. The arc is the same length for all three: it is a legend, not a value. | Replaces the teal glyph in a 46 pt outlined circle | Insights legend, About (C) if wanted |
| Restyled in place | `Design/StatusViews.swift`, `Design/Card.swift`, `Design/SafariView.swift` | `InlineMessage` (G6), `SelectableTile` (§A-11), `CheckRow.Kind`, `CapabilityState`, `NumberedStep`, `TrackerSetupCard` header (§A-12), `SafariView.preferredControlTintColor = textPrimary`. Tokens only. | | Today's error card gets the new `InlineMessage` for free |

New constants go on their component (`FormGroupSpec`, `LegendMarkSpec`, `PinnedBarSpec`, §P2-9 style, `nonisolated static let`),
except `Theme.Metrics.listRowHeight` and `Theme.Metrics.fieldRowHeight = 56`.

## 4. Screens in one table

| § | Screen | Frame | Primary | Quiet | Draft |
|---|---|---|---|---|---|
| A-1 | Welcome | `ViewThatFits`: fixed layout / scrolling at AX | Sign in with Apple (system, white) | Create account (outline), Log in (link) | a-01, a-01-ax3, a-01-ax3-end, a-02 |
| A-2 | Log in | pushed, scroll | Log in | Forgot password? (link) | a-03, -error, -busy, -ax3 |
| A-3 | Create account | pushed, scroll | Create account | Terms / Privacy links | a-04 |
| A-4 | Reset password | pushed, scroll | Send reset link | | a-05 |
| A-5 | Check your inbox | pushed, scroll | Open Mail | Resend (outline), Use another email (link) | a-06 |
| A-6 | Set new password / Change password | sheet | Save password | Cancel (circle, top) | a-07 |
| A-7 | Invite code | full screen or sheet, scroll | Continue | Not now; Use another account (outline) | a-08, -error |
| A-8 | Consent | full screen or sheet, scroll, actions inline | Agree and continue | Not now | a-09 (+ -end, -changed, -ax3, -ax3-end) |
| A-9 | About you | full screen, pinned bar | Continue | Skip | a-10-about-you, -year, -saved |
| A-10 | Connect Apple Health | full screen, pinned bar | Continue | Not now | a-11 |
| A-11 | What do you wear? | full screen, pinned bar | Continue | Skip | a-12 |
| A-12 | Set up your trackers | full screen, pinned bar | Done | Show me again later; Check sync (outline) | a-13 |
| A-13 | This is a new RYFT account | sheet | Use the other account | Continue with this one (outline) | a-14 |
| A-14 | Splash | full screen | | | a-15, a-15-waiting |
| A-15 | Misconfigured build | full screen | | | a-16 |
| A-16 | Banners, Details sheet | shared | | | a-17, a-18 |

---

## A-1. Welcome

**Purpose.** The first thing a stranger sees. It says what RYFT is in three lines and offers three ways in. The lock-up and
tagline are already Nocturne (`BrandLockup`) and stay as they are.

**Hierarchy.** First the lock-up, second the three metric lines, then the ways in, strongest at the bottom edge under the
thumb: Sign in with Apple, Create account, "Have an account? Log in", the privacy line.

**Layout** (`a-01`, 390 × 844, content 350, default size). Column, top to bottom, the same `Spacer(minLength: 32)` rhythm as
today so the ways in sit at the bottom: 32+ · `BrandLockup` (mark 44, wordmark 32, tagline 13 pt at 0.62, 14 apart; unchanged) ·
32+ · value lines · 32+ · actions · 12 bottom padding.

| Element | Spec |
|---|---|
| Value lines | Three rows, gap 22, leading aligned, `maxWidth` 360. Row: `LegendMark` (28) in violet (`metricSleep`) for Sleep, teal (`recovery`) for Recovery, blue (`metricStrain`) for Strain; 16 gap; name 17 pt Medium (`headline`) `textPrimary`; 2 below it the sentence 15 pt (`callout`) `textSecondary`. The mark aligns to the name's first line (1 pt down). One accessibility element per row, label "Sleep. Stages, need and debt, every night." (the mark is hidden). Sentences unchanged. |
| Sign in with Apple | The system `SignInWithAppleButton(.continue)`, style **`.white`** (the allowed style on a dark ground: the black style vanishes on `#0A0C0B`, the outline style is for white grounds), height 52 (`@ScaledMetric`, capped at 64, Apple's range), `clipShape(RoundedRectangle(26, .continuous))`, full width. Apple permits the corner radius; the label, the logo and the fill stay Apple's. While `auth.isWorking`: a `background` 60 % veil with a small `ProgressView` (as today). |
| Create account | `PillButton(.secondary)`, 12 below. |
| Log in | A 44 pt row, 12 below: "Have an account?" 15 pt `textSecondary`, 6 gap, "Log in" 16 pt Medium `textPrimary`, underlined. The whole row is one button. At AX sizes the two stack (prefix above, "Log in" below, 44 high). |
| Privacy line | 12 below. 12 pt caption, centred, `textTertiary`; the words "Privacy Policy" are a link, underlined, `textSecondary` (`LinkText`). Wording unchanged: "Your data is stored on the RYFT platform. Privacy Policy". |
| Debug | "Developer: use an API key" stays as is (Debug only). |

The ways in are `.disabled(!auth.isConfigured)` (35 %), with the key banner above them (B4).

**States.**

| State | Trigger | What the screen shows |
|---|---|---|
| Default | signed out | as above |
| Signed out by expiry (B1) | `auth.signOutNotice` | banner "You were signed out. Log in again to continue." (glyph `person.crop.circle.badge.exclamationmark`), 12 above the Apple button, id `welcome.notice` |
| Parked activities (B2) | `ParkedActivitiesNotice.parkedToMention` | a second banner with the count and the date, one text action "Delete from this iPhone" (neutral, in the banner's button row); the confirmation is the system dialog (title "Delete them from this iPhone?", destructive "Delete", cancel "Keep") |
| File waiting (B3) | `importer.hasFileForSignIn` | banner "Your file is ready. Sign in to continue." (glyph `doc.text`) in the top safe-area inset, 20 sides, 8 below the status bar |
| Not configured (B4) | `SupabaseConfig.problem` | banner with the problem text (glyph `key`), actions at 35 % |
| Sign-in failed | `auth.errorMessage` | the banner of G6 under the ways in, above the privacy line (`AuthErrorMessage`) |
| Busy | Apple sheet open | the veil on the Apple button; the others disabled |

`a-02` shows B1 and B2 together (the worst case that still fits at 844: two banners of about 63 and 93 pt, the spacers
tighten to their 32 pt minimum; nothing scrolls). More than that, or any AX size, switches to the scrolling child.

**Scrolling and keyboard.** `ViewThatFits(in: .vertical) { fixed; ScrollView { fixed } }`, exactly the #115 structure, kept: the
privacy line wraps whole and its link stays reachable. At AX3 (`a-01-welcome-ax3`, `a-01-welcome-ax3-end`) the content is about 1100 pt tall: lock-up
and the three lines first, the ways in further down in the same scroll. `LegendMark` grows with the text (to 44 at most),
the Apple button grows to 64, the outline pill wraps, "Have an account?" stacks. No text field here, `.ignoresSafeArea(.keyboard)`
stays.

**Accessibility.** Reading order: lock-up (trait header, label "RYFT — Engineered for peak."), Sleep, Recovery, Strain,
[banners], Continue with Apple, Create account, "Have an account? Log in" (button), Privacy line (static text; the Links rotor
reaches "Privacy Policy"). Banners come before the actions so the reason is read first. Reduce Motion: nothing moves on this screen.

**Strings.** New: `Have an account?`. Unchanged: the three lines, "Create account", "Log in", the privacy line, notices.

**Previews** (dark only, replacing the current six): Welcome, Welcome · AX3, Welcome · signed-out notice, Welcome · parked
activities, Welcome · file waiting, Welcome · not configured.

**Tests.** The two #115 hosted tests (`welcomePrivacyLine`, `welcomeHasNoOverlap`) keep passing at AX3 and AX5 and are extended:
`Log in` is reachable by scrolling and activating its node pushes `.logIn`; the Apple button's node is present and its frame
height is between 52 and 64.

---

## A-2. Log in (`a-03`, `a-03-login-error`, `a-03-login-busy`, `a-03-login-ax3`)

**Purpose.** Email and password, nothing else. Errors never say whether an email has an account (unchanged).

**Layout.** Pushed onto Welcome's stack, Welcome's navigation bar stays hidden, so the screen draws its own header: G3 pushed:
`CircleButton(chevron.left, "Back")` + 12 + "Log in" 26 pt Light, row 40 high at the safe-area top. 24 below the row: a `FormGroup`
with two rows (Email 56, hairline, Password 56 with a trailing 44 × 44 eye button: `eye` / `eye.slash` 15 pt `textSecondary`,
label "Show password" / "Hide password"). 4 below the card a trailing "Forgot password?" `LinkButton` (callout, `textSecondary`
underlined, 44 high). Then the error banner (if any) 12 above the primary `PillButton` "Log in". Space below is empty.

**States.**

| State | Trigger | Shown |
|---|---|---|
| Empty | on appear | Email focused (focus bar), primary at 35 % |
| Valid | `isEmail && !password.isEmpty` | primary enabled |
| Busy | `auth.isWorking` | primary busy, title "Logging in…", rows not editable |
| Wrong credentials | server | banner "Email or password is wrong." |
| Unconfirmed | server | banner "Confirm your email first: open the link we sent you." |
| Rate limited | 429 | banner "Too many attempts. Wait a minute and try again." (the primary stays enabled; the platform decides) |
| Offline | transport | banner "No connection. Check your internet and try again." |
| Other | anything else | banner "Something went wrong. Please try again." |

**Keyboard.** Email: `.emailAddress`, `.username`, `.submitLabel(.next)` → focus Password; Password: `.password`, `.submitLabel(.go)`,
submits when valid. Email takes focus when the push has finished (one `@FocusState`; the keyboard is part of the screen).
`scrollDismissesKeyboard(.interactively)` stays. At 844 the card ends near y = 238 and, with a banner, the primary near y = 400, above a 336 pt
keyboard's top (508).

**Swipe back** must keep working with the nav bar hidden and the system back button gone: a small modifier re-enables
`interactivePopGestureRecognizer` (D6A-6), tested by an XCUITest edge swipe.

**AX3** (`a-03-login-ax3`): the title wraps beside the back circle (40/44 pt, does not scale; Large Content Viewer on it), the
rows grow, the pill grows, everything scrolls. Reading order: Back, "Log in" (header), Email, Password, Show password, Forgot
password?, [error], Log in (button). The disabled primary carries the hint "Fill in your email and password first."

**Strings.** New: `Logging in…`, hint `Fill in your email and password first.`, `Back`. Existing: the rest.

**Tests.** Hosted: Email, Password rows are single elements labelled "Email" / "Password" (value read); focus order; at AX3 no
overlap and the primary reachable; busy pill value "Busy" and `isEnabled` false; pop gesture enabled (`interactivePopGestureRecognizer?.isEnabled`).

---

## A-3. Create account (`a-04`)

Header "Create account" (pushed). 12 below: the lead sentence 16 pt `textSecondary` ("One account for your sleep, recovery
and strain."). 24 below: `FormGroup` with Name (`.name`, words), Email, Password (new password, eye). 8 below the card, 4 in:
the hint "At least 10 characters." 13 pt at `textSecondary` (it explains the disabled button, so not `textTertiary`). 20 below:
primary "Create account" (busy: "Creating account…"). 16 below: the terms line, 12 pt `textTertiary`, "Terms" and "Privacy
Policy" as `LinkText` (underlined, `textSecondary`), opening the in-app Safari sheet; wording unchanged.

States as A-2, plus server messages: weak password ("Choose a stronger password with at least 10 characters."), reused password,
email in use ("This email can't be used for a new account. Log in instead, or reset your password."), signups closed ("New accounts
can't be created right now."), bad email ("Check the email address."). After success without a session the stack pushes Check your
inbox. Keyboard: Name `.next` → Email `.next` → Password `.go`. At 844 the card ends near y = 330 and the primary near y = 430: above the
keyboard's top (508). Reading order: Back, title, lead, Name, Email, Password, Show password, hint, [error], Create account, terms line
(Links rotor: Terms, Privacy Policy). **Strings** new: `Creating account…`.

## A-4. Reset password (`a-05`)

Header "Reset password"; lead "Enter your account's email. We'll send you a link to set a new password."; a one-row `FormGroup`
(Email, prefilled from Log in's email, focused); primary "Send reset link" (busy "Sending…"). Errors as A-2 (offline, rate limited,
other). The next screen is Check your inbox. **Strings** new: `Sending…` (shared with A-5).

## A-5. Check your inbox (`a-06`)

**Purpose.** A waiting state: the link is in the mail and opens the app by itself. **Pending is an outline**: instead of the
teal 44 pt `envelope.badge` the screen has a 72 pt circle, 1 pt stroke at ink 0.16 (the circle button's border), with an
`envelope` glyph 26 pt Light in `textPrimary` centred, 32 above and below.

Column: header (pushed) · 12 · lead = the existing subtitle, `confirmSignUp`: "We sent a confirmation link to alex@example.com." /
`resetPassword`: "If alex@example.com has a RYFT account, we sent it a link to set a new password." · the outline circle ·
"Open the link on this iPhone. It's valid for an hour." 16 pt `textSecondary` · 24 · primary "Open Mail" with the icon
`arrow.up.right` (it leaves the app) · 12 · secondary "Resend" · 4 · "Use another email" `LinkButton` centred (pops to the form) ·
[banner].

| State | Shown |
|---|---|
| Idle | as above |
| Resending | secondary title "Sending…", not dimmed, taps ignored |
| Sent | secondary "Sent again", disabled (35 %); VoiceOver announces "Sent again"; the state stays until the screen is left |
| Failed | banner "Something went wrong. Please try again." / offline text; "Resend" stays available |

Reading order: Back, title, lead, "Open the link on this iPhone…", Open Mail, Resend, Use another email, [error]. The circle is
`accessibilityHidden`. **Strings** new: none beyond `Sending…`.

## A-6. Set new password / Change password (`a-07`)

A sheet (the root's `needsNewPassword` sheet, and Profile → Change password). `.presentationBackground(Theme.background)`,
grabber visible, `NavigationStack` toolbar replaced by the screen's own header (G3 sheet): title "Set new password" (recovery) or
"Change password", `CircleButton(xmark, "Cancel")` trailing. Below: lead (recovery only) "Choose a new password for your RYFT
account." · `FormGroup` with "New password" (new-password content type, eye, focused) · hint "At least 10 characters." ·
primary "Save password" (busy "Saving…"). Saved: a row "Password saved." with `checkmark.circle` 17 pt in `textPrimary`
replaces the hint line (announced), the sheet dismisses after 0.8 s (unchanged). Errors: "This link has expired or was already used.
Request a new one.", "Choose a password you haven't used before.", offline, other, under the card. Cancel clears
`needsNewPassword`. Reading order: header (title, then Cancel) → lead → New password → Show password → hint → [error] → Save password; the sheet traps focus. **Strings** new: `Saving…`.

---

## A-7. Invite code (`a-08`, `a-08-invite-error`)

**Frame (all onboarding steps).** First run: full screen, `ScrollView`, padding 20, header row = `WordmarkLockup()` (40 high), 24 below
it the step title (26 Light, tracking −0.01 em, wraps), 12 below the lead (16 pt `textSecondary`), 24 below the content. As a
sheet over the tabs (B6, after the first run) the lock-up row is dropped and the content starts 24 below the grabber:
`model.isFirstRun` decides. The old 30 pt teal symbol above the title is gone in every step.

**Layout.** `FormGroup` with one row: label "Invite code", value in the system monospaced 16 pt (`.characters`, no autocorrect,
`.oneTimeCode`, `.go`), prompt "RYFT-XXXX-XXXX" in `textSecondary`; trailing the system `PasteButton` (icon only, capsule, tint
`surfaceRaised` so it reads as a quiet chip; ink on it is 11.6:1; if the glyph is not legible on device the tint falls back to
`textPrimary`). 12 below: banner (if any) then primary "Continue" (busy "Checking…"), "Not now" text action (only while
`canDefer(.invite)`, i.e. not for an enforced gate), a hairline, "Signed in with the wrong account?" 15 pt `textSecondary`,
secondary pill "Use another account". The keyboard rises on appear when the field is empty and no launch overlay covers it
(unchanged logic); with it up, everything down to "Not now" stays visible at 844.

**States.** Empty (primary disabled) · typing (uppercased, primary enabled) · prefilled from `ryft://invite/<code>` (filled, no
autofocus) · busy · refused (422: "This code doesn't work. Ask the person who invited you for a new one.") · rate limited (429: "Too many
tries. Wait an hour, then try the code again.") · other. **Gap found:** for any other failure the step shows `error.localizedDescription`,
the system's English ("The Internet connection appears to be offline."). Proposed: "No connection. Check your internet and try again."
when offline and "Something went wrong. Please try again." otherwise (the same sentences as `AuthMessage`; a string-only change in
`redeemInvite`'s `message:` closure, ios-developer decides).

**Sheet variant.** `interactiveDismissDisabled` when the gate is enforced; no "Not now" then. Reading order: title (header), lead,
Invite code field, Paste, [error], Continue, Not now, "Signed in with the wrong account?", Use another account.
**Strings** new: `Checking…`. **Tests**: the existing `shouldFocus` test stays; hosted: the field's node is labelled "Invite code".

## A-8. Consent (`a-09`, `a-09-consent-end`, `a-09-consent-changed`, `a-09-consent-ax3`, `a-09-consent-ax3-end`)

Wording, the policy link, the minimum-age line and the checkbox rule (a separate, unticked, deliberate tick) are unchanged;
only the layout and the colours change.

Column: header row · title "Your health data, your consent" · lead · **points card** (a `ListGroup`-style card, radius 22, four
points separated by hairlines, each point padding 16: a 17 pt neutral glyph (`textPrimary`) in a 28 pt column, 12 gap, title 16 pt
Medium `textPrimary`, 3 below it the text 15 pt `textSecondary`) · 20 · the minimum-age line "You must be at least 16 to use RYFT."
15 pt, **`textPrimary`** (it is a gate, it does not sit in grey) · the policy `LinkButton` "Read the privacy policy" (or "What changed")
with `arrow.up.right` · 4 · the **checkbox card** (`surface`, radius 22, padding 16, glyph 22 pt: `square` in `textSecondary` /
`checkmark.square.fill` in `textPrimary`, scaled with the text; ticked adds a 1 pt `textPrimary` 32 % border; the shape change, the border
and the `.isSelected` trait carry the state, not colour) · 16 · primary "Agree and continue" (disabled until ticked; busy "Saving your
consent…") · "Not now" · the version caption 12 pt `textTertiary` "Nothing is synced until you agree. Privacy policy version 2026-10.".

**Actions stay inline, not pinned (D6A-11).** A pinned primary that is dimmed while its reason (the box) is two screens away tells the
user nothing, and the box cannot be pinned with it at AX sizes (its label is 8 lines at AX3). So the whole step is one scroll that ends
in the box and the button, as today. At default size the content is about 1000 pt: the actions are reached by scrolling.

**AX3** (content about 2650 pt): each point stacks (glyph above the title, text at full width 310), the link wraps whole with its glyph
attached to the last word, the checkbox card and the pill grow. Everything is reachable by scrolling; nothing is truncated.

| State | Trigger | Shown |
|---|---|---|
| Default | first consent | as above, box unticked, primary at 35 % |
| Ticked | tap | border, filled glyph, primary enabled; announced "Ticked" via the trait |
| Policy changed | `model.earlierConsent` | a banner first (glyph `doc.badge.clock`): "The privacy policy changed since you agreed on 3 November. Read what changed, then agree again."; the link reads "What changed" |
| Busy | `agree()` | pill busy "Saving your consent…", box and "Not now" disabled |
| Policy updated meanwhile | 422 | banner "The privacy policy was just updated. Read the new version, then agree again." |
| Offline / other | transport | the same two sentences as A-7's proposal (today the system text) |
| Sheet | after the first run | no lock-up row; "Not now" defers for this session |

Reading order: title (header), lead, [banner], the four points (each one element "What RYFT reads. Heart rate, …"), the age line, the
link, the checkbox (button + selected trait, label = the agreement sentence), Agree and continue, Not now, the caption.
**Strings** new: `Saving your consent…`. **Tests**: hosted at AX3 and AX5: no two elements overlap; the policy link is reachable and the
Links/activate path opens `model.policyPage`; the checkbox node toggles `isSelected`; Agree is not enabled before ticking; the age line is
present (`consent.minimumAge`).

## A-9. About you (`a-10`, `a-10-about-you-year`, `a-10-about-you-saved`)

Header row, title "About you", lead (unchanged: "Your birth year gives an estimate of your maximum heart rate, which strain and heart-rate
zones are measured against. RYFT keeps only the year."), pinned bar.

*Choosing.* A group title "Birth year" (13 pt, ink 0.55), 8 below it a card (`surface`, radius 22) holding the wheel picker, 176 high, first
row "Choose your birth year" (selection nil), years newest first from `today − 16` to 1920. Pinned: "Continue" (disabled until a year is
chosen; busy "Saving…") and "Skip" (text action). The wheel's rows are `textPrimary` on the card.

*Saved.* After `saveAboutYou`, the group title reads "Estimated from your birth year" and the card becomes a `ListGroup` with two 46+ rows
that open area C's editors: "Maximum heart rate" · **183 bpm** (detail "Estimated from your age (born 1990)") and "Baseline sleep need" ·
**7 h 40 min** (detail "Learned · updated Sun"), values at ink 0.55 in tabular digits, a `chevron.right` each; under the card, 8 below,
12 pt `textTertiary`: "RYFT adjusts this from your nights unless you set it." Pinned: "Continue" only. These two numbers are settings,
not scores, so they take list rows and no `DotNumeral` or ruler (G9).

States: empty · chosen · busy · server refusal (field error: banner "Choose a year between 1920 and 2010." above the pinned bar's content,
under the wheel) · offline/other (as A-7) · saved · editing (sheet, area C). Reading order: title, lead, group title, "Birth year" wheel
(adjustable, value read), Continue, Skip; saved: the two rows (each "Maximum heart rate, 183 bpm, Estimated from your age (born 1990)",
button), the note, Continue. At AX3 the wheel keeps its 176 pt (a picker does not scale), the rows wrap their detail, the pinned bar is
about 125 pt. **Strings** new: `Estimated from your birth year`. **Tests**: hosted: Continue disabled until a year is chosen; saved rows
are buttons; AX3 pinned bar ≤ 25 % of the window.

## A-10. Connect Apple Health (`a-11`)

Header row (`WordmarkLockup`), 24 below a **72 pt mark**: a 1 pt ink 0.16 circle with a light heart outline (`heart`, 34 pt ultra-light,
`textPrimary`) and the pulse line across it (1.5 pt, `textPrimary`, 44 × 14). It replaces the 96 pt teal-tinted illustration; the pulse
draws in **once** (0.6 s, `Theme.Motion.slow`) and then holds, under Reduce Motion it is drawn at rest. The 2 s loop of today breaks the
"no looping motion" rule (D6A-7). 20 below: title "Connect Apple Health"; 12 below: the lead; 20 below: a three-point card (as consent: "What
RYFT reads", "Where it goes", "You decide", glyphs `waveform.path.ecg`, `server.rack`, `hand.raised` in `textPrimary`); under it the
"Privacy Policy" `LinkButton`. **Pinned bar:** "Continue" and "Not now". The content scrolls under the bar with the bar's rule on top.

| State | Shown |
|---|---|
| Explain | as above |
| Requesting | the system sheet is up; the primary is busy "Waiting for Apple Health…", "Not now" disabled; nothing else changes |
| Denied (declined or failed) | the step ends and the tabs show their empty states with `HealthAccessHint`; there is no error on this screen |

Reading order: title (header), lead, the three points, Privacy Policy, Continue, Not now (the mark is hidden). At AX3 the points stack as in
consent. **Strings** new: `Waiting for Apple Health…`. **Tests**: the existing intro tests keep passing; hosted: both pinned actions
reachable at AX3, no overlap.

## A-11. What do you wear? (`a-12`)

Header row, title, lead (unchanged), the tile grid, the caption (12 pt `textTertiary`, unchanged text), pinned bar "Continue" (disabled until a
tile is chosen) and "Skip". The grid is today's (`TrackerPickerGrid`: two columns, gap 10, "Other" and "Just my iPhone" full width and last,
one column at accessibility sizes or when a word would break). **`SelectableTile` restyle (tokens only):** `surface` fill (selected does not
change the fill), radius 22, no stroke when off; **selected: a 1.5 pt `textPrimary` 90 % border**, the glyph `textPrimary` (off: `textSecondary`),
the mark `checkmark.circle.fill` in `textPrimary` (off: `circle`, `textTertiary`). The check's shape and the border carry the selection, not
colour. 56 high, padding 12, glyph 20 pt. States: none picked · some · "Just my iPhone" alone (picking it clears the others, announced "Other choices
cleared") · AX single column. VoiceOver: the grid is a container "What do you wear?" with the hint "Choose all that apply"; each tile a button
with `.isSelected`; ids `wear.tile.<id>` unchanged. **Tests**: tile selection trait; the shape of the selected tile differs from the off tile (not colour only).

## A-12. Set up your trackers (`a-13`)

Header row, title ("Set up your tracker" / "Set up your trackers"), lead "A few minutes now saves a silent week of missing data.", the cards,
"Check sync" outline pill (12 above it) and its result below, pinned "Done" / "Show me again later".

The card keeps its structure and moves to tokens (shared with Profile → Devices & sync, so this is the one place it is specified):
`Card` is `surface`, radius 22; the disclosure header: glyph 22 pt `textSecondary`, name 17 Medium, verdict 15 `textSecondary`, `chevron.down` 13 pt
`textTertiary`; hairline between header, summary and the signal list; the group title "What reaches RYFT" 13 pt ink 0.55;
`CheckRow` rows 46 min: **arrived = `checkmark.circle.fill` in `textPrimary`, expected gap = `minus.circle` in `textTertiary`, waiting/neutral/late
unchanged in shape; "should arrive and doesn't" = `exclamationmark.circle` in `warning`** (the one status colour kept, it is a fault with a fix under it);
the result at `textSecondary`; `NumberedStep`: a 18 pt outlined circle (1 pt `textPrimary` 32 %) with the number in `textPrimary`, no tinted fill; store and
"Add a tracker" buttons: `PillButton(.secondary)`. States: one tracker (card open, no disclosure) · several (first open, others collapsed) · later
(a card put off closes, the next opens) · check open (embedded `TrackerCheckView`, area C owns its layout). Reading order per card: header (button, "Garmin, Heart
rate, sleep, workouts · no HRV", Expanded/Collapsed), summary, "What reaches RYFT" rows, steps ("Step 1 of 4, …"), buttons; then Check sync, then the pinned bar.

## A-13. New-account hint (`a-14`)

A sheet, detents `.medium` and `.large`, `interactiveDismissDisabled` (the choice is required), `presentationBackground(background)`.
Grabber, 24 below it the title "This is a new RYFT account" (26 Light), 12 below the text (16 pt `textSecondary`; one of three variants by
`otherProvider`: email, apple, other), 24 below `PillButton(.primary)` "Use the other account" (ids `hint.useOther`), 12 below `PillButton(.secondary)`
"Continue with this one" (`hint.keep`), 16 below the caption 12 pt `textTertiary` "Data in both accounts? Support can merge them: ryftapp.de/support" (the
address stays plain text; the domain chore owns its spelling). The teal `person.2` glyph is dropped. At AX sizes the sheet opens at `.large` and scrolls.
Reading order: title (header), text, Use the other account, Continue with this one, caption.

## A-14. Splash (`a-15`, `a-15-splash-waiting`)

The mark, 64 pt, `textPrimary`, centred on `background`: **identical in place and size to the launch screen so nothing jumps** (unchanged).
**New state, a reason:** a restore normally takes under a second, but the first run waits up to `checkTimeout` (10 s) on this screen. After 3 s a
caption appears 58 pt below the mark's centre, 13 pt `textSecondary`: "Checking your account…" (fade `quick`, none under Reduce Motion). The mark never
moves. VoiceOver: the mark's label "RYFT"; the caption is announced when it appears. **Strings** new: `Checking your account…`. This is the one
behavioural addition in this spec (a 3 s timer in `SplashView`); drop it if the user prefers (Q4).

## A-15. Misconfigured build (`a-16`)

Release builds only, a dead end by design. `RyftMark` 56 pt, 24 below the title (26 Light, centred, "This build is misconfigured"), 12 below the text
(16 pt `textSecondary`, centred, 32 side padding): "It's missing RYFT_API_URL. Install the latest version of RYFT." (the audit's empty list reads "It's missing ."; the
preview must pass a sample, e.g. `["RYFT_API_URL"]`, and the view should not render a sentence with an empty list). `Theme.background` replaces `Theme.graphite`.
The copy drops "from the App Store": beta testers install from TestFlight. **Strings** changed: the sentence (§9).

## A-16. Status banners and the Details sheet (`a-17`, `a-18`)

**`InlineMessage`** is restyled once (G6) and every flow inherits it (auth errors, onboarding errors, Today's error card, notices):
surface fill (opaque `surface`, was 60 %), radius 22 (was 16), no 1 pt stroke, glyph and sentence in `textPrimary`, caption `textSecondary` (tabular digits),
the buttons row "Try again" 16 Medium `textPrimary` + "Details" 15 `textSecondary`, 44 pt targets, 18 apart, stacked at AX sizes; `retrying` shows
"Trying again…" in `textSecondary` (no teal spinner); the `action` (plain action) becomes a third text button in the same row (it was a grey capsule).
A banner is announced when it appears (`AccessibilityNotification.Announcement`).

**`RefreshDetailsSheet`** (Today's Details): grouped `ListGroup` card of rows (label left `callout` `textSecondary`, value right `textPrimary`; the Request ID row stacks its
selectable monospaced value under the label with the copy button, because 36 characters do not fit a row), title "Details" + `CircleButton(xmark, "Done")`;
pinned actions: `PillButton(.primary)` "Send to RYFT" (was a teal capsule), `PillButton(.secondary)` "Copy details" ("Copied" when done, disabled), the caption "Sends this
and the last 20 requests. No health values." under them. **`SyncStatusLineView`**'s actions ("Try again", "Action needed: …") move from teal to `textPrimary` underlined
(T5.0's central change; listed so nobody restyles it twice).

---

## 5. Dynamic Type, summary (AX3 unless noted)

| Screen | Behaviour |
|---|---|
| Welcome | scrolls (#115), about 1100 pt; marks grow to 44; Apple button 64; "Have an account?" stacks |
| Log in, Create, Reset, Set password | header title wraps beside the back/cancel circle; rows grow; one scroll; the keyboard scrolls the focused row into view |
| Check inbox | everything stacks, the circle keeps 72 |
| Invite | the paste chip drops under the value; the rest as above |
| Consent | about 2650 pt; points stack; actions reached by scrolling |
| About you | wheel fixed 176; pinned bar ≈ 125 pt |
| Health, Wear, Tracker setup | pinned bar ≤ 25 % of the height at AX3 (check at AX5: the longest label, "Show me again later", wraps to three lines, ≈ 230 pt, 27 %); one-column grid |
| Account hint | `.large` detent, scrolls |
| Splash, Misconfigured | text wraps, centred; the splash caption wraps under the mark |

## 6. Reduce Motion, Reduce Transparency, Larger Text for icons

Reduce Motion: no banner fade, no step cross-fade, the Health pulse drawn at rest, tile selection without animation (existing), the splash caption without a fade.
Reduce Transparency: nothing here uses blur or translucency except the Apple button's veil, which becomes opaque `background`. Icon-only controls (the back/cancel
circles, the eye) do not scale; they carry the Large Content Viewer (`CircleButton` does; the eye button gets `accessibilityShowsLargeContentViewer`).

## 7. Contrast (WCAG 2.x, sRGB composites, computed for this spec)

| Pair | Ratio | Needs | |
|---|---|---|---|
| `textPrimary` on `surface` | 16.2 | 4.5 | pass |
| `textSecondary` (0.62) on `surface` / on `background` | 6.8 / 7.0 | 4.5 | pass: labels, lead, hint, links in captions |
| `textTertiary` (0.48) on `surface` / `background` | 4.54 / 4.54 | 4.5 | pass (margin 0.04): only meta text, the version caption, details |
| value text at 0.55 on `surface`; group title at 0.55 on `background` | 5.6 / 5.7 | 4.5 | pass |
| `textTertiary` on a 6 %-ink row fill | **4.34** | 4.5 | **fail: the reason there is no focus fill (G5, D6A-8) and why the placeholder is `textSecondary`** |
| selected tile border (ink 0.9) on `surface` | 13.2 | 3 | pass |
| white Apple button vs `background` | 19.6 | 3 | pass |
| ink on `surfaceRaised` (paste chip) | 11.6 | 4.5 | pass |
| outline pill stroke (0.20) / circle border (0.16) vs `background` | 1.71 / 1.49 | 3 (1.4.11) | below 3, as the PR 2 components already are; the label in the control names it, the boundary is not the only cue |
| surface vs `background` (card edge) | 1.07 | n/a | a tile is not a control; text inside carries the contrast |

The tests in §8 pin these with the PR 1 helpers (`NocturneTokenTests` pattern).

## 8. Tests to write

| # | Test | Ticket |
|---|---|---|
| 1 | `FormGroupSpec` numbers: row min 56, hairline 0.06, radius 22, focus bar 2 × 28 inset 6; `ListGroup` row min 46 (pure) | T6A.2 |
| 2 | Contrast of §7's pairs, including the 4.34 failure documented as the reason for no focus fill (`textTertiary` on a 6 % fill must stay below 4.5, so a future "focus fill" fails the test on purpose) | T6A.2 |
| 3 | Hosted: a `FormRow` is one element with the label and the value; `PasswordField`'s eye has the "Show password" / "Hide password" label | T6A.2 |
| 4 | Hosted: `PillButton(isBusy: true)` is not enabled, value "Busy", not dimmed (pixel at the title is the title colour, not 35 %) | T6A.2 |
| 5 | `LinkText`: link runs carry `underlineStyle`; the Links rotor still reaches them; `LinkButton` trait is link and joins the glyph with a no-break space | T6A.2 |
| 6 | Welcome: the two #115 hosted tests at AX3/AX5; Log in reachable and pushes `.logIn`; Apple button height 52…64; no teal pixel except the Recovery mark (sample the Create account pill and the value-line names) | T6A.3 |
| 7 | Hosted at default and AX3: Log in, Create account, Reset password: header, labels, reading order (§A-2, A-3), no overlap, primary reachable; disabled hint present | T6A.3 |
| 8 | Check inbox: Resend → "Sending…" → "Sent again" disabled (view-model or hosted); the announcement is posted | T6A.3 |
| 9 | Source scan (the `DarkOnlyTests` style): the files of areas A contain no `Theme.accent`, `Theme.onAccent`, `TealButtonStyle`, `PrimaryButton(` (after T5.0), `Theme.surfaceRaised.opacity(0.6)`; `HealthIllustration` has no repeating animation | T6A.3 / T6A.4 |
| 10 | Consent: AX3 and AX5 hosted (§A-8); the age line and the checkbox keep their ids; Agree disabled until ticked | T6A.4 |
| 11 | Wear: selected tile differs in shape from an off tile; "Just my iPhone" clears the others and announces | T6A.4 |
| 12 | About you: Continue disabled until a year; saved rows are buttons with the spoken detail | T6A.4 |
| 13 | Health, Wear, Tracker setup: pinned bar reachable at AX3 and AX5, ≤ 35 % of the window | T6A.4 |
| 14 | Splash: caption not before 3 s (injected clock/`Task.sleep` seam), never moves the mark (frame equality) | T6A.5 |
| 15 | Misconfigured: renders the sample list, never "It's missing ." (`PlatformConfigTests` extended) | T6A.5 |
| 16 | `InlineMessage`: no teal; buttons ≥ 44; banner announces; AX stacking (extends the existing status tests) | T6A.2 |
| 17 | String keys of §9 exist with comments; the removed ones are gone (`NocturneStringsTests` pattern) | T6A.6 |
| 18 | The existing UI tests that use these ids still pass: ids `welcome.*`, `invite.*`, `consent.*`, `aboutYou.*`, `wear.*`, `trackerSetup.*`, `health.*`, `hint.*` unchanged; an edge swipe pops Log in | T6A.3 / T6A.4 |

## 9. Strings (English; the localization-editor finalises)

| Key / text | Where | New / changed |
|---|---|---|
| Have an account? | Welcome | new |
| Logging in… / Creating account… / Sending… / Saving… / Checking… | busy pill titles (A-2, A-3, A-4/A-5, A-6/A-9, A-7) | new |
| Saving your consent… | A-8 busy | new |
| Waiting for Apple Health… | A-10 busy | new |
| Checking your account… | A-14 | new (optional, Q4) |
| Estimated from your birth year | A-9 | new |
| Fill in your email and password first. | A-2 hint (a11y) | new |
| Back | back circle label | new (was the system's) |
| It's missing %@. Install the latest version of RYFT. | A-15 | changed (was "… Install the version from the App Store.") |
| No connection. Check your internet and try again. / Something went wrong. Please try again. | A-7, A-8 fallbacks in place of `localizedDescription` | proposed reuse of existing `AuthMessage` strings |
| Everything else on these screens | | **unchanged**, including the consent text, the minimum-age line, the policy links and the privacy line |

## 10. Files each change touches

| File | Change | Ticket |
|---|---|---|
| `Design/FormGroup.swift` (new), `Design/ListGroup.swift` (new, or PR 5's), `Design/LegendMark.swift` (new), `Design/LinkText.swift` (new), `Design/PinnedBar.swift` (new) | §3 | T6A.2 |
| `Design/PillButton.swift` | `isBusy` (shared, reconcile with T5.0) | T6A.2 |
| `Design/StatusViews.swift` | `InlineMessage`, `RefreshDetailsSheet`, `CheckRow`, `NumberedStep`, `TrackerSetupCard`, `SetupCard` untouched | T6A.2 |
| `Design/Card.swift` | `SelectableTile`, `CapabilityState` colour | T6A.2 |
| `Design/SafariView.swift` | bar tint | T6A.2 |
| `Features/Profile/DebugComponentCatalog.swift` | entries for the new primitives (a section of its own; other areas add theirs) | T6A.2 |
| `Features/Auth/AuthComponents.swift` | **mechanical split first** (T6A.2, no change of content): `SignInMethodsView` → `Features/Profile/SignInMethodsView.swift` (area C's), `AccountHintSheet` → `Features/Auth/AccountHintSheet.swift`; what is left (`AuthScreen`, `AuthTextField`, `PasswordField`, `AuthErrorMessage`, `AuthValidation`, routes) is T6A.3's | T6A.2, T6A.3 |
| `Features/Auth/WelcomeView.swift`, `LogInView.swift`, `CreateAccountView.swift`, `ForgotPasswordView.swift`, `CheckInboxView.swift`, `SetNewPasswordView.swift`, `ParkedActivitiesNotice.swift`, `AccountHintSheet.swift` | A-1 … A-6, A-13 | T6A.3 |
| `Auth/AppleSignInButton.swift` | style, height, shape, veil | T6A.3 |
| `Features/Onboarding/HealthPermissionView.swift` | `OnboardingScreen` frame, `OnboardingError`, `InviteCodeView`, `ConsentView`, `ConsentPoint`, `CheckboxToggleStyle`, `AboutYouView`, `TrackerPickerView`, `TrackerSetupStepView`, `HealthPermissionScreen`, `HealthAccessHint`, `HealthWriteAccessHint`; `OnboardingFlowView` animation | T6A.4 |
| `Features/Onboarding/HealthIllustration.swift` | neutral, draws once | T6A.4 |
| `App/PlatformConfig.swift` (`MisconfiguredBuildView`), `App/RyftApp.swift` (`SplashView`, moved to `App/SplashView.swift`; the four `.animation(.easeInOut(duration: 0.3)…)` of `RootView` take `Theme.Motion.respecting`) | A-14, A-15, G10 | T6A.5 |
| `Resources/Localizable.xcstrings` | §9, targeted edits only (`make strings`, check `--stat`) | T6A.6 |
| `RyftTests/…`, `docs/STATUS.md`, `CHANGELOG.md` | tests §8; one line under Unreleased ("New look for sign-in and setup") | each ticket / T6A.6 |
| Not touched | The legal URLs (the domain chore owns them), `Models.swift`, `AuthService`, `OnboardingCoordinator` logic, the sync, the API, `Theme.swift` (except the two additive constants), `Localizable.xcstrings` by anyone but T6A.6, the pbxproj | |

## 11. Tickets (parallel worktrees)

| Ticket | Owner | Files | Depends on | Parallel-safe with |
|---|---|---|---|---|
| **T6A.2 shared primitives, restyles and the mechanical split** | ios-developer (design-system) | §10 rows "Design/…", the split of `AuthComponents.swift`, `Theme.Metrics` constants, catalog entries, tests 1–5, 16 | T5.0 for the button swap (soft: if T5.0 is not merged, T6A.2 carries `PillButton(isBusy:)` and T5.0 rebases); PR 5's `ListGroup` if it exists | nothing in area A until it merges; parallel with other areas except for `StatusViews.swift` / `Card.swift` / `PillButton.swift`, which **PR 5 area T5.0 and PR 6 areas B and C must not edit meanwhile** (or use the same ticket order) |
| **T6A.3 signed out** | ios-developer | `Features/Auth/*` (minus `SignInMethodsView`), `Auth/AppleSignInButton.swift`, tests 6–8, 9 (auth part), 18 | T6A.2 | T6A.4, T6A.5, T6A.6 |
| **T6A.4 onboarding** | ios-developer | `Features/Onboarding/*`, tests 9–13, 18 | T6A.2 | T6A.3, T6A.5, T6A.6 |
| **T6A.5 splash and misconfigured** | ios-developer | `App/PlatformConfig.swift`, `App/RyftApp.swift` (`SplashView` + the four animations), `App/SplashView.swift`, tests 14–15 | none (T6A.2 for nothing); small, can go first | all |
| **T6A.6 strings, STATUS, CHANGELOG** | localization-editor | `Localizable.xcstrings` (targeted), `docs/STATUS.md`, `CHANGELOG.md`, test 17 | T6A.3–5 (keys) | none (last) |

Shared files, one owner each: **the string catalog** T6A.6; **`MockData`**: nothing new is needed (the previews use `AuthService.preview`,
`OnboardingStepPreview`, `AppEnvironment.previewWithParkedRows`); **auth components** T6A.3 after T6A.2's split; **`StatusViews.swift`,
`Card.swift`, `PillButton.swift`, `SafariView.swift`** T6A.2. `HealthPermissionView.swift` is 1446 lines; if the lead wants two onboarding
worktrees, T6A.2 splits it mechanically first (coordinator / steps / tracker steps / Health) and T6A.4 becomes two tickets.

## 12. Draft renders

All in `/private/tmp/claude-501/-Users-tim-krebs-Development-Projects-ryft-app/6c6f1e78-44f0-4400-b13c-ddf23bb79e65/scratchpad/pr6-drafts/a/`:
`a-01-welcome`, `a-01-welcome-ax3` (top of the scroll), `a-01-welcome-ax3-end` (scrolled to the ways in), `a-02-welcome-notice`,
`a-03-login`, `a-03-login-error`, `a-03-login-busy`, `a-03-login-ax3`, `a-04-create-account`, `a-05-reset-password`, `a-06-check-inbox`,
`a-07-set-new-password`, `a-08-invite`, `a-08-invite-error`, `a-09-consent`, `a-09-consent-end`, `a-09-consent-changed`, `a-09-consent-ax3`,
`a-09-consent-ax3-end`, `a-10-about-you`, `a-10-about-you-year`, `a-10-about-you-saved`, `a-11-apple-health`, `a-12-wear`, `a-13-tracker-setup`,
`a-14-account-hint`, `a-15-splash`, `a-15-splash-waiting`, `a-16-misconfigured`, `a-17-states` (banners, pill states, field rows, checkbox),
`a-18-details-sheet`. The renders show the proposed look; they are not pixel-exact to the final views (prototype primitives, a faux status bar and
home indicator, wheel and paste chip are the system's).

## 13. Deviations

| # | From | To | Why |
|---|---|---|---|
| D6A-1 | Rows 46 high | Field rows 56 (label + value); list rows 46 | A row with a label above its value cannot be 46 |
| D6A-2 | Hairline between rows ("ink 0.06") | full width of the card | reading the board's `border-bottom` on a padded row; derived, not measured |
| D6A-3 | Primary = light `PillButton` | On Welcome the Apple button (white, system) is the strongest action and Create account is the outline | Apple's rules; Q1 |
| D6A-4 | Metric colours only on data | Three small ring marks in violet, teal, blue on Welcome | The audit asked for ring-legend or neutral icons; they name metrics and show no value; Q2 |
| D6A-5 | Padding 24–28 | 20 (350 content) | PR 4 convention |
| D6A-6 | System back button | `CircleButton` in the screen's header, bar hidden, swipe-back re-enabled | G3 |
| D6A-7 | 2 s looping pulse | draws once, 0.6 s | Motion rule |
| D6A-8 | A focus fill | a 2 × 28 bar and the label | 1.15:1 |
| D6A-9 | Coral for errors | neutral glyph and words | calm; state is never colour alone |
| D6A-10 | `InlineMessage` 60 % surface, stroke, radius 16, grey text, teal actions | opaque `surface`, no stroke, radius 22, `textPrimary`, neutral actions | L27; shared with Today (T4.2's card inherits it) |
| D6A-11 | Step fades 0.4 s / 0.3 s ignoring Reduce Motion | `Theme.Motion.quick`, none under Reduce Motion; consent stays inline, not pinned | G10; the dimmed primary needs its box in view |
| D6A-12 | Teal `envelope.badge` 44 pt | outlined 72 pt circle with `envelope` | "pending is an outline" |
| D6A-13 | — | splash caption after 3 s | honest wait |
| D6A-14 | Safari bar tinted teal | `textPrimary` | L27 |
| D6A-15 | `exclamationmark.circle` in `Theme.warning` kept for CheckRow's "should arrive and doesn't" | the single status colour left in this area | a fault with a fix; amber is a status, not an accent |

## 14. Questions for the user

1. Welcome keeps Apple above Create account (the white Apple button is the strongest thing, Create account is the outline pill). Or should Create account be the light primary pill with Apple below it?
2. OK for the three Welcome lines to carry the ring colours (violet, teal, blue) as small ring marks, or should they be neutral?
3. Every onboarding step loses its teal glyph above the title (the small lock-up row replaces it). Keep it that way, or give each step one neutral glyph?
4. Splash caption "Checking your account…" after 3 s: keep (a small behaviour addition) or drop?
5. Optional extras, none in the tickets unless you say so: a "Log in instead" action in the "email can't be used" banner, a "Resend" action in the "Confirm your email first" banner, a live character count under the password hint, a "Step 2 of 4" indicator in onboarding.
