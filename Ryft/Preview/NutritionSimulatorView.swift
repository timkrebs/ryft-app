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
    nonisolated(unsafe) private static var logged = false

    static let foodID = "a7e40c6e-bfb4-47eb-ad64-aea61136db01"
    private static let portionID = "a7e40c6e-bfb4-47eb-ad64-aea61136db04"
    private static let food = #"{"id":"\#(foodID)","name":"Apple","brand":"","type":"generic","quality":"source_reported"}"#
    private static let juice = #"{"id":"a7e40c6e-bfb4-47eb-ad64-aea61136db02","name":"Apple Juice","brand":"","type":"generic","quality":"source_reported"}"#
    private static let germanFood = #"{"id":"\#(foodID)","name":"Apfel","brand":"","type":"generic","quality":"source_reported"}"#
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
    private static let meal = """
    {"id":"ea0ac98d-9c71-410d-ac6a-61ce6f97f092","client_request_id":"9d94e3ec-e873-43d5-8887-86913a60fca8",
     "consumed_at":"2026-11-24T10:00:00Z","timezone":"UTC","local_date":"2026-11-24","meal_type":"snack",
     "input_method":"manual_search","name":"Apple snack","notes":"","revision":1,
     "items":[{"id":"63cf1226-48cf-43c7-957e-c994ec3bbe61","food_id":"\(foodID)","food_name":"Apple","brand":"",
               "quantity":100,"unit":"g","nutrients":{}}]}
    """

    override static func canInit(with request: URLRequest) -> Bool { request.url?.host == "nutrition.fixture.invalid" }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let german = request.value(forHTTPHeaderField: "Accept-Language") == "de"
        let (status, body) = Self.response(path: url.path, method: request.httpMethod, german: german)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func response(path: String, method: String?, german: Bool) -> (Int, String) {
        switch (method, path) {
        case ("GET", "/v1/nutrition/daily"):
            return (200, jsonDay)
        case ("GET", "/v1/nutrition/meals"):
            return (200, "{\"meals\":[\(lock.withLock { logged } ? meal : "")],\"next_offset\":null}")
        case ("POST", "/v1/nutrition/meals"):
            lock.withLock { logged = true }
            return (201, meal)
        case ("POST", "/v1/nutrition/foods/search"):
            return (200, "{\"foods\":[\(german ? germanFood : food),\(juice)],\"next_offset\":null}")
        case ("GET", "/v1/nutrition/foods/\(foodID)"):
            return (200, """
            {"id":"\(foodID)","name":"Apple","brand":"","type":"generic","quality":"source_reported",
             "names":[{"language":"de","label":"Apfel","alias":false}],"sources":[],
             "portions":[{"id":"\(portionID)","source_id":"\(foodID)","label":"Medium apple",
              "labels":{"de":"Mittelgroßer Apfel"},"quantity":1,"unit":"portion","weight_g":150,"estimated":false}],
             "nutrients":[{"code":"energy_kcal","amount":52,"unit":"kcal","reference_amount":100,"reference_unit":"g",
              "source_id":"\(foodID)","method":"synthetic","quality":"source_reported"}]}
            """)
        default:
            return (404, "{\"error\":\"fixture route unavailable\"}")
        }
    }
}
#endif
