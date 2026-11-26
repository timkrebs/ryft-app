import SwiftUI
import UniformTypeIdentifiers

struct NutritionSettingsView: View {
    let model: NutritionDiaryModel
    let api: APIClient

    var body: some View {
        SubpageScaffold(Text("Nutrition settings")) {
            VStack(spacing: GroupedListSpec.groupSpacing) {
                menu
                if model.hasFullAccess { NutritionWeightSharingView(model: model) }
            }
        }
    }

    private var menu: some View {
        GroupedCard {
            NutritionRouteRow(Text("Daily nutrient targets"), icon: "target") { NutritionTargetsEditor(model: model, api: api) }
            if model.hasFullAccess {
                NutritionRouteRow(Text("Recovery profile"), icon: "moon.zzz") { NutritionRecoveryEditor(model: model, api: api) }
                NutritionRouteRow(Text("Training goal"), icon: "figure.run") { NutritionGoalEditor(model: model, api: api) }
                NutritionRouteRow(Text("Session and fueling feedback"), icon: "square.and.pencil") {
                    NutritionFeedbackEditor(model: model, api: api)
                }
                NutritionRouteRow(Text("Glucose data"), icon: "waveform.path") { NutritionGlucoseView(model: model, api: api) }
            }
        }
    }
}

/// Erasure and local opt-out stay reachable when the server closes either Nutrition rollout.
struct NutritionPrivacyEntryView: View {
    @Environment(\.appEnvironment) private var env

    var body: some View {
        if let account = env.auth.accountID, let api = env.api as? APIClient, !env.isDemo {
            let model = NutritionDiaryModel(env: env, api: api, account: account, timezone: TimeZone.current.identifier)
            SubpageScaffold(Text("Nutrition privacy")) {
                VStack(spacing: GroupedListSpec.groupSpacing) {
                    NutritionWeightSharingView(model: model, allowsEnrollment: false)
                    GroupedCard {
                        NutritionRouteRow(Text("Glucose data"), icon: "waveform.path") {
                            NutritionGlucoseView(model: model, api: api, allowsImport: false)
                        }
                    }
                }
            }
            .id(account)
        }
    }
}

private struct NutritionField: Identifiable {
    let id: String
    let label: LocalizedStringKey
    let range: ClosedRange<Double>

    init(_ id: String, _ label: LocalizedStringKey, _ range: ClosedRange<Double>) {
        self.id = id
        self.label = label
        self.range = range
    }

    static func rows(_ fields: [Self], values: Binding<[String: String]>) -> some View {
        ForEach(fields) { field in
            NutritionInputRow(title: Text(field.label),
                              value: Binding(get: { values.wrappedValue[field.id, default: ""] },
                                             set: { values.wrappedValue[field.id] = $0 }), numeric: true)
        }
    }

    static func parse(_ fields: [Self], _ values: [String: String]) throws -> [String: Double] {
        var result = [String: Double]()
        for field in fields {
            result[field.id] = try NutritionNumbers.parse(values[field.id, default: ""], in: field.range)
        }
        return result
    }

    static func display(_ value: Double?) -> String? {
        value?.formatted(.number.grouping(.never).precision(.fractionLength(0...6)))
    }

    static func prefill(_ values: [String: Double?]) -> [String: String] {
        values.compactMapValues(display)
    }
}

private struct NutritionSettingsStatus: View {
    let message: String?
    let saved: Bool

    var body: some View {
        if let message { InlineMessage(message: message, systemImage: "exclamationmark.circle") }
        if saved { GroupFooter(Text("Saved")) }
    }
}

private struct NutritionTargetsEditor: View {
    let model: NutritionDiaryModel
    let api: APIClient
    @State private var values: [String: String] = [:]
    @State private var revision: Int?
    @State private var busy = false
    @State private var failure: String?
    @State private var saved = false
    @State private var conflict = false

    var body: some View {
        SubpageScaffold(Text("Daily nutrient targets")) {
            VStack(spacing: GroupedListSpec.groupSpacing) {
                if revision != nil {
                    GroupedCard(Text("Your targets"), footer: Text("Leave a goal blank to clear it. Coaching can set different training-day targets.")) {
                        ForEach(NutritionNutrient.allCases) { nutrient in
                            NutritionInputRow(title: Text(verbatim: "\(nutrient.title) (\(nutrient.unit))"),
                                              value: Binding(get: { values[nutrient.rawValue, default: ""] },
                                                             set: { values[nutrient.rawValue] = $0 }), numeric: true)
                        }
                    }
                    .disabled(busy)
                    PillButton(Text("Save targets"), busy: busy) { await save() }.disabled(conflict || !model.online)
                }
                if revision == nil || conflict {
                    PillButton(Text("Load targets"), style: .secondary, busy: busy) { await load() }
                }
                NutritionSettingsStatus(message: failure, saved: saved)
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let goals = try await api.nutritionGoals()
            try model.needsCurrentAccount()
            revision = goals.revision
            values = goals.targets.compactMapValues { NutritionField.display($0) }
            failure = nil
            conflict = false
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func save() async {
        guard let revision, !busy else { return }
        busy = true
        saved = false
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            var targets: [String: Double] = [:]
            for (key, text) in values {
                targets[key] = try NutritionNumbers.parse(text, in: 0.000_001...100_000)
            }
            let result = try await api.saveNutritionGoals(.init(revision: revision, targets: targets))
            try model.needsCurrentAccount()
            self.revision = result.revision
            failure = nil
            saved = true
            await model.reload()
        } catch {
            conflict = (error as? APIError)?.status == 409
            if !error.isCancellation {
                failure = conflict ? String(localized: "Your targets changed elsewhere. Load the current targets first.") : error.localizedDescription
            }
        }
    }
}

private struct NutritionRecoveryEditor: View {
    let model: NutritionDiaryModel
    let api: APIClient

    private static let fields: [NutritionField] = [
        .init("mass", "Body mass (kg)", 25...350),
        .init("rate", "Sweat rate (L/h)", 0...5),
        .init("sodium", "Sweat sodium (mg/L)", 0...5000),
        .init("caffeine", "Caffeine half-life (hours)", 1...12),
    ]

    @State private var values: [String: String] = [:]
    @State private var profile: NutritionRecoveryProfile?
    @State private var sex = "unspecified"
    @State private var bedtime = ""
    @State private var nextWorkout = Date.now
    @State private var hasNextWorkout = false
    @State private var loaded = false
    @State private var busy = false
    @State private var failure: String?
    @State private var saved = false
    @State private var deleting = false

    var body: some View {
        SubpageScaffold(Text("Recovery profile")) {
            VStack(spacing: GroupedListSpec.groupSpacing) {
                if loaded {
                    GroupedCard(Text("Nutrition-to-Recovery"),
                                footer: Text("Saving opts in to contextual scoring and recovery calibration. Optional values use Platform defaults.")) {
                        NutritionField.rows(Self.fields, values: $values)
                        Picker("Sex used for scoring", selection: $sex) {
                            Text("Unspecified").tag("unspecified")
                            Text("Female").tag("female")
                            Text("Male").tag("male")
                        }.nutritionField()
                        NutritionInputRow(title: Text("Expected bedtime (HH:mm)"), value: $bedtime, time: true)
                        Toggle("Next workout planned", isOn: $hasNextWorkout).nutritionField()
                        if hasNextWorkout {
                            DatePicker("Next workout", selection: $nextWorkout)
                                .environment(\.timeZone, NutritionDay.calendar(model.timezone).timeZone)
                                .nutritionField()
                        }
                    }
                    .disabled(busy)
                    PillButton(Text("Save recovery profile"), busy: busy) { await save() }.disabled(!model.online)
                    if profile != nil {
                        PillButton(Text("Turn off recovery scoring"), style: .destructive) { deleting = true }.disabled(busy || !model.online)
                    }
                } else {
                    PillButton(Text("Load profile"), style: .secondary, busy: busy) { await load() }
                }
                NutritionSettingsStatus(message: failure, saved: saved)
            }
        }
        .task { await load() }
        .confirmationDialog("Turn off recovery scoring?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Turn off and delete recovery profile", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes your recovery profile and its derived night records.")
        }
    }

    private func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let response = try await api.nutritionRecoveryProfile()
            try model.needsCurrentAccount()
            profile = response
            if let response {
                values = NutritionField.prefill(["mass": response.bodyMassKg, "rate": response.sweatRateLPerH,
                                                 "sodium": response.sweatNaMgPerL, "caffeine": response.caffeineHalfLifeH])
                sex = response.sex
                bedtime = response.expectedBedtime
                if let next = response.nextWorkoutStartAt {
                    nextWorkout = next
                    hasNextWorkout = true
                }
            }
            loaded = true
            failure = nil
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func save() async {
        guard !busy else { return }
        busy = true
        saved = false
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            let data = try NutritionField.parse(Self.fields, values)
            guard let mass = data["mass"] else { throw NutritionInputError.invalidNumber }
            let clock = bedtime.trimmingCharacters(in: .whitespaces)
            guard clock.isEmpty || clock.range(of: #"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"#, options: .regularExpression) != nil else {
                failure = String(localized: "Enter bedtime in 24-hour HH:mm format.")
                return
            }
            let result = try await api.saveNutritionRecoveryProfile(
                .init(bodyMassKg: mass, sex: sex, sweatRateLPerH: data["rate"], sweatNaMgPerL: data["sodium"],
                      caffeineHalfLifeH: data["caffeine"], expectedBedtime: clock, nextWorkoutStartAt: hasNextWorkout ? nextWorkout : nil)
            )
            try model.needsCurrentAccount()
            profile = result
            failure = nil
            saved = true
            await model.reload()
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func delete() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            try await api.deleteNutritionRecoveryProfile()
            try model.needsCurrentAccount()
            profile = nil
            values = [:]
            bedtime = ""
            hasNextWorkout = false
            sex = "unspecified"
            saved = false
            failure = nil
            await model.reload()
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }
}

private struct NutritionGoalEditor: View {
    let model: NutritionDiaryModel
    let api: APIClient

    private static let fields: [NutritionField] = [
        .init("height", "Height (cm)", 120...230), .init("fat", "Body fat (%)", 3...65),
        .init("ftp", "Cycling FTP (W)", 30...800), .init("max", "Maximum heart rate (bpm)", 80...240),
        .init("rest", "Resting heart rate (bpm)", 25...130), .init("sodium", "Sweat sodium (mg/L)", 200...2000),
    ]

    @State private var values: [String: String] = [:]
    @State private var goal = NutritionTrainingGoal.hypertrophy
    @State private var raceDate = Date.now
    @State private var hasRaceDate = false
    @State private var gutTrained = false
    @State private var recreational = true
    @State private var trainLow = false
    @State private var adjustment = ""
    @State private var savedProfile: NutritionGoalProfile?
    @State private var busy = false
    @State private var loaded = false
    @State private var failure: String?
    @State private var saved = false
    @State private var deleting = false

    private var isRace: Bool { goal == .marathon || goal == .cyclingRace }
    private var adjustmentRange: ClosedRange<Double> { goal == .hypertrophy ? 5...15 : 10...20 }

    var body: some View {
        SubpageScaffold(Text("Training goal")) {
            VStack(spacing: GroupedListSpec.groupSpacing) {
                if loaded {
                    GroupedCard(Text("Goal profile"), footer: Text("Coaching uses your birth year in Profile and your body mass in Recovery profile.")) {
                        Picker("Goal", selection: $goal) {
                            Text("Hypertrophy").tag(NutritionTrainingGoal.hypertrophy)
                            Text("Marathon").tag(NutritionTrainingGoal.marathon)
                            Text("Cycling race").tag(NutritionTrainingGoal.cyclingRace)
                            Text("Fat loss or recomposition").tag(NutritionTrainingGoal.recomposition)
                        }.nutritionField()
                        NutritionField.rows(Self.fields, values: $values)
                        if isRace {
                            Toggle("Set race date", isOn: $hasRaceDate).nutritionField()
                            if hasRaceDate {
                                DatePicker("Race day", selection: $raceDate, displayedComponents: .date)
                                    .environment(\.timeZone, NutritionDay.calendar(model.timezone).timeZone)
                                    .nutritionField()
                            }
                            Toggle("Recreational athlete", isOn: $recreational).nutritionField()
                        } else {
                            NutritionInputRow(title: goal == .hypertrophy ? Text("Preferred surplus (%)") : Text("Preferred deficit (%)"),
                                              value: $adjustment, numeric: true)
                        }
                        Toggle("Gut-trained for endurance fueling", isOn: $gutTrained).nutritionField()
                        Toggle("Allow low-carbohydrate Zone 2 sessions", isOn: $trainLow).nutritionField()
                    }
                    .disabled(busy)
                    PillButton(Text("Save training goal"), busy: busy) { await save() }.disabled(!model.online)
                    if savedProfile != nil {
                        PillButton(Text("Remove training goal"), style: .destructive) { deleting = true }.disabled(busy || !model.online)
                    }
                } else {
                    PillButton(Text("Load training goal"), style: .secondary, busy: busy) { await load() }
                }
                NutritionSettingsStatus(message: failure, saved: saved)
            }
        }
        .task { await load() }
        .confirmationDialog("Remove training goal?", isPresented: $deleting, titleVisibility: .visible) {
            Button("Remove goal and coaching history", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your training goal, coaching partner links, and coaching history.")
        }
    }

    private func load() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let profile = try await api.nutritionGoalProfile()
            try model.needsCurrentAccount()
            savedProfile = profile
            if let profile {
                goal = profile.goal
                values = NutritionField.prefill(["height": profile.heightCm, "fat": profile.bodyFatPct, "ftp": profile.ftpW,
                                                 "max": profile.hrMax, "rest": profile.hrRest, "sodium": profile.sweatNaMgPerL])
                if let date = profile.raceDate {
                    let pieces = date.split(separator: "-").compactMap { Int($0) }
                    if pieces.count == 3, let day = NutritionDay.calendar(model.timezone)
                        .date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2])) {
                        raceDate = day
                        hasRaceDate = true
                    }
                }
                recreational = profile.recreational
                gutTrained = profile.gutTrained
                trainLow = profile.trainLow
                adjustment = NutritionField.display(profile.goalAdjustment.map { $0 * 100 }) ?? ""
            }
            loaded = true
            failure = nil
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func save() async {
        guard !busy else { return }
        busy = true
        saved = false
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            let numbers = try NutritionField.parse(Self.fields, values)
            guard let height = numbers["height"] else { throw NutritionInputError.invalidNumber }
            let fraction = isRace ? nil : try NutritionNumbers.parse(adjustment, in: adjustmentRange).map { $0 / 100 }
            let race = isRace && hasRaceDate ? NutritionDay.key(raceDate, timezone: model.timezone) : nil
            let result = try await api.saveNutritionGoalProfile(
                .init(goal: goal, raceDate: race, heightCm: height, bodyFatPct: numbers["fat"], ftpW: numbers["ftp"],
                      hrMax: numbers["max"], hrRest: numbers["rest"], gutTrained: gutTrained, recreational: recreational,
                      sweatNaMgPerL: numbers["sodium"], goalAdjustment: fraction, trainLow: trainLow)
            )
            try model.needsCurrentAccount()
            savedProfile = result
            saved = true
            failure = nil
            await model.reload()
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func delete() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            try await api.deleteNutritionGoalProfile()
            try model.needsCurrentAccount()
            savedProfile = nil
            saved = false
            failure = nil
            await model.reload()
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }
}

private struct NutritionFeedbackEditor: View {
    let model: NutritionDiaryModel
    let api: APIClient

    private static let fields: [NutritionField] = [
        .init("minutes", "Completed workout duration (min)", 10...1440),
        .init("before", "Pre-workout mass (kg)", 25...350), .init("after", "Post-workout mass (kg)", 25...350),
        .init("fluid", "Fluids during workout (L)", 0...20), .init("urine", "Urine during workout (L)", 0...20),
        .init("patch", "Sweat patch sodium (mg/L)", 200...2000), .init("carbs", "Carbohydrates during workout (g)", 0...1500),
        .init("gi", "Digestive distress (0–10)", 0...10), .init("rpe", "Perceived exertion (0–10)", 0...10),
        .init("fatigue", "Fatigue (0–10)", 0...10), .init("rmr", "Measured resting metabolism (kcal)", 600...5000),
        .init("cycles", "Tracked cycles", 0...100), .init("water", "Measured cycle water offset (kg)", 0...4),
    ]

    @State private var values: [String: String] = [:]
    @State private var complete = false
    @State private var fasting = false
    @State private var confounder = false
    @State private var planned = false
    @State private var sessionType = "MODERATE"
    @State private var sport = ""
    @State private var duration = ""
    @State private var startAt = Date.now
    @State private var busy = false
    @State private var failure: String?
    @State private var saved = false

    var body: some View {
        SubpageScaffold(Text("Session feedback")) {
            VStack(spacing: GroupedListSpec.groupSpacing) {
                GroupedCard(Text(verbatim: model.day),
                            footer: Text("Saving replaces the feedback and planned session for this day.")) {
                    Toggle("Food log is complete", isOn: $complete).nutritionField()
                    Toggle("Fasting day", isOn: $fasting).nutritionField()
                    Toggle("Reported overnight confounder", isOn: $confounder).nutritionField()
                    Toggle("Add a planned session", isOn: $planned).nutritionField()
                    if planned {
                        DatePicker("Session start", selection: $startAt)
                            .environment(\.timeZone, NutritionDay.calendar(model.timezone).timeZone)
                            .nutritionField()
                        NutritionInputRow(title: Text("Sport"), value: $sport)
                        NutritionInputRow(title: Text("Planned duration (min)"), value: $duration, numeric: true)
                        Picker("Session type", selection: $sessionType) {
                            Text("Rest").tag("REST")
                            Text("Low-intensity Zone 2").tag("ZONE2_LOW")
                            Text("Moderate").tag("MODERATE")
                            Text("Key high-intensity session").tag("KEY_HIGH_INTENSITY")
                        }.nutritionField()
                    }
                    NutritionField.rows(Self.fields, values: $values)
                }
                .disabled(busy)
                PillButton(Text("Save feedback"), busy: busy) { await save() }.disabled(!model.online)
                NutritionSettingsStatus(message: failure, saved: saved)
            }
        }
        .onAppear { if !planned { startAt = model.date } }
    }

    private func save() async {
        guard !busy else { return }
        busy = true
        saved = false
        defer { busy = false }
        do {
            try model.needsCurrentAccount()
            let n = try NutritionField.parse(Self.fields, values)
            var session: NutritionPlannedSession?
            if planned {
                let activity = sport.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let minutes = try NutritionNumbers.parse(duration, in: 1...1440), !activity.isEmpty,
                      NutritionDay.key(startAt, timezone: model.timezone) == model.day else {
                    failure = String(localized: "Enter a sport, duration, and start time on the selected day.")
                    return
                }
                session = .init(startAt: startAt, sportType: activity, durationMin: minutes, classification: sessionType)
            }
            let cycles = n["cycles"].flatMap(Int.init(exactly:))
            guard n["cycles"] == nil || cycles != nil else { throw NutritionInputError.invalidNumber }
            let body = NutritionCoachingFeedback(intakeComplete: complete, isFastingDay: fasting, plannedSession: session,
                                                workoutMinutes: n["minutes"], preWorkoutMassKg: n["before"], postWorkoutMassKg: n["after"],
                                                fluidDuringWorkoutL: n["fluid"], urineDuringWorkoutL: n["urine"], sweatPatchNaMgPerL: n["patch"],
                                                intraWorkoutCarbsG: n["carbs"], giDistress: n["gi"], rpe: n["rpe"], fatigue: n["fatigue"],
                                                measuredRmrKcal: n["rmr"], cycleWaterKg: n["water"], reportedOvernightConfounder: confounder,
                                                trackedCycles: cycles)
            try await api.saveNutritionFeedback(body, day: model.day)
            try model.needsCurrentAccount()
            failure = nil
            saved = true
            await model.reload()
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }
}

private struct NutritionGlucoseView: View {
    let model: NutritionDiaryModel
    let api: APIClient
    var allowsImport = true
    @Environment(\.appEnvironment) private var env
    @State private var batch: NutritionGlucoseBatch?
    @State private var choosing = false
    @State private var busy = false
    @State private var deletion: AccountBinding?
    @State private var failure: String?
    @State private var result: String?

    var body: some View {
        SubpageScaffold(Text("Glucose data")) {
            VStack(spacing: GroupedListSpec.groupSpacing) {
                if allowsImport && model.hasFullAccess {
                    importCard
                    if batch != nil {
                        PillButton(Text("Upload readings"), busy: busy) { await upload() }.disabled(!model.online)
                    }
                }
                PillButton(Text("Delete glucose history"), style: .destructive) { deletion = AccountBinding(env) }
                    .disabled(!model.hasSignedInAccount || !model.online || busy)
                if let result { GroupFooter(Text(verbatim: result)) }
                if let failure { InlineMessage(message: failure, systemImage: "exclamationmark.circle") }
            }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.commaSeparatedText]) { selection in
            do {
                guard allowsImport else { return }
                try model.needsFullAccess()
                batch = try NutritionGlucoseCSV.read(selection.get())
                result = nil
                failure = nil
            } catch {
                batch = nil
                if !error.isCancellation { failure = error.localizedDescription }
            }
        }
        .confirmationDialog("Delete all uploaded glucose readings?",
                            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }),
                            titleVisibility: .visible, presenting: deletion) { binding in
            Button("Delete glucose history", role: .destructive) { Task { await remove(confirmedFor: binding) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("RYFT will remove the glucose readings stored for this account.")
        }
        .onChange(of: model.hasFullAccess) { _, available in
            if !available {
                choosing = false
                batch = nil
            }
        }
    }

    private var importCard: some View {
        GroupedCard(Text("CGM import"), footer: Text("Use a CSV with timestamp and glucose_mg_dl columns. Include the time zone in each timestamp.")) {
            GroupedRow.action(Text("Choose glucose CSV"), systemImage: "doc") { choosing = true }.disabled(busy)
            if let health = env.health as? HealthKitManager, health.isAvailable {
                GroupedRow.action(Text("Read glucose from Apple Health"), systemImage: "heart", busy: busy) {
                    Task { await collect(health) }
                }
            }
            if let batch {
                GroupedRow.value(Text("Readings to upload"), value: Text(verbatim: "\(batch.samples.count)"))
            }
        }
    }

    private func collect(_ health: HealthKitManager) async {
        guard allowsImport, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try model.needsFullAccess()
            let readings = try await health.nutritionGlucose(on: model.date, timezone: model.timezone)
            try model.needsFullAccess()
            batch = readings.samples.isEmpty ? nil : readings
            result = readings.samples.isEmpty ? String(localized: "No glucose readings were available for this day.") : nil
            failure = nil
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func upload() async {
        guard allowsImport, let batch, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            try model.needsFullAccess()
            for start in stride(from: 0, to: batch.samples.count, by: 500) {
                try model.needsFullAccess()
                let end = min(start + 500, batch.samples.count)
                try await api.uploadNutritionGlucose(.init(samples: Array(batch.samples[start..<end])))
            }
            try model.needsFullAccess()
            self.batch = nil
            result = String(localized: "Glucose readings uploaded.")
            failure = nil
            await model.reload()
        } catch {
            if !error.isCancellation { failure = error.localizedDescription }
        }
    }

    private func remove(confirmedFor binding: AccountBinding) async {
        guard !busy, binding.isCurrent(in: env) else { return }
        busy = true
        defer { busy = false }
        do {
            try model.needsSignedInAccount()
            try await env.auth.withBoundAccount(binding) {
                try await api.deleteNutritionGlucose()
            }
            guard binding.isCurrent(in: env) else { return }
            batch = nil
            result = String(localized: "Glucose history deleted.")
            failure = nil
            if allowsImport { await model.reload() }
        } catch {
            if binding.isCurrent(in: env), !error.isCancellation { failure = error.localizedDescription }
        }
    }
}
