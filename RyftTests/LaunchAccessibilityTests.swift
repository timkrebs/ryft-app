import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// What VoiceOver is told while the launch plays (docs/work/2026-11-16-nocturne/design.md §P3-6 and §P3-8 case 33,
/// launch-design.md §8): the overlay is one element, "Loading RYFT", modal, with a "Skip" action and an identifier for the
/// UI tests; the mark, the wordmark and the tagline are hidden; the root beneath is hidden until the hand-off. Hosted in a
/// real window and read through the accessibility tree (`HostedWindow`), as `NocturneComponentAccessibilityTests` does.
///
/// Not covered here (needs a device and VoiceOver): that focus lands on the root's first element after the hand-off
/// (`ScreenChanged` is posted, not observable), and how the label sounds.
@MainActor
@Suite("Launch: accessibility and strings", .serialized)
struct LaunchAccessibilityTests {
    /// A model that is playing, on a clock that never moves: the phase is whatever the test makes it, whatever the real time.
    private func playingModel(_ variant: LaunchSequence.Variant = .full) -> LaunchSequenceModel {
        let model = LaunchSequenceModel(decision: .play(variant), clock: TestClock(now: Date()), signposts: false)
        model.send(.scene(.active))
        return model
    }

    // MARK: the overlay

    @Test("The overlay is one modal element, \"Loading RYFT\", with a Skip action", arguments: [
        LaunchSequence.Variant.full, .reduced,
    ])
    private func theOverlayIsOneElement(_ variant: LaunchSequence.Variant) async throws {
        let model = playingModel(variant)
        try await HostedWindow.run(width: 402, height: 874, LaunchOverlay(model: model)) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.map(\.label) == ["Loading RYFT"], "\(variant): elements \(nodes.map(\.label))")
            let node = try #require(nodes.first)
            #expect((node.value ?? "").isEmpty, "a status with no value: \(String(describing: node.value))")
            #expect(node.isModal, "the modal trait: the screen beneath is not reachable")
            #expect(node.identifier == LaunchOverlay.identifier && node.identifier == "launch.sequence")
            #expect(node.actionNames == ["Skip"], "the rotor's actions: \(node.actionNames)")
            // It covers the whole screen, including the safe areas.
            #expect(node.frame == CGRect(x: 0, y: 0, width: 402, height: 874), "frame \(node.frame)")
            // The mark, the wordmark and the tagline are not elements of their own.
            for hidden in ["RYFT", "Engineered for peak."] { #expect(w.node(hidden, exactly: true) == nil, "'\(hidden)' is hidden") }
            #expect(model.phase == .playing, "reading the tree skips nothing")
        }
    }

    @Test func theDefaultActionSkipsIt() async throws {
        let model = playingModel()
        try await HostedWindow.run(width: 402, height: 874, LaunchOverlay(model: model)) { w in
            try await w.settle()
            let node = try #require(w.node("Loading RYFT", exactly: true))
            #expect(node.activate(), "VoiceOver's double tap is handled")
            #expect(model.phase == .handingOff && model.ending == .tapped)
        }
    }

    @Test func theSkipActionSkipsIt() async throws {
        let model = playingModel()
        try await HostedWindow.run(width: 402, height: 874, LaunchOverlay(model: model)) { w in
            try await w.settle()
            let node = try #require(w.node("Loading RYFT", exactly: true))
            #expect(node.perform(action: "Skip"))
            #expect(model.phase == .handingOff && model.ending == .tapped)
        }
    }

    @Test func aTapAnywhereSkipsIt() async throws {
        let model = playingModel()
        try await HostedWindow.run(width: 402, height: 874, LaunchOverlay(model: model)) { w in
            try await w.settle()
            // A touch is not synthesised here: the gesture is what the element's activation runs, and both end the same way.
            #expect(w.node("Loading RYFT", exactly: true) != nil)
            model.send(.tap)
            #expect(model.phase == .handingOff)
        }
    }

    // MARK: the host: the root is hidden while the overlay covers it

    private struct Root: View {
        var body: some View {
            Button("Today root") {}
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @Test("Under the overlay the root is hidden from VoiceOver; once it hands off the root is back and the overlay is not")
    func theRootIsHiddenUntilTheHandOff() async throws {
        let model = playingModel()
        // The hosted window has no scene phase of its own (the environment default is `.background`): say it is active.
        let host = LaunchHost(model: model) { Root() }.environment(\.scenePhase, .active)
        try await HostedWindow.run(width: 402, height: 874, host) { w in
            try await w.settle()
            #expect(model.phase == .playing, "the host forwards an active scene, which does nothing while playing")
            #expect(w.nodes().map(\.label) == ["Loading RYFT"], "first focus is the overlay: \(w.nodes().map(\.label))")

            w.node("Loading RYFT", exactly: true)?.activate()
            try await w.settle()
            #expect(model.phase == .handingOff && !model.coversRoot)
            let labels = w.nodes().map(\.label)
            #expect(labels == ["Today root"], "the root is back and the fading overlay is out of the tree: \(labels)")
        }
    }

    @Test func aSkippedLaunchLeavesTheRootAloneAndNoOverlay() async throws {
        let model = LaunchSequenceModel(decision: .skip(.harness), clock: TestClock(now: Date()), signposts: false)
        let host = LaunchHost(model: model) { Root() }.environment(\.scenePhase, .active)
        try await HostedWindow.run(width: 402, height: 874, host) { w in
            try await w.settle()
            #expect(w.nodes().map(\.label) == ["Today root"])
            #expect(w.node("Loading RYFT") == nil)
        }
    }

    // MARK: strings (plan.md criterion 6)

    private struct Entry: Decodable {
        let comment: String?
        let localizations: [String: Localization]?
        struct Localization: Decodable {}
    }

    private struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private func catalog() throws -> Catalog {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Ryft/Resources/Localizable.xcstrings")
        return try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
    }

    @Test("The launch's strings are in the catalog, in English, with a comment for the translator", arguments: [
        ("Loading RYFT", "VoiceOver status while the launch animation plays."),
        ("Engineered for peak.", "The tagline under the wordmark on the launch screen."),
    ])
    private func theLaunchStringsAreInTheCatalog(_ key: String, _ comment: String) throws {
        let catalog = try catalog()
        #expect(catalog.sourceLanguage == "en")
        let entry = try #require(catalog.strings[key], "'\(key)' is missing from Localizable.xcstrings")
        #expect(entry.comment == comment)
        #expect(entry.localizations?.keys.contains(where: { $0 != "en" }) != true, "English only (CLAUDE.md)")
    }

    /// The skip action is VoiceOver's, named with a string the catalog already had.
    @Test func theSkipActionsNameIsInTheCatalog() throws {
        #expect(try catalog().strings["Skip"] != nil)
    }
}
