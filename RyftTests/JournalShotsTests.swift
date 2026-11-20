import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T6B.8's shots of the Journal (PR 6 B §11, `b-17`, `b-22`): Today's card unanswered and answered, and every state of the
/// sheet, en_US, at the default size and AX3. Written only when `TEST_RUNNER_JOURNAL_SHOTS_DIR` is set (a folder);
/// `TEST_RUNNER_JOURNAL_SHOTS_ONLY` limits them to a comma-separated list of names.
@MainActor
@Suite("T6B.8: the Journal, shots", .serialized)
struct JournalShotsTests {
    nonisolated static let screens = ["card-unanswered", "card-answered", "sheet-answered", "sheet-offline", "sheet-readonly",
                                      "sheet-nohabits", "sheet-loading", "sheet-offline-uncached", "sheet-failed", "sheet-error",
                                      "sheet-saving"]

    private static func view(_ name: String) -> AnyView {
        let sheet: MockJournalStates.Sheet
        switch name {
        case "card-unanswered", "card-answered":
            return AnyView(ScrollView {
                JournalCardBody(summary: name == "card-answered" ? MockJournalStates.cardSummary : nil) {}
                    .padding(Theme.Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea()))
        case "sheet-offline": sheet = .offline
        case "sheet-readonly": sheet = .readOnly
        case "sheet-nohabits": sheet = .noHabits
        case "sheet-loading": sheet = .loading
        case "sheet-offline-uncached": sheet = .offlineUncached
        case "sheet-failed": sheet = .failed
        case "sheet-error": sheet = .saveFailed
        case "sheet-saving": sheet = .saving
        default: sheet = .answered
        }
        return AnyView(JournalSheetBody(content: MockJournalStates.content(sheet)))
    }

    @Test(arguments: screens)
    func writeScreen(_ name: String) async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["JOURNAL_SHOTS_DIR"] else { return }
        if let only = env["JOURNAL_SHOTS_ONLY"], !only.split(separator: ",").contains(Substring(name)) { return }
        for (size, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                           ("ax3", .accessibility3, .accessibilityExtraLarge)] {
            let view = Self.view(name).toggleStyle(.ryft).environment(\.locale, Locale(identifier: "en_US"))
            try await HostedWindow.run(width: 390, height: 844, typeSize: typeSize, category: category, view) { w in
                try await w.settle()
                try await w.settle()
                let image = try await PagedWindowShot.image(w)
                let data = try #require(image.pngData())
                try data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(size).png"))
            }
        }
    }
}
