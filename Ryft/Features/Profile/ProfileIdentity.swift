// Profile's identity row in Nocturne (docs/work/2026-11-16-nocturne/design.md §P5-6.1 row 2, "The avatar", "The display
// name", "The status row"; §P5-6.4): who the page is for, today's strain as a ring around the initials, and the sync's state
// in a word. The decisions are pure (`ProfileIdentity`, `ProfileStatus`), so tests 31 and 32 assert them without a view.
import SwiftUI

// MARK: - who

/// The identity row's title, its initials and today's strain (R-N2: the name is read-only until the platform can rename).
struct ProfileIdentity: Equatable, Sendable {
    /// Where the title came from.
    enum Source: Equatable, Sendable {
        /// `User.name`.
        case name
        /// The account's email (no name yet).
        case email
        /// Neither: the account's description (`AuthService.identityDescription`), or "Demo data".
        case description
    }

    let title: String
    let source: Source
    /// One or two letters, upper case; nil draws the `person` glyph.
    let initials: String?
    /// Today's strain (`DailyScore.strain`); nil draws the ring's track only.
    let strain: Double?

    /// The title falls back name → email → `fallback`; the initials follow the title.
    static func resolve(name: String?, email: String?, fallback: String, strain: Double?) -> ProfileIdentity {
        if let name = trimmed(name) {
            return ProfileIdentity(title: name, source: .name, initials: initials(name: name), strain: strain)
        }
        if let email = trimmed(email) {
            return ProfileIdentity(title: email, source: .email, initials: initials(email: email), strain: strain)
        }
        return ProfileIdentity(title: fallback, source: .description, initials: nil, strain: strain)
    }

    /// A name's initials: the first letter of each of its first two words ("Alex Doe" → "AD", "Åsa Öhman" → "ÅÖ"; one
    /// word, one letter). A word without a letter is skipped; no letter at all is nil.
    static func initials(name: String) -> String? {
        let letters = name.split(whereSeparator: \.isWhitespace)
            .compactMap { word in word.first(where: \.isLetter) }
            .prefix(2)
            .map { String($0).uppercased() }
        return letters.isEmpty ? nil : letters.joined()
    }

    /// An email's initial: the first letter of its local part ("alex@example.com" → "A").
    static func initials(email: String) -> String? {
        let local = email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        return local.first(where: \.isLetter).map { String($0).uppercased() }
    }

    /// The initials of a displayed title: an email's for an address, a name's otherwise; nil for nothing or blanks.
    static func initials(for title: String?) -> String? {
        guard let title = trimmed(title) else { return nil }
        return title.contains("@") ? initials(email: title) : initials(name: title)
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    /// The strain ring's sentence for VoiceOver.
    var spokenStrain: String {
        guard let strain else {
            return String(localized: "No strain yet today.",
                          comment: "VoiceOver, Profile's identity row: today's strain has no value yet (the ring shows its track only). The same words as the Strain tab's caption.")
        }
        return String(localized: "Strain today \(Fmt.strain(strain)) of 21.",
                      comment: "VoiceOver, Profile's identity row: today's strain on its 0–21 scale, e.g. 12.4.")
    }

    /// The row as one sentence (§P5-6.4): "Alex Doe. Apple Health, up to date. Strain today 12.4 of 21."
    func spokenLabel(_ status: ProfileStatus, now: Date) -> String {
        [title + ".", status.spoken(now: now), spokenStrain].joined(separator: " ")
    }
}

// MARK: - the sync's state

/// The status row under the name (§P5-6.1): the data's source and the shared `SyncLine` in one word, a dot whose shape and
/// ink are secondary cues (never teal: L27, D5-11), and what a tap does.
struct ProfileStatus: Equatable {
    /// The state's words, lower case after the source ("Apple Health · up to date").
    enum Word: Equatable {
        case upToDate, updating, offline, actionNeeded, notUpdatedYet
        /// Stale, or the last refresh or upload failed: how old the data is.
        case updated(Date)

        func text(now: Date, locale: Locale = .autoupdatingCurrent) -> String {
            switch self {
            case .upToDate:
                return String(localized: "up to date",
                              comment: "Profile's status row after the source: the sync is up to date (\"Apple Health · up to date\").")
            case .updating:
                return String(localized: "updating…", comment: "Profile's status row after the source: reading, uploading or scoring right now.")
            case .offline:
                return String(localized: "offline", comment: "Profile's status row after the source: no connection; it syncs when back.")
            case .actionNeeded:
                return String(localized: "action needed",
                              comment: "Profile's status row after the source: behind a gate (consent, invite) or signed out; a tap opens it.")
            case .notUpdatedYet:
                return String(localized: "not updated yet", comment: "Profile's status row after the source: nothing has loaded for this account yet.")
            case .updated(let date):
                let formatter = RelativeDateTimeFormatter()
                formatter.locale = locale
                formatter.dateTimeStyle = .named
                formatter.unitsStyle = .abbreviated
                let ago = formatter.localizedString(for: min(date, now), relativeTo: now)
                return String(localized: "updated \(ago)",
                              comment: "Profile's status row after the source: old data or a failed sync; when it last updated (\"updated 5 hr. ago\").")
            }
        }
    }

    /// The dot before the line: a state is never its colour alone (the word says it, the shape and ink follow).
    enum Dot: Equatable, CaseIterable {
        /// Up to date: a filled ink dot.
        case filled
        /// Updating, or nothing loaded yet: an ink ring.
        case hollow
        /// Offline or old data: a `warning` dot.
        case attention
        /// Action needed: an `alert` dot.
        case alert

        var color: Color {
            switch self {
            case .filled, .hollow: return Theme.textPrimary
            case .attention: return Theme.warning
            case .alert: return Theme.alert
            }
        }
    }

    /// What tapping the row does (as Today's status line).
    enum Tap: Equatable {
        case syncDetails
        /// The gate's step: consent or the invite.
        case gate(OnboardingCoordinator.Step)
        /// Try again: the data on screen is older than it should be.
        case retry
        /// Signed out (the session ended): back to Welcome to sign in again, as Today's card does (`signInAgain`).
        case signIn
        case none
    }

    let isDemo: Bool
    let word: Word
    let dot: Dot
    let tap: Tap

    /// "Apple Health" (the sync's source), "Demo data" in the demo.
    var source: String {
        isDemo ? String(localized: "Demo data") : String(localized: "Apple Health")
    }

    /// "Apple Health · up to date".
    func text(now: Date) -> String {
        let word = word.text(now: now)
        return String(localized: "\(source) · \(word)",
                      comment: "Profile's status row under the name: the data's source, then the sync's state (\"Apple Health · up to date\").")
    }

    /// "Apple Health, up to date." for VoiceOver.
    func spoken(now: Date) -> String {
        let word = word.text(now: now)
        return String(localized: "\(source), \(word).",
                      comment: "VoiceOver, Profile's identity row: the data's source and the sync's state (\"Apple Health, up to date.\").")
    }

    /// The row's word for Today's line, most urgent first as the line is. It never claims a freshness it doesn't have:
    /// `lastUpdated` is when the data on screen last loaded (a failed read says how old that is); `lastSync` is Apple
    /// Health's last good upload (`Settings.lastSync`: a paused upload says how old that is, and "up to date" needs one).
    static func decide(_ line: SyncLine, isDemo: Bool, lastUpdated: Date?, lastSync: Date?) -> ProfileStatus {
        func make(_ word: Word, _ dot: Dot, _ tap: Tap) -> ProfileStatus {
            ProfileStatus(isDemo: isDemo, word: word, dot: dot, tap: tap)
        }
        let uploaded = lastSync.map(Word.updated) ?? .notUpdatedYet
        switch line {
        case .actionNeeded(let step):
            return make(.actionNeeded, .alert, .gate(step))
        case .issue(_, signedOut: true):
            return make(.actionNeeded, .alert, .signIn)
        case .offline:
            return make(.offline, .attention, .syncDetails)
        case .stale(let since):
            return make(.updated(since), .attention, .retry)
        case .issue:
            return make(lastUpdated.map(Word.updated) ?? .notUpdatedYet, .attention, .syncDetails)
        case .paused:
            return make(uploaded, .attention, .syncDetails)
        case .waitingForUnlock:
            // Nothing is read while the iPhone is locked: the last upload's age, never "updating…".
            return make(uploaded, .hollow, .none)
        case .reading, .uploading, .scoring, .scoringSlow, .updating:
            return make(.updating, .hollow, .syncDetails)
        case .upToDate(let date, let demo):
            // The demo's sample is always there; an account's data may not have loaded, or Apple Health never uploaded.
            if !(demo || isDemo), date == nil || lastSync == nil { return make(.notUpdatedYet, .hollow, .syncDetails) }
            return make(.upToDate, .filled, .syncDetails)
        }
    }

    /// VoiceOver's hint for the row's tap.
    var hint: Text? {
        switch tap {
        case .syncDetails: return Text("Opens sync details")
        case .gate: return Text("Opens what's needed")
        case .retry: return Text("Tries to load your data again")
        case .signIn: return Text("Opens sign in", comment: "VoiceOver hint of Profile's status row when signed out: a tap opens sign in.")
        case .none: return nil
        }
    }
}

// MARK: - views

/// The avatar (§P5-6.1): a 72 pt frame; a strain ring of radius 34 from 12 o'clock clockwise by today's share of 21, ending in
/// a dot; inside, at inset 8, a `surface` disc with the initials (or the `person` glyph). No strain today: the track only.
/// Hidden from VoiceOver: the identity row says it.
struct ProfileAvatar: View {
    let initials: String?
    let strain: Double?

    private typealias L = ProfileLayout

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.textPrimary.opacity(L.trackOpacity), lineWidth: L.ringStroke)
                .frame(width: 2 * L.ringRadius, height: 2 * L.ringRadius)
            if let share = L.strainShare(strain) {
                Circle()
                    .trim(from: 0, to: share)
                    .stroke(Theme.metricStrain, style: StrokeStyle(lineWidth: L.ringStroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 2 * L.ringRadius, height: 2 * L.ringRadius)
                ZStack {
                    Circle().fill(Theme.background)
                        .frame(width: 2 * (L.endDotRadius + L.endDotRing), height: 2 * (L.endDotRadius + L.endDotRing))
                    Circle().fill(Theme.metricStrain)
                        .frame(width: 2 * L.endDotRadius, height: 2 * L.endDotRadius)
                }
                .position(L.endPoint(degrees: share * 360))
            }
            Circle()
                .fill(Theme.surface)
                .frame(width: L.discDiameter, height: L.discDiameter)
            if let initials {
                Text(verbatim: initials)
                    .font(.ryftNumber(size: L.initialsSize, weight: .light))
                    .tracking(L.initialsTracking)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Image(systemName: "person")
                    .font(.system(size: L.initialsSize, weight: .light))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .frame(width: L.avatar, height: L.avatar)
        .accessibilityHidden(true)
    }
}

/// The status row's dot: 6 pt at the default size, scaled with the caption, centred on the text's first line at any size
/// (a hidden line of the caption sits on the text's first baseline; the dot is in its middle).
struct ProfileStatusDot: View {
    let dot: ProfileStatus.Dot

    @ScaledMetric(relativeTo: .caption) private var size: CGFloat = ProfileLayout.statusDot

    var body: some View {
        Text(verbatim: "x")
            .font(.ryft(.caption))
            .lineLimit(1)
            .hidden()
            .frame(width: size)
            .overlay {
                Group {
                    if dot == .hollow {
                        Circle().strokeBorder(dot.color, lineWidth: ProfileLayout.hollowDotLine * size / ProfileLayout.statusDot)
                    } else {
                        Circle().fill(dot.color)
                    }
                }
                .frame(width: size, height: size)
            }
            .accessibilityHidden(true)
    }
}

/// The identity row (§P5-6.1 row 2): the avatar and, beside it, the name (20 Light, one line with middle truncation; it
/// wraps from AX1) over the status row. From AX1 the avatar sits over the name. One VoiceOver element, a header: "Alex Doe.
/// Apple Health, up to date. Strain today 12.4 of 21." The status row is the tap (Sync details, the gate's step, Try again,
/// sign in again), its target 44 pt high however short its line; VoiceOver activates the element for it.
struct ProfileIdentityRow: View {
    let identity: ProfileIdentity
    let status: ProfileStatus
    var onTap: () -> Void = {}

    private typealias L = ProfileLayout

    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title3) private var nameSize: CGFloat = ProfileLayout.nameSize

    var body: some View {
        // "updated 5 hr. ago" moves with the time alone.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            row(now: context.date)
        }
    }

    private func row(now: Date) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: L.identityStackedSpacing))
            : AnyLayout(HStackLayout(alignment: .center, spacing: L.identitySpacing))
        return layout {
            ProfileAvatar(initials: identity.initials, strain: identity.strain)
            VStack(alignment: .leading, spacing: L.nameToStatus) {
                Text(verbatim: identity.title)
                    .font(.ryftNumber(size: nameSize, weight: .light))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(stacked ? nil : 1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: stacked)
                statusLine(now: now)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: identity.spokenLabel(status, now: now)))
        .accessibilityAddTraits(status.tap == .none ? .isHeader : [.isHeader, .isButton])
        .accessibilityHint(status.hint ?? Text(verbatim: ""))
        .accessibilityAction {
            if status.tap != .none { onTap() }
        }
        .accessibilityIdentifier("profile.identity")
    }

    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        let line = HStack(alignment: .firstTextBaseline, spacing: L.statusDotGap) {
            ProfileStatusDot(dot: status.dot)
            Text(verbatim: status.text(now: now))
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        if status.tap == .none {
            line
        } else {
            Button(action: onTap) {
                line.modifier(StatusTapTarget())
            }
            .buttonStyle(.plain)
        }
    }
}

/// The status line's tap target: the line keeps its own height in the layout, its target reaches
/// `SyncStatusLineView.verticalOutset` past it above and below (44 pt or more for one line), as Today's status row's does.
private struct StatusTapTarget: ViewModifier {
    @State private var textHeight: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let outset = SyncStatusLineView.verticalOutset(textHeight: textHeight, scale: displayScale)
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            .padding(.vertical, outset)
            .contentShape(Rectangle())
            .padding(.vertical, -outset)
    }
}

// MARK: - previews (dark; default and AX3)

private enum ProfileIdentityPreview {
    static let named = ProfileIdentity.resolve(name: "Alex Doe", email: "alex@example.com", fallback: "", strain: 12.4)
    static let email = ProfileIdentity.resolve(name: "", email: "alex@example.com", fallback: "", strain: 4.1)
    static let noStrain = ProfileIdentity.resolve(name: "Alex Doe", email: nil, fallback: "", strain: nil)
    static let demo = ProfileIdentity.resolve(name: nil, email: nil, fallback: "Demo data", strain: 12.4)

    static func status(_ line: SyncLine, demo: Bool = false) -> ProfileStatus {
        let fiveHoursAgo = Date.now.addingTimeInterval(-5 * 3_600)
        return ProfileStatus.decide(line, isDemo: demo, lastUpdated: fiveHoursAgo, lastSync: fiveHoursAgo)
    }

    static var rows: some View {
        VStack(alignment: .leading, spacing: 24) {
            ProfileIdentityRow(identity: named, status: status(.upToDate(.now, demo: false)))
            ProfileIdentityRow(identity: email, status: status(.updating))
            ProfileIdentityRow(identity: noStrain, status: status(.offline))
            ProfileIdentityRow(identity: named, status: status(.stale(since: .now.addingTimeInterval(-5 * 3_600))))
            ProfileIdentityRow(identity: named, status: status(.actionNeeded(.consent)))
            ProfileIdentityRow(identity: demo, status: status(.upToDate(nil, demo: true), demo: true))
        }
    }
}

#Preview("Profile identity · states", traits: .sizeThatFitsLayout) {
    DarkPreview { ProfileIdentityPreview.rows }
}

#Preview("Profile identity · states · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { ProfileIdentityPreview.rows }
        .environment(\.dynamicTypeSize, .accessibility3)
}
