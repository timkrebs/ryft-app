import Foundation
import Testing
@testable import Ryft

enum NutritionDiaryFixtures {
    static let mealID = UUID(uuidString: "ea0ac98d-9c71-410d-ac6a-61ce6f97f092")!
    static let foodID = UUID(uuidString: "a7e40c6e-bfb4-47eb-ad64-aea61136db01")!

    static let meal = """
    {
      "id":"ea0ac98d-9c71-410d-ac6a-61ce6f97f092","client_request_id":"9d94e3ec-e873-43d5-8887-86913a60fca8",
      "consumed_at":"2026-11-24T22:30:00Z","timezone":"Europe/Berlin","local_date":"2026-11-24",
      "meal_type":"dinner","input_method":"barcode","name":"Dinner","notes":"","revision":2,
      "items":[{"id":"63cf1226-48cf-43c7-957e-c994ec3bbe61","food_id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01",
                "food_name":"Apple","brand":"","quantity":150,"unit":"g",
                "nutrients":{"energy_kcal":{"amount":78,"unit":"kcal","source_id":"a7e40c6e-bfb4-47eb-ad64-aea61136db01"}}}]
    }
    """

    static let score = """
    {
      "version":"1.0.0","n2r_score":null,"quality_score":null,"glucose_score":92,
      "budget":{"energy_target_kcal":2400,"strain":"high","carb_target_g":560,"sodium_exemption_mg":680},
      "fuel_multiplier":0.85,"omega_3_depot_mg":305,"covered_added_sugar_g":12,"autonomic_penalty":1.5,
      "tags":["underfueled_high_strain"]
    }
    """

    static let daily = """
    {
      "local_date":"2026-11-24","meal_count":1,"item_count":2,
      "nutrients":{"energy_kcal":{"known_subtotal":78,"unit":"kcal","known_items":1,"complete_for_logged_items":false}},
      "score_version":"1.0.0","nutrition_score":null,"quality_score":null,"glucose_score":92,
      "breakdown":{"fiber_g":4,"sodium_mg":null},"meal_glucose_scores":[
        {"meal_id":"\(mealID)","window_end":"2026-11-25T00:30:00Z","sample_count":5,"baseline_mg_dl":100,
         "peak_delta_mg_dl":24,"iauc_mg_dl_min":250,"end_delta_mg_dl":3,"peak_score":84,"auc_score":100,
         "recovery_score":100,"glucose_score":92}
      ],"chrononutrition_penalty":0,"n2r":\(score)
    }
    """

    static let briefing = """
    {
      "local_date":"2026-11-24","plan":{
        "energy_target_kcal":2800,"protein_target_g":125,"carb_target_g":430,"fat_target_g":70,"net_exercise_kcal":680,
        "session_class":"KEY_HIGH_INTENSITY","deficit_suspended":true,"train_low":false,
        "availability":{"state":"RED","energy_kcal_per_kg_ffm":29.5,"carbs_g_per_kg":2.6,"markers":["example"]},
        "fueling":{"carb_min_g_per_h":30,"carb_max_g_per_h":60,"glucose_fructose_ratio":"1:0.8","post_workout_fluids_l":1.5}
      },
      "readiness":"LEA_GUARDRAIL_ACTIVE","readiness_reasons":[],
      "training_load":{"acute_7d":230,"chronic_28d_weekly":197,"acwr":1.16,"tsb":-33},
      "n2r":null,"yesterday_n2r":\(score),
      "morning_biometrics":{"wake_date":"2026-11-24","ln_rmssd_7d_mean":3.9,"ln_rmssd_7d_sd":0.16,
                            "ln_rmssd_7d_cv":4.1,"swc":0.032,"ln_rmssd_delta":-0.17,"rhr_delta":3,"change":"moderate"},
      "cards":[{"code":"POST_WORKOUT_ENDURANCE_REFEED","actions":["Refuel after your session."],
                "targets":{"carb_min_g":56},"foods":[{"id":"\(foodID)","name":"Banana","brand":"","type":"generic","quality":"source_reported"}]}]
    }
    """
}

struct NutritionDiaryTests {
    @Test func decodesPartialTotalsAndBothScoringVersions() throws {
        let day = try APIClient.jsonDecoder.decode(NutritionDaily.self, from: Data(NutritionDiaryFixtures.daily.utf8))
        let energy = try #require(NutritionNutrient.energy.total(in: day.nutrients))
        #expect(energy.knownSubtotal == 78 && !energy.completeForLoggedItems && energy.knownItems == 1)
        #expect(day.nutritionScore == nil && day.breakdown["fiber_g"] == 4 && day.breakdown["sodium_mg"] == nil)
        #expect(day.mealGlucoseScores.first?.mealId == NutritionDiaryFixtures.mealID)
        #expect(day.mealGlucoseScores.first?.iaucMgDlMin == 250)
        #expect(day.n2r?.omega3DepotMg == 305 && day.n2r?.budget.sodiumExemptionMg == 680)
    }

    @Test func decodesFuelingAvailabilityCalibrationAndGuidanceFood() throws {
        let value = try APIClient.jsonDecoder.decode(NutritionBriefing.self, from: Data(NutritionDiaryFixtures.briefing.utf8))
        #expect(value.trainingLoad.acute7d == 230 && value.trainingLoad.chronic28dWeekly == 197)
        #expect(value.yesterdayN2r?.n2rScore == nil && value.yesterdayN2r?.fuelMultiplier == 0.85)
        #expect(value.morningBiometrics?.lnRmssd7dCv == 4.1)
        let hrvChange = try #require(value.morningBiometrics?.relativeHRVPercent)
        #expect(abs(hrvChange - (-15.6335)) < 0.001)
        #expect(value.plan?.availability.state == "RED" && value.plan?.deficitSuspended == true)
        #expect(value.plan?.fueling?.carbMaxGPerH == 60)
        #expect(value.cards.first?.foods.first?.id == NutritionDiaryFixtures.foodID)
        #expect(value.cards.first?.targets?["carb_min_g"] == 56)
    }

    @Test func ranksOnlyPositiveNutritionAdjustments() throws {
        let json = NutritionDiaryFixtures.score.replacingOccurrences(
            of: "\"autonomic_penalty\":1.5", with: "\"alcohol_penalty\":0,\"late_meal_penalty\":1.5,\"caffeine_penalty\":6"
        )
        let score = try APIClient.jsonDecoder.decode(NutritionRecoveryScore.self, from: Data(json.utf8))
        let factors = NutritionRecoveryFactor.ranked(in: score)
        #expect(factors.map(\.kind) == [.caffeine, .lateMeal])
        #expect(factors.map(\.points) == [6, 1.5])
    }

    @Test func retainedMealItemsSendOnlyTheirSnapshotID() throws {
        let meal = try APIClient.jsonDecoder.decode(NutritionMeal.self, from: Data(NutritionDiaryFixtures.meal.utf8))
        let original = try #require(meal.items.first)
        let choice = NutritionDraftItem(original)
        let patch = NutritionMealPatch(revision: meal.revision, items: [choice.request])
        let data = try APIClient.jsonEncoder.encode(patch)
        let sent = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let items = try #require(sent["items"] as? [[String: Any]])
        #expect(sent["revision"] as? Int == 2)
        #expect(items.first?.keys.sorted() == ["item_id"])
        #expect(original.nutrients["energy_kcal"]?.amount == 78)
    }

    @MainActor
    @Test func persistsAnIdenticalCreateRequestAndKeepsAccountLocalDay() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-11-24T23:30:00Z"))
        #expect(NutritionDay.key(date, timezone: "Europe/Berlin") == "2026-11-25")
        #expect(NutritionDay.key(date, timezone: "America/Los_Angeles") == "2026-11-24")
        let request = NutritionMealWrite(clientRequestId: UUID(), consumedAt: date.addingTimeInterval(0.125), timezone: "Europe/Berlin",
                                         mealType: "snack", inputMethod: "barcode", name: "", notes: "",
                                         items: [.init(foodId: NutritionDiaryFixtures.foodID, quantity: 125, unit: "g")])
        let store = TrainStore(inMemory: true)
        store.saveDocument(request, key: "nutrition.pending.test", at: date)
        #expect(store.document(NutritionMealWrite.self, key: "nutrition.pending.test") == request)
        #expect(request.consumedAt == date)
    }

    @Test func coachingFeedbackUsesNumericContractKeys() throws {
        let request = NutritionCoachingFeedback(
            intakeComplete: true, plannedSession: .init(startAt: .now, sportType: "running", durationMin: 75, classification: "MODERATE"),
            giDistress: 1, rpe: 6, fatigue: 3
        )
        let encoded = try APIClient.jsonEncoder.encode(request)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["gi_distress_0_10"] as? Double == 1)
        #expect(json["rpe_0_10"] as? Double == 6 && json["fatigue_0_10"] as? Double == 3)
        let session = try #require(json["planned_session"] as? [String: Any])
        #expect(session["class"] as? String == "MODERATE")
    }

    @Test func csvAndLocalizedNumbersRejectAmbiguousValues() throws {
        let valid = "timestamp,glucose_mg_dl\r\n2026-11-24T14:30:00+01:00,95\r\n2026-11-24T13:35:00Z,100"
        let result = try NutritionGlucoseCSV.parse(Data(valid.utf8))
        #expect(result.samples.map(\.glucoseMgDl) == [95, 100])
        for invalid in [
            valid + "\n2026-11-24T13:30:00Z,96",
            "timestamp,glucose_mg_dl\n2026-11-24T13:30:00Z,0",
            "timestamp,mmol_l\n2026-11-24T13:30:00Z,5",
        ] {
            #expect(throws: NutritionInputError.self) { try NutritionGlucoseCSV.parse(Data(invalid.utf8)) }
        }
        let de = Locale(identifier: "de_DE")
        #expect(try NutritionNumbers.parse("1,25", in: 0...10, locale: de) == 1.25)
        #expect(try NutritionNumbers.parse("", in: 0...10, locale: de) == nil)
        #expect(throws: NutritionInputError.self) { try NutritionNumbers.parse("1.2", in: 0...10, locale: de) }
    }

    @Test func onlyValidOptInWeightSamplesCanBeUploaded() {
        let at = Date.now
        #expect(Sample(type: .bodyMass, start: at, end: at, value: 75, unit: "kg", source: "Scale").passesValidation)
        #expect(!Sample(type: .bodyMass, start: at, end: at, value: 20, unit: "kg", source: "Scale").passesValidation)
        #expect(!Sample(type: .bodyMass, start: at, end: at, value: 70, unit: "lb", source: "Scale").passesValidation)
    }
}
