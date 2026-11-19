import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Strain and the Workout detail drawn in a window (design.md §P5-12 tests 26–27): the identifiers UI tests and VoiceOver use,
/// the loading and failed states as VoiceOver hears them; and, when `STRAIN_SHOTS_DIR` is set, the screens as 3x PNGs at the
/// default size and at AX3 for the comparison with the drafts (`TEST_RUNNER_STRAIN_SHOTS_DIR=<dir> xcodebuild …
/// -only-testing:RyftTests/StrainHostedTests test`).
@MainActor
@Suite("Strain: hosted", .serialized)
struct StrainHostedTests {
    private static let width: CGFloat = 390

    /// No workout running: the shared `TrainPreview.coordinator` reads `TrainPreview.store`'s active session, which another
    /// suite in the same run may have left, and the section would show the in-progress banner instead of Start.
    private static let idle: TrainCoordinator = {
        let store = TrainStore(inMemory: true)
        let sync = TrainSyncService.preview(store: store)
        return TrainCoordinator(sync: sync, library: TrainLibrary.preview(store: store, outbox: sync), liveActivities: false)
    }()

    private func page(_ content: StrainPageContent, add: Bool = true) -> some View {
        NavigationStack {
            StrainPage(content: content, actions: StrainActions(add: add ? {} : nil))
        }
        .environment(Self.idle)
    }

    private func workout(_ board: WorkoutBoard, offline: Bool = false) -> some View {
        NavigationStack { WorkoutDetailPage(board: board, isOffline: offline) }
    }

    @Test func theBoardsIdentifiers() async throws {
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0, page(StrainPreview.content())) { w in
            try await w.settle()
            let nodes = w.nodes()
            let ids = Set(nodes.compactMap(\.identifier))
            for id in ["strain.numeral", "strain.ruler", "strain.zones", "strain.tile.steps", "strain.tile.energy",
                       "strain.header.add", "train.start", "train.plans"] {
                #expect(ids.contains(id), "\(id) in \(ids.sorted())")
            }
            #expect(ids.contains { $0.hasPrefix("strain.row.workout.") }, "\(ids.sorted())")
            #expect(ids.filter { $0.hasPrefix("datestrip.day.") }.count == 7)
            let numeral = try #require(nodes.first { $0.identifier == "strain.numeral" })
            #expect(numeral.label.hasPrefix("Strain ") && numeral.label.hasSuffix(" of 21"), "\(numeral.label)")
            let zones = try #require(nodes.first { $0.identifier == "strain.zones" })
            #expect(zones.label == "Heart-rate zones")
            // The ruler's labels hang into the 20 pt under its 36 pt box; the tile starts under that (§P5-3.1).
            let ruler = try #require(nodes.first { $0.identifier == "strain.ruler" })
            #expect(abs(zones.frame.minY - ruler.frame.minY - StrainLayout.rulerToTile) < 0.5,
                    "ruler \(ruler.frame), zones \(zones.frame)")
            #expect(zones.value?.contains("Zone 5, max") == true, "\(zones.value ?? "")")
            let add = try #require(nodes.first { $0.identifier == "strain.header.add" })
            #expect(add.label == "Add activity" && add.hint == "Opens the add-activity sheet")
            let row = try #require(nodes.first { $0.identifier?.hasPrefix("strain.row.workout.") == true })
            #expect(row.hint == "Opens the workout")
            #expect(row.traits.contains(.button))
            #expect(nodes.contains { $0.label == "Activities" && $0.traits.contains(.header) })
            let title = try #require(nodes.first { $0.label == "Strain" && $0.traits.contains(.header) })
            #expect(title.value == String(localized: "Today"), "the header names the shown day")
        }
    }

    /// Review S4: another day is named twice, the header's spoken value and the date line under it (VoiceOver hears the
    /// value, the line is hidden from it); the date line sits under the header, above the strip.
    @Test func anotherDayIsNamed() async throws {
        let day = DayFormat.shift(StrainPreview.today, days: -3)
        let content = StrainPreview.content(day: day)
        let line = try #require(content.dateLine)
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0, page(content)) { w in
            try await w.settle()
            let nodes = w.nodes()
            let title = try #require(nodes.first { $0.label == "Strain" && $0.traits.contains(.header) })
            #expect(title.value == Fmt.dayTitle(day, today: StrainPreview.today))
            #expect(!nodes.contains { $0.label == line }, "the line is the header's value, not a second element")
        }
    }

    @Test func withoutMyDayTheAddButtonIsHidden() async throws {
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0, page(StrainPreview.content(), add: false)) { w in
            try await w.settle()
            #expect(!w.nodes().contains { $0.identifier == "strain.header.add" })
        }
    }

    @Test func loadingIsSaidOnceAndHasNoSpinner() async throws {
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0, page(StrainPreview.content(loading: true))) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.filter { $0.label == "Loading this day" }.count == 1)
            #expect(!nodes.contains { $0.identifier == "strain.zones" }, "the outline is decoration")
            #expect(!nodes.contains { $0.traits.contains(.updatesFrequently) }, "no spinner")
            #expect(!nodes.contains { $0.identifier?.hasPrefix("strain.row.") == true })
        }
    }

    @Test func aFailureSaysTheCalmSentence() async throws {
        let failure = SleepLoadFailure(reason: .unreachable, details: "HTTP 503")
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0,
                                   page(StrainPreview.content(failure: failure))) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.contains { $0.label == failure.message }, "\(nodes.map(\.label))")
            #expect(nodes.contains { $0.identifier == "strain.failure.retry" }, "Try again")
        }
    }

    @Test func noZonesSaysWhy() async throws {
        let earlier = DayFormat.shift(StrainPreview.today, days: -2)
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0,
                                   page(StrainPreview.content(day: earlier, zones: false, workouts: false))) { w in
            try await w.settle()
            let zones = try #require(w.nodes().first { $0.identifier == "strain.zones" })
            #expect(zones.value == StrainBoard.noZonesSentence)
            #expect(w.nodes().contains { $0.label == "No workouts recorded on this day." })
        }
        // Today the day isn't over (review S2).
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0,
                                   page(StrainPreview.content(zones: false, workouts: false))) { w in
            try await w.settle()
            let zones = try #require(w.nodes().first { $0.identifier == "strain.zones" })
            #expect(zones.value == StrainBoard.noZonesTodaySentence)
        }
    }

    /// Review S2: while the platform scores, the tile keeps its rows ("–") and says so, with no absence sentence.
    @Test func aPendingDaySaysItIsScoring() async throws {
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0,
                                   page(StrainPreview.content(pending: true))) { w in
            try await w.settle()
            let nodes = w.nodes()
            let zones = try #require(nodes.first { $0.identifier == "strain.zones" })
            #expect(zones.value == String(localized: "Scoring your latest data"))
            #expect(!nodes.contains { $0.label == StrainBoard.noStrainSentence || $0.label == StrainBoard.noStrainTodaySentence })
        }
    }

    @Test func theWorkoutsIdentifiersAndHeader() async throws {
        let board = WorkoutPreview.board(session: true)
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0, workout(board)) { w in
            try await w.settle()
            let nodes = w.nodes()
            let ids = Set(nodes.compactMap(\.identifier))
            for id in ["workout.back", "workout.header", "workout.numeral", "workout.ruler", "workout.zones", "workout.session",
                       "workout.chart", "workout.stat.duration", "workout.stat.trimp"] {
                #expect(ids.contains(id), "\(id) in \(ids.sorted())")
            }
            let ruler = try #require(nodes.first { $0.identifier == "workout.ruler" })
            let zones = try #require(nodes.first { $0.identifier == "workout.zones" })
            #expect(abs(zones.frame.minY - ruler.frame.minY - StrainLayout.rulerToTile) < 0.5,
                    "ruler \(ruler.frame), zones \(zones.frame)")
            let header = try #require(nodes.first { $0.identifier == "workout.header" })
            #expect(header.label == board.title && header.traits.contains(.header))
            let chart = try #require(nodes.first { $0.identifier == "workout.chart" })
            #expect(chart.label == "Heart rate over time")
            #expect(chart.value?.hasPrefix("Average ") == true, "\(chart.value ?? "")")
            #expect(nodes.contains { $0.label == board.sourceText })
        }
    }

    @Test func theWorkoutWhileLoading() async throws {
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0,
                                   workout(WorkoutPreview.board(loading: true))) { w in
            try await w.settle()
            let ids = Set(w.nodes().compactMap(\.identifier))
            #expect(!ids.contains("workout.zones") && !ids.contains("workout.chart"), "outlines")
            #expect(ids.contains("workout.numeral"), "the list's strain shows at once")
        }
    }

    /// Review S3: couldn't load is the calm sentence with Try again in the zones tile's place, and the chart's outline;
    /// never "no zones" or "no series".
    @Test func theWorkoutThatCouldntLoad() async throws {
        let failure = SleepLoadFailure(reason: .busy, details: "HTTP 503")
        try await HostedWindow.run(width: Self.width, height: 2_600, bottomInset: 0,
                                   workout(WorkoutPreview.board(failure: failure))) { w in
            try await w.settle()
            let nodes = w.nodes()
            let ids = Set(nodes.compactMap(\.identifier))
            #expect(nodes.contains { $0.label == failure.message }, "\(nodes.map(\.label))")
            #expect(ids.contains("workout.failure.retry"), "Try again in \(ids.sorted())")
            #expect(!ids.contains("workout.zones") && !ids.contains("workout.chart"))
            #expect(!nodes.contains { $0.label == String(localized: "No heart-rate series available for this workout.") })
            #expect(ids.contains("workout.numeral"), "the list's strain shows")
        }
    }

    // MARK: shots

    @Test func writeShots() async throws {
        guard let dir = ProcessInfo.processInfo.environment["STRAIN_SHOTS_DIR"] else { return }
        let failure = SleepLoadFailure(reason: .unreachable, details: "HTTP 503 · Request ID 01a1")
        let screens: [(String, AnyView)] = [
            ("strain", AnyView(page(StrainPreview.content()))),
            ("strain-loading", AnyView(page(StrainPreview.content(loading: true)))),
            ("strain-failed", AnyView(page(StrainPreview.content(failure: failure)))),
            ("strain-nozones-noworkouts", AnyView(page(StrainPreview.content(zones: false, workouts: false)))),
            ("strain-anotherday-offline", AnyView(page(StrainPreview.content(day: DayFormat.shift(StrainPreview.today, days: -2),
                                                                             status: .line(.offline))))),
            ("workout", AnyView(workout(WorkoutPreview.board(session: true)))),
            ("strain-pending", AnyView(page(StrainPreview.content(pending: true)))),
            ("strain-tendaysago", AnyView(page(StrainPreview.content(day: DayFormat.shift(StrainPreview.today, days: -10))))),
            ("strain-train-inprogress", AnyView(NavigationStack {
                StrainPage(content: StrainPreview.content()).environment(StrainPreview.liveTrain)
            })),
            ("workout-loading", AnyView(workout(WorkoutPreview.board(loading: true)))),
            ("workout-failed", AnyView(workout(WorkoutPreview.board(failure: failure)))),
            ("workout-noseries-nozones-offline", AnyView(workout(WorkoutPreview.board(series: false, zones: false), offline: true))),
            ("start-sheet", AnyView(StartWorkoutSheet().environment(Self.idle))),
            ("today-train-card", AnyView(ScrollView { TrainTodayCard().padding(20) }.background(Theme.background)
                    .environment(Self.idle))),
        ]
        for (name, view) in screens {
            for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                               ("ax3", .accessibility3, .accessibilityExtraLarge)] {
                try await HostedWindow.run(width: Self.width, height: 844, bottomInset: 34, typeSize: typeSize,
                                           category: category, view) { w in
                    try await w.settle()
                    let data = try #require(try await Self.croppedPNG(w))
                    try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
                }
            }
        }
    }

    /// The whole page, cut 60 px below the last row that is not the screen colour (as `NocturneStructuresShotsTests`).
    private static func croppedPNG(_ w: HostedWindow) async throws -> Data? {
        let image = try await PagedWindowShot.image(w)
        guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (width, height) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ground = (bytes[0], bytes[1], bytes[2])
        var last = 0
        for y in stride(from: height - 1, through: 0, by: -1) {
            let row = y * width * 4
            if (0..<width).contains(where: { x in
                let i = row + x * 4
                return abs(Int(bytes[i]) - Int(ground.0)) > 2 || abs(Int(bytes[i + 1]) - Int(ground.1)) > 2
                    || abs(Int(bytes[i + 2]) - Int(ground.2)) > 2
            }) {
                last = y
                break
            }
        }
        let cut = min(height, last + 60)
        guard let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: width, height: cut)) else { return nil }
        return UIImage(cgImage: cropped).pngData()
    }
}
