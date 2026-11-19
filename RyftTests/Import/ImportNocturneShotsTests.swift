import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes the training import's six steps, their states, the unavailable sheet and the rows that open it (Nocturne PR 6 C5,
/// drafts c-23 … c-23d) as 3x PNGs, whole pages (`PagedWindowShot`), at the default size and at AX3 when `IMPORT_SHOTS_DIR`
/// is set; otherwise does nothing. Run it with `TEST_RUNNER_IMPORT_SHOTS_DIR=<dir> xcodebuild … -only-testing:
/// RyftTests/ImportNocturneShotsTests test-without-building`, before and after a change, and compare. Drawn from a real window
/// (`drawHierarchy`); for comparing, not a golden-file test. Synthetic files only (ImportMockData), US English.
@MainActor
@Suite("C5: Import, shots", .serialized)
struct ImportNocturneShotsTests {
    @Test(arguments: Self.names)
    func writeScreen(_ name: String) async throws {
        guard let dir = ProcessInfo.processInfo.environment["IMPORT_SHOTS_DIR"] else { return }
        if let only = ProcessInfo.processInfo.environment["IMPORT_SHOTS_ONLY"], !only.split(separator: ",").contains(Substring(name)) {
            return
        }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            // The app root's toggle style (RyftApp): the previews' environment doesn't set it.
            let view = AnyView(Self.screen(name).toggleStyle(.ryft).environment(\.locale, Locale(identifier: "en_US")))
            try await HostedWindow.run(width: 390, height: 844, bottomInset: 34, typeSize: typeSize, category: category,
                                       view) { w in
                try await w.settle()
                let image = name.hasPrefix("sheet") ? Self.window(w) : try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/c5-\(name)-\(size).png"))
            }
        }
    }

    nonisolated static let names = [
        "1-pick", "1-pick-reading", "1-pick-problem", "1-pick-too-many",
        "2-detected", "2-detected-plan-only", "2-detected-warnings", "2-detected-not-supported",
        "3-choose", "3-choose-existing", "3-choose-nothing", "3-choose-range-empty",
        "4-map", "4-map-loading", "4-map-offline", "4-map-many",
        "5-preview-plan", "5-preview-history", "5-preview-unchecked", "5-preview-keep", "5-preview-already",
        "6-preparing", "6-uploading", "6-offline", "6-retrying", "6-attention", "6-saved", "6-account", "6-done",
        "6-done-plan", "6-done-plan-left", "6-rejections",
        "sheet-unavailable", "rows-profile", "rows-resume",
    ]

    private static func window(_ w: HostedWindow) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
    }

    private static func flow(_ model: ImportFlowModel) -> some View {
        ImportFlowView(model: model).previewEnvironment()
    }

    private static func result(_ status: ImportJobStatus) -> some View {
        flow(ImportMockData.flow(.result, uploader: ImportMockData.uploader(status)))
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    static func screen(_ name: String) -> AnyView {
        switch name {
        case "1-pick": return AnyView(flow(ImportMockData.flow(.pick)))
        case "1-pick-reading":
            return AnyView(flow(ImportMockData.flow(.pick, files: [ImportPickedFile(id: 0, name: "Upper-Lower_Workouts.csv",
                                                                                     status: .reading)])))
        case "1-pick-problem":
            return AnyView(flow(ImportMockData.flow(.pick, files: [ImportPickedFile(id: 0, name: "Export.numbers", status: .failed(.notCSV))])))
        case "1-pick-too-many": return AnyView(flow(ImportMockData.flow(.pick) { $0.tooManyFiles = true }))
        case "2-detected": return AnyView(flow(ImportMockData.flow(.detected)))
        case "2-detected-plan-only":
            return AnyView(flow(ImportMockData.flow(.detected, files: [ImportMockData.file(0, "Upper-Lower_Plans.csv", ImportMockData.plans)])))
        case "2-detected-warnings":
            return AnyView(flow(ImportMockData.flow(.detected, files: ImportMockData.withWarnings(
                [ImportMockData.file(0, "Upper-Lower_Workouts.csv", ImportMockData.workouts, confidence: .weak)])) { $0.showsWarnings = true }))
        case "2-detected-not-supported":
            return AnyView(flow(ImportMockData.flow(.detected, files: [ImportPickedFile(id: 0, name: "notes.txt", status: .failed(.notSupported))])))
        case "3-choose": return AnyView(flow(ImportMockData.flow(.choose, enrolled: false)))
        case "3-choose-existing": return AnyView(flow(ImportMockData.flow(.choose) { $0.selection?.markExisting([true]) }))
        case "3-choose-nothing":
            return AnyView(flow(ImportMockData.flow(.choose) {
                $0.selection?.setPlan(0, on: false)
                $0.selection?.includesHistory = false
            }))
        case "3-choose-range-empty":
            return AnyView(flow(ImportMockData.flow(.choose) {
                $0.selection?.setPlan(0, on: false)
                $0.selection?.preset = .custom
                $0.selection?.from = ImportMockData.day(2026, 4, 28)
            }))
        case "4-map": return AnyView(flow(ImportMockData.flow(.map)))
        case "4-map-loading": return AnyView(flow(ImportMockData.flow(.map) { $0.libraryState = .loading }))
        case "4-map-offline": return AnyView(flow(ImportMockData.flow(.map) { $0.libraryState = .unavailable }))
        case "4-map-many":
            return AnyView(flow(ImportMockData.flow(.map, files: [ImportMockData.file(0, "Workouts.csv", ImportMockData.manyExercises)])))
        case "5-preview-plan": return AnyView(flow(ImportMockData.previewFlow()))
        case "5-preview-history": return AnyView(flow(ImportMockData.previewFlow { $0.previewSegment = .history }))
        case "5-preview-unchecked":
            return AnyView(flow(ImportMockData.previewFlow(ImportMockData.build(duplicatesChecked: false)) { $0.previewSegment = .history }))
        case "5-preview-keep":
            return AnyView(flow(ImportMockData.previewFlow(uploader: ImportMockData.uploader(nil, available: false))))
        case "5-preview-already": return AnyView(flow(ImportMockData.previewFlow(ImportMockData.build(alreadyImportedAll: true))))
        case "6-preparing": return AnyView(result(MockTrainImport.status(.preparing, sessions: 0)))
        case "6-uploading": return AnyView(result(MockTrainImport.uploading))
        case "6-offline": return AnyView(result(MockTrainImport.offline))
        case "6-retrying": return AnyView(result(MockTrainImport.retrying))
        case "6-attention": return AnyView(result(MockTrainImport.status(.paused(.needsAttention), rejected: 3)))
        case "6-saved": return AnyView(result(MockTrainImport.savedOnPhone))
        case "6-account": return AnyView(result(MockTrainImport.status(.paused(.waitingForAccount))))
        case "6-done": return AnyView(result(MockTrainImport.leftAsIsDone))
        case "6-done-plan": return AnyView(result(MockTrainImport.done))
        case "6-done-plan-left": return AnyView(result(MockTrainImport.planLeftAsIsDone))
        case "6-rejections": return AnyView(result(MockTrainImport.mixedRejections))
        case "sheet-unavailable":
            return AnyView(Theme.background.ignoresSafeArea().sheet(isPresented: .constant(true)) { ImportUnavailableSheet() }
                .previewEnvironment())
        case "rows-profile":
            return AnyView(ScrollView {
                GroupedCard(Text(verbatim: "Data")) {
                    ImportProfileRows()
                        .frame(maxWidth: .infinity, minHeight: GroupedListSpec.rowMinHeight, alignment: .leading)
                        .padding(.horizontal, GroupedListSpec.rowInset)
                        .groupedRowHairline()
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .previewEnvironment(AppState.preview(flags: [.trainImport: true])))
        default:
            return AnyView(ScrollView {
                VStack(spacing: GroupedListSpec.groupSpacing) {
                    ImportResumeRow(status: MockTrainImport.uploading, open: {})
                    ImportResumeRow(status: MockTrainImport.offline, open: {})
                    ImportResumeRow(status: MockTrainImport.partlyDone, open: {})
                    ImportResumeRow(status: MockTrainImport.done, open: {}, dismiss: {})
                    ImportWaitingFileRow(name: "Workouts.csv", reason: .workout, canOpen: false, open: {}, viewProgress: {})
                    ImportWaitingFileRow(name: "Workouts.csv", reason: .upload, canOpen: true, open: {}, viewProgress: {})
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .previewEnvironment())
        }
    }
}
