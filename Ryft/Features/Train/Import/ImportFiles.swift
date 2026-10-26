import Foundation

/// Why one picked or opened file can't be imported (ui.md P3 to P6, D5). Never carries the file's text.
enum ImportFileProblem: Equatable, Sendable {
    /// P3: not a text type, or text in an encoding RYFT doesn't read (UTF-16, UTF-32).
    case notCSV
    /// P4: over 8 MiB.
    case tooLarge
    /// P5: no permission, not downloaded from iCloud, or the read failed.
    case unreadable
    /// P6: 0 bytes or only blank lines.
    case empty
    /// D5: text, but no format recognises it.
    case notSupported

    init(_ problem: ImportFileAccess.Problem) {
        switch problem {
        case .notText: self = .notCSV
        case .tooLarge: self = .tooLarge
        case .unreadable: self = .unreadable
        case .empty: self = .empty
        }
    }

    init(_ error: ImportError) {
        switch error {
        case .tooLarge: self = .tooLarge
        case .unsupportedEncoding: self = .notCSV
        case .empty: self = .empty
        case .notRecognised, .mixedFormats: self = .notSupported
        case .tooManyFiles: self = .unreadable
        }
    }

    /// Step 1 keeps these (the user picks again there); a file no format recognises goes on to step 2 (D5).
    var isPickProblem: Bool { self != .notSupported }
}

/// One picked or opened file in the flow (ui.md §4, §5).
struct ImportPickedFile: Identifiable, Equatable, Sendable {
    /// Stable for the flow, and the `SourceLine.file` of everything read from it.
    let id: Int
    /// Shown in steps 1 and 2 only: never stored or logged.
    let name: String
    var status: Status

    enum Status: Equatable, Sendable {
        case reading
        case read(ImportBundle, confidence: ImportConfidence)
        case failed(ImportFileProblem)
    }

    var bundle: ImportBundle? {
        if case let .read(bundle, _) = status { return bundle }
        return nil
    }

    var problem: ImportFileProblem? {
        if case let .failed(problem) = status { return problem }
        return nil
    }

    var isReading: Bool { status == .reading }

    /// What the file holds, for its row in step 2 ("Plans", "Workouts").
    var content: Content? {
        guard let bundle else { return nil }
        switch (bundle.plans.isEmpty, bundle.sessions.isEmpty) {
        case (false, true): return .plans
        case (true, false): return .workouts
        case (false, false): return .plansAndWorkouts
        case (true, true): return .nothing
        }
    }

    enum Content: Equatable, Sendable {
        case plans, workouts, plansAndWorkouts, nothing
    }
}

/// Parsing a file the flow holds in memory: detection and the parse, off the main actor.
enum ImportFileReading {
    @concurrent
    static func read(_ file: ImportFile, index: Int) async -> ImportPickedFile.Status {
        MainThread.assertOff("Parsing an import file")
        do {
            let bundle = try await TrainImportReader.read(file, index: index)
            let head = ImportHygiene.head(of: ImportHygiene.decode(file.data).utf8)
            let confidence = TrainImportFormats.best(for: head)?.1 ?? .strong
            return .read(bundle, confidence: confidence)
        } catch let error as ImportError {
            return .failed(ImportFileProblem(error))
        } catch {
            return .failed(.unreadable)
        }
    }
}

/// The counts step 2 leads with (ui.md §5): each drops out at 0.
struct ImportSummary: Equatable, Sendable {
    var plans = 0
    var days = 0
    /// Exercise entries over the plans' days.
    var exercises = 0
    var workouts = 0
    var firstDay: LocalDate?
    var lastDay: LocalDate?

    init(_ bundle: ImportBundle) {
        plans = bundle.plans.count
        days = bundle.plans.reduce(0) { $0 + $1.days.count }
        exercises = bundle.plans.reduce(0) { $0 + $1.days.reduce(0) { $0 + $1.exercises.count } }
        workouts = bundle.sessions.count
        firstDay = bundle.sessions.map(\.start.date).min()
        lastDay = bundle.sessions.map(\.start.date).max()
    }
}

/// What step 2 shows for the files in hand (ui.md §5): pure, from the files' states.
struct ImportDetection: Equatable, Sendable {
    let files: [ImportPickedFile]

    enum State: Equatable, Sendable {
        /// P2 on step 2: a file is still being read.
        case reading
        /// D1 to D4, D6, D8: something to import.
        case detected
        /// D7: recognised, but no plan and no workout.
        case nothingInFile
        /// D5: no file is in a format RYFT reads.
        case notSupported(name: String)
        /// Only files that couldn't be read (an opened file, P3 to P6).
        case failed(ImportFileProblem, name: String)
        /// Files from different apps (a later format).
        case mixedApps
    }

    var state: State {
        if files.contains(where: \.isReading) { return .reading }
        let read = files.filter { $0.bundle != nil }
        if read.isEmpty {
            if let unsupported = files.first(where: { $0.problem == .notSupported }) {
                return .notSupported(name: unsupported.name)
            }
            if let failed = files.first, let problem = failed.problem { return .failed(problem, name: failed.name) }
            return .nothingInFile
        }
        if Set(read.compactMap { $0.bundle?.format.rawValue }).count > 1 { return .mixedApps }
        return bundle?.isEmpty == false ? .detected : .nothingInFile
    }

    /// The read files merged in pick order: a workout in two files is kept once (`.duplicateInFiles`).
    var bundle: ImportBundle? {
        files.compactMap(\.bundle).reduce(nil) { merged, next in merged?.merging(next) ?? next }
    }

    var summary: ImportSummary? { bundle.map(ImportSummary.init) }
    var canContinue: Bool { state == .detected }
    var hasPlans: Bool { (summary?.plans ?? 0) > 0 }
    var hasWorkouts: Bool { (summary?.workouts ?? 0) > 0 }
    /// D2: a plan and no workouts. D3: workouts and no plan.
    var isPlanOnly: Bool { state == .detected && hasPlans && !hasWorkouts }
    var isWorkoutsOnly: Bool { state == .detected && hasWorkouts && !hasPlans }
    /// D8: a file only partly recognised; its warnings open by default.
    var isWeak: Bool { files.contains { if case .read(_, .weak) = $0.status { true } else { false } } }
    /// The file list shows with more than one file or any that failed (ui.md §5).
    var showsFileList: Bool { files.count > 1 || files.contains { $0.problem != nil } }

    /// Warnings that dropped something (the disclosure's count), and notes (its second line).
    var problems: [ImportWarning] { (bundle?.warnings ?? []).filter { !$0.kind.isNote } }
    var notes: [ImportWarning] { (bundle?.warnings ?? []).filter(\.kind.isNote) }
    var suppressedWarnings: Int { bundle?.suppressedWarnings ?? 0 }
    var hasWarnings: Bool { !(bundle?.warnings.isEmpty ?? true) || suppressedWarnings > 0 }

    func name(ofFile index: Int) -> String? { files.first { $0.id == index }?.name }
}

extension LocalDate {
    /// 2000-01-01: only for a clock outside the years a `LocalDate` holds (1900 to 2999), never in practice.
    static let fallback = LocalDate(valid: 2000, 1, 1)

    /// For constants known to be valid dates.
    private init(valid year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Noon of the day in `zone`: a date to format, never one to compute ids with.
    func date(in zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .distantPast
    }

    /// The day `date` falls on in `zone`.
    init?(_ date: Date, in zone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        self.init(year: year, month: month, day: day)
    }
}

/// Dates and ranges in the import's words (ui.md §0: numbers first, the zone the flow captured).
enum ImportDateText {
    /// "8 Jun to 5 Jul 2026"; `spoken`: "8 June to 5 July 2026" for VoiceOver.
    static func range(_ first: LocalDate, _ last: LocalDate, zone: TimeZone, spoken: Bool = false,
                      locale: Locale = .autoupdatingCurrent) -> String {
        let month: Date.FormatStyle.Symbol.Month = spoken ? .wide : .abbreviated
        let short = Date.FormatStyle(locale: locale, timeZone: zone).day().month(month)
        let long = short.year()
        let from = first.date(in: zone)
        let to = last.date(in: zone)
        let start = first.year == last.year ? from.formatted(short) : from.formatted(long)
        return String(localized: "\(start) to \(to.formatted(long))")
    }

    /// "5 Jul" or "5 Jul 2025" when not this year.
    static func day(_ day: LocalDate, zone: TimeZone, thisYear: Int?, locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(locale: locale, timeZone: zone).day().month(.abbreviated)
        return day.date(in: zone).formatted(day.year == thisYear ? style : style.year())
    }
}
