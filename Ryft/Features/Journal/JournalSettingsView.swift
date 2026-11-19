import SwiftUI

/// Journal settings' numbers (Nocturne, PR 6 C §4.8; plain values, so tests assert numbers).
enum JournalSettingsLayout {
    /// The header row → the first group (`SubpageSpec.contentGap`), and between groups (`GroupedListSpec.groupSpacing`).
    nonisolated static let headerToContent: CGFloat = 22, groupGap: CGFloat = 18
    /// The page's sides and the space under the last group (`SubpageScaffold`'s).
    nonisolated static let sidePadding: CGFloat = 20, bottomPadding: CGFloat = 32
    /// The card: radius 22; rows at least 46; the hairline inset 16 (`GroupedListSpec`).
    nonisolated static let cardRadius: CGFloat = 22, rowMinHeight: CGFloat = 46, rowInset: CGFloat = 16
    /// A habit's trash button: a 44 pt target, a 14 pt glyph in ink at 55 %; its target ends 8 before the switch's track
    /// (the glyph's centre 30 from it, as the draft), and the name keeps 40 more clear of it than the switch's own 12.
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
/// notice says nothing changed (writes need the network, `JournalStore.JournalError.offline`).
struct JournalSettingsView: View {
    let store: JournalStore
    @State private var failure: JournalSettingsFailure?
    @State private var adding = false
    /// Habits whose change or deletion is on its way: their switch is disabled meanwhile.
    @State private var pending: Set<UUID> = []
    /// The habit whose trash button asked to delete it: the confirmation is up.
    @State private var deleting: Behavior?

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
        List {
            SubpageHeader(Text("Journal")) {
                CircleButton(systemImage: "plus", accessibilityLabel: Text("Add a habit")) { adding = true }
                    .accessibilityIdentifier("journal.add")
            }
            .journalListRow(bottom: JournalSettingsLayout.headerToContent)
            if let failure {
                InlineMessage(message: failure.message, systemImage: "exclamationmark.circle", caption: failure.details)
                    .journalListRow(bottom: JournalSettingsLayout.groupGap)
            }
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
            failure = JournalSettingsFailure(error)
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

/// What Journal settings and Add a habit say when a change didn't reach RYFT: that nothing changed, in words, and the
/// status and request ID when there was a response (never the raw error text).
struct JournalSettingsFailure: Equatable {
    let message: String
    let details: String?

    init(_ error: Error) {
        if (error as? JournalStore.JournalError) == .offline {
            message = String(localized: "You're offline, so nothing changed. Try again when you're back online.",
                             comment: "Journal settings and Add a habit: a change that needs the network, offline.")
        } else {
            message = String(localized: "RYFT couldn't save that. Nothing changed; try again in a moment.",
                             comment: "Journal settings and Add a habit: a change the platform refused or didn't answer.")
        }
        details = error.diagnosticDetails
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
    private var identifier: String { "journal.habit.\(habit.slug)" }

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
                Image(systemName: "trash")
                    .font(.system(size: JournalSettingsLayout.trashGlyph, weight: .regular))
                    .foregroundStyle(Theme.textPrimary.opacity(JournalSettingsLayout.trashOpacity))
                    .frame(width: JournalSettingsLayout.trashTarget, height: JournalSettingsLayout.trashTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .padding(.trailing, RyftToggleStyle.trackSize.width + JournalSettingsLayout.trashToTrack)
            .accessibilityLabel(Text("Delete \(habit.name)", comment: "Journal settings: the trash button of one of your own habits."))
            .accessibilityIdentifier("journal.delete.\(habit.slug)")
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
    }
}

// MARK: - Add a habit

/// Add a habit (PR 6 C §4.8, F1, F23): a sheet with its own header and Close; the name (1–60 characters), the answer kind and
/// the category as select rows, and the pinned Add ("Adding…" while it goes). A failure shows above the groups and keeps
/// what was typed; offline it says nothing was added (writes need the network).
struct AddBehaviorSheet: View {
    let store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var kind: BehaviorKind = .yesNo
    @State private var category: BehaviorCategory = .custom
    @State private var failure: JournalSettingsFailure?
    @State private var saving: Bool
    @FocusState private var nameFocused: Bool

    static let maxName = 60

    /// The categories in the order the sheet offers them: the user's own first (the default), then the platform's.
    static let categories: [BehaviorCategory] = [.custom] + BehaviorCategory.allCases.filter { $0 != .custom }

    /// `name` and `saving`: previews and shots start with them.
    init(store: JournalStore, name: String = "", saving: Bool = false) {
        self.store = store
        _name = State(initialValue: name)
        _saving = State(initialValue: saving)
    }

    static func isValid(name: String) -> Bool {
        (1...maxName).contains(name.trimmingCharacters(in: .whitespaces).count)
    }

    var body: some View {
        SubpageScaffold(Text("Add a habit"), navigation: .close(), isSheet: true) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if let failure {
                    InlineMessage(message: failure.message, systemImage: "exclamationmark.circle", caption: failure.details)
                }
                Group {
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
                .disabled(saving)
            }
        }
        .pinnedBar {
            PillButton(saving ? Text("Adding…") : Text("Add"), systemImage: "plus", busy: saving) { await add() }
                .disabled(!Self.isValid(name: name) && !saving)
                .accessibilityIdentifier("addHabit.add")
        }
        .presentationDetents([.large])
    }

    private func add() async {
        guard Self.isValid(name: name), !saving else { return }
        nameFocused = false
        saving = true
        defer { saving = false }
        do {
            try await store.create(name: name, nameDe: nil, kind: kind, category: category)
            dismiss()
        } catch where error.isCancellation {
            return
        } catch {
            failure = JournalSettingsFailure(error)
        }
    }
}

// MARK: - previews (dark only)

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

#Preview("Add a habit · adding · AX3") {
    let state = AppState.preview()
    return AddBehaviorSheet(store: journalPreviewStore(state), name: "Evening walk", saving: true)
        .previewEnvironment(state)
        .dynamicTypeSize(.accessibility3)
}
