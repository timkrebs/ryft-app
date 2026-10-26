import Foundation

/// Turns a parsed bundle and the user's decisions into RYFT plans and completed sessions (design §5, §6, §8): derived
/// ids, the clock-change rules, the bodyweight answers, "last time" targets, duplicates and what already exists. Pure;
/// `build` runs off the main actor.
enum ImportBuilder {
    /// A plan's name and a session's title: the platform's limits.
    static let maxPlanNameLength = 80
    static let maxTitleLength = 120
    /// How far the account's sessions are read beyond the import's first and last day. Ids use the wall clock, but
    /// the platform files a session by its instant: imported again in another zone (UTC−12 … UTC+14, up to 26 hours
    /// apart), an edge day's session lies outside that day's window there and would come back as new.
    static let existingPadding: TimeInterval = 2 * 86_400

    /// The ids and days the preview asks the platform about (`TrainImportUploader.checkExisting(_:)`). Cheap: ids only,
    /// no mapping.
    static func query(for bundle: ImportBundle, decisions: ImportDecisions) -> ImportExistingQuery {
        let account = ImportIDs.account(decisions.account)
        let resolver = ImportTimeResolver(zone: decisions.zone)
        let sessionIDs = sessionIDs(of: bundle, account: account)
        var days = Set<String>()
        var first: LocalDate?
        var last: LocalDate?
        for session in bundle.sessions {
            let day = session.start.date
            days.insert(day.key)
            if first.map({ day < $0 }) ?? true { first = day }
            if last.map({ $0 < day }) ?? true { last = day }
        }
        var range: ClosedRange<Date>?
        if let first, let last {
            let start = resolver.startOfDay(first)
            // The end of the last day: the start of the next one (a day may have 23 or 25 hours).
            let next = LocalDate.after(last).map(resolver.startOfDay) ?? start.addingTimeInterval(86_400)
            let end = max(start, next.addingTimeInterval(-1))
            range = start.addingTimeInterval(-existingPadding)...end.addingTimeInterval(existingPadding)
        }
        return ImportExistingQuery(account: decisions.account, planIDs: planIDs(of: bundle, account: account),
                                   sessionIDs: sessionIDs, days: days, range: range, zone: decisions.zone)
    }

    /// The preview and the upload for these decisions. Throws only `CancellationError`.
    @concurrent
    static func build(_ bundle: ImportBundle, decisions: ImportDecisions, existing: ImportExisting,
                      now: Date) async throws -> ImportBuild {
        MainThread.assertOff("Building an import")
        let signpost = ImportLog.signposter.beginInterval("build", id: ImportLog.signposter.makeSignpostID())
        defer { ImportLog.signposter.endInterval("build", signpost) }
        return try buildNow(bundle, decisions: decisions, existing: existing, now: now)
    }

    /// The same, on the caller's thread (previews, tests).
    static func buildNow(_ bundle: ImportBundle, decisions: ImportDecisions, existing: ImportExisting,
                         now: Date) throws -> ImportBuild {
        let context = ImportBuildContext(bundle: bundle, decisions: decisions, existing: existing)
        // Plans first: whether a plan is sent decides whether sessions may point into it.
        let plans = try ImportPlanAssembly.plans(context)
        let built = try ImportSessionAssembly.build(context, plans: plans, now: now)
        let previews = try ImportPlanAssembly.withLastTime(plans, sessions: built.sessions, refs: built.refs,
                                                           context: context)
        let enrol = decisions.enrolPlanIndex.flatMap { index -> UUID? in
            guard let plan = previews.first(where: { $0.index == index }), plan.plan != nil,
                  plan.willBeSent || plan.state == .alreadyInRYFT else { return nil }
            return plan.id
        }
        var custom: [Exercise] = []
        var seen = Set<UUID>()
        let usedIDs = Set(previews.compactMap(\.plan).flatMap(\.days).flatMap(\.exercises).map(\.exerciseId))
            .union(built.sessions.compactMap(\.session).flatMap(\.exercises).map(\.exerciseId))
        for key in context.exerciseOrder {
            guard case let .custom(exercise)? = decisions.exercises[key]?.target, usedIDs.contains(exercise.id),
                  seen.insert(exercise.id).inserted else { continue }
            custom.append(exercise)
        }
        return ImportBuild(account: decisions.account, source: bundle.format, zone: decisions.zone, plans: previews,
                           sessions: built.sessions, customExercises: custom, warnings: ImportWarning.sorted(built.warnings),
                           duplicatesChecked: existing.checked, enrolPlanID: enrol)
    }

    static func totals(of build: ImportBuild, including included: Set<UUID>) -> ImportTotals {
        var totals = ImportTotals()
        totals.plans = build.plans.filter(\.willBeSent).count
        for session in build.sessions {
            switch session.verdict {
            case .new, .duplicate:
                guard included.contains(session.id), session.session != nil else {
                    if case .duplicate = session.verdict { totals.duplicatesOff += 1 }
                    continue
                }
                totals.sessions += 1
                totals.sets += session.setCount
                totals.volumeKg += session.volumeKg
                totals.skippedSets += session.skippedSetCount
                if session.clockChange != nil { totals.clockChanges += 1 }
            case .alreadyImported: totals.alreadyImported += 1
            case .outsideRange: totals.outsideRange += 1
            case .inFuture: totals.inFuture += 1
            case .empty: totals.empty += 1
            case .historyOff: break
            }
        }
        totals.customExercises = uploadPlan(of: build, including: included, planNames: [:]).exercises.count
        return totals
    }

    static func uploadPlan(of build: ImportBuild, including included: Set<UUID>,
                           planNames: [UUID: String]) -> ImportUploadPlan {
        var upload = ImportUploadPlan(enrolPlanID: build.enrolPlanID)
        for preview in build.plans {
            guard preview.willBeSent, var plan = preview.plan else {
                upload.skipped.plans += 1
                continue
            }
            if let edited = planNames[preview.id] {
                let name = ImportText.cut(ImportCustomExercise.clean(edited), max: maxPlanNameLength)
                if !name.isEmpty { plan.name = name }
            }
            upload.plans.append(plan)
        }
        var sessions: [TrainSession] = []
        for preview in build.sessions {
            switch preview.verdict {
            case .new, .duplicate:
                guard let session = preview.session, included.contains(preview.id) else {
                    if case .duplicate = preview.verdict { upload.skipped.duplicates += 1 } else { upload.skipped.deselected += 1 }
                    continue
                }
                sessions.append(session)
                upload.skipped.skippedSets += preview.skippedSetCount
            case .alreadyImported: upload.skipped.alreadyImported += 1
            case .outsideRange: upload.skipped.outsideRange += 1
            case .inFuture: upload.skipped.inFuture += 1
            case .empty: upload.skipped.empty += 1
            case .historyOff: break
            }
        }
        upload.sessions = sessions.sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        let used = Set(upload.plans.flatMap(\.days).flatMap(\.exercises).map(\.exerciseId))
            .union(upload.sessions.flatMap(\.exercises).map(\.exerciseId))
        upload.exercises = build.customExercises.filter { used.contains($0.id) }
        return upload
    }

    // MARK: ids (ADR 0007)

    /// One per plan of the bundle, in its order. Plans whose names fold the same and that start on the same date (or
    /// have none) are told apart by their occurrence, in the bundle's order (ADR 0007, Amendment 2).
    static func planIDs(of bundle: ImportBundle, account: UUID) -> [UUID] {
        var seen: [String: Int] = [:]
        return bundle.plans.map { plan in
            let key = SourceExerciseKey.fold(plan.name) + ImportIDs.separator + (plan.startDate?.key ?? "")
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            return ImportIDs.plan(account: account, source: bundle.format, name: plan.name, startDate: plan.startDate,
                                  occurrence: occurrence)
        }
    }

    /// One per session of the bundle, in its order. Two sessions with the same start are told apart by their
    /// occurrence, counted oldest first: the file lists the newest first, so from its end.
    static func sessionIDs(of bundle: ImportBundle, account: UUID) -> [UUID] {
        var seen: [String: Int] = [:]
        var ids = [UUID?](repeating: nil, count: bundle.sessions.count)
        for (index, session) in bundle.sessions.enumerated().reversed() {
            let key = session.start.key
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            ids[index] = ImportIDs.session(account: account, source: bundle.format, start: session.start,
                                           occurrence: occurrence)
        }
        return ids.compactMap { $0 }
    }
}

extension LocalDate {
    /// The next calendar day; nil past the parser's range (2999-12-31).
    static func after(_ date: LocalDate) -> LocalDate? {
        if let next = LocalDate(year: date.year, month: date.month, day: date.day + 1) { return next }
        if let next = LocalDate(year: date.year, month: date.month + 1, day: 1) { return next }
        return LocalDate(year: date.year + 1, month: 1, day: 1)
    }
}
