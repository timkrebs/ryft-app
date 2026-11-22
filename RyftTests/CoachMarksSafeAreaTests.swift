import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Gate part 2, round 3: the part 2 UI validation found the first coach card on Today centred at 120 and only clamped there,
/// so at AX3 and AX5 its title sat under the status bar. The card is laid out in the safe area (`CoachCardPlacement`).
@MainActor
@Suite("Gate part 2 round 3: the coach card in the safe area", .serialized)
struct CoachMarksSafeAreaTests {
    struct SizeCase: Sendable, CustomTestStringConvertible {
        let size: DynamicTypeSize
        let category: UIContentSizeCategory
        var testDescription: String { "\(size)" }
    }

    nonisolated static let ax3 = SizeCase(size: .accessibility3, category: .accessibilityExtraLarge)
    nonisolated static let ax5 = SizeCase(size: .accessibility5, category: .accessibilityExtraExtraExtraLarge)
    private static let width: CGFloat = 402, height: CGFloat = 874

    // MARK: the placement

    private let room = CGRect(x: 0, y: 12, width: 402, height: 754)

    @Test func aCardThatFitsBelowTheHoleGoesThere() {
        let hole = CGRect(x: 12, y: 40, width: 378, height: 300)
        let frame = CoachCardPlacement.frame(height: 200, hole: hole, room: room)
        #expect(frame.top == hole.maxY + CoachCardPlacement.gap && frame.height == 200)
    }

    @Test func aCardThatOnlyFitsAboveGoesAbove() {
        let hole = CGRect(x: 12, y: 400, width: 378, height: 300)
        let frame = CoachCardPlacement.frame(height: 200, hole: hole, room: room)
        #expect(frame.top + frame.height == hole.minY - CoachCardPlacement.gap && frame.height == 200)
    }

    /// The validation's case: the readiness hole near the top, a card taller than the room below. It never starts above the
    /// room: the old card was centred at 120, its top far above the screen.
    @Test func aCardTallerThanEitherSideIsCappedInsideTheRoom() {
        let hole = CGRect(x: 12, y: 100, width: 378, height: 420)
        let frame = CoachCardPlacement.frame(height: 700, hole: hole, room: room)
        #expect(frame.top >= room.minY && frame.top + frame.height <= room.maxY, "\(frame)")
        #expect(frame.height < 700 && frame.height >= room.height * CoachCardPlacement.minimumShare - 0.001,
                "capped, its text scrolling, at least half the room: \(frame)")
        #expect(abs(frame.top + frame.height - room.maxY) < 0.001, "on the larger side, below the hole, at the room's foot: \(frame)")
    }

    @Test func aCardTallerThanTheRoomTakesTheRoom() {
        let hole = CGRect(x: 12, y: 0, width: 378, height: 760)
        let frame = CoachCardPlacement.frame(height: 2_000, hole: hole, room: room)
        #expect(frame.top >= room.minY && frame.top + frame.height <= room.maxY + 0.001, "\(frame)")
    }

    // MARK: on Today, hosted

    private func node(_ w: HostedWindow, id: String) throws -> HostedWindow.Node {
        try #require(w.nodes().first { $0.identifier == id }, "\(id) in \(w.nodes().compactMap(\.identifier))")
    }

    @Test("Every coach step on Today at AX3 and AX5: the card inside the safe area, its title under the status bar, Next hittable",
          arguments: [ax3, ax5])
    func everyStepInTheSafeArea(_ s: SizeCase) async throws {
        let state = AppState.preview(coachMarks: true, scenario: .watch)
        let today = TodayView().previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))
        try await HostedWindow.run(width: Self.width, height: Self.height, bottomInset: 0, typeSize: s.size, category: s.category,
                                   today) { w in
            for (index, step) in CoachMarkTarget.allCases.enumerated() {
                let position = "\(index + 1) of \(CoachMarkTarget.allCases.count)"
                try await w.wait("step \(position)") {
                    w.nodes().contains { $0.label == position } && w.nodes().contains { $0.identifier == "coach.next" }
                }
                try await w.settle()
                let insets = w.host.view.safeAreaInsets
                let safe = CGRect(x: 0, y: insets.top, width: Self.width, height: Self.height - insets.top - insets.bottom)
                try #require(insets.top > 40, "the window has the device's status bar: \(insets)")
                let first = try #require(w.nodes().first { $0.label == position }, "\(position)")
                let title = try #require(w.nodes().first { $0.label == step.title }, "\(step.title)")
                let next = try node(w, id: "coach.next"), skip = try node(w, id: "coach.skip")
                // The card: its padding around the position line (its first) and the buttons (its last).
                let top = first.frame.minY - CardSpec.padding, bottom = max(next.frame.maxY, skip.frame.maxY) + CardSpec.padding
                #expect(top >= safe.minY - 0.5 && bottom <= safe.maxY + 0.5,
                        "\(position): the card \(top)…\(bottom) inside the safe area \(safe.minY)…\(safe.maxY)")
                #expect(title.frame.minY >= first.frame.maxY - 0.5 && title.frame.minY >= safe.minY,
                        "\(position): the title \(title.frame) under the position, under the status bar")
                #expect(safe.contains(next.frame) && next.frame.height >= Theme.Metrics.minHitTarget - 0.5,
                        "\(position): Next \(next.frame) whole in the safe area, 44 tall")
                #expect(next.activate(), "\(position): Next")
            }
            try await w.wait("the coach marks done") { !w.nodes().contains { $0.identifier == "coach.next" } }
        }
    }
}
