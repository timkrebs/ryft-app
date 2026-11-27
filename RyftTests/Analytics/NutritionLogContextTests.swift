import Foundation
import Testing
@testable import Ryft

private enum LogFixture {
    static let portionA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let portionB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    static let food = UUID(uuidString: "00000000-0000-0000-0000-0000000000F0")!
}

/// A selection and the last-used one of its food, with the unit mode the event must carry.
struct NutritionUnitModeRow: Sendable, CustomTestStringConvertible {
    let why: String
    let selection: NutritionMealSelection
    let lastUsed: NutritionCatalogSelection?
    let expected: AnalyticsUnitMode
    var testDescription: String { why }

    private static let a = LogFixture.portionA
    private static let b = LogFixture.portionB

    private static func selection(quantity: Double?, unit: String?, portion: UUID? = nil) -> NutritionMealSelection {
        NutritionMealSelection(foodId: LogFixture.food, quantity: quantity, unit: unit, portionId: portion)
    }

    static let all: [NutritionUnitModeRow] = [
        NutritionUnitModeRow(why: "portion, unit and quantity equal the last-used one",
                             selection: selection(quantity: 1, unit: "portion", portion: a),
                             lastUsed: NutritionCatalogSelection(portionId: a, quantity: 1, unit: "portion"),
                             expected: .lastUsedPortion),
        NutritionUnitModeRow(why: "the same portion in another quantity",
                             selection: selection(quantity: 2, unit: "portion", portion: a),
                             lastUsed: NutritionCatalogSelection(portionId: a, quantity: 1, unit: "portion"),
                             expected: .curatedPortion),
        NutritionUnitModeRow(why: "a fraction of the last-used portion",
                             selection: selection(quantity: 0.5, unit: "portion", portion: a),
                             lastUsed: NutritionCatalogSelection(portionId: a, quantity: 1, unit: "portion"),
                             expected: .curatedPortion),
        NutritionUnitModeRow(why: "another portion than the last-used one",
                             selection: selection(quantity: 1, unit: "portion", portion: b),
                             lastUsed: NutritionCatalogSelection(portionId: a, quantity: 1, unit: "portion"),
                             expected: .curatedPortion),
        NutritionUnitModeRow(why: "a portion and no last-used selection",
                             selection: selection(quantity: 1, unit: "portion", portion: a), lastUsed: nil,
                             expected: .curatedPortion),
        NutritionUnitModeRow(why: "a serving with a portion id and no last-used selection",
                             selection: selection(quantity: 1, unit: "serving", portion: a), lastUsed: nil,
                             expected: .curatedPortion),
        NutritionUnitModeRow(why: "grams, no last-used selection",
                             selection: selection(quantity: 150, unit: "g"), lastUsed: nil, expected: .grams),
        NutritionUnitModeRow(why: "millilitres, no last-used selection",
                             selection: selection(quantity: 250, unit: "ml"), lastUsed: nil, expected: .ml),
        NutritionUnitModeRow(why: "grams equal to a last-used grams amount",
                             selection: selection(quantity: 150, unit: "g"),
                             lastUsed: NutritionCatalogSelection(quantity: 150, unit: "g"), expected: .lastUsedPortion),
        NutritionUnitModeRow(why: "millilitres equal to a last-used millilitre amount",
                             selection: selection(quantity: 250, unit: "ml"),
                             lastUsed: NutritionCatalogSelection(quantity: 250, unit: "ml"), expected: .lastUsedPortion),
        NutritionUnitModeRow(why: "grams in another quantity than the last-used grams",
                             selection: selection(quantity: 100, unit: "g"),
                             lastUsed: NutritionCatalogSelection(quantity: 150, unit: "g"), expected: .grams),
        NutritionUnitModeRow(why: "millilitres where the last-used amount was grams",
                             selection: selection(quantity: 150, unit: "ml"),
                             lastUsed: NutritionCatalogSelection(quantity: 150, unit: "g"), expected: .ml),
        NutritionUnitModeRow(why: "no quantity yet is not the last-used one",
                             selection: selection(quantity: nil, unit: "g"),
                             lastUsed: NutritionCatalogSelection(quantity: 150, unit: "g"), expected: .grams),
        NutritionUnitModeRow(why: "no unit and no portion is grams", selection: selection(quantity: 100, unit: nil),
                             lastUsed: nil, expected: .grams),
    ]
}

struct NutritionFractionRow: Sendable, CustomTestStringConvertible {
    let quantity: Double?
    let unit: String?
    let expected: Bool
    var testDescription: String { "\(quantity.map { "\($0)" } ?? "nil") \(unit ?? "nil") -> \(expected)" }

    static let all: [NutritionFractionRow] = [
        NutritionFractionRow(quantity: 0.5, unit: "portion", expected: true),
        NutritionFractionRow(quantity: 1, unit: "portion", expected: false),
        NutritionFractionRow(quantity: 1.5, unit: "portion", expected: true),
        NutritionFractionRow(quantity: 0.25, unit: "portion", expected: true),
        NutritionFractionRow(quantity: 3, unit: "portion", expected: false),
        NutritionFractionRow(quantity: 2, unit: "serving", expected: false),
        NutritionFractionRow(quantity: 0.5, unit: "serving", expected: true),
        NutritionFractionRow(quantity: 12.5, unit: "g", expected: false),
        NutritionFractionRow(quantity: 150, unit: "g", expected: false),
        NutritionFractionRow(quantity: 12.5, unit: "ml", expected: false),
        NutritionFractionRow(quantity: nil, unit: "portion", expected: false),
        NutritionFractionRow(quantity: 1.5, unit: nil, expected: false),
        NutritionFractionRow(quantity: .nan, unit: "portion", expected: false),
        NutritionFractionRow(quantity: .infinity, unit: "portion", expected: false),
    ]
}

struct NutritionOpenedRow: Sendable, CustomTestStringConvertible {
    let type: String
    let hasDefault: Bool
    let hasLastUsed: Bool
    let rank: Int
    let expected: [String: String]
    var testDescription: String { "\(type), default \(hasDefault), last used \(hasLastUsed), rank \(rank)" }

    private static func row(_ type: String, default hasDefault: Bool = false, lastUsed: Bool = false, rank: Int = 1,
                            _ rankToken: String, staple: Bool) -> NutritionOpenedRow {
        func word(_ value: Bool) -> String { value ? "true" : "false" }
        return NutritionOpenedRow(type: type, hasDefault: hasDefault, hasLastUsed: lastUsed, rank: rank, expected: [
            "rank_position": rankToken, "is_canonical_staple": word(staple), "has_default_portion": word(hasDefault),
            "has_last_used_portion": word(lastUsed),
        ])
    }

    static let all: [NutritionOpenedRow] = [
        row("generic", "1", staple: true),
        row("branded", "1", staple: false),
        row("custom", "1", staple: false),
        row("generic", default: true, "1", staple: true),
        row("generic", lastUsed: true, "1", staple: true),
        row("branded", default: true, lastUsed: true, "1", staple: false),
        row("generic", rank: 2, "2", staple: true),
        row("generic", rank: 10, "10", staple: true),
        row("generic", rank: 11, "10+", staple: true),
        row("branded", rank: 1000, "10+", staple: false),
        row("generic", rank: 0, "1", staple: true),
    ]
}

@Suite("Analytics: nutrition log context")
@MainActor
struct NutritionLogContextTests {
    // MARK: helpers

    private func match(type: String, defaultPortion: Bool, lastUsed: Bool) -> NutritionFoodMatch {
        var food = NutritionFoodMatch(id: UUID(), name: "Food A", brand: "", type: type, quality: "high")
        if defaultPortion { food.defaultPortion = NutritionCatalogSelection(portionId: LogFixture.portionA, quantity: 1, unit: "portion") }
        if lastUsed { food.lastUsedPortion = NutritionCatalogSelection(quantity: 150, unit: "g") }
        return food
    }

    private func item(_ entry: AnalyticsNutritionEntryPoint?, quantity: Double? = 100, unit: String? = "g",
                      portion: UUID? = nil, lastUsed: NutritionCatalogSelection? = nil) -> NutritionDraftItem {
        var item = NutritionDraftItem(
            name: "Food A", inputMethod: "search",
            selection: NutritionMealSelection(foodId: LogFixture.food, quantity: quantity, unit: unit, portionId: portion))
        item.logContext = entry.map { NutritionLogContext($0, lastUsed: lastUsed) }
        return item
    }

    // MARK: unit mode and fraction

    @Test(arguments: NutritionUnitModeRow.all)
    func unitMode(_ row: NutritionUnitModeRow) {
        #expect(NutritionLogContext.unitMode(row.selection, lastUsed: row.lastUsed) == row.expected)
    }

    @Test(arguments: NutritionFractionRow.all)
    func isFractional(_ row: NutritionFractionRow) {
        let selection = NutritionMealSelection(foodId: LogFixture.food, quantity: row.quantity, unit: row.unit)
        #expect(NutritionLogContext.isFractional(selection) == row.expected)
    }

    @Test func theEventCarriesTheEntryPointTheModeAndTheFraction() {
        let context = NutritionLogContext(.detailSheet, lastUsed: nil)
        let selection = NutritionMealSelection(foodId: LogFixture.food, quantity: 1.5, unit: "portion",
                                               portionId: LogFixture.portionA)
        #expect(context.event(for: selection)
            == .nutritionFoodLogged(entryPoint: .detailSheet, unitMode: .curatedPortion, isFractional: true))
        #expect(context.event(for: selection).properties == [
            "entry_point": "detail_sheet", "unit_mode": "curated_portion", "is_fractional": "true",
        ])
    }

    @Test func theEventFollowsTheAmountTheMealIsSavedWith() {
        let lastUsed = NutritionCatalogSelection(quantity: 150, unit: "g")
        let context = NutritionLogContext(.quickAddButton, lastUsed: lastUsed)
        let first = NutritionMealSelection(foodId: LogFixture.food, quantity: 150, unit: "g")
        let edited = NutritionMealSelection(foodId: LogFixture.food, quantity: 200, unit: "g")
        #expect(context.event(for: first).properties["unit_mode"] == "last_used_portion")
        #expect(context.event(for: edited).properties["unit_mode"] == "grams")
    }

    @Test func aContextHoldsNothingButTheEntryPointAndTheLastUsedSelection() {
        // Nothing of the food reaches an event: the whole context is two fields.
        #expect(Mirror(reflecting: NutritionLogContext(.suggestion)).children.map { $0.label } == ["entryPoint", "lastUsed"])
    }

    // MARK: nutrition_food_opened

    @Test(arguments: NutritionOpenedRow.all)
    func openedEvent(_ row: NutritionOpenedRow) {
        let event = match(type: row.type, defaultPortion: row.hasDefault, lastUsed: row.hasLastUsed).openedEvent(rank: row.rank)
        #expect(event.name == "nutrition_food_opened")
        #expect(event.properties == row.expected)
    }

    @Test func theOpenedEventCarriesNothingOfTheFood() {
        let event = match(type: "generic", defaultPortion: true, lastUsed: true).openedEvent(rank: 3)
        for value in event.properties.values {
            #expect(!value.contains("Food A"))
        }
        #expect(Set(event.properties.keys) == ["rank_position", "is_canonical_staple", "has_default_portion", "has_last_used_portion"])
    }

    // MARK: loggedEvents

    @Test func threeQuickAddedGramItemsAreOneEvent() {
        let items = [item(.quickAddButton), item(.quickAddButton, quantity: 250), item(.quickAddButton, quantity: 30)]
        #expect(NutritionLogContext.loggedEvents(items)
            == [.nutritionFoodLogged(entryPoint: .quickAddButton, unitMode: .grams, isFractional: false)])
    }

    @Test func itemsWithoutAContextLogNothing() {
        #expect(NutritionLogContext.loggedEvents([item(nil), item(nil, quantity: 2, unit: "portion")]).isEmpty)
        #expect(NutritionLogContext.loggedEvents([]).isEmpty)
    }

    @Test func aRowLoadedFromASavedMealIsSkippedBesideNewOnes() {
        let events = NutritionLogContext.loggedEvents([item(nil), item(.barcode), item(nil)])
        #expect(events == [.nutritionFoodLogged(entryPoint: .barcode, unitMode: .grams, isFractional: false)])
    }

    @Test func twoEntryPointsAreTwoEventsInFirstSeenOrder() {
        let barcodeFirst = NutritionLogContext.loggedEvents([item(.barcode), item(.suggestion)])
        #expect(barcodeFirst == [
            .nutritionFoodLogged(entryPoint: .barcode, unitMode: .grams, isFractional: false),
            .nutritionFoodLogged(entryPoint: .suggestion, unitMode: .grams, isFractional: false),
        ])
        let suggestionFirst = NutritionLogContext.loggedEvents([item(.suggestion), item(.barcode)])
        #expect(suggestionFirst == Array(barcodeFirst.reversed()))
    }

    @Test func aRepeatedCombinationKeepsItsFirstPlace() {
        let events = NutritionLogContext.loggedEvents([item(.barcode), item(.suggestion), item(.barcode, quantity: 5)])
        #expect(events.map(\.properties["entry_point"]) == ["barcode", "suggestion"])
    }

    @Test func aDifferentUnitModeOrFractionIsAnotherEvent() {
        let portion = LogFixture.portionA
        let events = NutritionLogContext.loggedEvents([
            item(.detailSheet),
            item(.detailSheet, quantity: 250, unit: "ml"),
            item(.detailSheet, quantity: 1, unit: "portion", portion: portion),
            item(.detailSheet, quantity: 0.5, unit: "portion", portion: portion),
            item(.detailSheet, quantity: 2, unit: "portion", portion: portion),
        ])
        #expect(events == [
            .nutritionFoodLogged(entryPoint: .detailSheet, unitMode: .grams, isFractional: false),
            .nutritionFoodLogged(entryPoint: .detailSheet, unitMode: .ml, isFractional: false),
            .nutritionFoodLogged(entryPoint: .detailSheet, unitMode: .curatedPortion, isFractional: false),
            .nutritionFoodLogged(entryPoint: .detailSheet, unitMode: .curatedPortion, isFractional: true),
        ])
    }

    @Test func theLastUsedSelectionOfTheItemDecidesItsMode() {
        let lastUsed = NutritionCatalogSelection(quantity: 150, unit: "g")
        let events = NutritionLogContext.loggedEvents([
            item(.quickAddButton, quantity: 150, lastUsed: lastUsed), item(.quickAddButton, quantity: 100, lastUsed: lastUsed),
        ])
        #expect(events == [
            .nutritionFoodLogged(entryPoint: .quickAddButton, unitMode: .lastUsedPortion, isFractional: false),
            .nutritionFoodLogged(entryPoint: .quickAddButton, unitMode: .grams, isFractional: false),
        ])
    }

    @Test func everyLoggedEventPassesTheCatalogue() {
        let items = [item(.quickAddButton), item(.privateFood, quantity: 250, unit: "ml"),
                     item(.detailSheet, quantity: 1.5, unit: "portion", portion: LogFixture.portionA)]
        for event in NutritionLogContext.loggedEvents(items) {
            #expect(AnalyticsCatalog.check(name: event.name, properties: event.properties) == nil, "\(event)")
        }
    }
}
