import Foundation

/// Turns a parsed bundle and the user's decisions into RYFT plans and completed sessions (design §5, §6, §8): derived
/// ids, the clock-change rules, the bodyweight answers, "last time" targets, duplicates and what already exists. Pure;
/// `build` runs off the main actor.
enum ImportBuilder {
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
            range = start...max(start, next.addingTimeInterval(-1))
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
        // I5 fills this in: plans (§8), sessions (§5, §8), verdicts (§6) and warnings.
        ImportBuild(account: decisions.account, source: bundle.format, zone: decisions.zone, plans: [], sessions: [],
                    customExercises: [], warnings: [], duplicatesChecked: existing.checked, enrolPlanID: nil)
    }

    static func totals(of build: ImportBuild, including included: Set<UUID>) -> ImportTotals {
        var totals = ImportTotals()
        totals.plans = build.plans.filter(\.willBeSent).count
        for session in build.sessions {
            switch session.verdict {
            case .new, .duplicate:
                guard included.contains(session.id) else {
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
        ImportUploadPlan(enrolPlanID: build.enrolPlanID)
    }

    // MARK: ids (ADR 0007)

    /// One per plan of the bundle, in its order.
    static func planIDs(of bundle: ImportBundle, account: UUID) -> [UUID] {
        bundle.plans.map { ImportIDs.plan(account: account, source: bundle.format, name: $0.name, startDate: $0.startDate) }
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
