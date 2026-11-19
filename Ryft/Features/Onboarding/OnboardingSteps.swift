import SwiftUI

// MARK: - the steps

/// The first run's missing steps, full screen, before Apple Health and the tabs.
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
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.standard), value: model.flowStep)
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

/// Title, text and content on Graphite or Mist, like the Health explanation.
struct OnboardingScreen<Content: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 36)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                content()
            }
            .padding(.horizontal, Theme.Metrics.screenPadding + 4)
            .padding(.bottom, 24)
            .frame(maxWidth: 480, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
    }
}

/// The step's failure, with Details (status, code, request ID).
private struct OnboardingError: View {
    let model: OnboardingCoordinator

    var body: some View {
        if let message = model.errorMessage {
            InlineMessage(message: message, systemImage: "exclamationmark.circle", details: model.errorDetails)
        }
    }
}

/// "Not now" under the main button.
struct LaterButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.ryft(.body))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
    }
}

/// Invite code: one field, any case, spaces or dashes; paste-friendly.
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

    var body: some View {
        OnboardingScreen(symbol: "envelope.open",
                         title: "Enter your invite code",
                         text: "RYFT is invite-only during the beta. The person who invited you has a code for you, like RYFT-7K3M-QX9P.") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Invite code")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    TextField(text: Bindable(model).inviteCode, prompt: Text(verbatim: "RYFT-XXXX-XXXX")) {
                        Text("Invite code")
                    }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit { Task { await model.redeemInvite() } }
                        .accessibilityIdentifier("invite.code")
                    PasteButton(payloadType: String.self) { strings in
                        if let code = strings.first { model.inviteCode = code.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.iconOnly)
                    .tint(Theme.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.surfaceRaised.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            OnboardingError(model: model)
            PrimaryButton(title: "Continue", busy: model.isWorking) { await model.redeemInvite() }
                .disabled(model.inviteCode.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("invite.continue")
            if model.canDefer(.invite) {
                LaterButton(title: "Not now") { model.later(.invite) }
            }
            Divider().overlay(Theme.separator)
            Text("Signed in with the wrong account?")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            PrimaryButton(title: "Use another account", style: .secondary) { await auth.signOut() }
        }
        .onAppear {
            if Self.shouldFocus(inviteCodeEmpty: model.inviteCode.isEmpty, covered: launchCovers) { focused = true }
        }
        .onChange(of: launchCovers) { _, covers in
            if Self.shouldFocus(inviteCodeEmpty: model.inviteCode.isEmpty, covered: covers) { focused = true }
        }
    }
}

/// Consent to health-data processing for the policy in force: a plain summary, the
/// whole policy in Safari, and a separate checkbox that starts unticked.
struct ConsentView: View {
    let model: OnboardingCoordinator
    @State private var agreed = false
    @State private var legal: LegalPage?

    var body: some View {
        OnboardingScreen(symbol: "hand.raised",
                         title: "Your health data, your consent",
                         text: "To calculate your scores, RYFT processes health data from Apple Health. Here is what that means.") {
            if let earlier = model.earlierConsent {
                InlineMessage(message: String(localized: "The privacy policy changed since you agreed on \(Fmt.date(earlier.grantedAt)). Read what changed, then agree again."),
                              systemImage: "doc.badge.clock")
            }
            VStack(alignment: .leading, spacing: 14) {
                ConsentPoint(symbol: "waveform.path.ecg", title: "What RYFT reads",
                             text: "Heart rate, HRV, resting heart rate, breathing rate, blood oxygen, VO₂ max, steps, active energy, sleep and workouts.")
                ConsentPoint(symbol: "lock.shield", title: "Where it is stored",
                             text: "In your RYFT account, on servers in the EU. Never sold, never used for advertising.")
                ConsentPoint(symbol: "person.crop.circle.badge.checkmark", title: "Who can see it",
                             text: "Only you, and the operator of RYFT when something needs fixing.")
                ConsentPoint(symbol: "arrow.down.doc", title: "Always yours",
                             text: "Export or delete everything at any time in Profile. You can withdraw this consent in Profile → Privacy.")
            }
            Text("You must be at least 16 to use RYFT.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("consent.minimumAge")
            Button {
                legal = model.policyPage
            } label: {
                Text(model.earlierConsent == nil ? "Read the privacy policy" : "What changed")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            Toggle(isOn: $agreed) {
                Text("I agree that RYFT processes my health data to calculate my scores.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(CheckboxToggleStyle())
            .accessibilityIdentifier("consent.checkbox")
            OnboardingError(model: model)
            PrimaryButton(title: "Agree and continue", busy: model.isWorking) { await model.agree() }
                .disabled(!agreed)
                .accessibilityIdentifier("consent.agree")
            LaterButton(title: "Not now") { model.later(.consent) }
            Text("Nothing is synced until you agree. Privacy policy version \(model.policyVersion ?? "–").")
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .safariSheet($legal)
    }
}

private struct ConsentPoint: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.ryft(.headline)).foregroundStyle(Theme.textPrimary)
                Text(text).font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A square checkbox (the consent must be a separate, deliberate tick).
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(configuration.isOn ? Theme.accent : Theme.textSecondary)
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// Birth year → the platform's max-HR estimate, and the sleep need it starts from.
struct AboutYouView: View {
    let model: OnboardingCoordinator
    @State private var year: Int?
    @State private var editing: BodySetting?
    @Environment(\.appEnvironment) private var env

    private var years: [Int] { OnboardingCoordinator.birthYears(now: env.clock.now()) }

    var body: some View {
        OnboardingScreen(symbol: "person.text.rectangle",
                         title: "About you",
                         text: "Your birth year gives an estimate of your maximum heart rate, which strain and heart-rate zones are measured against. RYFT keeps only the year.") {
            if model.aboutYouSaved, model.user != nil {
                let editor = model.bodySettings
                VStack(alignment: .leading, spacing: 14) {
                    AboutYouValue {
                        SettingRow(title: "Maximum heart rate", value: editor.rowValue(.maxHR, saved: editor.maxHRText),
                                   detail: editor.rowDetail(.maxHR)) {
                            editing = .maxHR
                        }
                        .accessibilityIdentifier("aboutYou.maxHR")
                    }
                    AboutYouValue {
                        SettingRow(title: "Baseline sleep need", value: editor.rowValue(.sleepBase, saved: editor.sleepBaseText),
                                   detail: editor.rowDetail(.sleepBase)) {
                            editing = .sleepBase
                        }
                        .accessibilityIdentifier("aboutYou.sleepBase")
                        Text("RYFT adjusts this from your nights unless you set it.")
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                PrimaryButton(title: "Continue") { model.finishAboutYou() }
                    .accessibilityIdentifier("aboutYou.continue")
            } else {
                Picker("Birth year", selection: $year) {
                    Text("Choose your birth year").tag(Int?.none)
                    ForEach(years, id: \.self) { Text(verbatim: "\($0)").tag(Int?.some($0)) }
                }
                .pickerStyle(.wheel)
                .frame(height: 200)
                .accessibilityIdentifier("aboutYou.year")
                OnboardingError(model: model)
                PrimaryButton(title: "Continue", busy: model.isWorking) {
                    guard let year else { return }
                    await model.saveAboutYou(birthYear: year)
                }
                .disabled(year == nil)
                LaterButton(title: "Skip") { model.finishAboutYou() }
            }
        }
        // No past days to rescore yet: the editors offer none.
        .bodySettingSheet($editing, editor: model.bodySettings, rescores: false)
    }
}

/// One setting on About you, on a tile.
private struct AboutYouValue<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) { content() }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
    }
}

/// One onboarding step on mock data, for previews and the Debug `-RyftScreen` captures.
struct OnboardingStepPreview: View {
    let step: OnboardingCoordinator.Step
    /// About you after the birth year was saved: the values, editable.
    var saved = false
    @State private var model = OnboardingCoordinator(state: AppState.preview(), apiStatus: APIStatus()) {}

    var body: some View {
        OnboardingStepView(step: step, model: model)
            .task { if saved { await model.saveAboutYou(birthYear: 1990) } }
    }
}

#Preview("Invite code · dark") {
    OnboardingStepPreview(step: .invite).previewEnvironment()
}

#Preview("Invite code · light") {
    OnboardingStepPreview(step: .invite).previewEnvironment(scheme: .light)
}

#Preview("Consent · dark") {
    OnboardingStepPreview(step: .consent).previewEnvironment()
}

#Preview("Consent · light") {
    OnboardingStepPreview(step: .consent).previewEnvironment(scheme: .light)
}

#Preview("About you · dark") {
    OnboardingStepPreview(step: .aboutYou).previewEnvironment()
}

#Preview("About you · saved · dark") {
    OnboardingStepPreview(step: .aboutYou, saved: true).previewEnvironment()
}

#Preview("About you · saved · light") {
    OnboardingStepPreview(step: .aboutYou, saved: true).previewEnvironment(scheme: .light)
}

#Preview("About you · light") {
    OnboardingStepPreview(step: .aboutYou).previewEnvironment(scheme: .light)
}
