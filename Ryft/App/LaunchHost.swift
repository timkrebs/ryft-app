import SwiftUI

/// The `WindowGroup`'s view: the root beneath, the launch sequence over it while it is on screen (ADR 0017). The root
/// is built, and its lifecycle hooks fire, exactly as without the sequence; while it is covered (armed or playing) it is
/// hidden from VoiceOver, takes no taps and reads `launchCoversRoot`. It forwards the scene's phase to the model, and
/// moves VoiceOver to the root when the sequence hands off.
struct LaunchHost<Root: View>: View {
    let model: LaunchSequenceModel
    @ViewBuilder var root: () -> Root

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        root()
            .environment(\.launchCoversRoot, model.coversRoot)
            .environment(\.launchInterrupt, LaunchInterruptAction { [model] in model.send(.interrupted($0)) })
            .accessibilityHidden(model.coversRoot)
            .overlay {
                if model.isOnScreen { LaunchOverlay(model: model) }
            }
            // PR 4's matched move: Today's header reports its mark's frame here; `LaunchStage(markRect:)` draws into it.
            // The overlay ignores the safe areas: its origin is the screen's, so it converts with its own frame here.
            .coordinateSpace(.launch)
            // A re-created scene sends an `.active` the terminal sequence ignores: nothing plays twice.
            .onChange(of: scenePhase, initial: true) { _, phase in model.send(.scene(phase)) }
            .onChange(of: model.coversRoot) { covered, covers in
                guard covered, !covers, model.movesFocusToRoot else { return }
                // On the next turn, once the root is back in the accessibility tree: focus lands on its first element
                // (Today's header, then the greeting).
                Task { AccessibilityNotification.ScreenChanged(nil).post() }
            }
    }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// `LaunchHost`'s space: the root and the launch overlay share it.
    static var launch: NamedCoordinateSpace { .named("launch") }
}

/// What covers the root. Armed: the launch screen's colour and nothing else (no timeline, canvas, text or font before
/// the first `.active`). Playing and handing off: the stage at the sequence's moment, in a `TimelineView` over the pure
/// `LaunchSequence` (nothing is written per frame), fading out over the root at the hand-off. One VoiceOver element,
/// "Loading RYFT": its default action and "Skip" end it at once.
struct LaunchOverlay: View {
    let model: LaunchSequenceModel
    @Environment(\.self) private var environment

    /// The UI tests' handle (`LaunchSequenceUITests`).
    static let identifier = "launch.sequence"

    var body: some View {
        LaunchFullScreen { safeAreaBottom in
            content(safeAreaBottom: safeAreaBottom)
                .contentShape(Rectangle())
                .onTapGesture { model.send(.tap) }
                .allowsHitTesting(model.coversRoot)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Loading RYFT", comment: "VoiceOver status while the launch animation plays."))
                .accessibilityAddTraits(.isModal)
                .accessibilityIdentifier(Self.identifier)
                .accessibilityAction { model.send(.tap) }
                .accessibilityAction(named: Text("Skip")) { model.send(.tap) }
                .accessibilityHidden(!model.coversRoot)
        }
    }

    @ViewBuilder
    private func content(safeAreaBottom: CGFloat) -> some View {
        if model.phase == .armed {
            // Pixel for pixel the system launch screen (`UILaunchScreen`'s Graphite is this colour, ADR 0016).
            Theme.background
        } else {
            let palette = LaunchFrame.Palette.resolved(in: environment)
            TimelineView(.animation(paused: !model.isAnimating)) { context in
                let sequence = model.sequence
                ZStack {
                    Theme.background
                    LaunchStage(frame: LaunchFrame(t: sequence.frameProgress(at: context.date), palette: palette),
                                safeAreaBottom: safeAreaBottom)
                        .opacity(sequence.contentOpacity(at: context.date))
                }
                .opacity(1 - sequence.handOff(at: context.date))
            }
            // The timeline starts at its first frame on screen, not at the scene's `.active` (up to 0.15 s earlier in
            // Debug, when the first frame was t 0.03 at 77 % opacity): the mark fades in from nothing. Until the
            // sequence takes this, every frame is t = 0.
            .onAppear { model.send(.firstFrame) }
        }
    }
}

/// The whole screen for the launch overlay: `content` is laid out ignoring the safe areas and gets the bottom inset it
/// ignores, read here, outside `.ignoresSafeArea()`, where it is still the screen's (inside, a geometry reads 0).
struct LaunchFullScreen<Content: View>: View {
    @ViewBuilder var content: (_ safeAreaBottom: CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(proxy.safeAreaInsets.bottom)
                .ignoresSafeArea()
        }
    }
}

#if DEBUG
/// The real overlay over a stand-in root, on the system clock: it plays as the app does (tap to skip).
private struct LaunchHostPreview: View {
    @State private var model: LaunchSequenceModel

    init(variant: LaunchSequence.Variant) {
        _model = State(initialValue: LaunchSequenceModel(decision: .play(variant), clock: SystemClock(), signposts: false))
    }

    var body: some View {
        LaunchHost(model: model) {
            VStack(spacing: 16) {
                RyftHeader()
                Text(verbatim: "Today")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Launch · plays, tap to skip") {
    LaunchHostPreview(variant: .full)
}

#Preview("Launch · Reduce Motion plays") {
    LaunchHostPreview(variant: .reduced)
}
#endif
