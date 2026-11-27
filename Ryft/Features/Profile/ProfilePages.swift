import SwiftUI

/// Profile's account, body, display, training, privacy and version pages, in the same grouped list as the main page.
struct ProfilePageView: View {
    let page: ProfilePage

    @Environment(ScreenModels.self) private var screens
    @Environment(\.appEnvironment) private var env

    var body: some View {
        let facts = ProfileRowFacts(screens.profile, journalLive: screens.journal.isLive, bedtimeEnabled: screens.bedtime.isEnabled,
                                    showsAnalytics: env.analytics.showsToggle)
        SubpageScaffold(page.title) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                ForEach(ProfilePage.sections(page, facts)) { section in
                    ProfilePageCard(section: section)
                }
            }
        }
    }
}

/// A page's card and its own footer. A card with no notice or sentence has no footer gap.
struct ProfilePageCard: View {
    let section: ProfilePage.Section

    @Environment(ScreenModels.self) private var screens
    private var model: ProfileViewModel { screens.profile }

    var body: some View {
        if hasFooter {
            GroupedCard(section.title.map { GroupTitle($0) }) { rows } footer: { footer }
        } else {
            GroupedCard(section.title) { rows }
        }
    }

    // MARK: - rows

    private var rows: some View {
        Group {
            ProfileRowList(rows: section.rows)
            #if DEBUG
            if section.id == .advanced {
                GroupedRow.push(Text(verbatim: "Component catalog"), identifier: ProfileRows.devCatalog, route: ProfileRoute.catalog)
                GroupedRow.push(Text(verbatim: "Feature flags"), identifier: ProfileRows.devFlags, route: ProfileRoute.flags)
            }
            #endif
        }
    }

    // MARK: - footers

    private var hasFooter: Bool {
        switch section.id {
        case .body, .display, .healthAccess: return true
        case .account: return !model.isSignedIn || model.accountError != nil
        case .training: return WorkoutHealthExport.shared.needsAccess || model.showsSessionLayout
        case .sync: return model.syncNotice != nil
        case .healthWrites: return WorkoutHealthExport.shared.needsAccess
        case .advanced: return model.bodySettings.rescoreStatus != nil || model.demoExitError != nil
        case .consent: return model.consentError != nil || model.consentCheckMessage != nil || model.consentDetail != nil
        case .yourData: return model.exportError != nil || (model.isSignedIn && model.accountError != nil)
        case .analytics, .nutritionPrivacy, .version, .syncDetails: return false
        }
    }

    @ViewBuilder private var footer: some View {
        switch section.id {
        case .body:
            let editor = model.bodySettings
            FooterStack {
                if let error = editor.birthYearError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle", details: editor.birthYearErrorDetails)
                }
                // A save whose answer came after its editor page went: said here, where the user is.
                if editor.errorMissed, let error = editor.error {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle", details: editor.errorDetails)
                        .accessibilityIdentifier("profile.bodySettingsError")
                }
                GroupFooter(Text("Changing a setting doesn't rescore past days on its own."))
            }
        case .account:
            if model.isSignedIn {
                accountError
            } else {
                GroupFooter(Text("Turn off Demo data in Devices and sync to log in or create an account.",
                                 comment: "Account page footer for a signed-out user in Demo data."))
            }
        case .display:
            GroupFooter(Text("Large numbers on Today, Sleep and Strain.",
                             comment: "Footer under Profile → Display → Hero numbers: where the dots or thin digits show."))
        case .training:
            FooterStack {
                if WorkoutHealthExport.shared.needsAccess { HealthWriteAccessHint() }
                if model.showsSessionLayout {
                    GroupFooter(Text("Focused: one exercise at a time. List: all exercises on one screen. Applies the next time you open a workout.",
                                     comment: "Footer under Profile → Training → Session layout."))
                }
            }
        case .healthAccess:
            GroupFooter(Text("Garmin Connect must write to Apple Health (Garmin Connect → More → Settings → Apple Health), and RYFT must be allowed to read it (Health → Sharing → Apps → RYFT)."))
        case .sync:
            switch model.syncNotice {
            case .retrying(let notice):
                InlineMessage(message: notice, systemImage: "clock.arrow.circlepath")
            case .failed(let message, let details):
                InlineMessage(message: message, systemImage: "exclamationmark.arrow.triangle.2.circlepath", details: details)
            case nil:
                EmptyView()
            }
        case .healthWrites:
            HealthWriteAccessHint()
        case .advanced:
            FooterStack {
                RescoreStatus(editor: model.bodySettings)
                if let error = model.demoExitError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle")
                }
            }
        case .consent:
            FooterStack {
                if let error = model.consentError {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle", details: model.consentErrorDetails)
                }
                if let unanswered = model.consentCheckMessage {
                    InlineMessage(message: unanswered, systemImage: "exclamationmark.circle", details: model.consentCheckDetails,
                                  identifier: "privacy.checkUnanswered")
                }
                if let detail = model.consentDetail {
                    GroupFooter(consentFooter(detail))
                }
            }
        case .yourData:
            FooterStack {
                if let error = model.exportError {
                    InlineMessage(message: error, systemImage: "square.and.arrow.up")
                }
                if model.isSignedIn { accountError }
            }
        case .analytics, .nutritionPrivacy, .version, .syncDetails:
            EmptyView()
        }
    }

    @ViewBuilder private var accountError: some View {
        if let error = model.accountError {
            InlineMessage(message: error, systemImage: "exclamationmark.circle", details: model.accountErrorDetails)
        }
    }

    /// "Agreed on 3 Nov 2026 · policy 2026-11. Read the policy": the policy in force beside Withdraw consent, in the in-app
    /// sheet (`safariSheet` catches its `LegalPage` URL); the link in the link ink, underlined (`InlineLink`).
    private func consentFooter(_ detail: String) -> Text {
        let words = String(localized: "Read the policy",
                           comment: "Link at the end of Profile → Privacy's footer: opens the privacy policy in force in RYFT.")
        // One unit: the link wraps as a whole, never inside itself (UI validation round 3, 2).
        var link = AttributedString(words.replacingOccurrences(of: " ", with: "\u{00A0}"))
        link.link = model.policyPage.url
        return Text(InlineLink.styled(AttributedString(detail + " ") + link))
    }
}

// MARK: - previews (dark; default and AX3)

#if DEBUG
#Preview("Body and baselines") { ProfilePreview.page(.signedIn, route: .body) }
#Preview("Body and baselines · AX3") { ProfilePreview.page(.signedIn, route: .body, ax3: true) }
#Preview("Account") { ProfilePreview.page(.signedIn, route: .account) }
#Preview("Account · AX3") { ProfilePreview.page(.signedIn, route: .account, ax3: true) }
#Preview("Account · signed out") { ProfilePreview.page(.signedOutDemo, route: .account) }
#Preview("Units and display") { ProfilePreview.page(.signedIn, route: .display) }
#Preview("Units and display · AX3") { ProfilePreview.page(.signedIn, route: .display, ax3: true) }
#Preview("Training") { ProfilePreview.page(.signedIn, route: .training) }
#Preview("Training · AX3") { ProfilePreview.page(.signedIn, route: .training, ax3: true) }
#Preview("Privacy and data") { ProfilePreview.page(.signedIn, route: .privacyAndData) }
#Preview("Privacy and data · AX3") { ProfilePreview.page(.signedIn, route: .privacyAndData, ax3: true) }
#Preview("What's new") { ProfilePreview.page(.signedIn, route: .whatsNew) }
#Preview("What's new · AX3") { ProfilePreview.page(.signedIn, route: .whatsNew, ax3: true) }
#endif
