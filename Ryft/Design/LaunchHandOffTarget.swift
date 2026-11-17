// The seam for the launch's matched move (docs/work/2026-11-16-nocturne/design.md §P4-7, launch-design.md §7.5): a view the
// launch's mark or wordmark flies into reports its frame in the window's space, and hides while the overlay draws it in
// flight. `LaunchHost` provides the two environment values (the move itself is PR 4's T4.2); without them the registrar
// ignores the frames and nothing hides, so a target is an ordinary view everywhere else (previews, other roots, tests).
import SwiftUI

/// What the launch hands off to: the header lock-up's mark and its wordmark.
enum LaunchHandOffRole: Hashable, Sendable {
    case mark, wordmark
}

/// Takes a target's frame in the window's space (`.global`, which the overlay's stage measures itself in too); `nil` when
/// the target left the hierarchy. Wraps the closure because `@Entry` refuses a bare one. Without one (`init()`) it
/// collects nothing, and a target doesn't measure itself at all (CR3).
struct LaunchHandOffRegistrar: Sendable {
    private let action: (@MainActor @Sendable (LaunchHandOffRole, CGRect?) -> Void)?

    init(_ action: @escaping @MainActor @Sendable (LaunchHandOffRole, CGRect?) -> Void) {
        self.action = action
    }

    /// Collects nothing: the default, and `LaunchHost`'s once the launch has left the screen.
    init() {
        action = nil
    }

    /// Whether targets report their frames here.
    var isCollecting: Bool { action != nil }

    @MainActor func callAsFunction(_ role: LaunchHandOffRole, _ frame: CGRect?) { action?(role, frame) }
}

extension EnvironmentValues {
    /// Where hand-off targets report their frames. `LaunchHost` points it at the launch model only while the launch is on
    /// screen; the default, and `LaunchHost`'s after it, collects nothing.
    @Entry var launchHandOffRegistrar = LaunchHandOffRegistrar()
    /// The overlay draws the targets in flight (the mark moves and the phase is `handingOff`): they keep their place at
    /// opacity 0, still in the accessibility tree, until the launch is done, then show with identical pixels.
    @Entry var launchHidesHandOffTargets = false
}

extension View {
    /// A target of the launch's matched move: reports this view's frame in the window's space to
    /// `launchHandOffRegistrar` whenever it changes (and `nil` when the view goes), and draws at opacity 0 while
    /// `launchHidesHandOffTargets` is on. Only Today's header lock-up is one (`WordmarkLockup(handOff: true)`).
    func launchHandOffTarget(_ role: LaunchHandOffRole) -> some View {
        modifier(LaunchHandOffTarget(role: role))
    }
}

private struct LaunchHandOffTarget: ViewModifier {
    let role: LaunchHandOffRole
    @Environment(\.launchHandOffRegistrar) private var registrar
    @Environment(\.launchHidesHandOffTargets) private var hides

    func body(content: Content) -> some View {
        let collecting = registrar.isCollecting
        content
            .opacity(hides ? 0 : 1)
            // The window's space, not a name `LaunchHost` gives: Today's header sits in the `TabView`'s own hosting view,
            // where a name from outside is not found (VB1). Only while the launch collects: after it, Today's scrolling
            // measures nothing and reports nothing (the value stays nil, so the action never runs).
            .onGeometryChange(for: CGRect?.self) { collecting ? $0.frame(in: .global) : nil } action: { frame in
                if let frame { registrar(role, frame) }
            }
            .onDisappear { if collecting { registrar(role, nil) } }
    }
}
