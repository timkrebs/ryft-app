import Foundation
import Testing
@testable import Ryft

/// Catalog responses from Platform docs/architecture/nutrition/04-api-contracts.md.
enum NutritionCatalogFixtures {
    static let search = """
    {
      "foods":[{"id":"a7e40c6e-bfb4-47eb-ad64-aea61136db03","name":"Hähnchenbrust","brand":"","type":"generic","quality":"source_reported"}],
      "next_offset":null
    }
    """

    static let barcodeMiss = """
    {"gtin":"00012345678905","matches":[],"conflicted":false,"truncated":false}
    """

    static let portion = """
    {
      "label":"Medium apple","labels":{"de":"Mittelgroßer Apfel"},"quantity":1,"unit":"portion",
      "weight_g":150,"estimated":false,"id":"a7e40c6e-bfb4-47eb-ad64-aea61136db04","source_id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01"
    }
    """

    static let detail = """
    {
      "id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01","name":"Apple","brand":"","type":"generic","quality":"source_reported",
      "names":[{"language":"de","label":"Apfel","alias":false}],
      "sources":[{
        "id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01","provider":"ryft","external_id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01",
        "dataset_version":"seed-1","source_url":"","license_identifier":"RYFT"
      }],
      "portions":[\(portion)],
      "nutrients":[{
        "code":"fat","amount":0,"unit":"g","reference_amount":100,"reference_unit":"g",
        "source_id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01","method":"synthetic","quality":"source_reported"
      }]
    }
    """
}

struct NutritionCatalogTests {
    private let decoder = APIClient.jsonDecoder
    private let encoder = APIClient.jsonEncoder

    @Test func searchMatchesAndNullablePagination() throws {
        let fixture = NutritionCatalogFixtures.search
        let page = try decoder.decode(NutritionFoodSearchPage.self, from: Data(fixture.utf8))
        #expect(page.foods.map(\.name) == ["Hähnchenbrust"])
        #expect(page.nextOffset == nil)

        let next = fixture.replacingOccurrences(of: #""next_offset":null"#, with: #""next_offset":20"#)
        #expect(try decoder.decode(NutritionFoodSearchPage.self, from: Data(next.utf8)).nextOffset == 20)
    }

    @Test func barcodeMissPreservesGTINAndAnEmptyMatchList() throws {
        let result = try decoder.decode(NutritionBarcodeResult.self, from: Data(NutritionCatalogFixtures.barcodeMiss.utf8))
        #expect(result.gtin == "00012345678905")
        #expect(result.matches.isEmpty && !result.conflicted && !result.truncated)
    }

    @Test func detailPreservesProvenanceExplicitZerosAndUnknownMeasurements() throws {
        let detail = try decoder.decode(NutritionFoodDetail.self, from: Data(NutritionCatalogFixtures.detail.utf8))
        #expect(detail.names.first?.label == "Apfel")
        let source = try #require(detail.sources.first)
        #expect(source.datasetVersion == "seed-1" && source.licenseIdentifier == "RYFT")
        let portion = try #require(detail.portions.first)
        #expect(portion.sourceId == source.id)
        #expect(portion.labels?["de"] == "Mittelgroßer Apfel")
        #expect(portion.weightG == 150)
        #expect(portion.volumeMl == nil)
        #expect(detail.densityGMl == nil)
        let fat = try #require(detail.nutrients.first)
        #expect(fat.code == "fat" && fat.amount == 0)
        #expect(!detail.nutrients.contains { $0.code == "sodium" })
    }

    @Test func optionalFieldsUseTheAPIWireNames() throws {
        let query = NutritionFoodSearch(query: "apfel", language: "de", market: "DE", limit: 10, offset: 20)
        let body = try encoder.encode(query)
        let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(fields["query"] as? String == "apfel")
        #expect(fields["language"] as? String == "de")
        #expect(fields["market"] as? String == "DE")
        #expect(fields["limit"] as? Int == 10 && fields["offset"] as? Int == 20)

        let barcode = try encoder.encode(NutritionBarcodeQuery(barcode: "012345678905"))
        #expect(try decoder.decode([String: String].self, from: barcode) == ["barcode": "012345678905"])
    }

    @Test func catalogLanguageFollowsAppAndPrefersDachMarkets() {
        let german = NutritionCatalogLocale(locale: Locale(identifier: "en_US"), appLanguage: "de")
        #expect(german.language == "de" && german.market == "DE")
        let swiss = NutritionCatalogLocale(locale: Locale(identifier: "de_CH"), appLanguage: "de")
        #expect(swiss.language == "de" && swiss.market == "CH")
        let english = NutritionCatalogLocale(locale: Locale(identifier: "de_AT"), appLanguage: "en")
        #expect(english.language == "en" && english.market == "AT")
    }

    @Test func householdPreviewUsesCatalogWeightAndKeepsUnknownNutrients() throws {
        let fixture = NutritionCatalogFixtures.detail.replacingOccurrences(
            of: #""code":"fat","amount":0,"unit":"g""#, with: #""code":"energy_kcal","amount":52,"unit":"kcal""#
        )
        let food = try decoder.decode(NutritionFoodDetail.self, from: Data(fixture.utf8))
        let portion = try #require(food.portions.first)
        #expect(food.displayName(language: "de", fallback: "Apple") == "Apfel")
        #expect(portion.displayLabel(language: "de") == "Mittelgroßer Apfel")
        let preview = try #require(NutritionServingPreview(food: food, quantity: 0.5, unit: "portion", portion: portion))
        #expect(preview.weightG == 75 && preview.volumeMl == nil)
        #expect(preview.amounts[.energy] == 39 && preview.amounts[.protein] == nil)
        #expect(NutritionServingPreview(food: food, quantity: 100, unit: "g", portion: nil)?.amounts[.energy] == 52)
        #expect(NutritionServingPreview(food: food, quantity: 100, unit: "ml", portion: nil) == nil)
    }

    @Test func catalogIssueIncludesOnlyPublicIdentifier() throws {
        let page = try decoder.decode(NutritionFoodSearchPage.self, from: Data(NutritionCatalogFixtures.search.utf8))
        let food = try #require(page.foods.first)
        let report = try #require(food.catalogIssueReport)
        let body = try #require(JSONSerialization.jsonObject(with: encoder.encode(report)) as? [String: Any])
        #expect(body["message"] as? String == "Food catalog issue: \(food.id.uuidString.lowercased())")
        #expect(body["category"] as? String == "data")
        #expect(body["request_ids"] as? [String] == [])
        #expect(Set(body.keys) == ["message", "category", "request_ids"])
        let privateFood = NutritionFoodMatch(id: food.id, name: "Private Test Food", brand: "", type: "custom", quality: food.quality)
        #expect(privateFood.catalogIssueReport == nil)
    }

    @Test @MainActor func nutritionFlagsDefaultOffAndSeparateTheDiaryFromThePilot() {
        #expect(FeatureFlag.nutritionEnabled.rawValue == "nutrition.enabled")
        #expect(!FeatureFlag.nutritionEnabled.compiledDefault)
        #expect(FeatureFlag.nutritionDiaryEnabled.rawValue == "nutrition.diary_enabled")
        #expect(StaticFlags().nutritionAccess == .unavailable)
        #expect(StaticFlags([.nutritionDiaryEnabled: true]).nutritionAccess == .diary)
        #expect(StaticFlags([.nutritionEnabled: true]).nutritionAccess == .full)
        #expect(StaticFlags([.nutritionEnabled: true, .nutritionDiaryEnabled: true]).nutritionAccess == .full)
    }
}
