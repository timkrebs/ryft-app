import AVFoundation
import SwiftUI
import VisionKit
import Vision

struct NutritionFoodPicker: View {
    private enum Lookup: Hashable {
        case name(String), barcode(String)

        var inputMethod: String { if case .barcode = self { "barcode" } else { "manual_search" } }
    }

    private struct SearchTask: Hashable {
        let lookup: Lookup?
        let retry: Int
    }

    private struct FoodRoute: Hashable {
        let food: NutritionFoodMatch
        let inputMethod: String
    }

    private static let debounce: Duration = .milliseconds(300)
    private static let queryLength = 2...100
    private static let pageSize = 20
    private static let quickAddGrams = 100.0

    let model: NutritionDiaryModel
    let api: APIClient
    @Binding var initialFood: NutritionFoodMatch?
    @Binding var items: [NutritionDraftItem]
    let backToReview: (() -> Void)?
    let review: () -> Void

    @State private var query = ""
    @State private var barcode = ""
    @State private var searchesBarcode = false
    @State private var scanner = false
    @State private var detail: FoodRoute?
    @State private var createsFood = false
    @State private var matches: [NutritionFoodMatch] = []
    @State private var nextOffset: Int?
    @State private var barcodeResult: NutritionBarcodeResult?
    @State private var resultFor: Lookup?
    @State private var requestID = UUID()
    @State private var loadingMore = false
    @State private var failure: String?
    @State private var cameraFailure: String?
    @State private var retry = 0
    @FocusState private var editing: Bool

    private var typedName: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { items.count < NutritionMealEditor.maximumItems && model.online }
    private var lookup: Lookup? {
        guard model.online else { return nil }
        if searchesBarcode {
            guard [8, 12, 13, 14].contains(barcode.count),
                  barcode.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
            return .barcode(barcode)
        }
        guard Self.queryLength.contains(typedName.unicodeScalars.count) else { return nil }
        return .name(typedName)
    }

    var body: some View {
        if let food = initialFood {
            NutritionFoodDetailView(model: model, food: food, inputMethod: "manual_search") { item in
                append(item)
                initialFood = nil
            }
        } else {
            searchPage
        }
    }

    private var searchPage: some View {
        let task = SearchTask(lookup: lookup, retry: retry)
        return SubpageScaffold(Text("Add food"), navigation: backToReview.map { .back(.perform($0)) } ?? .back()) {
            if !items.isEmpty {
                PillButton(Text("Review"), style: .secondary, size: .compact) {
                    editing = false
                    review()
                }
                .accessibilityIdentifier("nutrition.reviewMeal")
            }
        } content: {
            VStack(alignment: .leading, spacing: Theme.Metrics.itemSpacing) {
                searchControls
                if !items.isEmpty {
                    Text("Foods in meal: \(items.count)")
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("nutrition.selectionCount")
                }
                if items.count >= NutritionMealEditor.maximumItems {
                    GroupFooter(Text("A meal can contain up to \(NutritionMealEditor.maximumItems) foods."))
                }
                if let cameraFailure { InlineMessage(message: cameraFailure, systemImage: "exclamationmark.circle") }
                searchResults
                if lookup == nil || (resultFor == lookup && matches.isEmpty) {
                    GroupedCard {
                        GroupedRow.push(Text("Create private food"), icon: "plus") {
                            editing = false
                            createsFood = true
                        }
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .defaultFocus($editing, true)
        .task(id: task) { await search(task.lookup) }
        .navigationDestination(item: $detail) { entry in
            NutritionFoodDetailView(model: model, food: entry.food, inputMethod: entry.inputMethod) { item in
                append(item)
                detail = nil
            }
        }
        .navigationDestination(isPresented: $createsFood) {
            NutritionCustomFoodView(model: model, api: api) { item in
                append(item)
                createsFood = false
            }
        }
        .sheet(isPresented: $scanner) {
            scannerContent.presentedRoot()
        }
    }

    private var searchControls: some View {
        VStack(alignment: .leading, spacing: Theme.Metrics.itemSpacing) {
            HStack(spacing: Theme.Metrics.itemSpacing) {
                if searchesBarcode {
                    GroupedCard {
                        NutritionInputRow(title: Text("Barcode digits"), value: $barcode, numeric: true)
                            .focused($editing)
                    }
                } else {
                    SearchField(text: $query, prompt: Text("Search foods"), identifier: "nutrition.foodQuery", focus: $editing)
                        .onSubmit { editing = false }
                }
                CircleButton(systemImage: searchesBarcode ? "magnifyingglass" : "barcode",
                             accessibilityLabel: searchesBarcode ? Text("Search foods") : Text("Barcode")) {
                    cameraFailure = nil
                    searchesBarcode.toggle()
                }
                .accessibilityIdentifier("nutrition.barcodeMode")
            }
            if searchesBarcode && DataScannerViewController.isSupported {
                GroupedCard {
                    GroupedRow.action(Text("Scan barcode"), systemImage: "barcode.viewfinder") {
                        Task { await beginScanner() }
                    }
                }
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        if !model.online {
            GroupFooter(Text("Connect to the internet to search the food catalog."))
        } else if !searchesBarcode && typedName.unicodeScalars.count > Self.queryLength.upperBound {
            GroupFooter(Text("Use up to \(Self.queryLength.upperBound) characters to search."))
        } else if let lookup {
            if resultFor != lookup {
                ProgressView().accessibilityLabel(Text("Searching foods"))
            } else {
                if !matches.isEmpty {
                    GroupedCard(footer: barcodeFooter) {
                        ForEach(matches) { food in resultRow(food, inputMethod: lookup.inputMethod) }
                        if nextOffset != nil && failure == nil {
                            GroupedRow.action(Text("Load more foods"), systemImage: "chevron.down", busy: loadingMore) {
                                Task { await loadMore(lookup) }
                            }
                        }
                    }
                } else if failure == nil {
                    GroupFooter(Text("No matches"))
                }
                if let failure {
                    InlineMessage(message: failure, systemImage: "exclamationmark.circle", retry: {
                        if nextOffset != nil {
                            await loadMore(lookup)
                        } else {
                            resultFor = nil
                            retry += 1
                        }
                    })
                }
            }
        }
    }

    private func resultRow(_ food: NutritionFoodMatch, inputMethod: String) -> some View {
        HStack(spacing: 0) {
            Button {
                editing = false
                detail = FoodRoute(food: food, inputMethod: inputMethod)
            } label: {
                GroupedRowLabel(Text(verbatim: food.name), detail: food.brand.isEmpty ? nil : Text(verbatim: food.brand))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .accessibilityIdentifier("nutrition.food.\(food.id.uuidString.lowercased())")
            Button {
                append(NutritionDraftItem(name: food.name, inputMethod: inputMethod,
                                          selection: NutritionMealSelection(foodId: food.id, quantity: Self.quickAddGrams, unit: "g")))
            } label: {
                Label {
                    NutritionDisplay.amount(Self.quickAddGrams, unit: "g").font(.ryft(.caption))
                } icon: {
                    Image(systemName: "plus")
                }
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, GroupedListSpec.rowSpacing)
                .frame(minHeight: Theme.Metrics.minHitTarget)
                .background(Theme.surfaceRaised, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .disabled(!canAdd)
            .accessibilityLabel(Text("Add \(NutritionDisplay.number(Self.quickAddGrams)) g of \(food.name)"))
            .accessibilityIdentifier("nutrition.quickAdd.\(food.id.uuidString.lowercased())")
            .padding(.trailing, GroupedListSpec.rowInset)
        }
        .groupedRowHairline()
    }

    private func append(_ item: NutritionDraftItem) {
        guard canAdd, model.hasCurrentAccount else { return }
        items.append(item)
    }

    private var barcodeFooter: Text? {
        guard let barcodeResult else { return nil }
        if barcodeResult.truncated { return Text("Showing up to 20 matches. Check the brand and name before selecting.") }
        if barcodeResult.conflicted { return Text("Several foods share this barcode. Check the brand and name before selecting.") }
        return nil
    }

    @ViewBuilder private var scannerContent: some View {
        if DataScannerViewController.isAvailable {
            NutritionBarcodeScanner { value in
                editing = false
                barcode = value
                scanner = false
            } failed: {
                scanner = false
                cameraFailure = String(localized: "Camera scanning is unavailable. You can enter the barcode digits.")
            }
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                Button("Close") { scanner = false }
                    .padding()
                    .background(.regularMaterial, in: Capsule())
            }
        } else {
            SubpageScaffold(Text("Barcode scanner"), navigation: .close(), isSheet: true) {
                GroupFooter(Text("Allow camera access in Settings or enter the barcode digits."))
            }
        }
    }

    private func beginScanner() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard model.hasCurrentAccount, searchesBarcode else { return }
        if granted {
            editing = false
            scanner = true
        } else {
            cameraFailure = String(localized: "Allow camera access in Settings or enter the barcode digits.")
        }
    }

    private func search(_ requested: Lookup?) async {
        guard requested == lookup, !Task.isCancelled else { return }
        let id = UUID()
        requestID = id
        resultFor = nil
        matches = []
        nextOffset = nil
        barcodeResult = nil
        loadingMore = false
        failure = nil
        guard let requested else { return }
        do {
            try await Task.sleep(for: Self.debounce)
            try model.needsCurrentAccount()
            switch requested {
            case .name(let name):
                let page = try await foodPage(name)
                try model.needsCurrentAccount()
                guard id == requestID, lookup == requested else { return }
                matches = page.foods
                nextOffset = page.nextOffset
            case .barcode(let code):
                let result = try await api.lookupNutritionBarcode(.init(barcode: code, market: Locale.current.region?.identifier))
                try model.needsCurrentAccount()
                guard id == requestID, lookup == requested else { return }
                barcodeResult = result
                matches = result.matches
            }
            resultFor = requested
        } catch {
            guard id == requestID, lookup == requested, !Task.isCancelled, !error.isCancellation else { return }
            failure = error.localizedDescription
            resultFor = requested
        }
    }

    private func loadMore(_ requested: Lookup) async {
        guard case .name(let name) = requested, lookup == requested, resultFor == requested,
              let nextOffset, !loadingMore else { return }
        let id = requestID
        loadingMore = true
        failure = nil
        defer { if id == requestID { loadingMore = false } }
        do {
            try model.needsCurrentAccount()
            let page = try await foodPage(name, offset: nextOffset)
            try model.needsCurrentAccount()
            guard id == requestID, lookup == requested else { return }
            let seen = Set(matches.map(\.id))
            matches += page.foods.filter { !seen.contains($0.id) }
            self.nextOffset = page.nextOffset
        } catch {
            if id == requestID, lookup == requested, !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func foodPage(_ name: String, offset: Int? = nil) async throws -> NutritionFoodSearchPage {
        try await model.searchFoods(.init(query: name, language: Locale.current.language.languageCode?.identifier,
                                         market: Locale.current.region?.identifier, limit: Self.pageSize, offset: offset))
    }
}

private struct NutritionBarcodeScanner: UIViewControllerRepresentable {
    let found: (String) -> Void
    let failed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean8, .ean13, .itf14])],
                                                   qualityLevel: .balanced, recognizesMultipleItems: false)
        controller.delegate = context.coordinator
        do { try controller.startScanning() } catch { Task { @MainActor in failed() } }
        return controller
    }

    func updateUIViewController(_: DataScannerViewController, context _: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator _: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var handled = false
        init(found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems _: [RecognizedItem]) {
            guard !handled, let label = addedItems.compactMap({ item -> String? in
                if case .barcode(let value) = item { return value.payloadStringValue }
                return nil
            }).first else { return }
            handled = true
            scanner.stopScanning()
            found(label)
        }
    }
}

struct NutritionFoodDetailView: View {
    let model: NutritionDiaryModel
    let food: NutritionFoodMatch
    let inputMethod: String
    let selected: (NutritionDraftItem) -> Void

    @State private var detail: NutritionFoodDetail?
    @State private var loading = false
    @State private var failure: String?
    @State private var quantity = "100"
    @State private var measure = "g"

    var body: some View {
        SubpageScaffold(Text(verbatim: food.name)) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if loading { ProgressView() }
                if let failure {
                    InlineMessage(message: failure, systemImage: "exclamationmark.circle")
                    if detail == nil { PillButton(Text("Try again"), style: .secondary, busy: loading) { await load() } }
                }
                if let detail {
                    GroupedCard(Text("Amount")) {
                        NutritionInputRow(title: Text("Quantity"), value: $quantity, numeric: true)
                        Picker("Measure", selection: $measure) {
                            Text("Grams").tag("g")
                            if supportsVolume(detail) { Text("Milliliters").tag("ml") }
                            ForEach(selectablePortions(detail)) { portion in
                                Text(verbatim: portion.labels?[Locale.current.language.languageCode?.identifier ?? ""] ?? portion.label)
                                    .tag(portion.id.uuidString)
                            }
                        }
                        .nutritionField()
                    }
                    PillButton(Text("Add to meal")) { add(detail) }
                    if !detail.nutrients.isEmpty {
                        GroupedCard(Text("Catalog nutrients"), footer: Text("Values include their reference amount and unit.")) {
                            ForEach(Array(detail.nutrients.enumerated()), id: \.offset) { _, value in
                                let name = NutritionNutrient(rawValue: value.code)?.title ?? value.code.replacingOccurrences(of: "_", with: " ").capitalized
                                GroupedRow.value(Text(verbatim: name),
                                                 value: Text(verbatim: "\(NutritionDisplay.number(value.amount)) \(value.unit) / " +
                                                             "\(NutritionDisplay.number(value.referenceAmount)) \(value.referenceUnit)"))
                            }
                        }
                    }
                    if !detail.sources.isEmpty {
                        GroupedCard(Text("Food data sources")) {
                            ForEach(detail.sources) { source in
                                GroupedRow.value(Text(verbatim: source.provider), value: Text(verbatim: source.licenseIdentifier))
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: measure) { _, next in quantity = next == "g" || next == "ml" ? "100" : "1" }
    }

    private func supportsVolume(_ food: NutritionFoodDetail) -> Bool {
        food.densityGMl != nil || food.nutrients.contains { $0.referenceUnit == "ml" }
    }

    private func selectablePortions(_ food: NutritionFoodDetail) -> [NutritionFoodPortion] {
        food.portions.filter { $0.unit == "portion" || $0.unit == "serving" }
    }

    private func add(_ food: NutritionFoodDetail) {
        do {
            guard let count = try NutritionNumbers.parse(quantity, in: 0.000_001...100_000) else {
                throw NutritionInputError.invalidNumber
            }
            let portion = selectablePortions(food).first { $0.id.uuidString == measure }
            selected(NutritionDraftItem(name: food.name, inputMethod: inputMethod,
                                       selection: NutritionMealSelection(foodId: food.id, quantity: count,
                                                                         unit: portion?.unit ?? measure, portionId: portion?.id)))
        } catch {
            failure = error.localizedDescription
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        failure = nil
        defer { loading = false }
        do {
            try model.needsCurrentAccount()
            let result = try await model.foodDetail(food.id)
            try model.needsCurrentAccount()
            detail = result
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }
}

struct NutritionCustomFoodView: View {
    let model: NutritionDiaryModel
    let api: APIClient
    let selected: (NutritionDraftItem) -> Void

    @State private var name = ""
    @State private var brand = ""
    @State private var quantity = "100"
    @State private var nutrients: [NutritionNutrient: String] = [:]
    @State private var vegetables = ""
    @State private var fruit = ""
    @State private var nuts = ""
    @State private var meat = ""
    @State private var drink = 0
    @State private var busy = false
    @State private var failure: String?
    @State private var requestId = UUID()
    @State private var created: NutritionFoodDetail?
    @State private var submitting = false
    @State private var submitted = false

    var body: some View {
        SubpageScaffold(Text("Create private food")) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if let created {
                    GroupedCard(Text(verbatim: created.name)) {
                        NutritionInputRow(title: Text("Grams to log"), value: $quantity, numeric: true)
                        GroupedRow.action(submitted ? Text("Submitted for review") : Text("Submit to catalog for review"),
                                          systemImage: "paperplane", busy: busy) { submitting = true }
                            .disabled(submitted)
                    }
                    PillButton(Text("Add to meal")) { add(created) }
                } else {
                    fields
                    PillButton(Text("Save private food"), busy: busy) { await create() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let failure { InlineMessage(message: failure, systemImage: "exclamationmark.circle") }
            }
        }
        .confirmationDialog("Submit this food for review?", isPresented: $submitting, titleVisibility: .visible) {
            Button("Submit for review") { Task { await submit() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This sends the food record for catalog review. Your meal log stays private.")
        }
    }

    private var fields: some View {
        VStack(spacing: GroupedListSpec.groupSpacing) {
            GroupedCard(Text("Food details")) {
                NutritionInputRow(title: Text("Food name"), value: $name)
                NutritionInputRow(title: Text("Brand"), value: $brand)
            }
            GroupedCard(Text("Nutrients per 100 g"), footer: Text("Leave an amount blank when it is unknown.")) {
                ForEach(NutritionNutrient.allCases) { key in
                    NutritionInputRow(title: Text(verbatim: "\(key.title) (\(key.unit))"),
                                      value: Binding(get: { nutrients[key, default: ""] }, set: { nutrients[key] = $0 }), numeric: true)
                }
            }
            GroupedCard(Text("Food quality categories"), footer: Text("Enter the percentage of edible weight for each category you know.")) {
                NutritionInputRow(title: Text("Non-starchy vegetables (%)"), value: $vegetables, numeric: true)
                NutritionInputRow(title: Text("Whole fruit (%)"), value: $fruit, numeric: true)
                NutritionInputRow(title: Text("Nuts and legumes (%)"), value: $nuts, numeric: true)
                NutritionInputRow(title: Text("Red and processed meat (%)"), value: $meat, numeric: true)
                Picker("Sugary drink or juice", selection: $drink) {
                    Text("Unknown").tag(0)
                    Text("Yes").tag(1)
                    Text("No").tag(2)
                }
                .nutritionField()
            }
        }
        .disabled(busy)
    }

    private func create() async {
        guard !busy else { return }
        busy = true
        failure = nil
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            let values = try NutritionNutrient.allCases.compactMap { nutrient -> NutritionNutrientWrite? in
                guard let amount = try NutritionNumbers.parse(nutrients[nutrient, default: ""], in: 0...100_000) else { return nil }
                return .init(code: nutrient.rawValue, amount: amount, unit: nutrient.unit, referenceAmount: 100, referenceUnit: "g")
            }
            let weights = try [vegetables, fruit, nuts, meat].map { try NutritionNumbers.parse($0, in: 0...100).map { $0 / 100 } }
            guard weights.compactMap({ $0 }).reduce(0, +) <= 1.000_000_1 else { throw NutritionInputError.invalidNumber }
            let classification = NutritionQualityProfile(nonStarchyVegetableFraction: weights[0], wholeFruitFraction: weights[1],
                                                         nutsLegumesFraction: weights[2], redProcessedMeatFraction: weights[3],
                                                         sugaryDrink: drink == 0 ? nil : drink == 1)
            let request = NutritionCustomFood(clientRequestId: requestId, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                              brand: brand.trimmingCharacters(in: .whitespacesAndNewlines), nutrients: values,
                                              qualityProfile: weights.contains(where: { $0 != nil }) || drink != 0 ? classification : nil)
            let result = try await api.createNutritionFood(request)
            try model.needsCurrentAccount()
            model.addedFood(result)
            created = result
        } catch {
            if let status = (error as? APIError)?.status, status == 409 {
                requestId = UUID()
            }
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func submit() async {
        guard let created, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            let response = try await api.submitNutritionFood(.init(foodId: created.id, status: "submitted"))
            try model.needsCurrentAccount()
            submitted = response.status == "submitted"
            failure = nil
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func add(_ created: NutritionFoodDetail) {
        do {
            guard let value = try NutritionNumbers.parse(quantity, in: 0.000_001...100_000) else { throw NutritionInputError.invalidNumber }
            selected(NutritionDraftItem(name: created.name, inputMethod: "manual_entry",
                                       selection: .init(foodId: created.id, quantity: value, unit: "g")))
        } catch {
            failure = error.localizedDescription
        }
    }
}
