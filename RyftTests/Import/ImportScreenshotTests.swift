import SwiftUI
import Testing
import UIKit
@testable import Ryft

extension Tag {
    /// The training-import screenshot suite (`make ui-shots`): renders, attaches PNGs, compares nothing.
    @Tag static var screenshots: Self
}

/// One language takes about 30 s (50 windows, one at a time), too long for the Unit plan: only `make ui-shots` turns
/// it on (`xcodebuild` forwards `TEST_RUNNER_RYFT_SCREENSHOTS=1` into the test process). At file scope: the suite's
/// own trait can't name a member of the suite (a circular macro reference).
private let importScreenshotsEnabled = ProcessInfo.processInfo.environment["RYFT_SCREENSHOTS"] == "1"

/// Renders the training import's screens from the preview mocks and attaches a PNG per screen, state, appearance and
/// text size to the test results, for a human to read (ui.md §12). The only assertion is that a render exists and has a
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
        func view(scheme: ColorScheme) -> AnyView {
            switch self {
            case .pick:
                return AnyView(NavigationStack { ImportPickView(model: ImportMockData.flow(.pick)) }.previewEnvironment(scheme: scheme))
            case .detected:
                return AnyView(NavigationStack { ImportDetectedView(model: ImportMockData.flow(.detected)) }
                    .previewEnvironment(scheme: scheme))
            case .choose:
                return AnyView(NavigationStack { ImportChooseView(model: ImportMockData.flow(.choose)) }.previewEnvironment(scheme: scheme))
            case .map:
                return AnyView(NavigationStack { ImportMapView(model: ImportMockData.flow(.map)) }.previewEnvironment(scheme: scheme))
            case .preview:
                return AnyView(NavigationStack { ImportPreviewView(model: ImportMockData.previewFlow()) }.previewEnvironment(scheme: scheme))
            case .uploading: return result(MockTrainImport.uploading, scheme)
            case .paused: return result(MockTrainImport.retrying, scheme)
            case .attention: return result(MockTrainImport.status(.paused(.needsAttention), rejected: 3), scheme)
            case .saved: return result(MockTrainImport.savedOnPhone, scheme)
            case .done: return result(MockTrainImport.done, scheme)
            case .rejections: return result(MockTrainImport.mixedRejections, scheme)
            case .unavailable:
                return AnyView(Color.clear.sheet(isPresented: .constant(true)) { ImportUnavailableSheet() }.preferredColorScheme(scheme))
            case .discardImport:
                // N1: Cancel on a middle step asks first.
                let flow = ImportMockData.flow(.detected) { $0.confirmsDiscard = true }
                return AnyView(ImportFlowView(model: flow).previewEnvironment(scheme: scheme))
            case .discardSaved:
                // S2: a saved import can be discarded after a confirmation.
                let flow = ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.savedOnPhone)) {
                    $0.confirmsDiscardJob = true
                }
                return AnyView(NavigationStack { ImportResultView(model: flow) }.previewEnvironment(scheme: scheme))
            }
        }

        @MainActor
        private func result(_ status: ImportJobStatus, _ scheme: ColorScheme) -> AnyView {
            let flow = ImportMockData.flow(.result, uploader: ImportMockData.uploader(status))
            return AnyView(NavigationStack { ImportResultView(model: flow) }.previewEnvironment(scheme: scheme))
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

    struct Shot: Sendable, CustomTestStringConvertible {
        let screen: Screen
        let dark: Bool
        let size: TextSize

        var scheme: ColorScheme { dark ? .dark : .light }
        var testDescription: String { "\(screen.rawValue) \(dark ? "dark" : "light") \(size.rawValue)" }

        func name(language: String) -> String { "\(screen.rawValue)-\(language)-\(dark ? "dark" : "light")-\(size.rawValue)" }
    }

    /// Every screen in light and dark at the default size and in light at AX5; the title-heavy and long screens at
    /// more sizes. Step 4 is the one German titles break first, so it gets AX3 in both schemes.
    nonisolated static let shots: [Shot] = Screen.allCases.flatMap { screen -> [Shot] in
        var all = [Shot(screen: screen, dark: false, size: .standard), Shot(screen: screen, dark: true, size: .standard),
                   Shot(screen: screen, dark: false, size: .ax5)]
        switch screen {
        case .pick, .detected, .choose, .done:
            all.append(Shot(screen: screen, dark: true, size: .ax3))
        case .map:
            all += [Shot(screen: screen, dark: false, size: .ax3), Shot(screen: screen, dark: true, size: .ax3)]
        case .preview:
            all += [Shot(screen: screen, dark: true, size: .ax3), Shot(screen: screen, dark: true, size: .ax5)]
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
        let root = shot.screen.view(scheme: shot.scheme).environment(\.dynamicTypeSize, shot.size.dynamicType)
        let host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = shot.size.category
        host.view.backgroundColor = .clear

        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let window = UIWindow(windowScene: scene)
        window.frame = frame
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = shot.dark ? .dark : .light
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
