import SwiftUI
import Testing
import UIKit
@testable import Ryft

extension Tag {
    /// The training-import screenshot suite (`make ui-shots`): renders, attaches PNGs, compares nothing.
    @Tag static var screenshots: Self
}

/// One language takes about 20 s (34 windows, one at a time), too long for the Unit plan: only `make ui-shots` turns
/// it on (`xcodebuild` forwards `TEST_RUNNER_RYFT_SCREENSHOTS=1` into the test process). At file scope: the suite's
/// own trait can't name a member of the suite (a circular macro reference).
private let importScreenshotsEnabled = ProcessInfo.processInfo.environment["RYFT_SCREENSHOTS"] == "1"

/// Renders the training import's screens from the preview mocks and attaches a PNG per screen, state and text size
/// (dark, the one appearance) to the test results, for a human to read (ui.md §12). The only assertion is that a render exists and has a
/// size: there are no reference images. `scripts/ui-shots.sh` runs it once per language on a simulator set to that
/// language; the language in each name is the localization the app's strings resolve to (`String(localized:)` follows
/// the process, not `\.locale`). Serialized: each shot owns the app's window scene while it renders.
@MainActor
@Suite("Import screenshots", .tags(.screenshots), .serialized, .enabled(if: importScreenshotsEnabled))
struct ImportScreenshotTests {
    /// A screen in one of its states, as the previews build it.
    enum Screen: String, CaseIterable, Sendable {
        case pick = "pick-empty"
        case detected = "detected-both"
        case choose = "choose-both"
        case map = "map-mixed"
        case preview = "preview-plan"
        case uploading = "result-uploading"
        case paused = "result-paused"
        case attention = "result-attention"
        case saved = "result-saved"
        case done = "result-done"
        case rejections = "result-rejections"
        case unavailable = "unavailable-sheet"
        case discardImport = "discard-import"
        case discardSaved = "discard-saved"

        /// Alerts and sheets exist only presented in a window; the capture waits for them.
        var isModal: Bool { self == .unavailable || self == .discardImport || self == .discardSaved }

        @MainActor
        func view() -> AnyView {
            switch self {
            case .pick:
                return AnyView(NavigationStack { ImportPickView(model: ImportMockData.flow(.pick)) }.previewEnvironment())
            case .detected:
                return AnyView(NavigationStack { ImportDetectedView(model: ImportMockData.flow(.detected)) }
                    .previewEnvironment())
            case .choose:
                return AnyView(NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose)) }.previewEnvironment())
            case .map:
                return AnyView(NavigationStack { ImportMapView(model: ImportMockData.flow(.map)) }.previewEnvironment())
            case .preview:
                return AnyView(NavigationStack { ImportPreviewView(model: ImportMockData.previewFlow()) }.previewEnvironment())
            case .uploading: return result(MockTrainImport.uploading)
            case .paused: return result(MockTrainImport.retrying)
            case .attention: return result(MockTrainImport.status(.paused(.needsAttention), rejected: 3))
            case .saved: return result(MockTrainImport.savedOnPhone)
            case .done: return result(MockTrainImport.done)
            case .rejections: return result(MockTrainImport.mixedRejections)
            case .unavailable:
                return AnyView(Color.clear.sheet(isPresented: .constant(true)) { ImportUnavailableSheet() }.preferredColorScheme(.dark))
            case .discardImport:
                // N1: Cancel on a middle step asks first.
                let flow = ImportMockData.flow(.detected) { $0.confirmsDiscard = true }
                return AnyView(ImportFlowView(model: flow).previewEnvironment())
            case .discardSaved:
                // S2: a saved import can be discarded after a confirmation.
                let flow = ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.savedOnPhone)) {
                    $0.confirmsDiscardJob = true
                }
                return AnyView(NavigationStack { ImportResultView(model: flow) }.previewEnvironment())
            }
        }

        @MainActor
        private func result(_ status: ImportJobStatus) -> AnyView {
            let flow = ImportMockData.flow(.result, uploader: ImportMockData.uploader(status))
            return AnyView(NavigationStack { ImportResultView(model: flow) }.previewEnvironment())
        }
    }

    enum TextSize: String, Sendable {
        case standard = "default"
        case ax3
        case ax5

        var category: UIContentSizeCategory {
            switch self {
            case .standard: .large
            case .ax3: .accessibilityLarge
            case .ax5: .accessibilityExtraExtraExtraLarge
            }
        }

        var dynamicType: DynamicTypeSize {
            switch self {
            case .standard: .large
            case .ax3: .accessibility3
            case .ax5: .accessibility5
            }
        }

        /// Tall enough for the top of a long screen at this size; the scroll view clips the rest.
        var height: CGFloat {
            switch self {
            case .standard: 874
            case .ax3: 1_600
            case .ax5: 2_400
            }
        }
    }

    /// One shot, dark (the app is dark-only, ADR 0016). The name keeps its `-dark-` so the files read as before.
    struct Shot: Sendable, CustomTestStringConvertible {
        let screen: Screen
        let size: TextSize

        var testDescription: String { "\(screen.rawValue) \(size.rawValue)" }

        func name(language: String) -> String { "\(screen.rawValue)-\(language)-dark-\(size.rawValue)" }
    }

    /// Every screen at the default size and at AX5; the title-heavy and long screens at AX3 too.
    nonisolated static let shots: [Shot] = Screen.allCases.flatMap { screen -> [Shot] in
        var all = [Shot(screen: screen, size: .standard), Shot(screen: screen, size: .ax5)]
        switch screen {
        case .pick, .detected, .choose, .map, .preview, .done:
            all.append(Shot(screen: screen, size: .ax3))
        default:
            break
        }
        return all
    }

    @Test("Render and attach", arguments: shots)
    func rendersAndAttaches(_ shot: Shot) async throws {
        // The localization the app's strings resolve to, not `Locale.current`. When the script names the language it
        // set, a language that didn't apply fails here instead of yielding English shots under another name.
        let language = Bundle.main.preferredLocalizations.first ?? "und"
        if let expected = ProcessInfo.processInfo.environment["RYFT_SHOT_LANG"] {
            try #require(language == expected, "the app resolves strings in \(language), not \(expected)")
        }
        let scene = try #require(await Self.windowScene(), "the test host has no window scene")
        let image = try #require(await Self.render(shot, in: scene))
        #expect(image.size.width > 0 && image.size.height > 0)
        Attachment.record(image, named: shot.name(language: language), as: .png)
    }

    // MARK: Rendering

    private static let width: CGFloat = 402

    /// The host app's scene; the first test can start before it connects. A window without a scene can't present
    /// alerts or sheets.
    private static func windowScene() async -> UIWindowScene? {
        for _ in 0..<100 {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first { return scene }
            await pump(0.05)
        }
        return nil
    }

    /// The screen in a window of the app's process, so navigation bars, alerts and sheets are real; nil if it can't
    /// be drawn.
    private static func render(_ shot: Shot, in scene: UIWindowScene) async -> UIImage? {
        let height = shot.screen.isModal ? TextSize.standard.height : shot.size.height
        let root = shot.screen.view().environment(\.dynamicTypeSize, shot.size.dynamicType)
        let host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = shot.size.category
        host.view.backgroundColor = .clear

        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController = host
        window.isHidden = false
        defer {
            // An alert or sheet still presented would keep the host and its flow model alive past the test.
            host.presentedViewController?.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
        }

        await pump(0.3)
        if shot.screen.isModal {
            var presented = false
            for _ in 0..<100 where !presented {
                presented = host.presentedViewController != nil
                if !presented { await pump(0.05) }
            }
            guard presented else { return nil }
            await pump(0.8) // the presentation animation
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let renderer = UIGraphicsImageRenderer(bounds: frame, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: frame, afterScreenUpdates: true)
        }
        return image
    }

    /// Leaves the main actor free for a moment: SwiftUI lays out and starts `.task`s between run-loop turns. A wait on
    /// time, not on a condition, only because a window gives no event to wait for.
    private static func pump(_ seconds: TimeInterval) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
