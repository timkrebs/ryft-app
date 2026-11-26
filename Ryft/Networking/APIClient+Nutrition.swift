import Foundation

extension APIClient {
    /// Catalog entry points use either the diary flag or the full Nutrition pilot before calling the API.
    func searchNutritionFoods(_ query: NutritionFoodSearch) async throws -> NutritionFoodSearchPage {
        try await Self.$singleAttempt.withValue(true) {
            try Task.checkCancellation()
            return try await send("POST", path: "/v1/nutrition/foods/search", body: query)
        }
    }

    func lookupNutritionBarcode(_ query: NutritionBarcodeQuery) async throws -> NutritionBarcodeResult {
        try await send("POST", path: "/v1/nutrition/foods/barcode", body: query)
    }

    func nutritionFood(id: UUID) async throws -> NutritionFoodDetail {
        try await send("GET", path: "/v1/nutrition/foods/\(id.uuidString.lowercased())", body: Optional<Int>.none)
    }

    func nutritionFoodPortions(id: UUID) async throws -> [NutritionFoodPortion] {
        try await send("GET", path: "/v1/nutrition/foods/\(id.uuidString.lowercased())/portions", body: Optional<Int>.none)
    }
}

extension APIClient {
    /// Access to the account's saved meal diary, including after health consent is withdrawn.
    func nutritionMealExport(after cursor: UUID?) async throws -> NutritionMealExportPage {
        let limit = NutritionMealExportPage.pageSize
        let after = cursor.map { "&after=\($0.uuidString.lowercased())" } ?? ""
        return try await send("GET", path: "/v1/me/nutrition-export?limit=\(limit)\(after)", body: Optional<Int>.none)
    }

    func createNutritionFood(_ food: NutritionCustomFood) async throws -> NutritionFoodDetail {
        try await send("POST", path: "/v1/nutrition/foods/custom", body: food)
    }

    func submitNutritionFood(_ food: NutritionFoodSubmission) async throws -> NutritionFoodSubmission {
        try await send("POST", path: "/v1/nutrition/foods/submissions", body: food)
    }

    func nutritionMeals(day: String, offset: Int = 0) async throws -> NutritionMealPage {
        try await send("GET", path: "/v1/nutrition/meals?from=\(day)&to=\(day)&limit=30&offset=\(offset)", body: Optional<Int>.none)
    }

    func nutritionMeal(_ id: UUID) async throws -> NutritionMeal {
        try await send("GET", path: nutritionMealPath(id), body: Optional<Int>.none)
    }

    func createNutritionMeal(_ meal: NutritionMealWrite) async throws -> NutritionMeal {
        try await send("POST", path: "/v1/nutrition/meals", body: meal)
    }

    func updateNutritionMeal(_ id: UUID, _ patch: NutritionMealPatch) async throws -> NutritionMeal {
        try await send("PATCH", path: nutritionMealPath(id), body: patch)
    }

    func deleteNutritionMeal(_ id: UUID) async throws {
        _ = try await data("DELETE", path: nutritionMealPath(id), body: Optional<Int>.none)
    }

    private func nutritionMealPath(_ id: UUID) -> String { "/v1/nutrition/meals/\(id.uuidString.lowercased())" }

    func nutritionDay(_ day: String) async throws -> NutritionDaily {
        try await send("GET", path: "/v1/nutrition/daily?date=\(day)&chrononutrition=true", body: Optional<Int>.none)
    }

    func nutritionSummary(from: String, to: String) async throws -> [NutritionDaily] {
        try await send("GET", path: "/v1/nutrition/summary?from=\(from)&to=\(to)&chrononutrition=true", body: Optional<Int>.none)
    }

    func nutritionGoals() async throws -> NutritionGoals {
        try await send("GET", path: "/v1/nutrition/goals", body: Optional<Int>.none)
    }

    func saveNutritionGoals(_ goals: NutritionGoals) async throws -> NutritionGoals {
        try await send("PUT", path: "/v1/nutrition/goals", body: goals)
    }

    func nutritionRecoveryProfile() async throws -> NutritionRecoveryProfile? {
        try await send("GET", path: "/v1/nutrition/n2r/profile", body: Optional<Int>.none)
    }

    func saveNutritionRecoveryProfile(_ profile: NutritionRecoveryProfile) async throws -> NutritionRecoveryProfile {
        try await send("PUT", path: "/v1/nutrition/n2r/profile", body: profile)
    }

    func deleteNutritionRecoveryProfile() async throws {
        _ = try await data("DELETE", path: "/v1/nutrition/n2r/profile", body: Optional<Int>.none)
    }

    func nutritionGuidance() async throws -> NutritionGuidance {
        try await send("GET", path: "/v1/nutrition/guidance/current", body: Optional<Int>.none)
    }

    func nutritionBriefing() async throws -> NutritionBriefing {
        try await send("GET", path: "/v1/coaching/daily-briefing", body: Optional<Int>.none)
    }

    func nutritionGoalProfile() async throws -> NutritionGoalProfile? {
        try await send("GET", path: "/v1/users/goal-profile", body: Optional<Int>.none)
    }

    func saveNutritionGoalProfile(_ profile: NutritionGoalProfile) async throws -> NutritionGoalProfile {
        try await send("PUT", path: "/v1/users/goal-profile", body: profile)
    }

    func deleteNutritionGoalProfile() async throws {
        _ = try await data("DELETE", path: "/v1/users/goal-profile", body: Optional<Int>.none)
    }

    func saveNutritionFeedback(_ feedback: NutritionCoachingFeedback, day: String) async throws {
        _ = try await data("PUT", path: "/v1/coaching/feedback/\(day)", body: feedback)
    }

    func uploadNutritionGlucose(_ batch: NutritionGlucoseBatch) async throws {
        _ = try await data("PUT", path: "/v1/nutrition/glucose", body: batch)
    }

    func deleteNutritionGlucose() async throws {
        _ = try await data("DELETE", path: "/v1/nutrition/glucose", body: Optional<Int>.none)
    }
}
