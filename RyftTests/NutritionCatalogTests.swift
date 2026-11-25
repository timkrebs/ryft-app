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

    @Test func nutritionFlagDefaultsOff() {
        #expect(FeatureFlag.nutritionEnabled.rawValue == "nutrition.enabled")
        #expect(!FeatureFlag.nutritionEnabled.compiledDefault)
    }
}
