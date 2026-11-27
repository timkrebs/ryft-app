#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// A simulator-only path through the real Nutrition views and API client.
struct NutritionSimulatorView: View {
    @State private var state = AppState(env: Self.makeEnvironment())

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("-RyftNutritionQuickLog") {
            RootTabs().previewEnvironment(state)
        } else {
            NavigationStack { NutritionEntryView() }
                .environment(state)
                .environment(\.appEnvironment, state.env)
        }
    }

    @MainActor
    private static func makeEnvironment() -> AppEnvironment {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NutritionSimulatorProtocol.self]
        let defaults = UserDefaults(suiteName: "ryft.nutrition.simulator") ?? .standard
        defaults.set(true, forKey: CoachMarks.doneKey)
        let settings = Settings(defaults: defaults)
        let api = APIClient(session: URLSession(configuration: config), tokens: NutritionSimulatorToken(),
                            baseURL: URL(string: "https://nutrition.fixture.invalid"), status: APIStatus(), settings: settings)
        let auth = AuthService.preview()
        let account = auth.accountID ?? "nutrition-fixture"
        let diaryOnly = ProcessInfo.processInfo.arguments.contains("-RyftNutritionDiaryOnly")
        let env = AppEnvironment(settings: settings, health: MockHealthStore(), liveAPI: api, demoAPI: MockPlatformAPI(), auth: auth,
                                 persistence: TrainStore(inMemory: true),
                                 clock: TestClock(now: Date(timeIntervalSince1970: 1_795_533_600.125)),
                                 notifier: MockNotifier(), flags: StaticFlags(diaryOnly ? [.nutritionDiaryEnabled: true] : [.nutritionEnabled: true]),
                                 connectivity: .preview(online: true), defaults: defaults, demoOverride: false)
        if ProcessInfo.processInfo.arguments.contains("-RyftNutritionPendingMeal"),
           let foodID = UUID(uuidString: NutritionSimulatorProtocol.foodID) {
            let draft = NutritionMealWrite(clientRequestId: UUID(), consumedAt: env.clock.now(), timezone: "UTC",
                                           mealType: "snack", inputMethod: "manual_search", name: "Apple snack", notes: "",
                                           items: [NutritionMealSelection(foodId: foodID, quantity: 100, unit: "g")])
            env.accountDocuments?.saveDocument(draft, key: "nutrition.pending.\(account)", at: draft.consumedAt)
        }
        return env
    }
}

private final class NutritionSimulatorToken: AccessTokenProvider, Sendable {
    func accessToken() async throws -> String { "nutrition-fixture" }
    func refreshedAccessToken() async throws -> String { "nutrition-fixture" }
    func rejectedAfterRefresh() async {}
}

private final class NutritionSimulatorProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var loggedMeal: String?

    static let foodID = "a7e40c6e-bfb4-47eb-ad64-aea61136db01"
    private static let juiceID = "a7e40c6e-bfb4-47eb-ad64-aea61136db02"
    private static let unmeasuredID = "a7e40c6e-bfb4-47eb-ad64-aea61136db03"
    private struct ApplePortion: Sendable {
        let id: String
        let en: String
        let de: String
        let deLabel: String
        let weight: Double
        let priority: Int
    }
    private static let apples = [
        ApplePortion(id: "a7e40c6e-bfb4-47eb-ad64-aea61136db06", en: "Large", de: "Groß", deLabel: "Großer Apfel", weight: 223, priority: 30),
        ApplePortion(id: "a7e40c6e-bfb4-47eb-ad64-aea61136db05", en: "Small", de: "Klein", deLabel: "Kleiner Apfel", weight: 149, priority: 10),
        ApplePortion(id: "a7e40c6e-bfb4-47eb-ad64-aea61136db04", en: "Medium", de: "Mittel", deLabel: "Mittelgroßer Apfel", weight: 182, priority: 20),
    ]
    private static let medium = apples[2]
    private static let jsonDay = """
    {"local_date":"2026-11-24","meal_count":1,"item_count":2,"nutrients":{
      "energy_kcal":{"known_subtotal":540,"unit":"kcal","known_items":1,"complete_for_logged_items":false},
      "protein":{"known_subtotal":28,"unit":"g","known_items":2,"complete_for_logged_items":true},
      "carbohydrates":{"known_subtotal":72,"unit":"g","known_items":2,"complete_for_logged_items":true},
      "fat":{"known_subtotal":16,"unit":"g","known_items":2,"complete_for_logged_items":true},
      "fiber":{"known_subtotal":10,"unit":"g","known_items":2,"complete_for_logged_items":true}},
     "score_version":"1.0.0","nutrition_score":null,"quality_score":null,"glucose_score":null,
     "breakdown":{"fiber_g":3.3,"whole_fruit_g":7.5,"sodium_mg":null},"meal_glucose_scores":[],"chrononutrition_penalty":0}
    """
    private static let mealHeader = """
    {"id":"ea0ac98d-9c71-410d-ac6a-61ce6f97f092","client_request_id":"9d94e3ec-e873-43d5-8887-86913a60fca8",
     "consumed_at":"2026-11-24T10:00:00Z","timezone":"UTC","local_date":"2026-11-24","meal_type":"snack",
     "input_method":"manual_search","name":"Apple snack","notes":"","revision":1,
    """

    override static func canInit(with request: URLRequest) -> Bool { request.url?.host == "nutrition.fixture.invalid" }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let german = request.value(forHTTPHeaderField: "Accept-Language") == "de"
        let (status, body) = Self.response(path: url.path, method: request.httpMethod, german: german,
                                           requestBody: Self.body(of: request))
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data? {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 2_048)
        var data = Data()
        while stream.hasBytesAvailable && data.count < 65_536 {
            let count = stream.read(&bytes, maxLength: bytes.count)
            guard count > 0 else { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return data
    }

    private static func selection(_ apple: ApplePortion, german: Bool) -> String {
        let label = german ? apple.deLabel : "\(apple.en) apple"
        return """
        {"portion_id":"\(apple.id)","quantity":1,"unit":"portion","short_label":"\(german ? apple.de : apple.en)",
         "label":"\(label)","gram_weight":\(apple.weight),"kcal":\(apple.weight * 0.52),"protein_g":\(apple.weight * 0.0026)}
        """
    }

    private static func appleDetail(german: Bool, retiredLarge: Bool) -> String {
        let portionRows = apples.filter { !retiredLarge || $0.en != "Large" }.map { apple in
            """
            {"id":"\(apple.id)","source_id":"\(foodID)","label":"\(apple.en) apple",
             "labels":{"de":"\(apple.deLabel)"},"quantity":1,"unit":"portion","weight_g":\(apple.weight),
             "estimated":false,"portion_key":"\(apple.en.lowercased())","short_label_en":"\(apple.en)",
             "short_label_de":"\(apple.de)","is_default":\(apple.en == "Medium"),"sort_order":\(apple.priority)}
            """
        }
        let nutrients = [("energy_kcal", 52.0, "kcal"), ("protein", 0.26, "g"), ("carbohydrates", 13.81, "g"), ("fat", 0.17, "g")].map { code, amount, unit in
            """
            {"code":"\(code)","amount":\(amount),"unit":"\(unit)","reference_amount":100,"reference_unit":"g",
             "source_id":"\(foodID)","method":"synthetic","quality":"source_reported"}
            """
        }.joined(separator: ",")
        return """
        {"id":"\(foodID)","name":"Apple","brand":"","type":"generic","quality":"source_reported",
         "subtitle":"\(german ? "Roh, mit Schale" : "Raw, with skin")",
         "names":[{"language":"de","label":"Apfel","alias":false}],"sources":[],
         "default_portion":\(selection(medium, german: german)),"portions":[\(portionRows.joined(separator: ","))],
         "nutrients":[\(nutrients)]}
        """
    }

    private static func savedMeal(_ body: Data?) -> String? {
        guard let body, let write = try? APIClient.jsonDecoder.decode(NutritionMealWrite.self, from: body) else { return nil }
        let items = write.items.compactMap { request -> [String: Any]? in
            guard let id = request.foodId, let quantity = request.quantity, let unit = request.unit else { return nil }
            let apple = apples.first { $0.id == request.portionId?.uuidString.lowercased() }
            let isGerman = request.language == "de"
            let name = id.uuidString.lowercased() == juiceID ? "Apple Juice" : isGerman ? "Apfel" : "Apple"
            var item: [String: Any] = ["id": UUID().uuidString, "food_id": id.uuidString, "food_name": name,
                                       "brand": "", "quantity": quantity, "unit": unit, "nutrients": [:]]
            if let apple {
                item["portion_id"] = apple.id
                item["portion_label"] = isGerman ? apple.deLabel : "\(apple.en) apple"
                item["portion_short_label"] = isGerman ? apple.de : apple.en
                item["weight_g"] = quantity * apple.weight
            } else if unit == "g" {
                item["weight_g"] = quantity
            }
            return item
        }
        guard items.count == write.items.count,
              let json = try? JSONSerialization.data(withJSONObject: items) else { return nil }
        return mealHeader + "\"items\":" + String(decoding: json, as: UTF8.self) + "}"
    }

    private static func response(path: String, method: String?, german: Bool, requestBody: Data?) -> (Int, String) {
        switch (method, path) {
        case ("GET", "/v1/nutrition/daily"):
            return (200, jsonDay)
        case ("GET", "/v1/nutrition/meals"):
            return (200, "{\"meals\":[\(lock.withLock { loggedMeal } ?? "")],\"next_offset\":null}")
        case ("POST", "/v1/nutrition/meals"):
            guard let meal = savedMeal(requestBody) else { return (422, "{\"error\":\"fixture could not read the meal\"}") }
            lock.withLock { loggedMeal = meal }
            return (201, meal)
        case ("POST", "/v1/nutrition/foods/search"):
            let name = german ? "Apfel" : "Apple"
            let data = requestBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let query = (data?["query"] as? String ?? "").lowercased()
            if query.hasPrefix("ka") {
                return (200, """
                {"foods":[{"id":"\(unmeasuredID)","name":"\(german ? "Kakaopulver" : "Cocoa powder")","brand":"","type":"generic","quality":"source_reported",
                 "reference_portion":{"quantity":100,"unit":"g","kcal":228}}],"next_offset":null}
                """)
            }
            guard ["apfel", "apple"].contains(where: { $0.hasPrefix(query) }) else {
                return (200, "{\"foods\":[],\"next_offset\":null}")
            }
            return (200, """
            {"foods":[{"id":"\(foodID)","name":"\(name)","brand":"","type":"generic","quality":"source_reported",
              "default_portion":\(selection(medium, german: german))},
             {"id":"\(juiceID)","name":"Apple Juice","brand":"","type":"generic","quality":"source_reported",
              "default_portion":{"quantity":200,"unit":"ml","volume_ml":200,"kcal":92}}],"next_offset":null}
            """)
        case ("GET", "/v1/nutrition/foods/\(foodID)"):
            let wasSaved = lock.withLock { loggedMeal != nil }
            return (200, appleDetail(german: german, retiredLarge: wasSaved))
        case ("GET", "/v1/nutrition/foods/\(unmeasuredID)"):
            return (200, """
            {"id":"\(unmeasuredID)","name":"Cocoa powder","brand":"","type":"generic","quality":"source_reported",
             "names":[],"sources":[],"portions":[],"nutrients":[]}
            """)
        default:
            return (404, "{\"error\":\"fixture route unavailable\"}")
        }
    }
}
#endif
