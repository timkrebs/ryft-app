import SwiftUI

/// Profile → Journal: the catalog by category, a toggle per behavior
/// (`PATCH /v1/behaviors`), your own behaviors (`POST`), swipe to delete those
/// (built-ins can't be deleted, so they don't offer it).
struct JournalSettingsView: View {
    let store: JournalStore
    @State private var error: String?
    @State private var adding = false

    private var groups: [(BehaviorCategory, [Behavior])] {
        var out: [(BehaviorCategory, [Behavior])] = []
        for b in store.behaviors {
            if let i = out.firstIndex(where: { $0.0 == b.category }) { out[i].1.append(b) } else { out.append((b.category, [b])) }
        }
        return out
    }

    var body: some View {
        List {
            if let error {
                Section { Text(error).font(.ryft(.callout)).foregroundStyle(Theme.alert) }
                    .listRowBackground(Theme.surface)
            }
            ForEach(groups, id: \.0) { category, behaviors in
                Section {
                    ForEach(behaviors) { b in
                        Toggle(isOn: Binding(get: { b.enabled }, set: { on in
                            Task { await run { try await store.setEnabled(b.id, on) } }
                        })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.name).font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
                                Text(Self.kindTitle(b.kind)).font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .tint(Theme.accent)
                        .swipeActions(edge: .trailing) {
                            if b.isCustom {
                                Button("Delete", role: .destructive) {
                                    Task { await run { try await store.delete(b.id) } }
                                }
                            }
                        }
                    }
                } header: {
                    Text(JournalSheetModel.title(category)).ryftLabelStyle()
                }
                .listRowBackground(Theme.surface)
            }
            Section {
                Button {
                    adding = true
                } label: {
                    Label("Add a behavior", systemImage: "plus")
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.accent)
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $adding) { AddBehaviorSheet(store: store) }
        .task { await store.load() }
    }

    private func run(_ work: () async throws -> Void) async {
        do {
            try await work()
            error = nil
        } catch {
            self.error = error.localizedDescription
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

/// A custom behavior: name (1–60), German name (optional), kind, category.
struct AddBehaviorSheet: View {
    let store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var nameDe = ""
    @State private var kind: BehaviorKind = .yesNo
    @State private var category: BehaviorCategory = .custom
    @State private var error: String?
    @State private var saving = false

    static let maxName = 60

    static func isValid(name: String) -> Bool {
        (1...maxName).contains(name.trimmingCharacters(in: .whitespaces).count)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("German name (optional)", text: $nameDe)
                } footer: {
                    Text("Up to \(Self.maxName) characters.")
                }
                Section {
                    Picker("Answer", selection: $kind) {
                        ForEach(BehaviorKind.allCases) { Text(JournalSettingsView.kindTitle($0)).tag($0) }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(BehaviorCategory.allCases) { Text(JournalSheetModel.title($0)).tag($0) }
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.alert) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .font(.ryft(.body))
            .navigationTitle("Add a behavior")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            saving = true
                            defer { saving = false }
                            do {
                                try await store.create(name: name, nameDe: nameDe, kind: kind, category: category)
                                dismiss()
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                    .disabled(!Self.isValid(name: name) || saving)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Journal settings · dark") {
    let state = AppState.preview()
    return NavigationStack { JournalSettingsView(store: journalPreviewStore(state)) }
        .previewEnvironment(state)
}

#Preview("Journal settings · light") {
    let state = AppState.preview()
    return NavigationStack { JournalSettingsView(store: journalPreviewStore(state)) }
        .previewEnvironment(state, scheme: .light)
}
