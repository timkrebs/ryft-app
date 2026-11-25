import SwiftUI

struct NutritionCoachingView: View {
    let model: NutritionDiaryModel
    let api: APIClient

    @State private var briefing: NutritionBriefing?
    @State private var fallback: NutritionGuidance?
    @State private var selected: NutritionFoodMatch?
    @State private var failure: String?
    @State private var loading = false

    var body: some View {
        SubpageScaffold(Text("Nutrition coaching")) {
            VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                if let briefing { briefingCards(briefing) }
                if let fallback {
                    if let score = fallback.score { NutritionRecoveryCard(score: score) }
                    if let biometric = fallback.morningBiometrics { NutritionBiometricCard(value: biometric) }
                }
                let cards = briefing?.cards ?? fallback?.cards ?? []
                ForEach(Array(cards.enumerated()), id: \.offset) { _, card in advice(card) }
                if let failure { InlineMessage(message: failure, systemImage: "exclamationmark.circle") }
                PillButton(Text("Refresh briefing"), style: .secondary, busy: loading) { await load() }
                    .disabled(!model.online)
            }
        }
        .task { await load() }
        .navigationDestination(item: $selected) { food in
            NutritionMealEditor(model: model, api: api, meal: nil, suggested: food) {
                selected = nil
                Task {
                    await model.reload()
                    await load()
                }
            }
        }
    }

    @ViewBuilder private func briefingCards(_ briefing: NutritionBriefing) -> some View {
        if let plan = briefing.plan {
            NutritionTrainingPlanCard(plan: plan, load: briefing.trainingLoad, readiness: briefing.readiness, reasons: briefing.readinessReasons)
        } else {
            GroupedCard(Text("Daily plan")) {
                NutritionRouteRow(Text("Set training goal"), icon: "target") {
                    NutritionSettingsView(model: model, api: api)
                }
            }
        }
        if let score = briefing.n2r { NutritionRecoveryCard(score: score) }
        if let score = briefing.yesterdayN2r {
            GroupedCard(Text("Yesterday")) {
                GroupedRow.value(Text("Nutrition-to-Recovery"), value: NutritionDisplay.score(score.n2rScore))
                NutritionRouteRow(Text("Score details"), icon: "list.bullet") {
                    SubpageScaffold(Text("Yesterday’s recovery nutrition")) {
                        NutritionRecoveryCard(score: score)
                    }
                }
            }
        }
        if let biometric = briefing.morningBiometrics { NutritionBiometricCard(value: biometric) }
    }

    private func advice(_ card: NutritionGuidanceCard) -> some View {
        GroupedCard(Text(verbatim: NutritionCoachingLabels.card(card.code))) {
            ForEach(Array(card.actions.enumerated()), id: \.offset) { _, action in
                Text(verbatim: action)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nutritionField()
            }
            if let targets = card.targets {
                ForEach(targets.keys.sorted(), id: \.self) { key in
                    GroupedRow.value(Text(verbatim: NutritionCoachingLabels.words(key)),
                                     value: Text(verbatim: NutritionDisplay.number(targets[key, default: 0])))
                }
            }
            ForEach(card.foods) { food in
                GroupedRow.push(Text(verbatim: food.name), detail: food.brand.isEmpty ? nil : Text(verbatim: food.brand),
                                icon: "fork.knife") {
                    selected = food
                }
                .disabled(model.pending != nil)
            }
        }
    }

    private func load() async {
        guard !loading else { return }
        loading = true
        failure = nil
        defer { loading = false }
        do {
            try model.needsCurrentAccount()
            do {
                let response = try await api.nutritionBriefing()
                try model.needsCurrentAccount()
                briefing = response
                fallback = nil
            } catch let error as APIError where error.isNotFound {
                let response = try await api.nutritionGuidance()
                try model.needsCurrentAccount()
                fallback = response
                briefing = nil
            }
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }
}

struct NutritionRecoveryCard: View {
    let score: NutritionRecoveryScore

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.rowSpacing) {
            GroupedCard(Text("Nutrition-to-Recovery"), footer: Text("This score estimates how your logged nutrition supports recovery. Compare these factors with your overnight readings across several days.")) {
                GroupedRow.value(Text("Recovery nutrition score"), value: NutritionDisplay.score(score.n2rScore))
                if score.n2rScore == nil {
                    GroupedRow.value(Text("Score availability"), value: Text("More data needed"),
                                     detail: Text("Log at least 30% of your energy target and foods with enough nutrient information."))
                }
                ForEach(NutritionRecoveryFactor.ranked(in: score)) { factor in
                    GroupedRow.value(factor.kind.title, value: Text("−\(NutritionDisplay.number(factor.points)) pts"),
                                     detail: factor.kind.explanation)
                }
                if score.fuelMultiplier < 1 {
                    GroupedRow.value(Text("Fuel adequacy"), value: NutritionDisplay.amount(score.fuelMultiplier * 100, unit: "%"),
                                     detail: Text("Your log shows low energy or carbohydrate intake for a demanding day. Check for missing meals and compare your intake with the coaching targets."))
                }
                if let covered = score.coveredAddedSugarG, covered > 0 {
                    GroupedRow.value(Text("Workout fueling"), value: NutritionDisplay.amount(covered, unit: "g"),
                                     detail: Text("This amount of added sugar was covered by the training allowance. The model accounts for carbohydrates used to refuel around qualifying sessions."))
                }
            }
            DisclosureGroup {
                calculation
            } label: {
                Text("Calculation details").font(.ryft(.callout))
            }
        }
    }

    private var calculation: some View {
        GroupedCard {
            GroupedRow.value(Text("Dynamic food quality"), value: NutritionDisplay.score(score.qualityScore))
            GroupedRow.value(Text("Contextual glucose impact"), value: NutritionDisplay.score(score.glucoseScore))
            GroupedRow.value(Text("Training strain"), value: Text(verbatim: NutritionCoachingLabels.words(score.budget.strain)))
            GroupedRow.value(Text("Energy target"), value: NutritionDisplay.amount(score.budget.energyTargetKcal, unit: "kcal"))
            GroupedRow.value(Text("Carbohydrate target"), value: NutritionDisplay.amount(score.budget.carbTargetG, unit: "g"))
            GroupedRow.value(Text("Fuel adequacy"), value: NutritionDisplay.amount(score.fuelMultiplier * 100, unit: "%"))
            if let allowance = score.budget.postWorkoutCarbBudgetG {
                GroupedRow.value(Text("Workout carbohydrate allowance"), value: NutritionDisplay.amount(allowance, unit: "g"))
            }
            if let covered = score.coveredAddedSugarG {
                GroupedRow.value(Text("Added sugar covered by training"), value: NutritionDisplay.amount(covered, unit: "g"))
            }
            if let covered = score.coveredCarbG {
                GroupedRow.value(Text("Carbohydrates covered by training"), value: NutritionDisplay.amount(covered, unit: "g"))
            }
            if let netSugar = score.netAddedSugarG {
                GroupedRow.value(Text("Added sugar after allowance"), value: NutritionDisplay.amount(netSugar, unit: "g"))
            }
            if let sodium = score.budget.sodiumExemptionMg {
                GroupedRow.value(Text("Sweat-sodium allowance"), value: NutritionDisplay.amount(sodium, unit: "mg"))
            }
            if let omega = score.omega3DepotMg {
                GroupedRow.value(Text("14-day omega-3 intake"), value: NutritionDisplay.amount(omega, unit: "mg/day"))
            }
            if let caffeine = score.caffeineBedMg {
                GroupedRow.value(Text("Estimated caffeine at bedtime"), value: NutritionDisplay.amount(caffeine, unit: "mg"))
            }
            if let halfLife = score.effectiveCaffeineHalfLifeH {
                GroupedRow.value(Text("Effective caffeine half-life"), value: NutritionDisplay.amount(halfLife, unit: "h"))
            }
            if let components = score.components {
                NutritionRouteRow(Text("Dynamic food quality breakdown"), icon: "list.bullet") {
                    SubpageScaffold(Text("Dynamic food quality")) { NutritionComponentsCard(components: components) }
                }
            }
        }
    }
}

struct NutritionRecoveryFactor: Identifiable {
    enum Kind: Int {
        case alcohol, caffeine, lateMeal

        var title: Text {
            switch self {
            case .alcohol: Text("Evening alcohol")
            case .caffeine: Text("Caffeine near bedtime")
            case .lateMeal: Text("Late meal timing")
            }
        }

        var explanation: Text {
            switch self {
            case .alcohol: Text("Alcohol can raise overnight heart rate and lower HRV. Look for patterns on evenings with and without alcohol.")
            case .caffeine: Text("The model estimates caffeine remaining at bedtime from when and how much you logged. An earlier last dose leaves more time for it to clear.")
            case .lateMeal: Text("Meal size, timing and composition contributed to this adjustment. See whether moving a large meal earlier changes how the next night feels.")
            }
        }
    }

    let kind: Kind
    let points: Double
    var id: Kind { kind }

    static func ranked(in score: NutritionRecoveryScore) -> [Self] {
        let adjustments: [(Kind, Double?)] = [(.alcohol, score.alcoholPenalty), (.caffeine, score.caffeinePenalty),
                                               (.lateMeal, score.lateMealPenalty)]
        return adjustments.compactMap { kind, points -> Self? in
            guard let points, points.isFinite, points > 0 else { return nil }
            return Self(kind: kind, points: points)
        }.sorted { $0.points == $1.points ? $0.kind.rawValue < $1.kind.rawValue : $0.points > $1.points }
    }
}

struct NutritionBiometricCard: View {
    let value: NutritionMorningBiometrics

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.rowSpacing) {
            GroupedCard(Text("Morning recovery"), footer: Text("These changes are measured against your own recent baseline. Compare them with sleep, training and nutrition over time.")) {
                if let delta = value.relativeHRVPercent {
                    datum(Text("HRV vs usual"), delta, "%")
                }
                if let delta = value.rhrDelta {
                    datum(Text("Resting heart rate vs usual"), delta, "bpm")
                }
                if value.relativeHRVPercent == nil && value.rhrDelta == nil {
                    GroupedRow.value(Text("Recent baseline"), value: Text("More data needed"))
                }
            }
            if value.lnRmssd7dMean != nil {
                DisclosureGroup {
                    GroupedCard {
                        GroupedRow.value(Text("Change"), value: Text(verbatim: NutritionCoachingLabels.words(value.change)))
                        statistic(Text("Log RMSSD change"), value.lnRmssdDelta)
                        statistic(Text("7-day log RMSSD mean"), value.lnRmssd7dMean)
                        statistic(Text("7-day standard deviation"), value.lnRmssd7dSd)
                        statistic(Text("7-day coefficient of variation"), value.lnRmssd7dCv, unit: "%")
                        statistic(Text("Smallest worthwhile change"), value.swc)
                    }
                } label: {
                    Text("Calculation details").font(.ryft(.callout))
                }
            }
        }
    }

    private func datum(_ title: Text, _ value: Double, _ unit: String) -> some View {
        let sign = value > 0 ? "+" : ""
        return GroupedRow.value(title, value: Text(verbatim: "\(sign)\(NutritionDisplay.number(value)) \(unit)"))
    }

    @ViewBuilder private func statistic(_ title: Text, _ amount: Double?, unit: String? = nil) -> some View {
        if let amount {
            let number = NutritionDisplay.number(amount, digits: 3)
            GroupedRow.value(title, value: Text(verbatim: unit.map { "\(number) \($0)" } ?? number))
        }
    }
}

struct NutritionTrainingPlanCard: View {
    let plan: NutritionCoachingPlan
    let load: NutritionTrainingLoad
    let readiness: String
    let reasons: [String]

    var body: some View {
        VStack(spacing: GroupedListSpec.groupSpacing) {
            GroupedCard(Text("Daily training plan")) {
                GroupedRowLabel(NutritionCoachingLabels.readinessTitle(readiness),
                                detail: NutritionCoachingLabels.readinessDetail(readiness), icon: "heart.text.clipboard")
                    .groupedRowHairline()
                ForEach(reasons, id: \.self) { reason in
                    GroupedRow.value(Text("Readiness context"), value: NutritionCoachingLabels.reason(reason))
                }
                GroupedRow.value(Text("Session"), value: Text(verbatim: NutritionCoachingLabels.words(plan.sessionClass)))
                row(Text("Energy target"), plan.energyTargetKcal, "kcal")
                row(Text("Protein target"), plan.proteinTargetG, "g")
                row(Text("Carbohydrate target"), plan.carbTargetG, "g")
                row(Text("Fat target"), plan.fatTargetG, "g")
                row(Text("Estimated net exercise energy"), plan.netExerciseKcal, "kcal")
                if plan.deficitSuspended { GroupedRow.value(Text("Calorie deficit"), value: Text("Suspended")) }
                if plan.trainLow { GroupedRow.value(Text("Train low"), value: Text("Planned")) }
            }
            GroupedCard(Text("Energy availability"), footer: Text("This estimates how much logged energy remains after exercise. The coaching plan uses the trend when assessing a calorie deficit.")) {
                GroupedRow.value(Text("Guardrail status"), value: Text(verbatim: NutritionCoachingLabels.availability(plan.availability.state)))
                if let energy = plan.availability.energyKcalPerKgFfm { row(Text("7-day energy availability"), energy, "kcal/kg FFM") }
                if let carbs = plan.availability.carbsGPerKg { row(Text("7-day carbohydrates"), carbs, "g/kg") }
                ForEach(plan.availability.markers ?? [], id: \.self) { marker in
                    GroupedRow.value(Text("Reason"), value: Text(verbatim: NutritionCoachingLabels.words(marker)))
                }
            }
            GroupedCard(Text("Training load")) {
                row(Text("7-day load"), load.acute7d, "")
                row(Text("28-day weekly load"), load.chronic28dWeekly, "")
                if let ratio = load.acwr { row(Text("Acute-to-chronic ratio"), ratio, "") }
                row(Text("Training stress balance"), load.tsb, "")
            }
            if let fuel = plan.fueling { fueling(fuel) }
        }
    }

    private func fueling(_ fuel: NutritionFuelingPlan) -> some View {
        GroupedCard(Text("Session fueling")) {
            if fuel.carbMaxGPerH > 0 {
                let range = "\(NutritionDisplay.number(fuel.carbMinGPerH))–\(NutritionDisplay.number(fuel.carbMaxGPerH))"
                GroupedRow.value(Text("Carbohydrates during exercise"), value: Text(verbatim: "\(range) g/h"))
            }
            if let ratio = fuel.glucoseFructoseRatio {
                GroupedRow.value(Text("Glucose to fructose"), value: Text(verbatim: ratio))
            }
            if let low = fuel.preRaceMinG, let high = fuel.preRaceMaxG {
                GroupedRow.value(Text("Pre-race carbohydrates"),
                                 value: Text(verbatim: "\(NutritionDisplay.number(low))–\(NutritionDisplay.number(high)) g"))
            }
            if let fluids = fuel.postWorkoutFluidsL { row(Text("Post-workout fluids"), fluids, "L") }
            if let sodium = fuel.sweatSodiumMg { row(Text("Sweat sodium"), sodium, "mg") }
        }
    }

    private func row(_ title: Text, _ value: Double, _ unit: String) -> some View {
        GroupedRow.value(title, value: NutritionDisplay.amount(value, unit: unit))
    }
}

enum NutritionCoachingLabels {
    static func words(_ key: String) -> String { key.replacingOccurrences(of: "_", with: " ").lowercased().capitalized }

    static func readinessTitle(_ key: String) -> Text {
        switch key {
        case "ACUTE_LIFESTYLE_SUPPRESSION": Text("Evening factors may play a role")
        case "AUTONOMIC_FATIGUE": Text("Signs of fatigue")
        case "LEA_GUARDRAIL_ACTIVE": Text("Fueling guardrail active")
        case "OPTIMAL": Text("Within your usual range")
        default: Text("More data needed")
        }
    }

    static func readinessDetail(_ key: String) -> Text? {
        switch key {
        case "ACUTE_LIFESTYLE_SUPPRESSION":
            Text("HRV fell and became more variable. Yesterday’s log contains evening factors that may help explain the pattern.")
        case "AUTONOMIC_FATIGUE":
            Text("HRV fell and became more variable. Coaching takes this pattern into account when setting today’s fueling targets.")
        case "LEA_GUARDRAIL_ACTIVE":
            Text("The intake and training trend triggered the fueling guardrail. Check the energy availability section for the reason.")
        default: nil
        }
    }

    static func reason(_ key: String) -> Text {
        switch key {
        case "alcohol_above_035gkg": Text("Alcohol in yesterday’s log")
        case "caffeine_bed_high": Text("Estimated caffeine at bedtime")
        case "late_satfat_meal": Text("Late meal high in saturated fat")
        case "lnrmssd_below_swc": Text("HRV below your recent baseline")
        case "lnrmssd_cv_rising": Text("HRV has varied more recently")
        default: Text(verbatim: words(key))
        }
    }

    static func availability(_ key: String) -> String {
        switch key {
        case "GREEN": String(localized: "Within target")
        case "YELLOW": String(localized: "Low availability")
        case "RED": String(localized: "Guardrail active")
        default: String(localized: "Insufficient data")
        }
    }

    static func card(_ code: String) -> String {
        switch code {
        case "POST_WORKOUT_ENDURANCE_REFEED": String(localized: "Endurance refueling")
        case "POST_WORKOUT_STRENGTH_PRESLEEP": String(localized: "Pre-sleep protein")
        case "CAFFEINE_CUTOFF_WARNING": String(localized: "Caffeine cutoff")
        case "LATE_MEAL_COMPOSITION_GUARD": String(localized: "Evening meal")
        case "ALCOHOL_MITIGATION": String(localized: "Alcohol and recovery")
        case "RED_RECOVERY_PROTOCOL": String(localized: "Recovery guidance")
        default: words(code)
        }
    }
}
