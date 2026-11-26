import Foundation

extension NutritionFoodMatch {
    var catalogIssueReport: FeedbackPost? {
        guard type == "generic" || type == "branded" else { return nil }
        return FeedbackPost(message: "Food catalog issue: \(id.uuidString.lowercased())", category: .data)
    }
}

extension NutritionFoodPortion {
    var isSelectable: Bool {
        guard quantity.isFinite, quantity > 0 else { return false }
        return unit == "serving" || (unit == "portion" && ((weightG ?? 0) > 0 || (volumeMl ?? 0) > 0))
    }

    func displayLabel(language: String) -> String {
        if let translated = labels?[language], !translated.isEmpty { return translated }
        switch label.lowercased() {
        case "serving", "portion": return String(localized: "Portion")
        case "tbsp", "tablespoon": return String(localized: "Tablespoon")
        case "tsp", "teaspoon": return String(localized: "Teaspoon")
        case "cup": return String(localized: "Cup")
        case "piece": return String(localized: "Piece")
        case "slice": return String(localized: "Slice")
        default: return label
        }
    }
}

extension NutritionFoodDetail {
    func displayName(language: String, fallback: String) -> String {
        names.first { !$0.alias && $0.language == language && !$0.label.isEmpty }?.label ?? fallback
    }
}

/// Read-only estimate from compatible catalog references. The saved meal is calculated by the API.
struct NutritionServingPreview {
    static let quantityLimits: ClosedRange<Double> = 0.000_001...100_000
    static let displayedNutrients: [NutritionNutrient] = [.energy, .protein, .carbs, .fat]

    let weightG: Double?
    let volumeMl: Double?
    let amounts: [NutritionNutrient: Double]

    init?(food: NutritionFoodDetail, quantity: Double, unit: String, portion: NutritionFoodPortion?) {
        guard Self.quantityLimits.contains(quantity) else { return nil }
        var grams = unit == "g" ? quantity : 0
        var milliliters = unit == "ml" ? quantity : 0
        if let portion {
            guard portion.isSelectable, portion.unit == unit else { return nil }
            grams = (portion.weightG ?? 0) * quantity / portion.quantity
            milliliters = (portion.volumeMl ?? 0) * quantity / portion.quantity
        } else if unit != "g" && unit != "ml" {
            return nil
        }
        if let density = food.densityGMl, density.isFinite, density > 0 {
            if grams == 0 { grams = milliliters * density }
            if milliliters == 0 { milliliters = grams / density }
        }
        let servingSource = portion?.unit == "serving" ? portion?.sourceId : nil
        guard (0...Self.quantityLimits.upperBound).contains(grams),
              (0...Self.quantityLimits.upperBound).contains(milliliters),
              grams > 0 || milliliters > 0 || servingSource != nil else { return nil }
        weightG = grams > 0 ? grams : nil
        volumeMl = milliliters > 0 ? milliliters : nil

        func measure(_ item: NutritionFoodNutrient) -> Double {
            switch item.referenceUnit {
            case "g": grams
            case "ml": milliliters
            case "serving": item.sourceId == servingSource ? quantity : 0
            default: 0
            }
        }

        let compatible = food.nutrients.filter { measure($0) > 0 && $0.referenceAmount > 0 }
        guard food.nutrients.isEmpty || !compatible.isEmpty else { return nil }
        let ranked = compatible.sorted { Self.ranksBefore($0, $1, preferred: unit) }
        var known: [NutritionNutrient: Double] = [:]
        for item in ranked {
            guard let nutrient = NutritionNutrient(rawValue: item.code), Self.displayedNutrients.contains(nutrient),
                  known[nutrient] == nil else { continue }
            known[nutrient] = item.amount * measure(item) / item.referenceAmount
        }
        amounts = known
    }

    private static func ranksBefore(_ lhs: NutritionFoodNutrient, _ rhs: NutritionFoodNutrient, preferred: String) -> Bool {
        let quality = ["verified": 3, "source_reported": 2, "user_reported": 1]
        let lhsQuality = quality[lhs.quality, default: 0]
        let rhsQuality = quality[rhs.quality, default: 0]
        if lhsQuality != rhsQuality { return lhsQuality > rhsQuality }
        func priority(_ unit: String) -> Int { unit == preferred ? 3 : unit == "g" ? 2 : 1 }
        let lhsPriority = priority(lhs.referenceUnit)
        let rhsPriority = priority(rhs.referenceUnit)
        if lhsPriority != rhsPriority { return lhsPriority > rhsPriority }
        if lhs.sourceId != rhs.sourceId { return lhs.sourceId.uuidString < rhs.sourceId.uuidString }
        return lhs.referenceAmount < rhs.referenceAmount
    }
}
