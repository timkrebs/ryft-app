import SwiftUI

/// An activity the user added or RYFT recorded (Nocturne PR 6 B §10.3, `b-21`). The pushed header (the sport, its day and
/// times, the Edit / Delete menu); while it isn't at RYFT, what is happening to the upload; the duration as the hero numeral
/// with its sources; the number tiles; the strain block (where the strain comes from); a recorded run's heart-rate link and
/// splits; notes; Edit and Delete. It reads only what this iPhone has, so it opens offline with the honest line, never a
/// spinner.
struct ActivityDetailView: View {
    let route: ActivityRoute
    @Environment(AppState.self) private var state

    var body: some View {
        ActivityDetailScreen(model: ActivityDetailViewModel(route: route, state: state))
    }
}

/// Layout only; the first model handed in is kept for the screen's lifetime.
struct ActivityDetailScreen: View {
    @State var model: ActivityDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(TrainCoordinator.self) private var coordinator
    @State private var editing: AddActivityModel?
    @State private var confirmsDelete = false
    @State private var workout: Workout?
    /// Deleted here: the screen is closing. Its title stays and "isn't on this iPhone any more" doesn't flash.
    @State private var closingTitle: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                if model.activity != nil {
                    if let line = model.syncLine {
                        syncMessage(line).padding(.top, ActivitiesLayout.syncGap)
                    }
                    hero
                        .padding(.top, ActivitiesLayout.numeralGap)
                    tiles
                        .padding(.top, ActivitiesLayout.tilesGap)
                    VStack(spacing: ActivitiesLayout.sectionSpacing) {
                        strainBlock
                        if let w = model.mergedWorkout { heartRateRow(w) }
                        if let splits = model.activity?.splits, !splits.isEmpty {
                            SplitsTable(splits: splits, paceStyle: model.activity?.sport.paceStyle ?? .pace)
                        }
                        notes
                        if model.suggestsTrain { trainBlock }
                        if model.isEditable { actions }
                    }
                    .padding(.top, ActivitiesLayout.sectionSpacing)
                } else if closingTitle == nil {
                    InlineMessage(message: String(localized: "This activity isn't on this iPhone any more.",
                                                  comment: "Activity detail: deleted meanwhile."),
                                  systemImage: "trash", identifier: "activityDetail.gone")
                        .padding(.top, ActivitiesLayout.tilesGap)
                }
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, ActivitiesLayout.detailBottomPadding)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
        .sheet(item: $editing) { AddActivitySheet(model: $0) }
        .navigationDestination(item: $workout) { WorkoutDetailView(workout: $0) }
        .confirmationDialog(Text("Delete this activity?"), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(role: .destructive) {
                let title = model.title
                // A tombstone until the platform confirms (or gone at once): either way it's no longer shown.
                if model.delete() {
                    closingTitle = title
                    dismiss()
                }
            } label: {
                Text("Delete", comment: "Confirms deleting an activity or a night the user added.")
            }
            .accessibilityIdentifier("activityDetail.confirmDelete")
            Button(role: .cancel) {} label: { Text("Keep", comment: "Cancels deleting an activity or a night.") }
        } message: {
            Text(model.isRecorded
                 ? String(localized: "It's removed from RYFT, including its route, and your strain for the day is recalculated.")
                 : String(localized: "It's removed from RYFT and your strain for the day is recalculated."))
        }
        .accessibilityIdentifier("activityDetail")
    }

    // MARK: header

    /// Back · the sport over "Tue, Nov 17 · 6:00 – 6:20 AM" · the Edit / Delete menu (or an empty slot when read-only).
    private var header: some View {
        PushedHeader(Text(verbatim: closingTitle ?? model.title),
                     subtitle: model.activity == nil ? nil : Text(verbatim: model.subtitle(locale: locale)),
                     spokenSubtitle: model.activity == nil ? nil : Text(verbatim: model.when(locale: locale)),
                     identifierPrefix: "activityDetail") {
            if model.isEditable {
                menu
            } else {
                PushedHeaderEmptySlot()
            }
        }
    }

    /// A menu, so a `CircleButton` (a button) can't be it: the label draws the circle button's look from its numbers.
    private var menu: some View {
        Menu {
            Button { editing = model.editModel() } label: { Label("Edit", systemImage: "pencil") }
                .accessibilityIdentifier("activityDetail.menu.edit")
            Button(role: .destructive) { confirmsDelete = true } label: { Label("Delete", systemImage: "trash") }
                .accessibilityIdentifier("activityDetail.menu.delete")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: CircleButton.iconSize, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: CircleButton.diameter, height: CircleButton.diameter)
                .overlay {
                    Circle().strokeBorder(Theme.textPrimary.opacity(CircleButton.borderOpacity), lineWidth: Theme.Metrics.hairline)
                }
                .frame(width: CircleButton.hitSize, height: CircleButton.hitSize)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("More", comment: "VoiceOver: the activity detail's menu (Edit, Delete)."))
        .accessibilityIdentifier("activityDetail.menu")
    }

    // MARK: sync (one line at a time, above the numeral)

    /// The upload's state while this iPhone has something to send; else, offline, that what's shown is what's saved here.
    @ViewBuilder
    private func syncMessage(_ line: ActivityDetailViewModel.SyncLine) -> some View {
        switch line {
        case .upload(let note):
            uploadMessage(note)
        case .offlineCache:
            InlineMessage(message: String(localized: "Showing what's saved on this iPhone."), systemImage: "wifi.slash",
                          identifier: "activityDetail.offline", readsAsOne: true)
        }
    }

    @ViewBuilder
    private func uploadMessage(_ note: ActivityDetailViewModel.UploadNote) -> some View {
        switch note {
        case .uploading:
            InlineMessage(message: String(localized: "Saved on this iPhone. Uploading to RYFT.", comment: "Activity detail: queued or being sent."),
                          systemImage: "icloud.and.arrow.up", identifier: "activityDetail.upload", readsAsOne: true)
        case .offline:
            InlineMessage(message: String(localized: "Saved on this iPhone. It will upload when you're online."),
                          systemImage: "icloud.and.arrow.up", identifier: "activityDetail.upload", readsAsOne: true)
        case .notAvailableYet:
            InlineMessage(message: String(localized: "Saved on this iPhone. Uploading activities to RYFT isn't available yet.",
                                          comment: "Activity detail: the platform doesn't take activities yet; nothing is sent."),
                          systemImage: "icloud.and.arrow.up", identifier: "activityDetail.upload", readsAsOne: true)
        case .gated:
            InlineMessage(message: String(localized: "Saved on this iPhone. It uploads once your account is ready.",
                                          comment: "Activity detail: the invite or consent step isn't done; the upload waits."),
                          systemImage: "icloud.and.arrow.up", identifier: "activityDetail.upload", readsAsOne: true)
        case .accountDeleting:
            InlineMessage(message: String(localized: "Your account is being deleted. This activity is deleted with it.",
                                          comment: "Activity detail: uploads stopped because the account is being deleted."),
                          systemImage: "trash", identifier: "activityDetail.upload", severity: .destructive, readsAsOne: true)
        case .retrying:
            InlineMessage(message: String(localized: "Saved on this iPhone. RYFT will try again, or tap Retry.",
                                          comment: "Activity detail: an upload failed and waits to be retried."),
                          systemImage: "icloud.and.arrow.up", retryTitle: "Retry", retry: { await model.retry() },
                          identifier: "activityDetail.upload")
        case .refused(let attempt):
            // The user has to change something: the one "needs attention" line.
            InlineMessage(message: String(localized: "RYFT couldn't accept this activity. It is still saved on this iPhone."),
                          systemImage: "exclamationmark.circle", retryTitle: "Try again", details: attempt.details,
                          retry: { await model.retry() }, identifier: "activityDetail.upload",
                          action: model.isEditable ? (title: String(localized: "Edit"), perform: { editing = model.editModel() }) : nil,
                          severity: .attention)
        case .failed(let attempt):
            InlineMessage(message: String(localized: "Couldn't upload. It is still saved on this iPhone.",
                                          comment: "Activity detail: retries ran out; the activity is still on the phone."),
                          systemImage: "exclamationmark.circle", retryTitle: "Retry", details: attempt.details,
                          retry: { await model.retry() }, identifier: "activityDetail.upload")
        }
    }

    // MARK: the numeral

    /// The duration as h:mm in dots (Light from AX1, or the user's Thin), "Duration · h:mm" 12 under it, the sources 8 under
    /// that. VoiceOver: "Duration, 20 minutes"; the caption is the numeral's.
    private var hero: some View {
        VStack(spacing: 0) {
            DotNumeral(model.durationNumeral, style: model.numeralStyle, glyphGap: DotNumeral.glyphGapDetail, placeholder: "0:00",
                       accessibilityLabel: Text("Duration"))
                .accessibilityValue(Text(verbatim: model.spokenDuration ?? ""))
                .accessibilityIdentifier("activityDetail.numeral")
            Text("Duration · h:mm", comment: "Activity detail: under the hero numeral, what it shows and how (hours:minutes).")
                .ryftLabelStyle()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ActivitiesLayout.captionGap)
                .accessibilityHidden(true)
            if let sources = model.item?.sources, !sources.isEmpty {
                SourceBadges(sources: sources, merged: model.isMerged)
                    .fixedSize(horizontal: typeSize.isAccessibilitySize ? false : true, vertical: true)
                    .padding(.top, ActivitiesLayout.badgeGap)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activityDetail.hero")
    }

    // MARK: tiles

    /// Two columns, 12 apart (an odd last one alone, left); one column from AX1. Each pair matches the taller.
    private var tiles: some View {
        let stats = model.stats(locale: locale)
        return VStack(spacing: ActivitiesLayout.tileSpacing) {
            if typeSize.isAccessibilitySize {
                ForEach(stats) { tile($0) }
            } else {
                ForEach(Array(stride(from: 0, to: stats.count, by: ActivitiesLayout.tileColumns)), id: \.self) { i in
                    HStack(spacing: ActivitiesLayout.tileSpacing) {
                        tile(stats[i])
                        if i + 1 < stats.count {
                            tile(stats[i + 1])
                        } else {
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activityDetail.stats")
    }

    private func tile(_ stat: ActivityDetailViewModel.Stat) -> some View {
        NeutralTile(Text(verbatim: stat.title), value: Text(verbatim: stat.value), unit: stat.unit.map { Text(verbatim: $0) },
                    accessibilityValue: stat.spoken.map { Text(verbatim: $0) })
            .accessibilityIdentifier("activityDetail.stat.\(stat.id)")
    }

    // MARK: strain

    /// Where the strain comes from (§10.3 item 3): from heart rate, Today's strain tile (the glow, the value, the band, the
    /// compact ruler) with its source under it; otherwise a `surface` card that says what is missing and why. A merged activity
    /// says what each side gave instead of the source.
    @ViewBuilder private var strainBlock: some View {
        Group {
            switch model.strainLine {
            case .heartRate(let value, let source):
                scored(value, caption: model.isMerged ? mergeText : source.map { String(localized: "Heart rate from \($0)") })
            case .value(let value):
                scored(value, caption: model.isMerged ? mergeText : nil)
            case .effort(let value, let rating):
                unscoredCard(value: value,
                             line: Text("No heart rate for this time."), systemImage: "minus.circle",
                             reason: rating.map {
                                 Text("From your effort rating (\($0) of 10). Strain becomes more precise when heart rate arrives.")
                             } ?? Text("From your effort rating. Strain becomes more precise when heart rate arrives.",
                                       comment: "Activity detail: strain from perceived effort, the rating unknown."))
            case .noHeartRate:
                unscoredCard(value: nil, line: Text("No heart rate for this time."), systemImage: "minus.circle",
                             reason: Text("Without heart rate there is no strain for this activity."))
            case .waiting:
                unscoredCard(value: nil, line: Text("Waiting for heart rate"), systemImage: nil, reason: nil)
            }
        }
        .accessibilityIdentifier("activityDetail.strain")
    }

    /// Today's strain tile and, 8 under it, where its heart rate came from. One element: "Strain", "10.6 of 21, Moderate
    /// strain. Heart rate from Garmin Connect".
    private func scored(_ value: Double, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: ActivitiesLayout.strainCaptionGap) {
            ActivityStrainTile(strain: value)
            if let caption {
                Text(verbatim: caption)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Strain"))
        .accessibilityValue(Text(verbatim: ActivityStrainTile.spokenBlock(value, caption: caption)))
    }

    /// "Strain" (with the platform's value when it made one from the effort rating), the line with its glyph, the reason.
    private func unscoredCard(value: Double?, line: Text, systemImage: String?, reason: Text?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: ActivitiesLayout.strainCardSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Strain").ryftLabelStyle()
                    Spacer(minLength: 8)
                    if let value {
                        HStack(alignment: .firstTextBaseline, spacing: TodayLayout.strainCaptionGap) {
                            Text(verbatim: Fmt.strain(value))
                                .font(.ryftNumber(size: NeutralTile.valueSize, weight: .light))
                                .foregroundStyle(Theme.textPrimary)
                            Text(verbatim: TodayStrainBand(value).caption)
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .lineLimit(1)
                        .fixedSize()
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                    } else {
                        // Waiting: an outline dot, the pending mark of the rows.
                        Circle()
                            .strokeBorder(Theme.textTertiary, lineWidth: Theme.Metrics.controlOutline)
                            .frame(width: 12, height: 12)
                            .accessibilityHidden(true)
                    }
                    line
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reason {
                    reason
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, ActivitiesLayout.strainReasonGap - ActivitiesLayout.strainCardSpacing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// What a merge took from each side (`MergedPart`), named by the tracker.
    private var mergeText: String {
        let source = model.mergeSource ?? MyDayAssembler.appleHealth
        switch model.mergedPart {
        case .route:
            return String(localized: "Merged from two sources: heart rate from \(source), route and distance from RYFT. RYFT counts this activity once.")
        case .recording:
            return String(
                localized: "Merged from two sources: heart rate from \(source), everything else from RYFT's recording. RYFT counts this activity once.",
                comment: "Activity detail: a merged indoor or pedometer recording; the tracker's name.")
        case .entry:
            return String(localized: "Merged from two sources: heart rate from \(source), the rest from what you added. RYFT counts this activity once.",
                          comment: "Activity detail: a merged manual activity; the tracker's name.")
        }
    }

    // MARK: rows

    /// The merged tracker workout's heart rate and zones: an activity row with a chevron, opening PR 5's Workout detail.
    private func heartRateRow(_ w: Workout) -> some View {
        Button { workout = w } label: {
            ActivityListRow(content: ActivityListRow.Content(
                systemImage: "heart", title: String(localized: "Heart rate and zones"), meta: model.mergeSource, value: nil,
                spoken: [String(localized: "Heart rate and zones"), model.mergeSource].compactMap { $0 }.joined(separator: ", "),
                showsValue: false),
                            accessory: .chevron)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("Opens the workout", comment: "VoiceOver hint: the row opens the workout's detail."))
        .accessibilityIdentifier("activityDetail.mergedWorkout")
    }

    @ViewBuilder
    private var notes: some View {
        if let text = model.activity?.notes, !text.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes").ryftLabelStyle()
                    Text(verbatim: text)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("activityDetail.notes")
        } else if model.isEditable {
            Button { editing = model.editModel() } label: {
                HStack(spacing: ActivitiesLayout.addNoteSpacing) {
                    // The row's `callout`, so the glyph grows with the words.
                    Image(systemName: "square.and.pencil")
                        .accessibilityHidden(true)
                    Text("Add a note")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: ActivitiesLayout.addNoteHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("activityDetail.addNote")
        }
    }

    // MARK: actions

    /// A manual Strength activity has no sets: the sentence, then Log this in Train (D8).
    private var trainBlock: some View {
        VStack(alignment: .leading, spacing: ActivitiesLayout.actionSpacing) {
            Text("Strength is best logged in Train. Your sets, reps and load count toward muscular load.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(Text("Log this in Train"), style: .secondary) { await coordinator.quickStart(.auto) }
                .accessibilityIdentifier("activityDetail.logInTrain")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Edit (an outline pill) and Delete (the destructive outline, "Delete activity" for VoiceOver), 12 apart.
    private var actions: some View {
        VStack(spacing: ActivitiesLayout.actionSpacing) {
            PillButton(Text("Edit"), style: .secondary) { editing = model.editModel() }
                .accessibilityIdentifier("activityDetail.edit")
            PillButton(Text("Delete"), style: .destructive) { confirmsDelete = true }
                .accessibilityLabel(Text("Delete activity", comment: "VoiceOver: the activity detail's Delete pill."))
                .accessibilityIdentifier("activityDetail.delete")
        }
    }
}

/// Today's strain tile on an activity (PR 5's `TodayStrainTile` drawn from the same parts: the strain glow tile, the value
/// and its band caption, the compact ruler with the moderate band). Not a button here: the detail is where it leads. From AX1:
/// the label, then the value and the caption, then the ruler. The caller makes it one VoiceOver element.
struct ActivityStrainTile: View {
    let strain: Double
    /// Previews and tests; nil follows the system.
    var reduceTransparency: Bool?

    @Environment(\.dynamicTypeSize) private var typeSize

    private var band: TodayStrainBand { TodayStrainBand(strain) }

    var body: some View {
        GlowTile(Theme.metricStrain, kind: .strain, reduceTransparency: reduceTransparency) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: TodayLayout.tileRowGap) {
                    label.fixedSize(horizontal: false, vertical: true)
                    TodayStrainValueRow(value: Fmt.strain(strain), caption: band.caption)
                    ruler
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    label
                    Spacer(minLength: TodayLayout.tileRowGap)
                    TodayStrainTile.value(Fmt.strain(strain))
                    TodayStrainTile.caption(band.caption)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.leading, TodayLayout.strainCaptionGap)
                }
                .frame(maxWidth: .infinity, minHeight: TodayLayout.strainContentHeight, alignment: .top)
                .overlay(alignment: .bottom) { ruler }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Strain"))
        .accessibilityValue(Text(verbatim: Self.spoken(strain)))
    }

    /// "10.6 of 21, Moderate strain".
    static func spoken(_ strain: Double) -> String {
        "\(Fmt.strain(strain)) \(TodayStrainBand.scaleOnly), \(TodayStrainBand(strain).spoken)"
    }

    /// The detail's strain block after "Strain": "10.6 of 21, Moderate strain. Heart rate from Garmin Connect".
    static func spokenBlock(_ strain: Double, caption: String?) -> String {
        [spoken(strain), caption].compactMap { $0 }.joined(separator: ". ")
    }

    private var label: some View {
        Text("Strain")
            .ryftGlowLabelStyle()
            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
    }

    private var ruler: some View {
        RulerScale(range: 0...OrbitGaugeValues.strainScale, value: strain, zone: TodayStrainBand.zone,
                   zoneStyle: .standard, tickCount: RulerScale.Ticks.strainCompact, size: .compact,
                   accessibilityLabel: Text("Strain scale", comment: "VoiceOver label of a strain ruler (0 to 21)."),
                   accessibilityValue: Text(verbatim: Self.spoken(strain)))
    }
}

// MARK: - previews (dark only)

@MainActor
private enum DetailPreview {
    static let state = AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true])
    /// The same with the uploader held by the consent gate (`.pending(.gated)`).
    static let gated: AppState = {
        let state = AppState.preview(flags: [.todayMyDay: true, .activitiesManual: true])
        state.env.uploader.gate = { _ in .gate(.consentRequired) }
        return state
    }()
    /// Offline: what this iPhone saved waits to upload.
    static let offline = AppState.preview(online: false, flags: [.todayMyDay: true, .activitiesManual: true])
    static var demo: [SportActivity] { MockActivitiesSource.demo() }

    /// The demo platform's activities cached, plus a manual HIIT on this iPhone (not uploaded yet).
    static func host(_ pick: (([SportActivity]) -> SportActivity?)?, local: Bool = false,
                     state given: AppState? = nil) -> some View {
        let state = given ?? Self.state
        let all = demo
        for day in Set(all.map { DayFormat.string(from: $0.start) }) {
            state.repository.seed(.activities(all.filter { DayFormat.string(from: $0.start) == day }, day: day))
        }
        var id = pick?(all)?.id ?? UUID()
        var day = pick?(all)?.start ?? .now
        if local, let saved = state.env.activities.save(manual: ActivityDraft(
            sport: .hiit, start: .now.addingTimeInterval(-3_600), end: .now.addingTimeInterval(-1_800), perceivedEffort: 8,
            notes: "Intervals, 8 × 1 min")) {
            id = saved.id
            day = saved.start
        }
        return NavigationStack { ActivityDetailView(route: ActivityRoute(id: id, day: day)) }
    }
}

#Preview("Detail · manual, no heart rate (mobility)") {
    DetailPreview.host { $0.first { $0.sport == .mobility } }.previewEnvironment(DetailPreview.state)
}

#Preview("Detail · merged run with splits") {
    DetailPreview.host { $0.first { $0.mergedWith != nil } }.previewEnvironment(DetailPreview.state)
}

#Preview("Detail · recorded ride") {
    DetailPreview.host { $0.first { $0.sport == .cycling } }.previewEnvironment(DetailPreview.state)
}

#Preview("Detail · strain pending (yoga)") {
    DetailPreview.host { $0.first { $0.sport == .yoga } }.previewEnvironment(DetailPreview.state)
}

#Preview("Detail · effort strain (padel)") {
    DetailPreview.host { $0.first { $0.sport == .padel } }.previewEnvironment(DetailPreview.state)
}

#Preview("Detail · saved offline (HIIT)") {
    DetailPreview.host(nil, local: true, state: DetailPreview.offline).previewEnvironment(DetailPreview.offline)
}

#Preview("Detail · waiting for consent (gated)") {
    DetailPreview.host(nil, local: true, state: DetailPreview.gated).previewEnvironment(DetailPreview.gated)
}

#Preview("Detail · merged run · AX3") {
    DetailPreview.host { $0.first { $0.mergedWith != nil } }.previewEnvironment(DetailPreview.state)
        .environment(\.dynamicTypeSize, .accessibility3)
}
