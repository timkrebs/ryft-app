import Foundation
import Observation

/// Short-lived reads for a single open diary. The signed-in account is checked before every use.
struct NutritionReadCache<Key: Hashable, Value> {
    private var entries: [Key: (value: Value, at: Date)] = [:]
    let lifetime: TimeInterval
    let capacity: Int

    func value(for key: Key, at now: Date) -> Value? {
        guard let entry = entries[key], (0..<lifetime).contains(now.timeIntervalSince(entry.at)) else { return nil }
        return entry.value
    }

    mutating func insert(_ value: Value, for key: Key, at now: Date) {
        entries[key] = (value, now)
        if entries.count > capacity, let oldest = entries.min(by: { $0.value.at < $1.value.at })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    mutating func clear() { entries.removeAll(keepingCapacity: true) }
}

enum NutritionDay {
    static func calendar(_ timezone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timezone) ?? .current
        return calendar
    }

    static func key(_ date: Date, timezone: String) -> String {
        let parts = calendar(timezone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

enum NutritionInputError: LocalizedError {
    case invalidNumber, invalidGlucoseFile, invalidMeal, pendingMeal, storage, offline

    var errorDescription: String? {
        switch self {
        case .invalidNumber: String(localized: "Enter valid numbers in the selected units.")
        case .invalidGlucoseFile: String(localized: "Use a CSV with 1–500 unique readings and the headers timestamp,glucose_mg_dl.")
        case .invalidMeal: String(localized: "Add at least one food and review its quantity before saving.")
        case .pendingMeal: String(localized: "Finish or discard your pending meal before saving a new one.")
        case .storage: String(localized: "RYFT couldn't save this meal draft on the device.")
        case .offline: String(localized: "You're offline. Connect to the internet to update Nutrition.")
        }
    }
}

enum NutritionNumbers {
    /// Empty inputs are unknown. A nonempty invalid value stays visible for correction on save.
    static func parse(_ text: String, in limits: ClosedRange<Double>, locale: Locale = .current) throws -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let decimal = locale.decimalSeparator ?? "."
        let parts = value.components(separatedBy: decimal)
        guard parts.count <= 2, let n = Double(parts.joined(separator: ".")),
              value.replacingOccurrences(of: decimal, with: "").allSatisfy({ $0.isASCII && ($0.isNumber || $0 == "-") }),
              n.isFinite, limits.contains(n) else { throw NutritionInputError.invalidNumber }
        return n
    }
}

enum NutritionGlucoseCSV {
    static let maximumBytes = 96_000

    static func parse(_ data: Data) throws -> NutritionGlucoseBatch {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else {
            throw NutritionInputError.invalidGlucoseFile
        }
        let lines = text.split(whereSeparator: \.isNewline)
        guard let header = lines.first, header.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            == "timestamp,glucose_mg_dl", (2...501).contains(lines.count) else { throw NutritionInputError.invalidGlucoseFile }
        let iso = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var timestamps = Set<Int64>()
        let readings: [NutritionGlucoseReading] = try lines.dropFirst().map { line in
            let pair = line.split(separator: ",", omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard pair.count == 2, let at = iso.date(from: pair[0]) ?? fractional.date(from: pair[0]),
                  let amount = Double(pair[1]), amount.isFinite, amount > 0, amount <= 10_000,
                  (1900...2200).contains(Calendar(identifier: .gregorian).component(.year, from: at)),
                  timestamps.insert(Int64(at.timeIntervalSince1970.rounded(.down))).inserted else {
                throw NutritionInputError.invalidGlucoseFile
            }
            return NutritionGlucoseReading(timestamp: at, glucoseMgDl: amount)
        }
        return NutritionGlucoseBatch(samples: readings)
    }

    static func read(_ url: URL) throws -> NutritionGlucoseBatch {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        return try parse(file.read(upToCount: maximumBytes + 1) ?? Data())
    }
}

struct NutritionDraftItem: Identifiable {
    var id = UUID()
    let name: String
    let inputMethod: String
    var selection: NutritionMealSelection

    init(name: String, inputMethod: String, selection: NutritionMealSelection) {
        self.name = name
        self.inputMethod = inputMethod
        self.selection = selection
    }

    init(_ saved: NutritionMealItem) {
        self.init(name: saved.foodName, inputMethod: "manual_entry",
                  selection: NutritionMealSelection(itemId: saved.id, foodId: saved.foodId, quantity: saved.quantity,
                                                    unit: saved.unit, portionId: saved.portionId))
    }

    var request: NutritionMealSelection {
        if let saved = selection.itemId { return NutritionMealSelection(itemId: saved) }
        return selection
    }
}

enum NutritionNutrient: String, CaseIterable, Identifiable {
    case energy = "energy_kcal"
    case protein
    case carbs = "carbohydrates"
    case fat, fiber, water
    case sodium
    case sugars = "total_sugar"
    case addedSugar = "added_sugar"
    case satFat = "saturated_fat"
    case transFat = "trans_fat"
    case monoFat = "monounsaturated_fat"
    case polyFat = "polyunsaturated_fat"
    case caffeine, alcohol, epa, dha

    var id: Self { self }

    static let main: [Self] = [.energy, .protein, .carbs, .fat, .fiber, .water]
    var unit: String {
        switch self {
        case .energy: "kcal"
        case .sodium, .caffeine: "mg"
        default: "g"
        }
    }

    var title: String {
        switch self {
        case .energy: String(localized: "Energy")
        case .protein: String(localized: "Protein")
        case .carbs: String(localized: "Carbohydrates")
        case .fat: String(localized: "Fat")
        case .fiber: String(localized: "Fiber")
        case .water: String(localized: "Water")
        case .sodium: String(localized: "Sodium")
        case .sugars: String(localized: "Total sugars")
        case .addedSugar: String(localized: "Added sugar")
        case .satFat: String(localized: "Saturated fat")
        case .transFat: String(localized: "Trans fat")
        case .monoFat: String(localized: "Monounsaturated fat")
        case .polyFat: String(localized: "Polyunsaturated fat")
        case .caffeine: String(localized: "Caffeine")
        case .alcohol: String(localized: "Alcohol")
        case .epa: "EPA"
        case .dha: "DHA"
        }
    }

    func total(in totals: [String: NutritionTotal]) -> NutritionTotal? {
        totals[rawValue] ?? (self == .carbs ? totals["carbohydrates_total"] : nil)
    }
}

@MainActor
@Observable
final class NutritionDiaryModel {
    private struct DayRead {
        let daily: NutritionDaily
        let firstPage: NutritionMealPage
    }

    let api: APIClient?
    let timezone: String
    let account: String?
    @ObservationIgnored private let env: AppEnvironment?
    private(set) var date: Date
    private(set) var daily: NutritionDaily?
    private(set) var meals: [NutritionMeal] = []
    private(set) var nextOffset: Int?
    private(set) var pending: NutritionMealWrite?
    private(set) var loading = false
    private(set) var saving = false
    private(set) var error: String?
    @ObservationIgnored private var readID = UUID()
    @ObservationIgnored private var days = NutritionReadCache<String, DayRead>(lifetime: 120, capacity: 7)
    @ObservationIgnored private var searches = NutritionReadCache<NutritionFoodSearch, NutritionFoodSearchPage>(lifetime: 120, capacity: 24)
    @ObservationIgnored private var foods = NutritionReadCache<UUID, NutritionFoodDetail>(lifetime: 300, capacity: 20)
    @ObservationIgnored private var catalogGeneration = 0

    init(env: AppEnvironment, api: APIClient, account: String, timezone: String) {
        self.env = env
        self.api = api
        self.account = account
        self.timezone = timezone
        date = env.clock.now()
        pending = env.accountDocuments?.document(NutritionMealWrite.self, key: "nutrition.pending.\(account)")
    }

    #if DEBUG
    init(preview: NutritionDaily?, meals: [NutritionMeal] = []) {
        env = nil
        api = nil
        account = nil
        timezone = TimeZone.current.identifier
        date = .now
        daily = preview
        self.meals = meals
    }
    #endif

    var day: String { NutritionDay.key(date, timezone: timezone) }
    var canAdvance: Bool {
        day < NutritionDay.key(env?.clock.now() ?? .now, timezone: timezone)
    }

    var online: Bool { env?.connectivity.isOnline ?? true }
    private var now: Date { env?.clock.now() ?? .now }
    var hasCurrentAccount: Bool {
        guard let env else { return false }
        return env.auth.accountID == account && !env.isDemo && env.flags.newest(.nutritionEnabled) == true
    }

    func move(_ days: Int) {
        guard days < 0 || canAdvance else { return }
        guard let next = NutritionDay.calendar(timezone).date(byAdding: .day, value: days, to: date) else { return }
        readID = UUID()
        date = next
        daily = nil
        meals = []
        nextOffset = nil
        error = nil
        loading = false
    }

    func reload() async {
        days.clear()
        readID = UUID()
        loading = false
        await load()
    }

    func load(more: Bool = false, force: Bool = false) async {
        guard let api, hasCurrentAccount, !loading else { return }
        if !more, !force, let cached = days.value(for: day, at: now) {
            if daily == nil { show(cached) }
            error = nil
            return
        }
        let offset = more ? nextOffset : 0
        guard let offset else { return }
        let id = UUID()
        readID = id
        loading = true
        error = nil
        defer { if readID == id { loading = false } }
        do {
            guard online else { throw NutritionInputError.offline }
            if more {
                let page = try await api.nutritionMeals(day: day, offset: offset)
                try needsCurrentAccount()
                guard readID == id else { return }
                let seen = Set(meals.map(\.id))
                meals += page.meals.filter { !seen.contains($0.id) }
                nextOffset = page.nextOffset
                return
            }
            let selectedDay = day
            async let totals = api.nutritionDay(selectedDay)
            async let list = api.nutritionMeals(day: selectedDay)
            let (newTotals, page) = try await (totals, list)
            try needsCurrentAccount()
            guard readID == id else { return }
            let read = DayRead(daily: newTotals, firstPage: page)
            days.insert(read, for: selectedDay, at: now)
            show(read)
        } catch {
            if readID == id && !error.isCancellation { self.error = error.localizedDescription }
        }
    }

    private func show(_ read: DayRead) {
        daily = read.daily
        meals = read.firstPage.meals
        nextOffset = read.firstPage.nextOffset
    }

    func searchFoods(_ query: NutritionFoodSearch) async throws -> NutritionFoodSearchPage {
        try needsCurrentAccount()
        guard online, let api else { throw NutritionInputError.offline }
        if let cached = searches.value(for: query, at: now) { return cached }
        let generation = catalogGeneration
        let page = try await api.searchNutritionFoods(query)
        try needsCurrentAccount()
        if generation == catalogGeneration { searches.insert(page, for: query, at: now) }
        return page
    }

    func foodDetail(_ id: UUID) async throws -> NutritionFoodDetail {
        try needsCurrentAccount()
        if let cached = foods.value(for: id, at: now) { return cached }
        guard online, let api else { throw NutritionInputError.offline }
        let detail = try await api.nutritionFood(id: id)
        try needsCurrentAccount()
        foods.insert(detail, for: id, at: now)
        return detail
    }

    func addedFood(_ food: NutritionFoodDetail) {
        guard hasCurrentAccount else { return }
        catalogGeneration += 1
        searches.clear()
        foods.insert(food, for: food.id, at: now)
    }

    func showError(_ failure: Error) {
        if !failure.isCancellation { error = failure.localizedDescription }
    }

    func needsCurrentAccount() throws {
        try Task.checkCancellation()
        guard hasCurrentAccount else { throw CancellationError() }
    }

    func create(_ meal: NutritionMealWrite) async throws -> NutritionMeal {
        try needsCurrentAccount()
        guard let api, let env, let account, let store = env.accountDocuments, !saving else { throw CancellationError() }
        guard pending == nil || pending == meal else { throw NutritionInputError.pendingMeal }
        guard !meal.items.isEmpty else { throw NutritionInputError.invalidMeal }
        saving = true
        defer { saving = false }
        let key = "nutrition.pending.\(account)"
        store.saveDocument(meal, key: key, at: env.clock.now())
        guard store.document(NutritionMealWrite.self, key: key) == meal else { throw NutritionInputError.storage }
        pending = meal
        guard online else { throw NutritionInputError.offline }
        let saved = try await api.createNutritionMeal(meal)
        try needsCurrentAccount()
        store.removeDocument(key: key)
        pending = nil
        return saved
    }

    func discardRejected(_ request: NutritionMealWrite) {
        if pending == request { discardPending() }
    }

    func discardPending() {
        guard hasCurrentAccount, !saving, let account else { return }
        env?.accountDocuments?.removeDocument(key: "nutrition.pending.\(account)")
        pending = nil
    }
}
