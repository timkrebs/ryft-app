import Foundation

/// How a draft item came into this editor session, for `nutrition_food_logged` (plan 2026-11-27, decision 8). Local
/// only: it never goes into a request, a pending draft or anything encoded. Rows loaded from a saved meal have none,
/// so saving a reopened meal logs nothing for them.
struct NutritionLogContext: Equatable, Sendable {
    let entryPoint: AnalyticsNutritionEntryPoint
    /// The food's last-used selection when it was added (`last_used_portion` when the saved amount is exactly it).
    let lastUsed: NutritionCatalogSelection?

    init(_ entryPoint: AnalyticsNutritionEntryPoint, lastUsed: NutritionCatalogSelection? = nil) {
        self.entryPoint = entryPoint
        self.lastUsed = lastUsed
    }

    /// The event for the amount the meal is saved with (an edit on the review page counts, not the first choice).
    func event(for selection: NutritionMealSelection) -> AnalyticsEvent {
        .nutritionFoodLogged(entryPoint: entryPoint, unitMode: Self.unitMode(selection, lastUsed: lastUsed),
                             isFractional: Self.isFractional(selection))
    }

    /// What a save sends: one `nutrition_food_logged` per distinct `(entry_point, unit_mode, is_fractional)` among the
    /// items with a context, in first-seen order. Never one per food: with their timestamps those would add up to a
    /// meal log, and the count would tell how many foods the meal has.
    static func loggedEvents(_ items: [NutritionDraftItem]) -> [AnalyticsEvent] {
        var seen = Set<AnalyticsEvent>()
        return items.compactMap { item in
            guard let event = item.logContext?.event(for: item.selection), seen.insert(event).inserted else { return nil }
            return event
        }
    }

    /// `last_used_portion` when the selection is the food's last-used one; otherwise a catalogue portion is
    /// `curated_portion`, `ml` is `ml`, anything else grams.
    static func unitMode(_ selection: NutritionMealSelection, lastUsed: NutritionCatalogSelection?) -> AnalyticsUnitMode {
        if let lastUsed, lastUsed.portionId == selection.portionId, lastUsed.unit == selection.unit,
           lastUsed.quantity == selection.quantity {
            return .lastUsedPortion
        }
        if selection.portionId != nil { return .curatedPortion }
        return selection.unit == "ml" ? .ml : .grams
    }

    /// A portion or serving counted in a non-whole number (½ slice, 1.5 cups). Grams and millilitres never are.
    static func isFractional(_ selection: NutritionMealSelection) -> Bool {
        guard selection.unit == "portion" || selection.unit == "serving", let quantity = selection.quantity,
              quantity.isFinite else { return false }
        return quantity.rounded() != quantity
    }
}

extension NutritionFoodMatch {
    /// `nutrition_food_opened` for this result at `rank` (1-based). A canonical staple is a catalogue generic food
    /// (not branded, not private); the API has no staple field (plan, decision 7).
    func openedEvent(rank: Int) -> AnalyticsEvent {
        .nutritionFoodOpened(rank: AnalyticsRank(position: rank), isCanonicalStaple: type == "generic",
                             hasDefaultPortion: defaultPortion != nil, hasLastUsedPortion: lastUsedPortion != nil)
    }
}
