import SwiftUI

/// Search the library with muscle and kind filters, or create a custom exercise.
/// Works offline from the cached library.
struct AddExerciseSheet: View {
    var title: LocalizedStringKey = "Add exercise"
    let onPick: (Exercise) -> Void

    @EnvironmentObject private var library: TrainLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var muscle: Muscle?
    @State private var kind: ExerciseKind?
    @State private var showsCustom = false

    private var muscles: [Muscle] {
        Array(Set(library.exercises.flatMap(\.primaryMuscles))).sorted { $0.title < $1.title }
    }

    private var kinds: [ExerciseKind] {
        ExerciseKind.allCases.filter { k in library.exercises.contains { $0.kind == k } }
    }

    private var results: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return library.exercises.filter { e in
            (q.isEmpty || e.name.lowercased().contains(q) || e.slug.contains(q))
                && (muscle.map { e.primaryMuscles.contains($0) || e.secondaryMuscles.contains($0) } ?? true)
                && (kind.map { e.kind == $0 } ?? true)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    filters
                    if results.isEmpty {
                        InlineMessage(message: library.exercises.isEmpty
                                      ? String(localized: "The exercise library hasn't loaded yet. Create a custom exercise to log it now.")
                                      : String(localized: "No exercise matches. Create it as a custom exercise."),
                                      systemImage: "magnifyingglass")
                    }
                    LazyVStack(spacing: 8) {
                        ForEach(results) { e in
                            Button {
                                onPick(e)
                                dismiss()
                            } label: {
                                ExerciseRow(exercise: e)
                            }
                            .buttonStyle(PressableButtonStyle())
                        }
                    }
                    Button {
                        showsCustom = true
                    } label: {
                        Label("Custom exercise", systemImage: "plus.circle")
                    }
                    .buttonStyle(TealButtonStyle(prominent: false))
                    .padding(.top, 4)
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text("Search exercises"))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showsCustom) {
                CustomExerciseForm(name: query) { e in
                    onPick(e)
                    dismiss()
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    FilterChip(title: String(localized: "All muscles"), selected: muscle == nil) { muscle = nil }
                    ForEach(muscles) { m in
                        FilterChip(title: m.title, selected: muscle == m) { muscle = muscle == m ? nil : m }
                    }
                }
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    FilterChip(title: String(localized: "All kinds"), selected: kind == nil) { kind = nil }
                    ForEach(kinds) { k in
                        FilterChip(title: k.title, selected: kind == k) { kind = kind == k ? nil : k }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

struct ExerciseRow: View {
    let exercise: Exercise

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: Self.icon(for: exercise.kind))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 40, height: 40)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(exercise.name)
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textPrimary)
                    if exercise.isCustom {
                        Text("Custom")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.accentSecondary)
                    }
                }
                Text(([exercise.kind.title] + exercise.primaryMuscles.map(\.title)).joined(separator: " · "))
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(12)
        .frame(minHeight: 56)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    static func icon(for kind: ExerciseKind) -> String {
        switch kind {
        case .barbell, .dumbbell, .kettlebell: return "dumbbell.fill"
        case .bodyweight: return "figure.strengthtraining.functional"
        case .machine, .cable: return "figure.strengthtraining.traditional"
        case .cardio: return "figure.rower"
        }
    }
}

struct FilterChip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.ryft(.callout))
                .foregroundStyle(selected ? Theme.graphite : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(selected ? Theme.accent : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A user's own exercise; saved locally first, so it can be logged offline.
struct CustomExerciseForm: View {
    @State var name: String
    let onSave: (Exercise) -> Void

    @EnvironmentObject private var library: TrainLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ExerciseKind = .dumbbell
    @State private var muscle: Muscle = .chest
    @State private var loadType: LoadType = .weight
    @State private var unilateral = false
    @State private var saving = false

    private static let muscles = Muscle.allCases.sorted { $0.title < $1.title }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .font(.ryft(.body))
                        .textInputAutocapitalization(.words)
                }
                Section("Kind") {
                    Picker("Kind", selection: $kind) {
                        ForEach(ExerciseKind.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Main muscle", selection: $muscle) {
                        ForEach(Self.muscles) { Text($0.title).tag($0) }
                    }
                    Picker("Logged as", selection: $loadType) {
                        ForEach([LoadType.weight, .bodyweight, .time, .distance], id: \.self) { Text($0.title).tag($0) }
                    }
                    Toggle("One side at a time", isOn: $unilateral)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Custom exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(trimmed.isEmpty || saving)
                }
            }
        }
    }

    private func save() async {
        saving = true
        let slug = trimmed.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        let e = Exercise(slug: slug, name: trimmed, kind: kind, primaryMuscles: [muscle],
                         equipment: [kind.rawValue], loadType: loadType,
                         bodyweightFactor: loadType == .bodyweight ? 1 : 0, isUnilateral: unilateral, isCustom: true)
        let saved = await library.createExercise(e) ?? e
        saving = false
        onSave(saved)
        dismiss()
    }
}

#Preview("Add exercise · dark") {
    AddExerciseSheet { _ in }
        .environmentObject(TrainPreview.library)
        .preferredColorScheme(.dark)
}

#Preview("Add exercise · light") {
    AddExerciseSheet { _ in }
        .environmentObject(TrainPreview.library)
        .preferredColorScheme(.light)
}

#Preview("Custom exercise") {
    CustomExerciseForm(name: "Landmine press") { _ in }
        .environmentObject(TrainPreview.library)
        .preferredColorScheme(.dark)
}
