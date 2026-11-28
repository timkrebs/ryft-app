import AVFoundation
import SwiftUI
import VisionKit
import Vision

struct NutritionFoodPicker: View {
    private enum Lookup: Hashable {
        case name(String), barcode(String)

        var inputMethod: String { if case .barcode = self { "barcode" } else { "manual_search" } }

        /// `nutrition_food_logged` → `entry_point`: anything added from a barcode's result is `barcode`.
        func entryPoint(quickAdd: Bool) -> AnalyticsNutritionEntryPoint {
            if case .barcode = self { return .barcode }
            return quickAdd ? .quickAddButton : .detailSheet
        }

        /// `nutrition_search_completed`'s lookup and length bucket: the length only, never the text.
        var searchTokens: (AnalyticsSearchLookup, AnalyticsQueryLength) {
            switch self {
            case .name(let name): return (.name, AnalyticsQueryLength(characters: name.count))
            case .barcode(let code): return (.barcode, AnalyticsQueryLength(characters: code.count))
            }
        }
    }

    private struct SearchTask: Hashable {
        let lookup: Lookup?
        let retry: Int
        let language: String
        let market: String?
    }

    private struct FoodRoute: Hashable {
        let food: NutritionFoodMatch
        let inputMethod: String
        /// Where an Add to meal from this detail counts as added (an Edit amount keeps the quick add's).
        let entryPoint: AnalyticsNutritionEntryPoint
        var editingID: UUID?
    }

    private struct QuickAddition {
        let itemID: UUID
        let route: FoodRoute
    }

    private static let debounce: Duration = .milliseconds(300)
    private static let queryLength = 2...100
    private static let pageSize = 20
    private static let quickAdditionNoticeDuration: Duration = .seconds(10)

    let model: NutritionDiaryModel
    let api: APIClient
    @Binding var initialFood: NutritionFoodMatch?
    @Binding var items: [NutritionDraftItem]
    let onBack: () -> Void
    let review: () -> Void

    @State private var query = ""
    @State private var barcode = ""
    @State private var searchesBarcode: Bool
    @State private var scanner = false
    @State private var detail: FoodRoute?
    @State private var quickAddition: QuickAddition?
    @State private var quickAddFeedback = 0
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
    /// The search last reported as `nutrition_search_completed`: the page's `.task(id:)` restarts the same search when it
    /// reappears (Back, Add to meal, Edit amount, Create private food), and that isn't a new one. A Retry is (`retry`).
    @State private var reportedSearch: SearchTask?
    @FocusState private var editing: Bool
    @Environment(\.locale) private var locale
    @Environment(\.appEnvironment) private var env

    init(model: NutritionDiaryModel, api: APIClient, initialFood: Binding<NutritionFoodMatch?>,
         items: Binding<[NutritionDraftItem]>, startsWithBarcode: Bool = false,
         onBack: @escaping () -> Void, review: @escaping () -> Void) {
        self.model = model
        self.api = api
        _initialFood = initialFood
        _items = items
        _searchesBarcode = State(initialValue: startsWithBarcode)
        self.onBack = onBack
        self.review = review
    }

    private var catalogLocale: NutritionCatalogLocale { NutritionCatalogLocale(locale: locale) }

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
            NutritionFoodDetailView(model: model, food: food, inputMethod: "manual_search", entryPoint: .suggestion,
                                    onBack: onBack) { item in
                append(item)
                initialFood = nil
            }
        } else {
            searchPage
        }
    }

    private var searchPage: some View {
        let task = SearchTask(lookup: lookup, retry: retry, language: catalogLocale.language, market: catalogLocale.market)
        return SubpageScaffold(Text("Add food"), navigation: .back(.perform({
            editing = false
            onBack()
        }))) {
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
                if let quickAddition { addedNotice(quickAddition) }
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
        .task(id: task) { await search(task) }
        .task(id: quickAddition?.itemID) {
            guard let id = quickAddition?.itemID,
                  (try? await Task.sleep(for: Self.quickAdditionNoticeDuration)) != nil else { return }
            if quickAddition?.itemID == id { quickAddition = nil }
        }
        .sensoryFeedback(.selection, trigger: quickAddFeedback)
        .navigationDestination(item: $detail) { entry in
            let starting = items.first { $0.id == entry.editingID }?.selection
            NutritionFoodDetailView(model: model, food: entry.food, inputMethod: entry.inputMethod,
                                    entryPoint: entry.entryPoint, startingSelection: starting,
                                    onBack: { detail = nil }) { item in
                if let id = entry.editingID {
                    guard model.hasCurrentAccount, let index = items.firstIndex(where: { $0.id == id }) else { return }
                    var replacement = item
                    replacement.id = id
                    items[index] = replacement
                } else {
                    append(item)
                }
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
                        ForEach(matches) { food in resultRow(food, lookup: lookup) }
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

    private func resultRow(_ food: NutritionFoodMatch, lookup: Lookup) -> some View {
        let inputMethod = lookup.inputMethod
        let choice = food.quickSelection
        let amount = food.describedSelection?.summary(locale: locale) ?? ""
        let descriptions = [food.subtitle ?? food.brand, amount].filter { !$0.isEmpty }
        return HStack(spacing: 0) {
            Button {
                editing = false
                open(food, lookup: lookup)
            } label: {
                GroupedRowLabel(Text(verbatim: food.name),
                                detail: descriptions.isEmpty ? nil : Text(verbatim: descriptions.joined(separator: " · ")))
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .accessibilityIdentifier("nutrition.food.\(food.id.uuidString.lowercased())")
            Button {
                guard canAdd, model.hasCurrentAccount else { return }
                guard let choice else {
                    editing = false
                    open(food, lookup: lookup)
                    return
                }
                let entryPoint = lookup.entryPoint(quickAdd: true)
                var item = choice.draft(food: food, inputMethod: inputMethod, language: catalogLocale.language)
                item.logContext = NutritionLogContext(entryPoint, lastUsed: food.lastUsedPortion)
                append(item)
                quickAddition = QuickAddition(itemID: item.id,
                                              route: FoodRoute(food: food, inputMethod: inputMethod, entryPoint: entryPoint,
                                                               editingID: item.id))
                quickAddFeedback += 1
            } label: {
                Image(systemName: "plus")
                    .frame(minWidth: Theme.Metrics.minHitTarget, minHeight: Theme.Metrics.minHitTarget)
                    .background(Theme.surfaceRaised, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .disabled(!canAdd)
            .accessibilityLabel(choice == nil ? Text("Choose an amount for \(food.name)") : Text("Add \(food.name)"))
            .accessibilityValue(Text(verbatim: amount))
            .accessibilityIdentifier("nutrition.quickAdd.\(food.id.uuidString.lowercased())")
            .padding(.trailing, GroupedListSpec.rowInset)
        }
        .groupedRowHairline()
    }

    private func addedNotice(_ addition: QuickAddition) -> some View {
        let name = addition.route.food.name
        return VStack(alignment: .trailing, spacing: ValueChipSpec.spacing) {
            UndoToast(message: String(localized: "Added \(name) to meal"),
                      announcement: String(localized: "Added \(name) to meal. Undo available."),
                      onUndo: {
                          items.removeAll { $0.id == addition.itemID }
                          quickAddition = nil
                      },
                      onDismiss: { quickAddition = nil },
                      undoIdentifier: "nutrition.undoQuickAdd")
            Button("Edit amount") {
                editing = false
                detail = addition.route
                quickAddition = nil
            }
            .ryftLink()
            .accessibilityIdentifier("nutrition.editQuickAdd")
        }
        .id(addition.itemID)
    }

    /// A search result opens its detail (the row, or "+" without a quick selection): `nutrition_food_opened` with its
    /// 1-based place in the list (plan, decision 9; not for Edit amount, nor the suggestion).
    /// A food that isn't in `matches` (any more) opens without the event: its rank is unknown, not 1.
    private func open(_ food: NutritionFoodMatch, lookup: Lookup) {
        if let index = matches.firstIndex(where: { $0.id == food.id }) {
            env.analytics.track(food.openedEvent(rank: index + 1))
        }
        detail = FoodRoute(food: food, inputMethod: lookup.inputMethod, entryPoint: lookup.entryPoint(quickAdd: false))
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

    private func search(_ task: SearchTask) async {
        let requested = task.lookup
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
            // `latency_ms`: from after the debounce to the result, what the person waits for.
            let clock = env.clock
            let started = clock.uptime()
            let count: Int
            switch requested {
            case .name(let name):
                let page = try await foodPage(name)
                try model.needsCurrentAccount()
                guard id == requestID, lookup == requested else { return }
                matches = page.foods
                nextOffset = page.nextOffset
                count = page.foods.count
            case .barcode(let code):
                let result = try await api.lookupNutritionBarcode(.init(barcode: code, market: catalogLocale.market))
                try model.needsCurrentAccount()
                guard id == requestID, lookup == requested else { return }
                barcodeResult = result
                matches = result.matches
                count = result.matches.count
            }
            resultFor = requested
            // The first page or the barcode's result only: a failure isn't completed, Load more isn't a new search,
            // and the same search restarted by the page reappearing was reported already.
            guard task != reportedSearch else { return }
            reportedSearch = task
            let (kind, length) = requested.searchTokens
            env.analytics.track(.nutritionSearchCompleted(lookup: kind, queryLength: length,
                                                          results: AnalyticsResultCount(count),
                                                          latency: AnalyticsLatency(clock.uptime() - started)))
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
        try await model.searchFoods(.init(query: name, language: catalogLocale.language,
                                         market: catalogLocale.market, limit: Self.pageSize, offset: offset))
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
    /// Where Add to meal counts as added, for `nutrition_food_logged` (the item's local `logContext`).
    var entryPoint: AnalyticsNutritionEntryPoint?
    var startingSelection: NutritionMealSelection?
    let onBack: () -> Void
    let selected: (NutritionDraftItem) -> Void

    @State private var detail: NutritionFoodDetail?
    @State private var loading = false
    @State private var failure: String?
    @State private var quantity = "100"
    @State private var measure = "g"
    @State private var confirmsReport = false
    @State private var reporting = false
    @State private var reported = false
    @State private var favorite: Bool?
    @State private var updatingFavorite = false
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var typeSize

    private var language: String { NutritionCatalogLocale(locale: locale).language }
    private var displayName: String { detail?.displayName(language: language, fallback: food.name) ?? food.name }

    var body: some View {
        SubpageScaffold(Text(verbatim: displayName), navigation: .back(.perform(onBack))) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if loading { ProgressView() }
                if let failure {
                    InlineMessage(message: failure, systemImage: "exclamationmark.circle")
                    if detail == nil { PillButton(Text("Try again"), style: .secondary, busy: loading) { await load() } }
                }
                if let detail {
                    foodSummary(detail)
                    let portion = chosenPortion(detail)
                    let preview = servingPreview(detail, portion: portion)
                    GroupedCard(Text("Amount")) {
                        amountControls(detail, portion: portion)
                        if let preview, portion?.volumeMl != nil, let volume = preview.volumeMl {
                            GroupedRow.value(Text("Volume"), value: NutritionDisplay.amount(volume, unit: "mL", locale: locale))
                        } else if let preview, portion != nil, let weight = preview.weightG {
                            GroupedRow.value(Text("Weight"), value: NutritionDisplay.amount(weight, unit: "g", locale: locale))
                        }
                    }
                    if let preview {
                        GroupedCard(Text("For this amount"), footer: Text("Estimated from the food catalog.")) {
                            ForEach(NutritionServingPreview.displayedNutrients) { nutrient in
                                GroupedRow.value(Text(verbatim: nutrient.title),
                                                 value: preview.amounts[nutrient].map {
                                                     NutritionDisplay.amount($0, unit: nutrient.unit, locale: locale)
                                                 } ?? Text("Unknown"))
                            }
                        }
                    } else {
                        GroupFooter(Text("Enter a quantity with an available measure."))
                    }
                    PillButton(startingSelection == nil ? Text("Add to meal") : Text("Apply amount")) {
                        add(detail, portion: portion, preview: preview)
                    }
                        .disabled(preview == nil)
                    if !detail.nutrients.isEmpty {
                        GroupedCard(Text("Catalog nutrients"), footer: Text("Values include their reference amount and unit.")) {
                            ForEach(Array(detail.nutrients.enumerated()), id: \.offset) { _, value in
                                let name = NutritionNutrient(catalogCode: value.code)?.title ?? value.code.replacingOccurrences(of: "_", with: " ").capitalized
                                GroupedRow.value(Text(verbatim: name),
                                                 value: Text(verbatim: "\(NutritionDisplay.number(value.amount)) \(value.unit) / " +
                                                             "\(NutritionDisplay.number(value.referenceAmount)) \(value.referenceUnit)"))
                            }
                        }
                    }
                    if !detail.sources.isEmpty {
                        GroupedCard(Text("Food data sources")) {
                            ForEach(detail.sources) { source in
                                GroupedRow.value(Text(verbatim: source.provider), value: Text(verbatim: source.licenseIdentifier),
                                                 detail: source.attribution.map { Text(verbatim: $0) })
                            }
                        }
                    }
                    if food.catalogIssueReport != nil {
                        PillButton(reported ? Text("Food issue reported") : Text("Report food issue"),
                                   style: .secondary, busy: reporting) { confirmsReport = true }
                            .disabled(reported)
                    }
                }
            }
        }
        .task { await load() }
        .confirmationDialog("Report a catalog issue?", isPresented: $confirmsReport, titleVisibility: .visible) {
            Button("Send report") { Task { await reportIssue() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The report includes only the catalog item's identifier with your account. Your meal and search stay private.")
        }
    }

    @ViewBuilder private func foodSummary(_ detail: NutritionFoodDetail) -> some View {
        let subtitle = detail.subtitle ?? food.subtitle ?? food.brand
        if !subtitle.isEmpty || favorite != nil {
            HStack {
                if !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if let favorite {
                    CircleButton(systemImage: favorite ? "star.fill" : "star",
                                 accessibilityLabel: favorite ? Text("Remove from favorites") : Text("Add to favorites")) {
                        Task { await changeFavorite(!favorite) }
                    }
                    .disabled(updatingFavorite)
                    .accessibilityIdentifier("nutrition.food.favorite")
                }
            }
        }
    }

    private func amountControls(_ detail: NutritionFoodDetail, portion: NutritionFoodPortion?) -> some View {
        let grid = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 90), spacing: ValueChipSpec.spacing)]
        return VStack(alignment: .leading, spacing: ValueChipSpec.spacing) {
            if !detail.sortedPortions.isEmpty {
                LazyVGrid(columns: grid, alignment: .leading, spacing: ValueChipSpec.spacing) {
                    ForEach(detail.sortedPortions) { option in
                        let id = option.id.uuidString
                        amountChip(Text(verbatim: option.chipLabel(language: language)), value: id, detail: detail,
                                   amount: catalogAmount(option))
                            .accessibilityIdentifier("nutrition.portion.\(option.portionKey ?? id.lowercased())")
                    }
                }
            }
            ValueChipGroup {
                amountChip(Text("Grams"), value: "g", detail: detail)
                    .accessibilityIdentifier("nutrition.measure.grams")
                if supportsVolume(detail) {
                    amountChip(Text("Milliliters"), value: "ml", detail: detail)
                        .accessibilityIdentifier("nutrition.measure.milliliters")
                }
            }
            if let portion { multiplierChips(for: portion) }
            quantityControl(household: portion != nil)
        }
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.vertical, GroupedListSpec.rowSpacing)
        .groupedRowHairline()
    }

    private func amountChip(_ title: Text, value: String, detail: NutritionFoodDetail, amount: Text? = nil) -> some View {
        selectionChip(title, isSelected: measure == value, amount: amount) { choose(value, from: detail) }
    }

    private func multiplierChips(for portion: NutritionFoodPortion) -> some View {
        let columns = [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 120 : 62), spacing: ValueChipSpec.spacing)]
        return LazyVGrid(columns: columns, spacing: ValueChipSpec.spacing) {
            ForEach(NutritionServingPreview.householdMultipliers, id: \.self) { multiplier in
                let count = portion.quantity * multiplier
                let label = NutritionDisplay.number(multiplier, locale: locale)
                selectionChip(Text(verbatim: "\(label)×"), isSelected: parsedQuantity == count) {
                    quantity = NutritionDisplay.editableQuantity(count, locale: locale)
                    failure = nil
                }
                .disabled(!NutritionServingPreview.isValidQuantity(count))
                .accessibilityIdentifier("nutrition.quantity.multiplier.\(multiplier)")
            }
        }
    }

    private func selectionChip(_ title: Text, isSelected: Bool, amount: Text? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                title.font(.ryft(.callout)).fixedSize(horizontal: false, vertical: true)
                if let amount { amount.font(.ryft(.caption)).monospacedDigit() }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, ValueChipSpec.horizontalPadding)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minHitTarget)
            .foregroundStyle(isSelected ? Theme.background : Theme.textPrimary)
            .background(isSelected ? Theme.textPrimary : Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: ValueChipSpec.height / 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func catalogAmount(_ portion: NutritionFoodPortion) -> Text? {
        if let ml = portion.volumeMl { return NutritionDisplay.amount(ml, unit: "mL", locale: locale) }
        if let grams = portion.weightG { return NutritionDisplay.amount(grams, unit: "g", locale: locale) }
        return nil
    }

    private func quantityControl(household: Bool) -> some View {
        let step = household ? NutritionServingPreview.householdStep : NutritionServingPreview.metricStep
        let current = parsedQuantity
        return HStack(spacing: ValueChipSpec.spacing) {
            CircleButton(systemImage: "minus", accessibilityLabel: Text("Decrease quantity")) { adjustQuantity(-step) }
                .disabled(current.map { $0 <= step } ?? true)
                .accessibilityIdentifier("nutrition.quantity.decrease")
            VStack(alignment: .leading, spacing: 2) {
                Text("Quantity").font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
                TextField("", text: $quantity)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel(Text("Quantity"))
                    .accessibilityIdentifier("nutrition.quantity")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            CircleButton(systemImage: "plus", accessibilityLabel: Text("Increase quantity")) { adjustQuantity(step) }
                .disabled(current.map { $0 > NutritionServingPreview.quantityLimits.upperBound - step } ?? true)
                .accessibilityIdentifier("nutrition.quantity.increase")
        }
    }

    private var parsedQuantity: Double? {
        try? NutritionServingPreview.parseQuantity(quantity, locale: locale)
    }

    private func adjustQuantity(_ step: Double) {
        guard let current = parsedQuantity, NutritionServingPreview.isValidQuantity(current + step) else { return }
        quantity = NutritionDisplay.editableQuantity(current + step, locale: locale)
    }

    private func changeFavorite(_ enabled: Bool) async {
        guard !updatingFavorite else { return }
        updatingFavorite = true
        failure = nil
        defer { updatingFavorite = false }
        do {
            try await model.setFavorite(enabled, foodID: food.id)
            favorite = enabled
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func supportsVolume(_ food: NutritionFoodDetail) -> Bool {
        food.densityGMl != nil || food.nutrients.contains { $0.referenceUnit == "ml" }
    }

    private func chosenPortion(_ food: NutritionFoodDetail) -> NutritionFoodPortion? {
        food.sortedPortions.first { $0.id.uuidString == measure }
    }

    private func choose(_ choice: String, from food: NutritionFoodDetail) {
        guard choice != measure else { return }
        measure = choice
        quantity = chosenPortion(food).map { NutritionDisplay.editableQuantity($0.quantity, locale: locale) } ?? "100"
        failure = nil
    }

    private func servingPreview(_ food: NutritionFoodDetail, portion: NutritionFoodPortion?) -> NutritionServingPreview? {
        guard let count = parsedQuantity else { return nil }
        return NutritionServingPreview(food: food, quantity: count, unit: portion?.unit ?? measure, portion: portion)
    }

    private func add(_ food: NutritionFoodDetail, portion: NutritionFoodPortion?, preview: NutritionServingPreview?) {
        do {
            guard let count = try NutritionServingPreview.parseQuantity(quantity, locale: locale) else {
                throw NutritionInputError.invalidNumber
            }
            var item = NutritionDraftItem(name: displayName, inputMethod: inputMethod,
                                          selection: NutritionMealSelection(foodId: food.id, quantity: count,
                                                                            unit: portion?.unit ?? measure, portionId: portion?.id,
                                                                            language: food.mealInputLanguage(language)),
                                          portionLabel: portion?.displayLabel(language: language), weightG: preview?.weightG,
                                          volumeMl: portion?.volumeMl == nil ? nil : preview?.volumeMl)
            item.logContext = entryPoint.map { NutritionLogContext($0, lastUsed: food.lastUsedSelection) }
            selected(item)
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
            let result = try await model.foodDetail(food.id, language: language)
            try model.needsCurrentAccount()
            detail = result
            favorite = result.favorited ?? food.favorited
            let selection = result.preferredSelection(editing: startingSelection)
            measure = selection.portionId?.uuidString ?? selection.unit
            quantity = NutritionDisplay.editableQuantity(selection.quantity, locale: locale)
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func reportIssue() async {
        guard !reporting, !reported, let api = model.api, let report = food.catalogIssueReport else { return }
        reporting = true
        defer { reporting = false }
        do {
            try model.needsCurrentAccount()
            try await api.postFeedback(report)
            try model.needsCurrentAccount()
            reported = true
        } catch {
            if !error.isCancellation { failure = String(localized: "Could not send the food report. Try again.") }
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
            guard let value = try NutritionServingPreview.parseQuantity(quantity, locale: .current) else {
                throw NutritionInputError.invalidNumber
            }
            var item = NutritionDraftItem(name: created.name, inputMethod: "manual_entry",
                                          selection: .init(foodId: created.id, quantity: value, unit: "g"))
            item.logContext = NutritionLogContext(.privateFood)
            selected(item)
        } catch {
            failure = error.localizedDescription
        }
    }
}
