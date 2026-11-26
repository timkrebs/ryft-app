import Foundation
import Testing
@testable import Ryft

/// The landing review of #148: a write that finishes late, Add food's back swipe, Retry save after a refusal, the
/// six-decimal quantity rule, USDA's carbohydrate code and the portion order of a server without `sort_order`.
struct NutritionEditorSafetyTests {
    private let decoder = APIClient.jsonDecoder

    // MARK: a finished write closes only its own editor

    private struct Route: Identifiable, Equatable { let id = UUID() }

    @Test func aWriteThatFinishesAfterBackLeavesTheNextEditorOpen() {
        let a = Route(), b = Route()
        var current: Route? = a
        // Meal A's save is in flight; the user goes Back (A's own Back) and opens meal B.
        NutritionRoutes.close(&current, startedBy: a)
        #expect(current == nil)
        current = b
        // A's delayed response arrives: B stays open with its edits.
        NutritionRoutes.close(&current, startedBy: a)
        #expect(current == b)
        // B's own completion closes B.
        NutritionRoutes.close(&current, startedBy: b)
        #expect(current == nil)
    }

    @Test func coachingRoutesAreOnePerTap() throws {
        let page = try decoder.decode(NutritionFoodSearchPage.self, from: Data(NutritionCatalogFixtures.search.utf8))
        let food = try #require(page.foods.first)
        let first = NutritionSuggestedMealRoute(food: food), second = NutritionSuggestedMealRoute(food: food)
        #expect(first != second, "the same suggested food twice is two editors")
        var current: NutritionSuggestedMealRoute? = second
        NutritionRoutes.close(&current, startedBy: first)
        #expect(current == second)
    }

    // MARK: Add food from a reviewed draft keeps the draft

    @Test func backSwipeIsOffOnlyWhileAddingToAReviewedMeal() {
        #expect(NutritionMealEditor.blocksBackSwipe(isAdding: true, hasReviewed: true))
        #expect(!NutritionMealEditor.blocksBackSwipe(isAdding: true, hasReviewed: false), "the first search: Back leaves")
        #expect(!NutritionMealEditor.blocksBackSwipe(isAdding: false, hasReviewed: true), "the review: Back leaves")
    }

    // MARK: Retry save after a definitive refusal

    private func draft() throws -> NutritionMealWrite {
        NutritionMealWrite(clientRequestId: try #require(UUID(uuidString: "6f1f2b0e-34a8-4d47-9f6a-1d3a7b2c9e01")),
                           consumedAt: Date(timeIntervalSince1970: 1_800_000_000), timezone: "Europe/Berlin",
                           mealType: "lunch", inputMethod: "manual_search", name: "", notes: "",
                           items: [NutritionMealSelection(foodId: UUID(), quantity: 1, unit: "portion", portionId: UUID())])
    }

    @Test(arguments: [400, 404, 413, 422])
    func aDefinitiveRefusalUnfreezesTheRows(_ status: Int) throws {
        let write = try draft()
        #expect(NutritionMealEditor.retainedRequest(write, after: APIError.http(status, "invalid meal")) == nil)
    }

    @Test(arguments: [401, 403, 409, 429, 500, 503])
    func anAmbiguousOrRetryableFailureKeepsTheRequest(_ status: Int) throws {
        let write = try draft()
        #expect(NutritionMealEditor.retainedRequest(write, after: APIError.http(status, "")) == write)
    }

    @Test func offlineAndTimeoutKeepTheRequestAndItsID() throws {
        let write = try draft()
        #expect(NutritionMealEditor.retainedRequest(write, after: NutritionInputError.offline) == write)
        #expect(NutritionMealEditor.retainedRequest(write, after: URLError(.timedOut))?.clientRequestId == write.clientRequestId)
    }

    // MARK: six decimals, one rule

    @Test func quantitiesFollowTheSixDecimalRule() throws {
        let german = Locale(identifier: "de_DE")
        #expect(try NutritionServingPreview.parseQuantity("0,333333", locale: german) == 0.333333)
        #expect(try NutritionServingPreview.parseQuantity("1,5", locale: german) == 1.5)
        #expect(try NutritionServingPreview.parseQuantity("", locale: german) == nil)
        #expect(throws: NutritionInputError.self) { try NutritionServingPreview.parseQuantity("0,3333333", locale: german) }
        #expect(throws: NutritionInputError.self) { try NutritionServingPreview.parseQuantity("0.0000001", locale: Locale(identifier: "en_US")) }
        #expect(NutritionServingPreview.isValidQuantity(100_000) && NutritionServingPreview.isValidQuantity(0.000_001))
        #expect(!NutritionServingPreview.isValidQuantity(1.0 / 3.0))
        #expect(!NutritionServingPreview.isValidQuantity(.nan) && !NutritionServingPreview.isValidQuantity(100_000.5))

        let food = try decoder.decode(NutritionFoodDetail.self, from: Data(NutritionCatalogFixtures.detail.utf8))
        let portion = try #require(food.portions.first)
        #expect(NutritionServingPreview(food: food, quantity: 1.0 / 3.0, unit: "portion", portion: portion) == nil)
        #expect(NutritionServingPreview(food: food, quantity: 0.333333, unit: "portion", portion: portion) != nil)
        #expect(!NutritionCatalogSelection(portionId: portion.id, quantity: 1.0 / 3.0, unit: "portion").isSupported,
                "quick add never reuses a selection the API would refuse")

        let fine = NutritionMealSelection(foodId: food.id, quantity: 0.333333, unit: "portion", portionId: portion.id)
        var tooFine = fine
        tooFine.quantity = 0.3333333
        #expect(NutritionMealEditor.writableQuantities([fine]))
        #expect(!NutritionMealEditor.writableQuantities([fine, tooFine]))
        #expect(throws: NutritionInputError.self, "nine decimals as typed") {
            try NutritionServingPreview.parseQuantity("1,000000001", locale: german)
        }
        // An untouched saved row goes out as its item_id only: its stored quantity never blocks a save.
        let stored = NutritionDraftItem(name: "Apfel", inputMethod: "manual_entry",
                                        selection: NutritionMealSelection(itemId: UUID(), foodId: food.id, quantity: 0.3333333,
                                                                          unit: "portion", portionId: portion.id))
        #expect(NutritionMealEditor.writableQuantities([stored.request]))
        #expect(!NutritionMealEditor.writableQuantities([stored.selection]))
    }

    // MARK: USDA carbohydrates

    @Test func usdaCarbohydratesTotalReachTheLivePreview() throws {
        let banana = """
        {
          "id":"b1c2d3e4-0000-4000-8000-000000000001","name":"Banana, raw","brand":"","type":"generic","quality":"verified",
          "names":[],
          "sources":[{
            "id":"b1c2d3e4-0000-4000-8000-000000000002","provider":"usda_fdc","external_id":"173944",
            "dataset_version":"fixture","source_url":"","license_identifier":"CC0-1.0"
          }],
          "portions":[{
            "id":"b1c2d3e4-0000-4000-8000-000000000003","source_id":"b1c2d3e4-0000-4000-8000-000000000002",
            "label":"Medium banana","quantity":1,"unit":"portion","weight_g":118,"estimated":false
          }],
          "nutrients":[
            {"code":"energy_kcal","amount":89,"unit":"kcal","reference_amount":100,"reference_unit":"g",
             "source_id":"b1c2d3e4-0000-4000-8000-000000000002","method":"analytical","quality":"verified"},
            {"code":"carbohydrates_total","amount":22.84,"unit":"g","reference_amount":100,"reference_unit":"g",
             "source_id":"b1c2d3e4-0000-4000-8000-000000000002","method":"analytical","quality":"verified"}
          ]
        }
        """
        let food = try decoder.decode(NutritionFoodDetail.self, from: Data(banana.utf8))
        let portion = try #require(food.portions.first)
        let half = try #require(NutritionServingPreview(food: food, quantity: 0.5, unit: "portion", portion: portion))
        #expect(half.weightG == 59)
        let carbs = try #require(half.amounts[.carbs], "carbohydrates_total counts as carbohydrates")
        #expect(abs(carbs - 22.84 * 59 / 100) < 1e-9)
        #expect(abs((half.amounts[.energy] ?? 0) - 89 * 59 / 100) < 1e-9)
        #expect(NutritionNutrient(catalogCode: "carbohydrates_total") == .carbs)
        #expect(NutritionNutrient(catalogCode: "carbohydrates") == .carbs && NutritionNutrient(catalogCode: "fat") == .fat)
    }

    // MARK: a server without sort_order

    @Test func portionsWithoutSortOrderKeepTheServersOrderAndDefault() throws {
        let legacy = """
        [{"id":"a7e40c6e-bfb4-47eb-ad64-aea61136db04","source_id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01",
          "label":"Medium apple","quantity":1,"unit":"portion","estimated":false,"weight_g":182},
         {"id":"a7e40c6e-bfb4-47eb-ad64-aea61136db05","source_id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01",
          "label":"Small apple","quantity":1,"unit":"portion","estimated":false,"weight_g":149},
         {"id":"a7e40c6e-bfb4-47eb-ad64-aea61136db06","source_id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01",
          "label":"Large apple","quantity":1,"unit":"portion","estimated":false,"weight_g":223}]
        """
        let json = NutritionCatalogFixtures.detail.replacingOccurrences(of: "[\(NutritionCatalogFixtures.portion)]", with: legacy)
        let food = try decoder.decode(NutritionFoodDetail.self, from: Data(json.utf8))
        #expect(food.sortedPortions.map(\.weightG) == [182, 149, 223], "the server's order, not the English label's")
        #expect(food.preferredSelection().portionId == food.portions[0].id, "the first measured portion, as before")
    }
}
