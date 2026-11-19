import SwiftUI

/// The Journal's numbers (Nocturne PR 6 B §11, `b-17`, `b-22`; plain values, so tests assert numbers).
enum JournalLayout {
    // MARK: Today's card

    /// The card's disc → its words → "Answer", and the title → the line under it.
    nonisolated static let cardSpacing: CGFloat = 12, cardLineGap: CGFloat = 4

    // MARK: the sheet

    /// The header → the day strip (8), the strip → the first group or notice (20), and between the groups and notices (18,
    /// `GroupedListSpec.groupSpacing`).
    nonisolated static let headerToStrip: CGFloat = 8, stripToContent: CGFloat = 20, groupSpacing: CGFloat = 18
    /// The last group → the sheet's bottom edge.
    nonisolated static let bottomPadding: CGFloat = 32
    /// A day chip: at least 48 × 56, radius 16, 8 apart, 6 inside at the sides; the weekday 2 above the day's number (17).
    nonisolated static let chipWidth: CGFloat = 48, chipHeight: CGFloat = 56, chipRadius: CGFloat = 16
    nonisolated static let chipSpacing: CGFloat = 8, chipInset: CGFloat = 6, chipLineGap: CGFloat = 2
    nonisolated static let chipDaySize: CGFloat = 17
    /// A day that can't change any more: its rows at 55 % (the switches keep their look; `.disabled` would draw them off).
    nonisolated static let readOnlyOpacity = 0.55
    /// The habits' counts: 1 to 50 (`JournalSheetModel.Row.count`).
    nonisolated static let countRange = 1...50
    /// The offline pill: a 1 pt outline at ink 12 % (the source badge's), a 12 pt glyph, 12 × 6 inside, 6 between.
    nonisolated static let pillOutlineOpacity = 0.12, pillGlyphSize: CGFloat = 12
    /// The pill's outline once its words wrap (accessibility sizes).
    nonisolated static let pillWrappedRadius: CGFloat = 16
    nonisolated static let pillHorizontal: CGFloat = 12, pillVertical: CGFloat = 6, pillSpacing: CGFloat = 6
    /// The no-habits sentence → its pill.
    nonisolated static let noHabitsGap: CGFloat = 12
    /// While the catalog isn't known either: three outline rows.
    nonisolated static let placeholderRows = 3
}

// MARK: - Today's card

/// Today → Journal: "How was yesterday?" until yesterday is answered, then "Yesterday" and the answers. Hidden while the journal
/// isn't live (M5).
struct JournalCard: View {
    let store: JournalStore
    let open: () -> Void

    var body: some View {
        JournalCardBody(summary: store.days[store.yesterday].flatMap { store.summary(of: $0) }, open: open)
    }
}

/// The card itself (PR 6 B §11.1, `b-17`): a 36 pt outline disc with the clipboard, the question in `callout` over why to answer
/// it in `caption`, or once answered "Yesterday" over the answers; "Answer" / "Edit" in link ink at the end of the first line
/// (under the words from AX1). The whole card is the one button, "Opens the journal"; VoiceOver reads its words in order.
struct JournalCardBody: View {
    /// Yesterday's answers in a line; nil until yesterday is answered.
    let summary: String?
    let open: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: open) {
            Card {
                HStack(alignment: .top, spacing: JournalLayout.cardSpacing) {
                    IconDisc(systemImage: "list.bullet.clipboard")
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: JournalLayout.cardSpacing) {
                            words
                            actionWord
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: JournalLayout.cardSpacing) {
                            words.frame(maxWidth: .infinity, alignment: .leading)
                            actionWord
                        }
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("Opens the journal"))
        .accessibilityIdentifier("journal.card")
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: JournalLayout.cardLineGap) {
            if let summary {
                Text("Yesterday")
                    .font(.ryft(.label))
                    .foregroundStyle(Theme.textSecondary)
                Text(verbatim: summary)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("How was yesterday?")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("A few taps, and RYFT shows how your habits change the morning after.")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// "Answer" or "Edit" as a link looks (`ryftLink`'s ink and underline): a word of the card's button, not a button of its own.
    private var actionWord: some View {
        (summary == nil ? Text("Answer") : Text("Edit"))
            .font(.ryft(.callout))
            .foregroundStyle(InlineLink.ink)
            .underline(true, pattern: .solid, color: InlineLink.ink.opacity(InlineLink.underlineOpacity))
            .fixedSize()
    }
}

// MARK: - the sheet

/// What the sheet draws at one moment: the model's state and the iPhone's connection. Previews, shots and tests build it
/// directly for each state.
struct JournalSheetContent {
    /// "Yesterday" or "Mon, Nov 16".
    var title: String
    /// The strip's days, newest first, and the selected one ("2026-11-18").
    var days: [String]
    var selected: String
    var phase: JournalSheetModel.Phase
    var groups: [JournalSheetModel.Group]
    var editable: Bool
    var readOnlyReason: String?
    var isSaving: Bool
    var saved: Bool
    var error: String?
    var errorDetails: String?
    var isOnline: Bool

    /// Save is offered for a day whose rows are shown and can change, until it is saved: not while it saves (busy), not for a
    /// read-only day, not without a habit, not while the day isn't on this phone (an empty form would answer "no" to all).
    var canSave: Bool { phase == .ready && editable && !isSaving && !saved }

    /// Why Save is off, for VoiceOver's hint.
    var saveHint: String? {
        guard !canSave, !isSaving, !saved else { return nil }
        if phase == .noHabits { return JournalSheetBody.noHabitsMessage }
        return readOnlyReason
    }
}

extension JournalSheetContent {
    @MainActor
    init(_ model: JournalSheetModel, isOnline: Bool) {
        self.init(title: model.title, days: model.stripDays, selected: model.day, phase: model.phase(isOnline: isOnline),
                  groups: model.groups, editable: model.editable, readOnlyReason: model.readOnlyReason, isSaving: model.isSaving,
                  saved: model.saved, error: model.error, errorDetails: model.errorDetails, isOnline: isOnline)
    }
}

/// What the sheet's controls do: the live sheet passes its model's, previews leave them empty.
struct JournalSheetActions {
    var select: (String) -> Void = { _ in }
    var setOn: (UUID, Bool) -> Void = { _, _ in }
    var setCount: (UUID, Int) -> Void = { _, _ in }
    var setTime: (UUID, String) -> Void = { _, _ in }
    var save: () async -> Void = {}
    /// Reads the day again (offline, failed).
    var retry: () async -> Void = {}
    /// Profile → Journal's page (no habits chosen).
    var chooseHabits: () -> Void = {}
}

/// The journal sheet: yesterday by default, the strip steps back 14 days. Loads the day on open, and again when the iPhone is back
/// online while the day isn't on it (not when it is: that would undo answers being given). Saving closes it.
struct JournalSheet: View {
    @State var model: JournalSheetModel
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectivityMonitor.self) private var connectivity
    @State private var choosesHabits = false

    var body: some View {
        NavigationStack {
            JournalSheetBody(content: JournalSheetContent(model, isOnline: connectivity.isOnline), actions: actions)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $choosesHabits) { JournalSettingsView(store: model.store) }
        }
        .toggleStyle(.ryft)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.background)
        .task { await model.load() }
        .onChange(of: connectivity.isOnline) { _, online in
            if online, !model.hasDay { Task { await model.load() } }
        }
        // Back from Profile → Journal: the habits chosen there.
        .onChange(of: choosesHabits) { _, open in
            if !open { Task { await model.load() } }
        }
    }

    private var actions: JournalSheetActions {
        let model = model
        return JournalSheetActions(select: { day in Task { await model.select(day) } },
                                   setOn: { model.set($0, on: $1) },
                                   setCount: { model.set($0, count: $1) },
                                   setTime: { model.set($0, time: $1) },
                                   save: { await save() },
                                   retry: { await model.load() },
                                   chooseHabits: { choosesHabits = true })
    }

    private func save() async {
        await model.save()
        if model.saved { dismiss() }
    }
}

/// The sheet's page (PR 6 B §11.2, `b-22`): the sheet header (Close, the day, a compact Save that reads "Saved" once it has
/// saved), the day strip, then the notices and the groups. A group per category, a switch per habit; a habit that's on opens
/// its sub-row (Count, a stepper; Time, a chip) without a hairline of its own.
///
/// States: offline, a one-line pill over the groups (saving needs the network, `JournalStore`, so it says so and never that
/// the answers will be sent later); a read-only day, a lock notice and the rows at 55 %, untappable; no habits, the sentence and
/// a pill to Profile → Journal; a day not on this phone, outline cards while it loads, a line with Try again when offline or
/// when the read failed; a failed save, the message with Try again and Details on top; saving, the busy Save.
struct JournalSheetBody: View {
    let content: JournalSheetContent
    var actions = JournalSheetActions()

    static var noHabitsMessage: String {
        String(localized: "Choose habits in Profile → Journal.",
               comment: "Journal sheet: no habit is chosen yet; a button to Profile → Journal follows.")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    JournalDateStrip(days: content.days, selected: content.selected, select: actions.select)
                        .padding(.top, JournalLayout.headerToStrip)
                    VStack(alignment: .leading, spacing: JournalLayout.groupSpacing) {
                        notices
                        phaseContent
                    }
                    .padding(.top, JournalLayout.stripToContent)
                }
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.bottom, JournalLayout.bottomPadding)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: header

    private var header: some View {
        SheetHeader(Text(verbatim: content.title)) {
            PillButton(content.saved ? Text("Saved") : Text("Save"), size: .compact, busy: content.isSaving) {
                await actions.save()
            }
            .disabled(!content.canSave && !content.isSaving)
            .accessibilityHint(Text(verbatim: content.saveHint ?? ""))
            .accessibilityIdentifier("journal.save")
            // A compact pill keeps its one line (`SheetHeader`).
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .accessibilityShowsLargeContentViewer()
        }
        .padding(.horizontal, SheetHeaderSpec.sidePadding)
        .padding(.top, SheetHeaderSpec.topInset)
    }

    // MARK: notices

    @ViewBuilder private var notices: some View {
        let showsRows = content.phase == .ready || content.phase == .noHabits
        if showsRows, !content.isOnline {
            OfflinePill()
                .accessibilityIdentifier("journal.offlinePill")
        }
        if let error = content.error {
            InlineMessage(message: error, systemImage: "exclamationmark.circle", details: content.errorDetails,
                          retry: actions.save, identifier: "journal.error")
        }
        if showsRows, let reason = content.readOnlyReason {
            InlineMessage(message: reason, systemImage: "lock", identifier: "journal.readOnly", announces: false, readsAsOne: true)
        }
    }

    // MARK: the rows, or what stands in for them

    @ViewBuilder private var phaseContent: some View {
        switch content.phase {
        case .ready:
            ForEach(content.groups) { group in
                GroupedCard(Text(JournalSheetModel.title(group.category))) {
                    ForEach(group.rows) { row in
                        JournalHabitRow(row: row, editable: content.editable, actions: actions)
                    }
                }
            }
        case .noHabits:
            noHabits
        case .loading:
            loading
        case .offline:
            InlineMessage(message: String(localized: "This day's answers appear once you're online.",
                                          comment: "Journal sheet: offline, and the selected day isn't saved on this iPhone yet."),
                          systemImage: "wifi.slash", retry: actions.retry, identifier: "journal.offline")
        case .failed:
            InlineMessage(message: String(localized: "Couldn't load this day.",
                                          comment: "Journal sheet: the selected day couldn't be read and isn't saved on this iPhone."),
                          retry: actions.retry, identifier: "journal.failed")
        }
    }

    /// "Choose habits in Profile → Journal." and the pill that opens it.
    private var noHabits: some View {
        VStack(alignment: .leading, spacing: JournalLayout.noHabitsGap) {
            Text(verbatim: Self.noHabitsMessage)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("journal.noHabits")
            PillButton(Text("Choose habits", comment: "Journal sheet, no habits chosen: opens Profile → Journal."),
                       style: .secondary, action: actions.chooseHabits)
                .accessibilityHint(Text("Opens the Journal page in Profile",
                                        comment: "VoiceOver hint of the Journal sheet's Choose habits button."))
                .accessibilityIdentifier("journal.chooseHabits")
        }
    }

    /// The groups as outline cards, each as tall as its rows (three rows while the catalog isn't known either): one element,
    /// "Loading…".
    private var loading: some View {
        VStack(alignment: .leading, spacing: JournalLayout.groupSpacing) {
            if content.groups.isEmpty {
                PlaceholderRow(height: CGFloat(JournalLayout.placeholderRows) * GroupedListSpec.rowMinHeight)
            } else {
                ForEach(content.groups) { group in
                    VStack(alignment: .leading, spacing: GroupedListSpec.titleGap) {
                        GroupTitle(Text(JournalSheetModel.title(group.category)))
                        PlaceholderRow(height: CGFloat(group.rows.count) * GroupedListSpec.rowMinHeight)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading…"))
        .accessibilityIdentifier("journal.loading")
    }
}

/// A habit: its switch (`GroupedRow.toggle`, "Alcohol, switch, on"), and while it's on its sub-row in the same card, without a
/// hairline: Count as a quiet stepper row (VoiceOver "Drinks, 2", adjustable), Time as a chip. A read-only day's row doesn't
/// take taps and draws at 55 %; VoiceOver's activation changes nothing either.
private struct JournalHabitRow: View {
    let row: JournalSheetModel.Row
    let editable: Bool
    let actions: JournalSheetActions

    /// A built-in by its fixed slug; the user's own by its id (as Profile → Journal names them).
    private var key: String { row.behavior.isCustom ? row.id.uuidString.lowercased() : row.behavior.slug }

    var body: some View {
        VStack(spacing: 0) {
            GroupedRow.toggle(Text(verbatim: row.behavior.name), isOn: Binding(get: { row.on }, set: { on in
                if editable { actions.setOn(row.id, on) }
            }))
            .accessibilityIdentifier("journal.habit.\(key)")
            if row.on {
                subRow
                    .environment(\.isInGroupedCard, false)
            }
        }
        .allowsHitTesting(editable)
        .opacity(editable ? 1 : JournalLayout.readOnlyOpacity)
    }

    @ViewBuilder private var subRow: some View {
        switch row.control {
        case .toggle:
            EmptyView()
        case .stepper:
            RyftStepperRow(Text("Count", comment: "Journal sheet: the sub-row with how many of a habit (drinks), a stepper."),
                           quiet: true,
                           value: Binding(get: { row.count }, set: { count in if editable { actions.setCount(row.id, count) } }),
                           in: JournalLayout.countRange)
                .accessibilityLabel(Text(verbatim: row.behavior.name))
                .accessibilityIdentifier("journal.count.\(key)")
        case .time:
            ValueChipRow(Text("Time")) {
                ValueChip(Text(verbatim: row.behavior.name),
                          date: Binding(get: { Self.date(row.time) }, set: { date in
                              if editable { actions.setTime(row.id, Self.hhmm(date)) }
                          }),
                          displayedComponents: .hourAndMinute)
                    .accessibilityIdentifier("journal.time.\(key)")
            }
        }
    }

    static func date(_ hhmm: String) -> Date { NotificationSettingsViewModel.date(hhmm) }
    static func hhmm(_ date: Date) -> String { NotificationSettingsViewModel.string(date) }
}

/// The last 14 days as chips, newest first (yesterday): 48 × 56, radius 16, 8 apart, the weekday over the day's number. The
/// selected day is filled with ink and its words are the ground's; the others are `surface` with ink. Today isn't in it: the
/// journal is for days gone by, so nothing marks "now". VoiceOver: each chip "Monday, November 16", selected; the strip is a
/// container.
struct JournalDateStrip: View {
    let days: [String]
    let selected: String
    let select: (String) -> Void

    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .headline) private var daySize: CGFloat = JournalLayout.chipDaySize

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: JournalLayout.chipSpacing) {
                    ForEach(days, id: \.self) { day in
                        chip(day).id(day)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onAppear { proxy.scrollTo(selected) }
        }
        .accessibilityElement(children: .contain)
    }

    private func chip(_ day: String) -> some View {
        let date = DayFormat.date(from: day) ?? .now
        let isSelected = day == selected
        return Button {
            select(day)
        } label: {
            VStack(spacing: JournalLayout.chipLineGap) {
                Text(verbatim: date.formatted(.dateTime.weekday(.abbreviated).locale(locale)))
                    .font(.ryft(.caption))
                Text(verbatim: date.formatted(.dateTime.day().locale(locale)))
                    .font(.ryftNumber(size: daySize))
            }
            .foregroundStyle(isSelected ? Theme.background : Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, JournalLayout.chipInset)
            .frame(minWidth: JournalLayout.chipWidth, minHeight: JournalLayout.chipHeight)
            .background(isSelected ? Theme.textPrimary : Theme.surface,
                        in: RoundedRectangle(cornerRadius: JournalLayout.chipRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: JournalLayout.chipRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale))))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("journal.day.\(day)")
    }
}

/// "Offline. You can save once you're back online." over the Journal's groups: one line in a 1 pt outline (ink 12 %), `wifi.slash`
/// 12 (scaling with the words), `caption` in `textSecondary`. Saving needs the network (`JournalStore`), so it says that, never
/// that the answers are saved on this phone or sent later. At accessibility sizes the words wrap and the capsule becomes a
/// rounded rectangle (a capsule's ends would cut into the lines). One element for VoiceOver.
struct OfflinePill: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var glyphSize: CGFloat = JournalLayout.pillGlyphSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: JournalLayout.pillSpacing) {
            Image(systemName: "wifi.slash")
                .font(.system(size: glyphSize))
                .accessibilityHidden(true)
            Text("Offline. You can save once you're back online.",
                 comment: "Journal sheet: the iPhone is offline; saving the day's answers needs the network.")
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.ryft(.caption))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, JournalLayout.pillHorizontal)
        .padding(.vertical, JournalLayout.pillVertical)
        .overlay {
            let ink = Theme.textPrimary.opacity(JournalLayout.pillOutlineOpacity)
            if typeSize.isAccessibilitySize {
                RoundedRectangle(cornerRadius: JournalLayout.pillWrappedRadius, style: .continuous)
                    .strokeBorder(ink, lineWidth: Theme.Metrics.hairline)
            } else {
                Capsule().strokeBorder(ink, lineWidth: Theme.Metrics.hairline)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A store with the mock catalog and yesterday already cached (previews render
/// before an async load finishes).
@MainActor
func journalPreviewStore(_ state: AppState) -> JournalStore {
    let p = state.env.persistence
    p.saveDocument(MockJournal.behaviors, key: JournalStore.behaviorsKey, at: .now)
    let yesterday = DayFormat.string(from: DayFormat.shift(.now, days: -1))
    p.saveDocument(MockJournal.journal(day: yesterday), key: JournalStore.dayKey(yesterday), at: .now)
    return JournalStore(env: state.env)
}

// MARK: - previews (dark only; MockJournalStates)

#Preview("Journal card", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            JournalCardBody(summary: nil) {}
            JournalCardBody(summary: MockJournalStates.cardSummary) {}
        }
    }
}

#Preview("Journal card · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            JournalCardBody(summary: nil) {}
            JournalCardBody(summary: MockJournalStates.cardSummary) {}
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Journal sheet · answered") {
    JournalSheetBody(content: MockJournalStates.content(.answered)).toggleStyle(.ryft).previewEnvironment()
}

#Preview("Journal sheet · offline") {
    JournalSheetBody(content: MockJournalStates.content(.offline)).toggleStyle(.ryft).previewEnvironment()
}

#Preview("Journal sheet · read-only") {
    JournalSheetBody(content: MockJournalStates.content(.readOnly)).toggleStyle(.ryft).previewEnvironment()
}

#Preview("Journal sheet · no habits") {
    JournalSheetBody(content: MockJournalStates.content(.noHabits)).toggleStyle(.ryft).previewEnvironment()
}

#Preview("Journal sheet · loading") {
    JournalSheetBody(content: MockJournalStates.content(.loading)).toggleStyle(.ryft).previewEnvironment()
}

#Preview("Journal sheet · offline, not on this iPhone") {
    JournalSheetBody(content: MockJournalStates.content(.offlineUncached)).toggleStyle(.ryft).previewEnvironment()
}

#Preview("Journal sheet · save failed") {
    JournalSheetBody(content: MockJournalStates.content(.saveFailed)).toggleStyle(.ryft).previewEnvironment()
}

#Preview("Journal sheet · saving") {
    JournalSheetBody(content: MockJournalStates.content(.saving)).toggleStyle(.ryft).previewEnvironment()
}

#Preview("Journal sheet · AX3") {
    JournalSheetBody(content: MockJournalStates.content(.answered)).toggleStyle(.ryft).previewEnvironment()
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Journal sheet · live") {
    let state = AppState.preview()
    let store = journalPreviewStore(state)
    return JournalSheet(model: JournalSheetModel(store: store))
        .previewEnvironment(state)
}
