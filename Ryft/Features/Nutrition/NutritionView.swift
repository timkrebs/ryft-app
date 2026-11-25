import SwiftUI

struct NutritionEntryView: View {
    var opensMealEditor = false

    @Environment(\.appEnvironment) private var env
    @Environment(AppState.self) private var state

    var body: some View {
        if let account = env.auth.accountID, let api = env.api as? APIClient, !env.isDemo, env.flags.newest(.nutritionEnabled) {
            let model = NutritionDiaryModel(env: env, api: api, account: account,
                                            timezone: state.user?.tz ?? TimeZone.current.identifier)
            Group {
                if opensMealEditor {
                    NutritionQuickLogView(model: model, api: api)
                } else {
                    NutritionView(model: model)
                }
            }
            .id(account)
        }
    }
}

struct NutritionQuickLogView: View {
    @State private var model: NutritionDiaryModel
    @State private var showsDiary: Bool
    let api: APIClient

    init(model: NutritionDiaryModel, api: APIClient) {
        _model = State(initialValue: model)
        _showsDiary = State(initialValue: model.pending != nil)
        self.api = api
    }

    var body: some View {
        if showsDiary {
            NutritionView(model: model)
        } else {
            NutritionMealEditor(model: model, api: api, meal: nil) { showsDiary = true }
        }
    }
}

struct NutritionView: View {
    @State var model: NutritionDiaryModel
    @State private var editor: NutritionMealEditorRoute?
    @State private var confirmingDiscard = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SubpageScaffold(Text("Nutrition")) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                dayPicker
                if let error = model.error {
                    InlineMessage(message: error, systemImage: "exclamationmark.circle")
                    PillButton(Text("Try again"), style: .secondary, busy: model.loading) { await model.load(force: true) }
                }
                if let daily = model.daily { dayTotals(daily) }
                if model.loading && model.daily == nil { ProgressView().accessibilityLabel(Text("Loading nutrition")) }
                if model.pending != nil { pendingCard }
                mealCard
                if model.api != nil && model.pending == nil {
                    PillButton(Text("Log meal"), systemImage: "plus") { editor = NutritionMealEditorRoute() }
                        .accessibilityIdentifier("nutrition.logMeal")
                }
                if let api = model.api { details(api) }
            }
        }
        .task(id: model.day) { await model.load() }
        .refreshable { await model.load(force: true) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.load() } }
        }
        .onChange(of: model.online) { _, online in
            if online { Task { await model.load() } }
        }
        .navigationDestination(item: $editor) { entry in
            if let api = model.api {
                NutritionMealEditor(model: model, api: api, meal: entry.meal) {
                    editor = nil
                    Task { await model.reload() }
                }
            }
        }
        .confirmationDialog("Discard pending meal?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard draft", role: .destructive) { model.discardPending() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("If a previous save reached RYFT, the meal will still be in your diary.")
        }
    }

    private var dayPicker: some View {
        HStack(spacing: GroupedListSpec.rowSpacing) {
            Button { model.move(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel(Text("Previous day"))
                .frame(minWidth: 44, minHeight: 44)
            Text(model.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .environment(\.timeZone, NutritionDay.calendar(model.timezone).timeZone)
                .font(.ryft(.label))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("nutrition.date")
            Button { model.move(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel(Text("Next day"))
                .frame(minWidth: 44, minHeight: 44)
                .disabled(!model.canAdvance)
        }
        .foregroundStyle(Theme.textPrimary)
        .buttonStyle(.plain)
    }

    private func dayTotals(_ daily: NutritionDaily) -> some View {
        GroupedCard(Text("Logged nutrients"), footer: Text("Partial values are the known subtotal from your logged foods.")) {
            ForEach(NutritionNutrient.main) { nutrient in
                GroupedRow.value(Text(verbatim: nutrient.title), value: NutritionDisplay.total(nutrient.total(in: daily.nutrients)))
            }
            if !daily.nutrients.isEmpty {
                NutritionRouteRow(Text("All nutrients"), icon: "list.bullet") { NutritionNutrientDetailView(day: daily) }
            }
            NavigationLink {
                NutritionScoreView(daily: daily, meals: model.meals)
            } label: {
                GroupedRowLabel(Text("Nutrition score"), value: NutritionDisplay.score(daily.nutritionScore), accessory: .chevron)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nutrition.score")
        }
    }

    private var mealCard: some View {
        GroupedCard(Text("Meals")) {
            if let daily = model.daily, daily.mealCount == 0 {
                GroupedRow.value(Text("Meal log"), value: Text("No meals yet"))
            }
            ForEach(model.meals) { meal in
                GroupedRow.push(NutritionDisplay.mealTitle(meal), detail: NutritionDisplay.mealTime(meal), icon: "fork.knife",
                                identifier: "nutrition.meal.\(meal.id.uuidString.lowercased())") {
                    editor = NutritionMealEditorRoute(meal: meal)
                }
            }
            if model.nextOffset != nil {
                GroupedRow.action(Text("Load more meals"), systemImage: "chevron.down", busy: model.loading) {
                    Task { await model.load(more: true) }
                }
            }
        }
    }

    private var pendingCard: some View {
        GroupedCard(Text("Pending meal"), footer: Text("Your draft is saved on this device. Retry to finish logging it.")) {
            GroupedRow.action(Text("Retry save"), systemImage: "arrow.clockwise", busy: model.saving,
                              identifier: "nutrition.pending.retry") {
                Task {
                    guard let pending = model.pending else { return }
                    do {
                        _ = try await model.create(pending)
                        await model.reload()
                    } catch {
                        model.showError(error)
                    }
                }
            }
            .disabled(!model.online)
            GroupedRow.action(Text("Discard draft"), systemImage: "trash") { confirmingDiscard = true }
                .disabled(model.saving)
        }
    }

    private func details(_ api: APIClient) -> some View {
        GroupedCard {
            NutritionRouteRow(Text("Coaching"), icon: "figure.run") {
                NutritionCoachingView(model: model, api: api)
            }
            NutritionRouteRow(Text("7-day history"), icon: "chart.bar") {
                NutritionHistoryView(model: model, api: api)
            }
            NutritionRouteRow(Text("Nutrition settings"), icon: "slider.horizontal.3") {
                NutritionSettingsView(model: model, api: api)
            }
        }
    }
}

private struct NutritionMealEditorRoute: Identifiable, Hashable {
    let id = UUID()
    var meal: NutritionMeal?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct NutritionRouteRow<Destination: View>: View {
    let label: Text
    let icon: String
    let destination: () -> Destination

    init(_ label: Text, icon: String, @ViewBuilder destination: @escaping () -> Destination) {
        self.label = label
        self.icon = icon
        self.destination = destination
    }

    var body: some View {
        NavigationLink(destination: destination) {
            GroupedRowLabel(label, icon: icon, accessory: .chevron)
        }
        .buttonStyle(.plain)
        .groupedRowHairline()
    }
}

enum NutritionDisplay {
    static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...digits)))
    }

    static func amount(_ value: Double, unit: String) -> Text {
        Text(verbatim: "\(number(value)) \(unit)")
    }

    static func score(_ value: Double?, max: Int = 100) -> Text {
        guard let value else { return Text("Unavailable") }
        return Text(verbatim: "\(number(value)) / \(max)")
    }

    static func total(_ value: NutritionTotal?) -> Text {
        guard let value else { return Text("Unknown") }
        let formatted = "\(number(value.knownSubtotal)) \(value.unit)"
        return value.completeForLoggedItems ? Text(verbatim: formatted) : Text("\(formatted) · Partial")
    }

    static func mealTime(_ meal: NutritionMeal) -> Text {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.timeZone = NutritionDay.calendar(meal.timezone).timeZone
        return Text(verbatim: formatter.string(from: meal.consumedAt))
    }

    static func mealTitle(_ meal: NutritionMeal) -> Text {
        meal.name.isEmpty ? Text(verbatim: meal.mealType.capitalized) : Text(verbatim: meal.name)
    }
}

private struct NutritionNutrientDetailView: View {
    let day: NutritionDaily

    var body: some View {
        SubpageScaffold(Text("All nutrients")) {
            GroupedCard {
                ForEach(day.nutrients.keys.sorted(), id: \.self) { code in
                    let label = NutritionNutrient(rawValue: code)?.title ?? NutritionCoachingLabels.words(code)
                    if let total = day.nutrients[code] {
                        GroupedRow.value(Text(verbatim: label), value: NutritionDisplay.total(total),
                                         detail: Text("Known for \(total.knownItems) of \(day.itemCount) items"))
                    }
                }
            }
        }
    }
}

struct NutritionScoreView: View {
    let daily: NutritionDaily
    let meals: [NutritionMeal]

    var body: some View {
        SubpageScaffold(Text("Nutrition score")) {
            VStack(spacing: GroupedListSpec.groupSpacing) {
                GroupedCard(Text("Daily scores"), footer: Text("Food quality summarizes the nutrients in your log. Glucose impact uses readings around your meals when enough glucose data is available.")) {
                    GroupedRow.value(Text("Nutrition"), value: NutritionDisplay.score(daily.nutritionScore))
                    GroupedRow.value(Text("Food quality"), value: NutritionDisplay.score(daily.qualityScore))
                    GroupedRow.value(Text("Glucose impact"), value: NutritionDisplay.score(daily.glucoseScore))
                    if daily.chrononutritionPenalty > 0 {
                        GroupedRow.value(Text("Late eating adjustment"), value: NutritionDisplay.amount(daily.chrononutritionPenalty, unit: "pts"))
                    }
                }
                NutritionComponentsCard(components: daily.breakdown)
                if let score = daily.n2r { NutritionRecoveryCard(score: score) }
                ForEach(daily.mealGlucoseScores) { glucose in
                    GroupedCard(meals.first(where: { $0.id == glucose.mealId }).map(NutritionDisplay.mealTitle) ?? Text("Meal glucose"),
                                footer: Text("A higher glucose impact score means a smaller rise, less time and elevation above baseline, or a reading closer to baseline at the end of the meal window.")) {
                        GroupedRow.value(Text("Glucose impact"), value: NutritionDisplay.score(glucose.glucoseScore))
                        GroupedRow.value(Text("Peak score"), value: NutritionDisplay.score(glucose.peakScore))
                        GroupedRow.value(Text("Area under the curve score"), value: NutritionDisplay.score(glucose.aucScore))
                        GroupedRow.value(Text("Return toward baseline"), value: NutritionDisplay.score(glucose.recoveryScore))
                        GroupedRow.value(Text("Peak rise"), value: NutritionDisplay.amount(glucose.peakDeltaMgDl, unit: "mg/dL"))
                        GroupedRow.value(Text("Baseline"), value: NutritionDisplay.amount(glucose.baselineMgDl, unit: "mg/dL"))
                        GroupedRow.value(Text("Incremental area"), value: NutritionDisplay.amount(glucose.iaucMgDlMin, unit: "mg·min/dL"))
                        GroupedRow.value(Text("End rise"), value: NutritionDisplay.amount(glucose.endDeltaMgDl, unit: "mg/dL"))
                        GroupedRow.value(Text("Readings"), value: Text(verbatim: String(glucose.sampleCount)))
                    }
                }
            }
        }
    }
}

struct NutritionComponentsCard: View {
    let components: NutritionComponents

    var body: some View {
        GroupedCard(Text("Food quality breakdown")) {
            row("non_starchy_veg_g", Text("Non-starchy vegetables"))
            row("whole_fruit_g", Text("Whole fruit"))
            row("fiber_g", Text("Fiber"))
            row("nuts_legumes_g", Text("Nuts and legumes"))
            row("omega3_epa_dha_mg", Text("Omega-3 EPA and DHA"))
            row("unsaturated_fat_kcal_pct", Text("Unsaturated fat"))
            row("added_sugar_g", Text("Added sugar"))
            row("red_processed_meat_g", Text("Red and processed meat"))
            row("sodium_mg", Text("Sodium"))
            row("trans_fat_kcal_pct", Text("Trans fat"))
        }
    }

    private func row(_ key: String, _ title: Text) -> some View {
        GroupedRow.value(title, value: NutritionDisplay.score(components[key], max: 10))
    }
}

struct NutritionHistoryView: View {
    let model: NutritionDiaryModel
    let api: APIClient
    @State private var days: [NutritionDaily]?
    @State private var failure: String?
    @State private var loading = false

    var body: some View {
        SubpageScaffold(Text("7-day nutrition history")) {
            VStack(spacing: GroupedListSpec.groupSpacing) {
                if loading { ProgressView() }
                if let failure {
                    InlineMessage(message: failure, systemImage: "exclamationmark.circle")
                    PillButton(Text("Try again"), style: .secondary, busy: loading) { await load() }
                }
                if let days {
                    GroupedCard {
                        ForEach(days.reversed()) { day in
                            NutritionRouteRow(Text(verbatim: day.localDate), icon: "calendar") { NutritionScoreView(daily: day, meals: []) }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        failure = nil
        do {
            let calendar = NutritionDay.calendar(model.timezone)
            guard let start = calendar.date(byAdding: .day, value: -6, to: model.date) else { return }
            let values = try await api.nutritionSummary(from: NutritionDay.key(start, timezone: model.timezone), to: model.day)
            try model.needsCurrentAccount()
            days = values
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }
}

#if DEBUG
#Preview("Nutrition diary") {
    NavigationStack { NutritionView(model: NutritionDiaryModel(preview: nil)) }
        .preferredColorScheme(.dark)
}
#endif
