import SwiftUI

@MainActor
struct NutritionTab: View {
    @Binding var mealEditor: NutritionMealEditorRoute?

    var body: some View {
        NavigationStack {
            NutritionEntryView(tabMealEditor: $mealEditor)
        }
    }

    static var header: some View {
        ScreenHeader(title: Text(AppTab.nutrition.title)) { HeaderActions() }
    }
}

#Preview("Nutrition tab · Demo") {
    NutritionTab(mealEditor: .constant(nil))
        .previewEnvironment(.preview(flags: [.structureV2: true]))
}

#if DEBUG
#Preview("Nutrition tab · Diary") {
    NavigationStack {
        NutritionView(model: NutritionDiaryModel(preview: nil), tabMealEditor: .constant(nil))
    }
    .previewEnvironment(.preview(flags: [.structureV2: true]))
}
#endif
