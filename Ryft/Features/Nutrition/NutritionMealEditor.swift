import SwiftUI

enum NutritionMealType: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack, other

    var id: Self { self }
    var title: String {
        switch self {
        case .breakfast: String(localized: "Breakfast")
        case .lunch: String(localized: "Lunch")
        case .dinner: String(localized: "Dinner")
        case .snack: String(localized: "Snack")
        case .other: String(localized: "Other")
        }
    }
}

struct NutritionMealEditor: View {
    nonisolated static let maximumItems = 50

    let model: NutritionDiaryModel
    let api: APIClient
    let finished: () -> Void

    @State private var suggestion: NutritionFoodMatch?
    @State private var saved: NutritionMeal?
    @State private var consumedAt: Date
    @State private var type: NutritionMealType
    @State private var name: String
    @State private var notes: String
    @State private var items: [NutritionDraftItem]
    @State private var isAdding: Bool
    @State private var hasReviewed: Bool
    @State private var busy = false
    @State private var failure: String?
    @State private var conflict = false
    @State private var deleting = false
    @State private var request: NutritionMealWrite?

    init(model: NutritionDiaryModel, api: APIClient, meal: NutritionMeal?, suggested: NutritionFoodMatch? = nil,
         finished: @escaping () -> Void) {
        self.model = model
        self.api = api
        _suggestion = State(initialValue: suggested)
        self.finished = finished
        _saved = State(initialValue: meal)
        _consumedAt = State(initialValue: meal?.consumedAt ?? model.date)
        _type = State(initialValue: meal.flatMap { NutritionMealType(rawValue: $0.mealType) } ?? .other)
        _name = State(initialValue: meal?.name ?? "")
        _notes = State(initialValue: meal?.notes ?? "")
        _items = State(initialValue: meal?.items.map(NutritionDraftItem.init) ?? [])
        _isAdding = State(initialValue: meal == nil)
        _hasReviewed = State(initialValue: meal != nil)
    }

    var body: some View {
        if isAdding {
            NutritionFoodPicker(model: model, api: api, initialFood: $suggestion, items: $items,
                                backToReview: hasReviewed ? { isAdding = false } : nil) {
                hasReviewed = true
                isAdding = false
            }
        } else {
            reviewPage
        }
    }

    private var reviewPage: some View {
        SubpageScaffold(saved == nil ? Text("Log meal") : Text("Edit meal")) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                foods
                if let failure { InlineMessage(message: failure, systemImage: "exclamationmark.circle") }
                if conflict {
                    PillButton(Text("Load latest meal"), style: .secondary, busy: busy) { await reload() }
                }
                if !items.isEmpty {
                    PillButton(request == nil ? Text("Save meal") : Text("Retry save"), busy: busy) { await save() }
                        .disabled(conflict || (saved != nil && !model.online))
                        .accessibilityIdentifier("nutrition.meal.save")
                }
                DisclosureGroup {
                    metadata
                } label: {
                    Text("Meal details").font(.ryft(.callout))
                }
                if saved != nil {
                    PillButton(Text("Delete meal"), style: .destructive) { deleting = true }
                        .disabled(busy || !model.online)
                }
            }
        }
        .confirmationDialog("Delete this meal?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Delete meal", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var metadata: some View {
        GroupedCard {
            NutritionInputRow(title: Text("Name"), value: $name)
            DatePicker("Eaten at", selection: $consumedAt)
                .environment(\.timeZone, NutritionDay.calendar(saved?.timezone ?? model.timezone).timeZone)
                .nutritionField()
            Picker("Meal type", selection: $type) {
                ForEach(NutritionMealType.allCases) { entry in Text(verbatim: entry.title).tag(entry) }
            }
            .nutritionField()
            NutritionInputRow(title: Text("Notes"), value: $notes)
        }
        .disabled(busy || request != nil)
    }

    private var foods: some View {
        GroupedCard(Text("Foods")) {
            ForEach($items) { $item in
                HStack {
                    if item.selection.foodId != nil {
                        NavigationLink {
                            NutritionDraftQuantityView(item: $item)
                        } label: {
                            GroupedRowLabel(Text(verbatim: item.name), detail: itemQuantity(item), accessory: .chevron)
                        }
                        .buttonStyle(.plain)
                    } else {
                        GroupedRowLabel(Text(verbatim: item.name), detail: itemQuantity(item))
                    }
                    Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: {
                        Image(systemName: "minus.circle")
                            .frame(minWidth: 44, minHeight: 44)
                            .foregroundStyle(Theme.alert)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove \(item.name)"))
                    .padding(.trailing, GroupedListSpec.rowInset)
                }
                .groupedRowHairline()
            }
            GroupedRow.action(Text("Add food"), systemImage: "plus", identifier: "nutrition.addFood") { isAdding = true }
                .disabled(items.count >= Self.maximumItems || !model.online)
        }
        .disabled(busy || request != nil)
    }

    private func itemQuantity(_ item: NutritionDraftItem) -> Text {
        NutritionDisplay.amount(item.selection.quantity ?? 0, unit: item.selection.unit ?? "")
    }

    private func save() async {
        guard !busy else { return }
        busy = true
        failure = nil
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            if let saved {
                let patch = NutritionMealPatch(revision: saved.revision, consumedAt: consumedAt, mealType: type.rawValue,
                                               name: name, notes: notes, items: items.map(\.request))
                _ = try await api.updateNutritionMeal(saved.id, patch)
            } else {
                let draft = request ?? NutritionMealWrite(
                    clientRequestId: UUID(), consumedAt: consumedAt, timezone: model.timezone, mealType: type.rawValue,
                    inputMethod: items.first?.inputMethod ?? "manual_entry", name: name, notes: notes, items: items.map(\.request)
                )
                do {
                    _ = try await model.create(draft)
                } catch {
                    if model.pending == draft {
                        let code = (error as? APIError)?.status
                        if let code, (400..<500).contains(code), code != 401, code != 403, code != 409, code != 429 {
                            model.discardRejected(draft)
                        } else {
                            request = draft
                        }
                    }
                    throw error
                }
            }
            try model.needsCurrentAccount()
            finished()
        } catch {
            if (error as? APIError)?.status == 409, saved != nil {
                conflict = true
                failure = String(localized: "This meal changed elsewhere. Load the latest version to review your edits.")
            } else if !error.isCancellation {
                failure = error.localizedDescription
            }
        }
    }

    private func reload() async {
        guard let current = saved, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let latest = try await api.nutritionMeal(current.id)
            try model.needsCurrentAccount()
            saved = latest
            consumedAt = latest.consumedAt
            type = NutritionMealType(rawValue: latest.mealType) ?? .other
            name = latest.name
            notes = latest.notes
            items = latest.items.map(NutritionDraftItem.init)
            conflict = false
            failure = nil
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func delete() async {
        guard let saved, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            try await api.deleteNutritionMeal(saved.id)
            try model.needsCurrentAccount()
            finished()
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }
}

private struct NutritionDraftQuantityView: View {
    @Binding var item: NutritionDraftItem
    @Environment(\.dismiss) private var dismiss
    @State private var quantity = ""
    @State private var failure: String?

    var body: some View {
        SubpageScaffold(Text(verbatim: item.name)) {
            VStack(spacing: GroupedListSpec.groupSpacing) {
                GroupedCard {
                    NutritionInputRow(title: Text("Quantity"), value: $quantity, numeric: true)
                    GroupedRow.value(Text("Unit"), value: Text(verbatim: item.selection.unit ?? ""))
                }
                if let failure { InlineMessage(message: failure, systemImage: "exclamationmark.circle") }
                PillButton(Text("Apply quantity")) {
                    do {
                        guard let value = try NutritionNumbers.parse(quantity, in: 0.000_001...100_000) else {
                            throw NutritionInputError.invalidNumber
                        }
                        if value != item.selection.quantity {
                            item.selection.itemId = nil
                            item.selection.quantity = value
                        }
                        dismiss()
                    } catch {
                        failure = error.localizedDescription
                    }
                }
            }
        }
        .onAppear { quantity = item.selection.quantity?.formatted(.number.grouping(.never)) ?? "" }
    }
}

struct NutritionInputRow: View {
    let title: Text
    @Binding var value: String
    var numeric = false
    var time = false

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.detailGap) {
            title.font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
            TextField("", text: $value)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .keyboardType(time ? .numbersAndPunctuation : numeric ? .decimalPad : .default)
                .accessibilityLabel(title)
        }
        .nutritionField()
    }
}

extension View {
    func nutritionField() -> some View {
        padding(.horizontal, GroupedListSpec.rowInset)
            .padding(.vertical, GroupedListSpec.detailGap)
            .frame(minHeight: GroupedListSpec.rowMinHeight)
            .groupedRowHairline()
    }
}
