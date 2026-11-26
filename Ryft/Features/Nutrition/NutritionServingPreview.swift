import Foundation

extension NutritionFoodMatch {
    var catalogIssueReport: FeedbackPost? {
        guard type == "generic" || type == "branded" else { return nil }
        return FeedbackPost(message: "Food catalog issue: \(id.uuidString.lowercased())", category: .data)
    }

    var quickSelection: NutritionCatalogSelection? {
        [lastUsedPortion, defaultPortion].compactMap { $0 }.first(where: \.isSupported)
    }

    var describedSelection: NutritionCatalogSelection? {
        quickSelection ?? referencePortion.flatMap { $0.isSupported ? $0 : nil }
    }
}

extension NutritionCatalogSelection {
    var isSupported: Bool {
        guard NutritionServingPreview.isValidQuantity(quantity) else { return false }
        switch unit {
        case "g", "ml": return portionId == nil
        case "portion", "serving": return portionId != nil
        default: return false
        }
    }

    var weightForDisplay: Double? { gramWeight ?? (unit == "g" ? quantity : nil) }
    var volumeForDisplay: Double? { volumeMl ?? (unit == "ml" ? quantity : nil) }

    func summary(locale: Locale) -> String {
        var parts: [String] = []
        if let title = shortLabel ?? label, !title.isEmpty { parts.append(title) }
        if unit != "g", let volumeForDisplay {
            parts.append("\(NutritionDisplay.number(volumeForDisplay, locale: locale)) mL")
        } else if let weightForDisplay {
            parts.append("\(NutritionDisplay.number(weightForDisplay, locale: locale)) g")
        }
        if let kcal, kcal.isFinite, kcal >= 0 {
            parts.append("\(NutritionDisplay.number(kcal, locale: locale)) kcal")
        }
        return parts.joined(separator: " · ")
    }

    func draft(food: NutritionFoodMatch, inputMethod: String, language: String) -> NutritionDraftItem {
        NutritionDraftItem(name: food.name, inputMethod: inputMethod,
                           selection: .init(foodId: food.id, quantity: quantity, unit: unit, portionId: portionId, language: language),
                           portionLabel: portionId == nil ? nil : (label ?? shortLabel),
                           weightG: weightForDisplay, volumeMl: volumeForDisplay)
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

    func chipLabel(language: String) -> String {
        let short = language == "de" ? shortLabelDe : shortLabelEn
        return short.flatMap { $0.isEmpty ? nil : $0 } ?? displayLabel(language: language)
    }

    var catalogSelection: NutritionCatalogSelection {
        NutritionCatalogSelection(portionId: id, quantity: quantity, unit: unit)
    }
}

extension NutritionFoodDetail {
    func displayName(language: String, fallback: String) -> String {
        names.first { !$0.alias && $0.language == language && !$0.label.isEmpty }?.label ?? fallback
    }

    func mealInputLanguage(_ language: String) -> String? {
        // The previous API rejects unknown meal item fields. Enhanced details include a favorite status.
        guard favorited != nil || defaultPortion != nil || lastUsedSelection != nil || referencePortion != nil else { return nil }
        return language
    }

    /// By `sort_order`; ties, and a server without it, keep the server's order (not the English label's).
    var sortedPortions: [NutritionFoodPortion] {
        portions.enumerated().filter { $0.element.isSelectable }.sorted { a, b in
            let left = a.element.sortOrder ?? Int.max
            let right = b.element.sortOrder ?? Int.max
            if left != right { return left < right }
            return a.offset < b.offset
        }.map(\.element)
    }

    func preferredSelection(editing current: NutritionMealSelection? = nil) -> NutritionCatalogSelection {
        let edited = current.flatMap { item -> NutritionCatalogSelection? in
            guard let quantity = item.quantity, let unit = item.unit else { return nil }
            return NutritionCatalogSelection(portionId: item.portionId, quantity: quantity, unit: unit)
        }
        let portions = sortedPortions
        let explicit = portions.filter { $0.isDefault == true }.map(\.catalogSelection)
        let measured = portions.filter { !$0.estimated }.map(\.catalogSelection)
        let candidates = [edited, lastUsedSelection, defaultPortion].compactMap { $0 }
            + explicit + measured + portions.map(\.catalogSelection)
        let grams = NutritionCatalogSelection(quantity: 100, unit: "g")
        let milliliters = NutritionCatalogSelection(quantity: 100, unit: "ml")
        return (candidates + [grams, milliliters]).first { candidate in
            guard candidate.isSupported else { return false }
            let portion = portions.first { $0.id == candidate.portionId }
            return NutritionServingPreview(food: self, quantity: candidate.quantity, unit: candidate.unit, portion: portion) != nil
        } ?? grams
    }
}

/// Read-only estimate from compatible catalog references. The saved meal is calculated by the API.
struct NutritionServingPreview {
    static let quantityLimits: ClosedRange<Double> = 0.000_001...100_000
    static let displayedNutrients: [NutritionNutrient] = [.energy, .protein, .carbs, .fat]
    static let householdMultipliers = [0.5, 1.0, 1.5, 2.0]
    static let householdStep = 0.5
    static let metricStep = 10.0
    /// The platform holds a quantity at six decimals and refuses one it can't: the one rule for typed amounts, the
    /// preview, quick add and meal writes.
    static let quantityFractionDigits = 6

    /// Within `quantityLimits` and representable at six decimals (`0,333333` is, `0,3333333` isn't).
    static func isValidQuantity(_ quantity: Double) -> Bool {
        guard quantity.isFinite, quantityLimits.contains(quantity) else { return false }
        let scaled = quantity * 1_000_000
        return abs(scaled - scaled.rounded()) < 0.001
    }

    /// A typed amount (empty is unknown), refused when it breaks `isValidQuantity`.
    static func parseQuantity(_ text: String, locale: Locale) throws -> Double? {
        guard let value = try NutritionNumbers.parse(text, in: quantityLimits, locale: locale) else { return nil }
        guard isValidQuantity(value) else { throw NutritionInputError.invalidNumber }
        return value
    }

    let weightG: Double?
    let volumeMl: Double?
    let amounts: [NutritionNutrient: Double]

    init?(food: NutritionFoodDetail, quantity: Double, unit: String, portion: NutritionFoodPortion?) {
        guard Self.isValidQuantity(quantity) else { return nil }
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
            guard let nutrient = NutritionNutrient(catalogCode: item.code), Self.displayedNutrients.contains(nutrient),
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
