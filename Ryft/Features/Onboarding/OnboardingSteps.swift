import SwiftUI

// MARK: - the steps

/// The first run's missing steps, full screen, before Apple Health and the tabs. A step change cross-fades with
/// `Theme.Motion.quick`, at once under Reduce Motion (PR 6 A G10).
struct OnboardingFlowView: View {
    let model: OnboardingCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let step = model.flowStep {
                OnboardingStepView(step: step, model: model)
                    .id(step)
                    .transition(.opacity)
            }
        }
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: model.flowStep)
    }
}

/// One step's screen; the same views serve the full-screen flow and the sheet.
struct OnboardingStepView: View {
    let step: OnboardingCoordinator.Step
    let model: OnboardingCoordinator

    var body: some View {
        switch step {
        case .invite: InviteCodeView(model: model)
        case .consent: ConsentView(model: model)
        case .aboutYou: AboutYouView(model: model)
        case .wear: TrackerPickerView(model: model)
        }
    }
}

/// The onboarding steps' numbers (PR 6 A §A-7 frame, G3, G11).
enum OnboardingSpec {
    /// The first run's header row: the lock-up (`WordmarkLockup`, mark 26), 40 high, no title in it.
    static let headerHeight = ScreenHeaderSpec.height
    /// The header row → the title 24; the title → the lead 12; the lead → the content 24.
    static let titleGap: CGFloat = 24, leadGap: CGFloat = 12, contentGap: CGFloat = 24
    /// A step in a sheet (after the first run) starts 24 below the grabber, which sits 12 from the sheet's edge.
    static let sheetTopInset: CGFloat = 36
    /// 20 at the sides (`Theme.Metrics.screenPadding`), at most 480 wide, centred on a wide window; 32 under the content.
    static let maxWidth: CGFloat = 480, bottomPadding: CGFloat = 32
    /// A block → the banner, the banner → the primary, a pill → the next pill: 12. A card → its primary without a banner: 20.
    static let actionGap: CGFloat = 12, primaryGap: CGFloat = 20
    /// The quiet text action ("Not now", "Skip") right under its pill.
    static let quietGap: CGFloat = 4
}

/// A step's frame: in the first run the lock-up row, 24 below it the title (26 Light, header trait), 12 below the lead
/// (16 pt `textSecondary`), 24 below that the content; as a sheet (`showsLockup` false) the title starts 24 below the grabber.
/// One scroll, 20 from the sides, at most 480 wide, the keyboard dismissed by a drag. A long step pins its actions with
/// `.pinnedBar { … }` on this view.
struct OnboardingScreen<Content: View>: View {
    private let title: Text
    private let lead: Text
    private let showsLockup: Bool
    private let dismissible: Bool
    private let content: Content

    /// `dismissible`: the step can wait (`OnboardingCoordinator.canDefer`); as a sheet only then does it show the grabber.
    init(title: Text, lead: Text, showsLockup: Bool, dismissible: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.lead = lead
        self.showsLockup = showsLockup
        self.dismissible = dismissible
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsLockup {
                    // Decoration: VoiceOver starts at the step's title, its first heading.
                    WordmarkLockup()
                        .frame(height: OnboardingSpec.headerHeight)
                        .padding(.bottom, OnboardingSpec.titleGap)
                        .accessibilityHidden(true)
                }
                ScreenHeaderTitle(text: title)
                lead
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, OnboardingSpec.leadGap)
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.top, OnboardingSpec.contentGap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: OnboardingSpec.maxWidth)
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.top, showsLockup ? 0 : OnboardingSpec.sheetTopInset)
            .padding(.bottom, OnboardingSpec.bottomPadding)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .presentationBackground(Theme.background)
        .presentationDragIndicator(dismissible ? .visible : .hidden)
    }
}

/// The step's failure, with Details (status, code, request ID): the neutral banner.
private struct OnboardingError: View {
    let model: OnboardingCoordinator

    var body: some View {
        if let message = model.errorMessage {
            InlineMessage(message: message, systemImage: "exclamationmark.circle", details: model.errorDetails)
                .padding(.top, OnboardingSpec.actionGap)
        }
    }
}

/// The quiet third action under a pill ("Not now", "Skip", "Show me again later", G2): 16 pt `textSecondary`, centred,
/// 44 high, the whole width tappable.
struct LaterButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ryft(.body))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One point of a points card (Consent, Apple Health): a 17 pt neutral glyph in a 28 pt column, 12, the title 16 Medium and
/// 3 below it the text 15 pt `textSecondary`; 16 padding; at accessibility sizes the glyph goes above the title. One VoiceOver
/// element ("What RYFT reads. Heart rate, …"), the glyph hidden.
struct OnboardingPoint: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: OnboardingPointSpec.stackedGap))
            : AnyLayout(HStackLayout(alignment: .top, spacing: OnboardingPointSpec.glyphGap))
        layout {
            Image(systemName: symbol)
                .font(.system(size: OnboardingPointSpec.glyphSize, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: OnboardingPointSpec.glyphColumn, alignment: typeSize.isAccessibilitySize ? .leading : .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: OnboardingPointSpec.textGap) {
                Text(title)
                    .font(.ryft(.button)) // 16 Medium
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(OnboardingPointSpec.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .groupedRowHairline()
        .accessibilityElement(children: .combine)
    }
}

enum OnboardingPointSpec {
    static let glyphSize: CGFloat = 17, glyphColumn: CGFloat = 28, glyphGap: CGFloat = 12
    static let textGap: CGFloat = 3, padding: CGFloat = 16
    /// At accessibility sizes: the glyph, then 8, then the title.
    static let stackedGap: CGFloat = 8
}

/// Invite code: one field, any case, spaces or dashes; paste-friendly. Nocturne (PR 6 A §A-7): a one-row card with the
/// system Paste chip, the banner, Continue (busy while it checks: the pill's spinner, the title stays), Not now, and the way
/// out for the wrong account.
struct InviteCodeView: View {
    let model: OnboardingCoordinator
    @Environment(AuthService.self) private var auth
    /// The launch sequence plays over the root: no keyboard over its arcs, no keystrokes into a field nobody sees.
    @Environment(\.launchCoversRoot) private var launchCovers
    @FocusState private var focused: Bool

    /// The field takes the keyboard by itself only when it can be seen and holds nothing yet: on appear when nothing
    /// covers it, else at the launch's hand-off (ADR 0017).
    static func shouldFocus(inviteCodeEmpty: Bool, covered: Bool) -> Bool {
        inviteCodeEmpty && !covered
    }

    private var isEmpty: Bool { model.inviteCode.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        OnboardingScreen(title: Text("Enter your invite code"),
                         lead: Text("RYFT is invite-only during the beta. The person who invited you has a code for you, like RYFT-7K3M-QX9P."),
                         showsLockup: model.isFirstRun, dismissible: model.canDefer(.invite)) {
            GroupedCard {
                FormField(Text("Invite code"), isFocused: focused) {
                    TextField(text: Bindable(model).inviteCode, prompt: Text(verbatim: "RYFT-XXXX-XXXX").fieldPrompt()) {
                        Text("Invite code")
                    }
                    .font(.system(size: RyftTextStyle.body.size, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textContentType(.oneTimeCode)
                    .submitLabel(.go)
                    .focused($focused)
                    .onSubmit { Task { await model.redeemInvite() } }
                    .accessibilityIdentifier("invite.code")
                } trailing: {
                    // The system's chip (it pastes without the paste prompt): a quiet `surfaceRaised` capsule, ink on it 11.6:1.
                    PasteButton(payloadType: String.self) { strings in
                        if let code = strings.first { model.inviteCode = code.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.iconOnly)
                    .tint(Theme.surfaceRaised)
                    .foregroundStyle(Theme.textPrimary)
                }
            }
            .disabled(model.isWorking)
            OnboardingError(model: model)
            PillButton(Text("Continue"), busy: model.isWorking) {
                await model.redeemInvite()
            }
            .disabled(isEmpty)
            .padding(.top, model.errorMessage == nil ? OnboardingSpec.primaryGap : OnboardingSpec.actionGap)
            .accessibilityIdentifier("invite.continue")
            if model.canDefer(.invite) {
                LaterButton(title: "Not now") { model.later(.invite) }
                    .disabled(model.isWorking)
                    .padding(.top, OnboardingSpec.quietGap)
            }
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.Metrics.hairline)
                .padding(.vertical, InviteSpec.ruleGap)
                .accessibilityHidden(true)
            Text("Signed in with the wrong account?")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(Text("Use another account"), style: .secondary) { await auth.signOut() }
                .disabled(model.isWorking)
                .padding(.top, OnboardingSpec.actionGap)
        }
        .onAppear {
            if Self.shouldFocus(inviteCodeEmpty: model.inviteCode.isEmpty, covered: launchCovers) { focused = true }
        }
        .onChange(of: launchCovers) { _, covers in
            if Self.shouldFocus(inviteCodeEmpty: model.inviteCode.isEmpty, covered: covers) { focused = true }
        }
        // A refused code (422): back to the field, to correct it.
        .onChange(of: model.errorMessage) { _, message in
            if message != nil { focused = true }
        }
    }
}

private enum InviteSpec {
    /// Above and below the rule before "Signed in with the wrong account?".
    static let ruleGap: CGFloat = 20
}

/// Consent to health-data processing for the policy in force: a plain summary, the
/// whole policy in Safari, and a separate checkbox that starts unticked. Nocturne (PR 6 A §A-8, D6A-11): the points card,
/// the age line in ink (it is a gate), the policy link, the checkbox card, then Agree and continue (busy while it saves: the
/// pill's spinner, the title stays), Not now and the version caption, all inline in one scroll.
struct ConsentView: View {
    let model: OnboardingCoordinator
    @State private var agreed = false
    @State private var legal: LegalPage?

    var body: some View {
        OnboardingScreen(title: Text("Your health data, your consent"),
                         lead: Text("To calculate your scores, RYFT processes health data from Apple Health. Here is what that means."),
                         showsLockup: model.isFirstRun) {
            if let earlier = model.earlierConsent {
                InlineMessage(message: String(localized: "The privacy policy changed since you agreed on \(Fmt.date(earlier.grantedAt)). Read what changed, then agree again."),
                              systemImage: "doc.badge.clock")
                    .padding(.bottom, OnboardingSpec.actionGap)
            }
            GroupedCard {
                OnboardingPoint(symbol: "waveform.path.ecg", title: "What RYFT reads",
                                text: "Heart rate, HRV, resting heart rate, breathing rate, blood oxygen, VO₂ max, steps, active energy, sleep and workouts.")
                OnboardingPoint(symbol: "lock.shield", title: "Where it is stored",
                                text: "In your RYFT account, on servers in the EU. Never sold, never used for advertising.")
                OnboardingPoint(symbol: "person.crop.circle.badge.checkmark", title: "Who can see it",
                                text: "Only you, and the operator of RYFT when something needs fixing.")
                OnboardingPoint(symbol: "arrow.down.doc", title: "Always yours",
                                text: "Export or delete everything at any time in Profile. You can withdraw this consent in Profile → Privacy.")
            }
            Text("You must be at least 16 to use RYFT.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, ConsentSpec.ageGap)
                .accessibilityIdentifier("consent.minimumAge")
            // The shared link (`ryftLink`); its ↗ glyph waits for `InlineLink` to offer one (reported to the lead).
            Button { legal = model.policyPage } label: {
                model.earlierConsent == nil ? Text("Read the privacy policy") : Text("What changed")
            }
            .ryftLink()
            .accessibilityIdentifier("consent.policy")
            Toggle(isOn: $agreed) {
                Text("I agree that RYFT processes my health data to calculate my scores.")
            }
            .toggleStyle(CheckboxToggleStyle())
            .disabled(model.isWorking)
            .padding(.top, ConsentSpec.checkboxGap)
            .accessibilityIdentifier("consent.checkbox")
            OnboardingError(model: model)
            // Agree records the version on screen: with none known (the config didn't load), it waits for one.
            if model.policyVersion == nil, model.policyRead == .failed {
                InlineMessage(message: String(localized: "The privacy policy version didn't load. You can agree once it's shown."),
                              systemImage: "doc.badge.clock",
                              retry: { await model.loadPolicyIfMissing() },
                              identifier: "consent.policyVersion")
                    .padding(.top, OnboardingSpec.actionGap)
            }
            // The version this step drew: a newer one arriving before the tap isn't agreed to.
            let shown = model.policyVersion
            PillButton(Text("Agree and continue"), systemImage: PillButton.Icon.confirm, busy: model.isWorking) {
                await model.agree(shown: shown)
            }
            .disabled(!agreed || !model.canAgree)
            .padding(.top, model.errorMessage == nil ? ConsentSpec.primaryGap : OnboardingSpec.actionGap)
            .accessibilityIdentifier("consent.agree")
            LaterButton(title: "Not now") { model.later(.consent) }
                .disabled(model.isWorking)
                .padding(.top, OnboardingSpec.quietGap)
            policyCaption
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, OnboardingSpec.actionGap)
        }
        .safariSheet($legal)
        .task { await model.loadPolicyIfMissing() }
        // Another version on screen: the tick was for the old one, so it is given again, deliberately.
        .onChange(of: model.policyVersion) { old, new in
            if old != nil, new != nil, old != new { agreed = false }
        }
    }

    /// What agreeing records: the policy version, or that it is still on its way.
    private var policyCaption: Text {
        if let version = model.policyVersion {
            return Text("Nothing is synced until you agree. Privacy policy version \(version).")
        }
        return model.policyRead == .loading
            ? Text("Nothing is synced until you agree. Loading the privacy policy version…")
            : Text("Nothing is synced until you agree.")
    }
}

/// Consent's numbers (A §A-8).
enum ConsentSpec {
    /// The points card → the age line 20; the link → the checkbox card 4; the card → the primary 16.
    static let ageGap: CGFloat = 20, checkboxGap: CGFloat = 4, primaryGap: CGFloat = 16
    /// The checkbox card: `surface`, radius 22, padding 16; the glyph 22 pt, scaled with the text; ticked adds a 1 pt
    /// `textPrimary` border at 32 %.
    static let cardPadding: CGFloat = 16, glyphSize: CGFloat = 22, glyphGap: CGFloat = 12
    static let tickedBorderOpacity = 0.32
}

/// The consent's checkbox (a separate, deliberate tick) as a card: `square` in `textSecondary`, ticked
/// `checkmark.square.fill` in `textPrimary` with a 1 pt border; the shape, the border and the selected trait carry the state.
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        CheckboxCard(configuration: configuration)
    }

    private struct CheckboxCard: View {
        let configuration: ToggleStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @ScaledMetric(relativeTo: .callout) private var glyph: CGFloat = ConsentSpec.glyphSize

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius, style: .continuous)
            Button {
                configuration.isOn.toggle()
            } label: {
                HStack(alignment: .top, spacing: ConsentSpec.glyphGap) {
                    Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                        .font(.system(size: glyph, weight: .regular))
                        .foregroundStyle(configuration.isOn ? Theme.textPrimary : Theme.textSecondary)
                    configuration.label
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(ConsentSpec.cardPadding)
                .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minHitTarget, alignment: .leading)
                .background(Theme.surface, in: shape)
                .overlay {
                    shape
                        .strokeBorder(Theme.textPrimary.opacity(ConsentSpec.tickedBorderOpacity), lineWidth: Theme.Metrics.hairline)
                        .opacity(configuration.isOn ? 1 : 0)
                }
                .contentShape(shape)
                .opacity(isEnabled ? 1 : PillButton.disabledOpacity)
                .animation(Theme.Motion.respecting(reduceMotion), value: configuration.isOn)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
        }
    }
}

/// Birth year → the platform's max-HR estimate, and the sleep need it starts from. Nocturne (PR 6 A §A-9): the wheel in a
/// card under "Birth year", then, saved, the two values as rows that open Profile's editors; Continue (and Skip) pinned.
struct AboutYouView: View {
    let model: OnboardingCoordinator
    @State private var year: Int?
    @State private var editing: BodySetting?
    @Environment(\.appEnvironment) private var env

    private var years: [Int] { OnboardingCoordinator.birthYears(now: env.clock.now()) }
    private var isSaved: Bool { model.aboutYouSaved && model.user != nil }

    var body: some View {
        OnboardingScreen(title: Text("About you"),
                         lead: Text("Your birth year gives an estimate of your maximum heart rate, which strain and heart-rate zones are measured against. RYFT keeps only the year."),
                         showsLockup: model.isFirstRun) {
            if isSaved {
                let editor = model.bodySettings
                GroupedCard(GroupTitle(Text("Estimated from your birth year"))) {
                    GroupedRow.push(Text("Maximum heart rate"), value: Text(verbatim: editor.rowValue(.maxHR, saved: editor.maxHRText)),
                                    detail: editor.rowDetail(.maxHR).map { Text(verbatim: $0) }) { editing = .maxHR }
                        .accessibilityIdentifier("aboutYou.maxHR")
                    GroupedRow.push(Text("Baseline sleep need"),
                                    value: Text(verbatim: editor.rowValue(.sleepBase, saved: editor.sleepBaseText)),
                                    detail: editor.rowDetail(.sleepBase).map { Text(verbatim: $0) }) { editing = .sleepBase }
                        .accessibilityIdentifier("aboutYou.sleepBase")
                } footer: {
                    VStack(alignment: .leading, spacing: GroupedListSpec.footerGap) {
                        // A save whose answer came after its editor sheet went: said here, where the user is (as Profile).
                        if editor.errorMissed, let error = editor.error {
                            InlineMessage(message: error, systemImage: "exclamationmark.circle", details: editor.errorDetails)
                                .accessibilityIdentifier("aboutYou.bodySettingsError")
                        }
                        GroupFooter(Text("RYFT adjusts this from your nights unless you set it."))
                    }
                }
            } else {
                GroupedCard(Text("Birth year")) {
                    Picker(selection: $year) {
                        Text("Choose your birth year").tag(Int?.none)
                        ForEach(years, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
                    } label: {
                        Text("Birth year")
                    }
                    .pickerStyle(.wheel)
                    .frame(height: AboutYouSpec.wheelHeight)
                    .frame(maxWidth: .infinity)
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("aboutYou.year")
                }
                OnboardingError(model: model)
            }
        }
        .pinnedBar {
            if isSaved {
                PillButton(Text("Continue")) { model.finishAboutYou() }
                    .accessibilityIdentifier("aboutYou.continue")
            } else {
                PillButton(Text("Continue"), busy: model.isWorking) {
                    guard let year else { return }
                    await model.saveAboutYou(birthYear: year)
                }
                .disabled(year == nil)
                .accessibilityIdentifier("aboutYou.save")
                LaterButton(title: "Skip") { model.finishAboutYou() }
                    .disabled(model.isWorking)
                    .accessibilityIdentifier("aboutYou.skip")
            }
        }
        // No past days to rescore yet: the editors offer none.
        .bodySettingSheet($editing, editor: model.bodySettings, rescores: false)
    }
}

/// About you's numbers (A §A-9).
enum AboutYouSpec {
    /// The wheel keeps its height at every text size (a picker does not scale).
    static let wheelHeight: CGFloat = 176
}

/// One onboarding step on mock data, for previews and the Debug `-RyftScreen` captures.
struct OnboardingStepPreview: View {
    let step: OnboardingCoordinator.Step
    /// About you after the birth year was saved: the values, editable.
    var saved = false
    /// Demo data: consent's version comes from the mock config, read by the step itself (`loadPolicyIfMissing()`).
    @State private var model = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}

    var body: some View {
        OnboardingStepView(step: step, model: model)
            .task { if saved { await model.saveAboutYou(birthYear: 1990) } }
    }
}

// Dark only (NOCTURNE_STYLE §1).
#Preview("Invite code") {
    OnboardingStepPreview(step: .invite).previewEnvironment()
}

#Preview("Invite code · AX3") {
    OnboardingStepPreview(step: .invite).previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}

#Preview("Consent") {
    OnboardingStepPreview(step: .consent).previewEnvironment()
}

#Preview("Consent · AX3") {
    OnboardingStepPreview(step: .consent).previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}

#Preview("About you") {
    OnboardingStepPreview(step: .aboutYou).previewEnvironment()
}

#Preview("About you · saved") {
    OnboardingStepPreview(step: .aboutYou, saved: true).previewEnvironment()
}

#Preview("About you · saved · AX3") {
    OnboardingStepPreview(step: .aboutYou, saved: true).previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}
