import SwiftUI

/// Journal settings' numbers (Nocturne, PR 6 C §4.8; plain values, so tests assert numbers).
enum JournalSettingsLayout {
    /// The header row → the first group (`SubpageSpec.contentGap`), and between groups (`GroupedListSpec.groupSpacing`).
    nonisolated static let headerToContent: CGFloat = 22, groupGap: CGFloat = 18
    /// The page's sides and the space under the last group (`SubpageScaffold`'s).
    nonisolated static let sidePadding: CGFloat = 20, bottomPadding: CGFloat = 32
    /// The card: radius 22; rows at least 46; the hairline inset 16 (`GroupedListSpec`).
    nonisolated static let cardRadius: CGFloat = 22, rowMinHeight: CGFloat = 46, rowInset: CGFloat = 16
    /// A habit's trash button: 44 wide and as tall as the row (at least 44), a 14 pt glyph in ink at 55 %; its target
    /// ends 8 before the switch's track (the glyph's centre 30 from it, as the draft), and the name keeps 40 more clear of
    /// it than the switch's own 12.
    nonisolated static let trashTarget: CGFloat = 44, trashGlyph: CGFloat = 14, trashOpacity = 0.55
    nonisolated static let trashToTrack: CGFloat = 8, labelClearance: CGFloat = 40
}

/// Profile → Journal in Nocturne (PR 6 C §4.8, the user's F1 and F22): which habits the Journal asks about, one group per
/// category in the platform's order, a switch per habit (`PATCH /v1/behaviors`), and the header's plus for Add a habit
/// (`POST`). The user's own habits have a trash button that asks first; swiping a row still deletes it. Built-ins can only
/// be turned off.
///
/// A `List` (swipe-to-delete needs one) drawn as the subpage grammar: the header as its first row, each group's rows on one
/// `surface` card of radius 22 with inset hairlines (`JournalCardSegment`), no system separators or backgrounds. The values
/// are the cached catalog (`JournalStore`), so the page reads the same offline; a change that can't be saved goes back and a
/// notice under the habit's group says what happened (writes need the network, `JournalStore.JournalError.offline`). The
/// page scrolls to the notice and VoiceOver announces it, wherever the habit was on the page.
struct JournalSettingsView: View {
    let store: JournalStore
    /// The last change that failed, and the group its habit is in: the notice shows under that group.
    @State private var failure: GroupFailure?
    @State private var adding = false
    /// Habits whose change or deletion is on its way: their switch is disabled meanwhile.
    @State private var pending: Set<UUID> = []
    /// The habit whose trash button asked to delete it: the confirmation is up.
    @State private var deleting: Behavior?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct GroupFailure: Equatable {
        let category: BehaviorCategory
        let failure: JournalSettingsFailure
    }

    /// The failure notice's row, for scrolling to it.
    private static let failureRow = "journal.failure"

    /// One group per category, in the order the platform sends the habits.
    private struct HabitGroup: Identifiable {
        let category: BehaviorCategory
        var habits: [Behavior]
        var id: BehaviorCategory { category }
    }

    private var groups: [HabitGroup] {
        var out: [HabitGroup] = []
        for b in store.behaviors {
            if let i = out.firstIndex(where: { $0.category == b.category }) {
                out[i].habits.append(b)
            } else {
                out.append(HabitGroup(category: b.category, habits: [b]))
            }
        }
        return out
    }

    var body: some View {
        ScrollViewReader { proxy in
            list
                .onChange(of: failure) { _, new in
                    guard new != nil else { return }
                    withAnimation(Theme.Motion.respecting(reduceMotion)) { proxy.scrollTo(Self.failureRow) }
                }
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
        .sheet(isPresented: $adding) { AddBehaviorSheet(store: store) }
        .confirmationDialog(Text(verbatim: deleting.map { Self.deleteTitle($0.name) } ?? ""),
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { habit in
            Button("Delete", role: .destructive) {
                Task { await delete(habit) }
            }
        } message: { _ in
            Text("This removes the habit from your Journal.")
        }
        .task { await store.load() }
    }

    private var list: some View {
        List {
            SubpageHeader(Text("Journal")) {
                CircleButton(systemImage: "plus", accessibilityLabel: Text("Add a habit")) { adding = true }
                    .accessibilityIdentifier("journal.add")
            }
            .journalListRow(bottom: JournalSettingsLayout.headerToContent)
            if store.behaviors.isEmpty {
                emptyOrLoading
                    .journalListRow()
            }
            let groups = groups
            ForEach(groups) { group in
                GroupTitle(Text(JournalSheetModel.title(group.category)))
                    .journalListRow(top: group.category == groups.first?.category ? 0 : JournalSettingsLayout.groupGap,
                                    bottom: GroupedListSpec.titleGap)
                ForEach(Array(group.habits.enumerated()), id: \.element.id) { index, habit in
                    row(habit)
                        .background { JournalCardSegment(first: index == 0, last: index == group.habits.count - 1) }
                        .journalListRow()
                        .swipeActions(edge: .trailing) {
                            if habit.isCustom {
                                Button("Delete", role: .destructive) {
                                    Task { await delete(habit) }
                                }
                            }
                        }
                }
                // Under the card of the habit that didn't change: where the user looked.
                if let failure, failure.category == group.category {
                    InlineMessage(message: failure.failure.message, systemImage: "exclamationmark.circle",
                                  caption: failure.failure.details, announces: false)
                        .textSelection(.enabled)
                        .journalListRow(top: GroupedListSpec.footerGap)
                        .id(Self.failureRow)
                }
            }
            if store.behaviors.contains(where: \.isCustom) {
                GroupFooter(Text("Your own habits can be deleted. The built-in ones can only be turned off."))
                    .journalListRow(top: GroupedListSpec.footerGap)
            }
            Color.clear
                .frame(height: JournalSettingsLayout.bottomPadding)
                .accessibilityHidden(true)
                .journalListRow()
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
    }

    /// The catalog before it has loaded (one outline, "Loading…"), or a journal without habits.
    @ViewBuilder private var emptyOrLoading: some View {
        if store.availability == .unknown {
            PlaceholderRow(height: JournalSettingsLayout.rowMinHeight) {
                Text("Loading…")
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
            }
        } else {
            Text("No habits yet.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ habit: Behavior) -> some View {
        HabitRow(habit: habit,
                 isOn: Binding(get: { habit.enabled }, set: { on in Task { await setEnabled(habit, on) } }),
                 busy: pending.contains(habit.id),
                 delete: habit.isCustom ? { deleting = habit } : nil)
    }

    /// "Delete “Evening walk”?": the confirmation's title.
    static func deleteTitle(_ name: String) -> String {
        String(localized: "Delete “\(name)”?", comment: "Journal settings: the title of the dialog that deletes one of your own habits.")
    }

    // MARK: writes

    private func setEnabled(_ habit: Behavior, _ on: Bool) async {
        guard !pending.contains(habit.id) else { return }
        await run(habit) { try await store.setEnabled(habit.id, on) }
    }

    private func delete(_ habit: Behavior) async {
        guard !pending.contains(habit.id) else { return }
        await run(habit) { try await store.delete(habit.id) }
    }

    private func run(_ habit: Behavior, _ work: () async throws -> Void) async {
        pending.insert(habit.id)
        defer { pending.remove(habit.id) }
        do {
            try await work()
            failure = nil
        } catch where error.isCancellation {
            return
        } catch {
            let failed = JournalSettingsFailure(error)
            failure = GroupFailure(category: habit.category, failure: failed)
            // Heard wherever VoiceOver is: the habit may be far from where the notice draws.
            AccessibilityNotification.Announcement(failed.message).post()
        }
    }

    static func kindTitle(_ kind: BehaviorKind) -> String {
        switch kind {
        case .yesNo: return String(localized: "Yes or no")
        case .count: return String(localized: "How many")
        case .time: return String(localized: "What time")
        }
    }
}

/// What Journal settings and Add a habit say when a change didn't go through: the settings pages' words, judged by what
/// left the phone (`SettingsWriteFailure`, shared with Notifications and the body-setting editors; PR 6 C review S4), with
/// the status and request ID as the caption when RYFT answered (never the raw error text):
/// - offline (`JournalError.offline`, or nothing sent): nothing changed;
/// - no answer (a timeout, a dropped connection, the network gone while it was out, a `2xx` this build can't read): it may
///   have saved, and the list is asked again (`JournalStore.rereading`);
/// - a `5xx`: RYFT had a problem; the list is asked again too;
/// - a `429`: RYFT is busy, nothing changed;
/// - refused (`403`, a `409` twice, any other `4xx`): nothing changed;
/// - a `422`: RYFT refused the values; trying the same again won't help, so it doesn't say to. (The platform's own sentence
///   is developer English and may say "behavior", F1, so the calm one shows and the request ID goes along.)
struct JournalSettingsFailure: Equatable {
    let message: String
    let details: String?
    let kind: SettingsWriteFailure

    init(_ error: Error) {
        kind = Self.kind(of: error)
        if (error as? APIError)?.isFieldError == true {
            message = String(localized: "RYFT didn't accept that, so nothing changed.",
                             comment: "Journal settings and Add a habit: RYFT refused the values (422); the same again won't help.")
        } else {
            message = kind.saveMessage
        }
        details = error.diagnosticDetails
    }

    /// A Journal write's failure as the settings pages judge it: the store's own two first (offline: nothing was sent; a
    /// taken id twice: RYFT said no), then the shared classifier.
    static func kind(of error: Error) -> SettingsWriteFailure {
        switch error as? JournalStore.JournalError {
        case .offline?: return .offline
        case .idTaken?: return .refused
        case nil: return SettingsWriteFailure(error)
        }
    }
}

// MARK: - rows

private extension View {
    /// A row of the journal's list as the subpage grammar draws it: 20 from the sides, no system separator or background.
    func journalListRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: JournalSettingsLayout.sidePadding, bottom: bottom,
                                 trailing: JournalSettingsLayout.sidePadding))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// One row's part of its group's card: `surface`, the card's 22 pt corners on the first and the last row, and the 1 pt
/// `separator` hairline inset 16 on top of every row but the first (`GroupedCard`'s look, row by row, so a list row can
/// swipe).
struct JournalCardSegment: View {
    let first: Bool
    let last: Bool

    var body: some View {
        let radius = JournalSettingsLayout.cardRadius
        UnevenRoundedRectangle(topLeadingRadius: first ? radius : 0, bottomLeadingRadius: last ? radius : 0,
                               bottomTrailingRadius: last ? radius : 0, topTrailingRadius: first ? radius : 0,
                               style: .continuous)
            .fill(Theme.surface)
            .overlay(alignment: .top) {
                if !first {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: Theme.Metrics.hairline)
                        .padding(.horizontal, JournalSettingsLayout.rowInset)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A habit: its name and its answer kind ("How many") and the switch, the whole row the target (`GroupedRow.toggle`'s look).
/// One of the user's own also has the trash button just before the switch ("Delete Evening walk"), on top of the row so it
/// takes its own taps; the name wraps before it. VoiceOver: the switch is "Evening walk, Yes or no", on or off, then the
/// trash button.
private struct HabitRow: View {
    let habit: Behavior
    let isOn: Binding<Bool>
    let busy: Bool
    /// Asks to delete it: the user's own habits only.
    let delete: (() -> Void)?

    private var title: Text { Text(verbatim: habit.name) }
    private var detail: Text { Text(JournalSettingsView.kindTitle(habit.kind)) }
    /// A built-in by its fixed slug; the user's own by its id (a slug comes from the name, and two names can share one).
    private var key: String { habit.isCustom ? habit.id.uuidString.lowercased() : habit.slug }
    private var identifier: String { "journal.habit.\(key)" }

    var body: some View {
        if let delete {
            custom(delete)
        } else {
            GroupedRow.toggle(title, detail: detail, identifier: identifier, isOn: isOn)
                .disabled(busy)
        }
    }

    /// `GroupedRow.toggle` drawn here, its text kept clear of the trash button over it.
    private func custom(_ delete: @escaping () -> Void) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
                title
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                detail
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, GroupedListSpec.textPadding)
            .padding(.trailing, JournalSettingsLayout.labelClearance)
        }
        .accessibilityIdentifier(identifier)
        .disabled(busy)
        .overlay(alignment: .trailing) {
            Button(action: delete) {
                // As tall as the row: a tap above or below the glyph is the trash's, never the switch's.
                Image(systemName: "trash")
                    .font(.system(size: JournalSettingsLayout.trashGlyph, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(JournalSettingsLayout.trashOpacity))
                    .frame(width: JournalSettingsLayout.trashTarget)
                    .frame(minHeight: JournalSettingsLayout.trashTarget, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .padding(.trailing, RyftToggleStyle.trackSize.width + JournalSettingsLayout.trashToTrack)
            .accessibilityLabel(Text("Delete \(habit.name)", comment: "Journal settings: the trash button of one of your own habits."))
            .accessibilityIdentifier("journal.delete.\(key)")
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
    }
}

// MARK: - Add a habit

/// Add a habit (PR 6 C §4.8, F1, F23): a sheet with its own header and Close; the name (1–60 characters), the answer kind and
/// the category as select rows, and the pinned Add (its spinner while it goes). A failure shows above the groups and keeps
/// what was typed; offline it says it wasn't saved (writes need the network).
///
/// - One habit per sheet: every Add sends the sheet's own ids (`POST` with the same id updates it, `200`), so a retry after
///   no answer can't add it twice.
/// - With 50 of the user's own the platform takes no more (`422`): the bar says so and Add stays disabled.
/// - While it saves, the sheet can't be closed (Close disabled, no swipe down): the answer has somewhere to go.
struct AddBehaviorSheet: View {
    let store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: BehaviorKind = .yesNo
    @State private var category: BehaviorCategory = .custom
    @State private var failure: JournalSettingsFailure?
    @State private var saving: Bool
    /// The habit's id, and the one to try once if the first is taken (`409`): the same on every Add from this sheet.
    @State private var habitID: UUID
    @State private var retryID = UUID()
    @FocusState private var nameFocused: Bool

    /// The platform's limits (API.md → `POST /v1/behaviors`): 1–60 characters, counted as it counts them (Unicode scalars,
    /// Go's runes), and 50 of the user's own.
    static let maxName = 60, maxOwn = 50

    /// The categories in the order the sheet offers them: the user's own first (the default), then the platform's.
    static let categories: [BehaviorCategory] = [.custom] + BehaviorCategory.allCases.filter { $0 != .custom }

    /// `name` and `saving`: previews and shots start with them; `id`: tests know the habit's.
    init(store: JournalStore, name: String = "", saving: Bool = false, id: UUID = UUID()) {
        self.store = store
        _name = State(initialValue: name)
        _saving = State(initialValue: saving)
        _habitID = State(initialValue: id)
    }

    /// 1–60 once the spaces at the ends are gone, in Unicode scalars as the platform counts them: an "é" typed as "e" and a
    /// combining accent is two, a flag is two.
    static func isValid(name: String) -> Bool {
        (1...maxName).contains(name.trimmingCharacters(in: .whitespaces).unicodeScalars.count)
    }

    /// The user has the most habits of their own the platform keeps, not counting `id` (this sheet's, if a retry saved it).
    static func isFull(_ behaviors: [Behavior], adding id: UUID) -> Bool {
        behaviors.filter { $0.isCustom && $0.id != id }.count >= maxOwn
    }

    private var isFull: Bool { Self.isFull(store.behaviors, adding: habitID) }

    var body: some View {
        SubpageScaffold(Text("Add a habit"), navigation: .close(), isSheet: true) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if let failure {
                    InlineMessage(message: failure.message, systemImage: "exclamationmark.circle", caption: failure.details)
                        .textSelection(.enabled)
                }
                GroupedCard(footer: Text("Up to \(Self.maxName) characters.")) {
                    FormField(Text("Name"), isFocused: nameFocused) {
                        TextField(text: $name) { Text("Name") }
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .accessibilityIdentifier("addHabit.name")
                    }
                }
                GroupedCard(Text("Answer")) {
                    ForEach(BehaviorKind.allCases) { option in
                        GroupedRow.select(Text(JournalSettingsView.kindTitle(option)), isSelected: kind == option,
                                          identifier: "addHabit.answer.\(option.rawValue)") { kind = option }
                    }
                }
                GroupedCard(Text("Category")) {
                    ForEach(Self.categories) { option in
                        GroupedRow.select(Text(JournalSheetModel.title(option)), isSelected: category == option,
                                          identifier: "addHabit.category.\(option.rawValue)") { category = option }
                    }
                }
            }
        }
        // The fields and Close: the sheet stays as it is until the answer is in.
        .disabled(saving)
        .pinnedBar(caption: isFull ? Self.fullCaption : nil) {
            // Busy keeps the title and shows the spinner; VoiceOver says "In progress" (as the editors' Save does).
            PillButton(Text("Add"), systemImage: "plus", busy: saving) { await add() }
                .disabled((!Self.isValid(name: name) || isFull) && !saving)
                .accessibilityIdentifier("addHabit.add")
        }
        .interactiveDismissDisabled(saving)
        .presentationDetents([.large])
    }

    static var fullCaption: Text {
        Text("You have \(maxOwn) habits of your own, the most RYFT keeps. Delete one to add another.",
             comment: "Add a habit: the bar's caption while Add is disabled because the user has 50 habits of their own.")
    }

    private func add() async {
        guard Self.isValid(name: name), !isFull, !saving else { return }
        nameFocused = false
        saving = true
        defer { saving = false }
        do {
            try await store.create(name: name, nameDe: nil, kind: kind, category: category, id: habitID, retryID: retryID)
            dismiss()
        } catch where error.isCancellation {
            return
        } catch {
            failure = JournalSettingsFailure(error)
        }
    }
}

// MARK: - previews (dark only)

// Previews only: `journalPreviewStore` is debug-only, and a Release build has no previews.
#if DEBUG

#Preview("Journal settings") {
    let state = AppState.preview()
    return NavigationStack { JournalSettingsView(store: journalPreviewStore(state)) }
        .previewEnvironment(state)
        .toggleStyle(.ryft)
}

#Preview("Journal settings · AX3") {
    let state = AppState.preview()
    return NavigationStack { JournalSettingsView(store: journalPreviewStore(state)) }
        .previewEnvironment(state)
        .toggleStyle(.ryft)
        .dynamicTypeSize(.accessibility3)
}

#Preview("Add a habit") {
    let state = AppState.preview()
    return Color.clear
        .sheet(isPresented: .constant(true)) { AddBehaviorSheet(store: journalPreviewStore(state), name: "Evening walk") }
        .previewEnvironment(state)
}

#Preview("Add a habit · 50 of your own") {
    let state = AppState.preview()
    let own = MockJournal.behaviors.filter(\.isCustom).count
    let more = (own..<AddBehaviorSheet.maxOwn).map { n in
        Behavior(id: UUID(), slug: "habit-\(n)", name: "Habit \(n)", nameEn: "Habit \(n)", nameDe: "Habit \(n)",
                 category: .custom, kind: .yesNo, defaultOn: true, enabled: true, isCustom: true, sort: n)
    }
    return AddBehaviorSheet(store: journalPreviewStore(state, behaviors: MockJournal.behaviors + more), name: "Evening walk")
        .previewEnvironment(state)
}

#Preview("Add a habit · adding · AX3") {
    let state = AppState.preview()
    return AddBehaviorSheet(store: journalPreviewStore(state), name: "Evening walk", saving: true)
        .previewEnvironment(state)
        .dynamicTypeSize(.accessibility3)
}
#endif
