import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// R2 V1 S2 (PR 6 B §12: "sheets open at `.large` from XL"): the Start workout sheet and the plate calculator, presented as
/// the app presents them, read through the sheet's own `UISheetPresentationController`: half height first with the drag up
/// to full below XL, full height only from XL (AX3 included), so large text never opens in half a screen.
@MainActor
@Suite("R2 V1: Start workout and the plate calculator open full height from XL", .serialized)
struct SheetDetentsHostedTests {
    struct SizeCase: Sendable, CustomTestStringConvertible {
        let size: DynamicTypeSize
        let category: UIContentSizeCategory
        /// Only `.large` (from XL); else `.medium` and `.large`.
        let largeOnly: Bool
        var testDescription: String { "\(size)" }
    }

    nonisolated static let sizes = [
        SizeCase(size: .large, category: .large, largeOnly: false),
        SizeCase(size: .xLarge, category: .extraLarge, largeOnly: true),
        SizeCase(size: .accessibility3, category: .accessibilityExtraLarge, largeOnly: true),
    ]

    /// The presented sheet's detents, as UIKit holds them.
    private func detents(_ w: HostedWindow) -> Set<UISheetPresentationController.Detent.Identifier> {
        Set(w.host.presentedViewController?.sheetPresentationController?.detents.map(\.identifier) ?? [])
    }

    private func expected(_ s: SizeCase) -> Set<UISheetPresentationController.Detent.Identifier> {
        s.largeOnly ? [.large] : [.medium, .large]
    }

    private func presented(_ s: SizeCase, _ sheet: some View, body: (HostedWindow) async throws -> Void) async throws {
        let host = SheetHost { sheet.environment(\.dynamicTypeSize, s.size).presentedRoot() }
        try await HostedWindow.run(width: 402, height: 874, typeSize: s.size, category: s.category, host) { w in
            try await w.wait("the sheet") { w.host.presentedViewController?.sheetPresentationController != nil }
            try await w.settle()
            try await body(w)
        }
    }

    @Test("Start workout: medium and large below XL, large only from XL", arguments: sizes)
    func startWorkout(_ s: SizeCase) async throws {
        try await presented(s, StartWorkoutSheet()) { w in
            #expect(detents(w) == expected(s), "\(detents(w).map(\.rawValue))")
        }
    }

    @Test("Plate calculator: medium and large below XL, large only from XL", arguments: sizes)
    func plateCalculator(_ s: SizeCase) async throws {
        try await presented(s, PlateCalculatorSheet(target: 102.5, onUse: { _ in })) { w in
            #expect(detents(w) == expected(s), "\(detents(w).map(\.rawValue))")
        }
    }
}
