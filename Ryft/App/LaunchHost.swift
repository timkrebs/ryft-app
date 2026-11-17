import SwiftUI

/// The `WindowGroup`'s view: the root beneath, the launch sequence over it while it is on screen (ADR 0017). The root
/// is built, and its lifecycle hooks fire, exactly as without the sequence; while it is covered (armed or playing) it is
/// hidden from VoiceOver, takes no taps and reads `launchCoversRoot`. It forwards the scene's phase to the model, and
/// moves VoiceOver to the root when the sequence hands off. Today's header reports its lock-up here
/// (`launchHandOffRegistrar`), so the hand-off can fly the mark into it (design.md §P4-7): the lock-up hides while the
/// overlay draws it in flight, and `launchRevealsRoot` holds Today's gauge entrance until it lands.
struct LaunchHost<Root: View>: View {
    let model: LaunchSequenceModel
    @ViewBuilder var root: () -> Root

    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        root()
            .environment(\.launchCoversRoot, model.coversRoot)
            .environment(\.launchRevealsRoot, model.revealsRoot)
            .environment(\.launchHidesHandOffTargets, model.hidesHandOffTargets)
            .environment(\.launchHandOffRegistrar, LaunchHandOffRegistrar { [model] in model.register($0, $1) })
            .environment(\.launchInterrupt, LaunchInterruptAction { [model] in model.send(.interrupted($0)) })
            .accessibilityHidden(model.coversRoot)
            .overlay {
                if model.isOnScreen { LaunchOverlay(model: model) }
            }
            // The matched move: Today's header reports its lock-up's frames in this space; the overlay ignores the safe
            // areas, so `LaunchStage.overlayRect(fromLaunch:safeArea:)` converts them.
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
/// `LaunchSequence` (nothing is written per frame), fading out over the root at the hand-off, or, when the mark moves,
/// the background and the tagline fading while the lock-up flies into Today's header. One VoiceOver element,
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
                let frame = LaunchFrame(t: sequence.frameProgress(at: context.date), palette: palette)
                if let move = Self.move(sequence, targets: model.targets, at: context.date, frame: frame, palette: palette) {
                    // The matched move: the mark and the wordmark stay at full ink until `done`; the background and the
                    // tagline are gone 0.25 s in, so Today shows around the lock-up in flight.
                    let fade = sequence.moveFade(at: context.date)
                    ZStack {
                        Theme.background.opacity(fade)
                        LaunchStage(frame: frame, safeAreaBottom: safeAreaBottom, move: move)
                    }
                } else {
                    ZStack {
                        Theme.background
                        LaunchStage(frame: frame, safeAreaBottom: safeAreaBottom)
                            .opacity(sequence.contentOpacity(at: context.date))
                    }
                    .opacity(1 - sequence.handOff(at: context.date))
                }
            }
            // The timeline starts at its first frame on screen, not at the scene's `.active` (up to 0.15 s earlier in
            // Debug, when the first frame was t 0.03 at 77 % opacity): the mark fades in from nothing. Until the
            // sequence takes this, every frame is t = 0.
            .onAppear { model.send(.firstFrame) }
        }
    }
}

extension LaunchOverlay {
    /// The matched move at `date`, or nil for the cross-fade: only while handing off, when the sequence moves the mark
    /// and a mark target is known.
    static func move(_ sequence: LaunchSequence, targets: [LaunchHandOffRole: CGRect], at date: Date, frame: LaunchFrame,
                     palette: LaunchFrame.Palette) -> LaunchStage.Move? {
        guard sequence.movesMark, sequence.phase(at: date) == .handingOff, let mark = targets[.mark] else { return nil }
        return LaunchStage.Move(mark: mark, wordmark: targets[.wordmark], time: sequence.moveTime(at: date),
                                taglineOpacity: frame.taglineOpacity * sequence.moveFade(at: date), palette: palette)
    }
}

/// The whole screen for the launch overlay: `content` is laid out ignoring the safe areas and gets the bottom inset it
/// ignores, read here, outside `.ignoresSafeArea()`, where it is still the screen's (inside, a geometry reads 0). All four
/// insets go down as `launchSafeArea`, for the matched move's conversion.
struct LaunchFullScreen<Content: View>: View {
    @ViewBuilder var content: (_ safeAreaBottom: CGFloat) -> Content

    var body: some View {
        GeometryReader { proxy in
            content(proxy.safeAreaInsets.bottom)
                .environment(\.launchSafeArea, proxy.safeAreaInsets)
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
            // Today's header lock-up, the move's target: the mark and "RYFT" fly into it at the natural end.
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(handOff: true) { EmptyView() }
                Text(verbatim: "Today")
                    .font(.ryft(.title))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
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
