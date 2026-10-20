import SwiftUI

/// Today → Journal: "How was yesterday?" until yesterday is answered, then a
/// one-line summary with Edit. Hidden while the journal isn't live (M5).
struct JournalCard: View {
    let store: JournalStore
    let open: () -> Void

    var body: some View {
        let day = store.days[store.yesterday]
        Button(action: open) {
            Card {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        if let day, let summary = store.summary(of: day) {
                            Text("Yesterday").ryftLabelStyle()
                            Text(summary)
                                .font(.ryft(.callout))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("How was yesterday?")
                                .font(.ryft(.headline))
                                .foregroundStyle(Theme.textPrimary)
                            Text("A few taps, and RYFT shows how your habits change the morning after.")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(day?.answered == true ? "Edit" : "Answer")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityHint(Text("Opens the journal"))
    }
}

/// The journal sheet: yesterday by default, the strip steps back 14 days.
struct JournalSheet: View {
    @State var model: JournalSheetModel
    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectivityMonitor.self) private var connectivity

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                    JournalDateStrip(days: model.stripDays, selected: model.day) { day in
                        Task { await model.select(day) }
                    }
                    if !connectivity.isOnline { OfflinePill() }
                    if let reason = model.readOnlyReason {
                        InlineMessage(message: reason, systemImage: "lock")
                    }
                    ForEach(model.groups) { group in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(JournalSheetModel.title(group.category)).ryftLabelStyle()
                            Card {
                                VStack(spacing: 14) {
                                    ForEach(group.rows) { row in
                                        JournalRowView(row: row, model: model)
                                        if row.id != group.rows.last?.id { Divider().overlay(Theme.separator) }
                                    }
                                }
                            }
                        }
                    }
                    if model.groups.isEmpty {
                        InlineMessage(message: String(localized: "Choose behaviors in Profile → Journal."),
                                      systemImage: "list.bullet")
                    }
                    if let error = model.error {
                        InlineMessage(message: error, systemImage: "exclamationmark.circle")
                    }
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.saved ? "Saved" : "Save") {
                        Task {
                            await model.save()
                            if model.saved { dismiss() }
                        }
                    }
                    .disabled(!model.editable || model.isSaving || model.groups.isEmpty)
                }
            }
            .task { await model.load() }
        }
    }
}

private struct JournalRowView: View {
    let row: JournalSheetModel.Row
    let model: JournalSheetModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { row.on }, set: { model.set(row.id, on: $0) })) {
                Text(row.behavior.name)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.accent)
            if row.on {
                switch row.control {
                case .toggle:
                    EmptyView()
                case .stepper:
                    Stepper(value: Binding(get: { row.count }, set: { model.set(row.id, count: $0) }), in: 1...50) {
                        Text("\(row.count)")
                            .font(.ryft(.callout).monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                case .time:
                    DatePicker("Time", selection: Binding(get: { Self.date(row.time) },
                                                          set: { model.set(row.id, time: Self.hhmm($0)) }),
                               displayedComponents: .hourAndMinute)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        // Read-only days: not `.disabled`, which drew every switch as off.
        .allowsHitTesting(model.editable)
        .opacity(model.editable ? 1 : 0.55)
    }

    static func date(_ hhmm: String) -> Date { NotificationSettingsViewModel.date(hhmm) }
    static func hhmm(_ date: Date) -> String { NotificationSettingsViewModel.string(date) }
}

/// The last 14 days as chips, newest first.
struct JournalDateStrip: View {
    let days: [String]
    let selected: String
    let select: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    let date = DayFormat.date(from: day) ?? .now
                    Button { select(day) } label: {
                        VStack(spacing: 2) {
                            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.ryft(.caption))
                            Text(date.formatted(.dateTime.day()))
                                .font(.ryft(.headline).monospacedDigit())
                        }
                        .frame(width: 48, height: 52)
                        .foregroundStyle(day == selected ? Theme.onAccent : Theme.textPrimary)
                        .background(day == selected ? Theme.accent : Theme.surface,
                                    in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(date.formatted(date: .complete, time: .omitted)))
                    .accessibilityAddTraits(day == selected ? .isSelected : [])
                }
            }
        }
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

#Preview("Journal card · dark", traits: .sizeThatFitsLayout) {
    let state = AppState.preview()
    let store = journalPreviewStore(state)
    return SchemePair {
        VStack(spacing: 12) {
            JournalCard(store: store) {}
        }
    }
    .task {
        await store.load()
        await store.loadDay(store.yesterday)
    }
}

#Preview("Journal sheet · dark") {
    let state = AppState.preview()
    let store = journalPreviewStore(state)
    return JournalSheet(model: JournalSheetModel(store: store))
        .task { await store.load() }
        .previewEnvironment(state)
}

#Preview("Journal sheet · light") {
    let state = AppState.preview()
    let store = journalPreviewStore(state)
    return JournalSheet(model: JournalSheetModel(store: store))
        .task { await store.load() }
        .previewEnvironment(state, scheme: .light)
}
