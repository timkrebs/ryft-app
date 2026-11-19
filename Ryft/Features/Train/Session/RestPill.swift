import SwiftUI

/// The rest timer of the Focused layout (design.md §2.7, PR 6 B §4.5), a single button pinned at the bottom. Idle: an outline
/// on `surface` with the exercise's rest. Running: the same capsule, wider, its edge a little brighter, with a ring whose
/// progress is Volt (the running rest is one of the page's two "now" marks, F13, F15) and the time counting down. "Rest over"
/// for a moment after it, on an ink fill (no fill under Reduce Motion: the words alone change). Running is told from idle by
/// the ring, the live number and the width, not by a fill. A tap opens the rest sheet. `RestBar` stays for List.
///
/// VoiceOver: one button, "Rest, 1 minute 55 seconds left, next Bench press set 2 of 4"; while running also adjustable
/// (±15 s) with a Skip action, so a rest can be changed without the sheet.
struct RestPill: View {
    var controller: SessionController
    var onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func height(_ typeSize: DynamicTypeSize) -> CGFloat { typeSize >= .accessibility3 ? 56 : 48 }
    /// Idle and running: at least 112 and 144 wide.
    static let idleMinWidth: CGFloat = 112, runningMinWidth: CGFloat = 144
    /// The capsule's edge: ink at 12 % idle, 20 % running. "Rest over" fills it with ink at 12 %.
    static let idleEdge = 0.12, runningEdge = 0.20, overFill = 0.12
    /// The ring: 24 pt, a 3 pt stroke on a track of ink at 16 %.
    static let ring: CGFloat = 24, ringLine: CGFloat = 3, ringTrack = 0.16
    /// The space a pill takes on the screen.
    static let rowPadding: CGFloat = 8
    static func rowHeight(_ typeSize: DynamicTypeSize) -> CGFloat { height(typeSize) + 2 * rowPadding }

    private var isLarge: Bool { typeSize >= .accessibility3 }

    var body: some View {
        // A container, not a `Group`: that would hand `onChange` to each branch, and a rest's end changes the branch.
        ZStack {
            switch controller.restPillState {
            case .hidden:
                EmptyView()
            case .idle:
                button(at: .now) { outline(Text(Fmt.clock(TimeInterval(controller.pageExercise?.restSec ?? 0)))
                        .font(.ryftNumber(size: isLarge ? 26 : 20)), fill: 0) }
            case .finished:
                button(at: .now) { outline(Text("Rest over").font(.ryft(.headline)), fill: reduceMotion ? 0 : Self.overFill) }
            case .running:
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    button(at: context.date) { running(at: context.date) }
                        .modifier(RunningRestActions(controller: controller))
                }
            }
        }
    }

    private func button<Label: View>(at date: Date, @ViewBuilder label: () -> Label) -> some View {
        Button(action: onOpen, label: label)
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(Text("Rest"))
            .accessibilityValue(Text(verbatim: controller.restPillValue(at: date)))
            .accessibilityHint(ExercisePage.sheetHint)
            .accessibilityInputLabels([Text("Rest timer"), Text("Rest")])
            .accessibilityIdentifier("session.restPill")
    }

    /// Idle and "Rest over": the timer glyph and the words or the exercise's rest. `fill`: the ink behind "Rest over".
    private func outline(_ text: some View, fill: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            text
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minWidth: Self.idleMinWidth, minHeight: Self.height(typeSize))
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().fill(Theme.textPrimary.opacity(fill)))
        .overlay(Capsule().strokeBorder(Theme.textPrimary.opacity(Self.idleEdge), lineWidth: Theme.Metrics.hairline))
        .contentShape(Capsule())
    }

    private func running(at date: Date) -> some View {
        HStack(spacing: 10) {
            ring(at: date)
            Text(Fmt.clock(controller.rest.remaining(at: date).rounded(.up)))
                .font(.ryftNumber(size: isLarge ? 30 : 24))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(minWidth: Self.runningMinWidth, minHeight: Self.height(typeSize))
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.textPrimary.opacity(Self.runningEdge), lineWidth: Theme.Metrics.hairline))
        .contentShape(Capsule())
    }

    /// Volt on an ink track. Under Reduce Motion it still draws, and jumps from tick to tick (it never eases).
    private func ring(at date: Date) -> some View {
        ZStack {
            Circle().stroke(Theme.textPrimary.opacity(Self.ringTrack), lineWidth: Self.ringLine)
            Circle()
                .trim(from: 0, to: controller.rest.fraction(at: date))
                .stroke(Theme.signal, style: StrokeStyle(lineWidth: Self.ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Self.ring, height: Self.ring)
        .accessibilityHidden(true)
    }
}

/// Only while a rest runs: an idle pill mustn't say it can be adjusted.
private struct RunningRestActions: ViewModifier {
    var controller: SessionController

    func body(content: Content) -> some View {
        content
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: controller.adjustRest(by: RestTimer.step)
                case .decrement: controller.adjustRest(by: -RestTimer.step)
                @unknown default: break
                }
            }
            .accessibilityAction(named: Text("Skip rest")) { controller.skipRest() }
    }
}

/// Idle, running (1:54 left), "Rest over".
@MainActor
private func pills() -> some View {
    DarkPreview {
        VStack(spacing: 12) {
            RestPill(controller: FocusedPreview.controller(.midSession)) {}
            RestPill(controller: FocusedPreview.controller(.restRunning)) {}
            RestPill(controller: FocusedPreview.controller(.restOver)) {}
        }
    }
}

#Preview("Rest pill", traits: .sizeThatFitsLayout) {
    pills().previewEnvironment()
}

#Preview("Rest pill · AX3", traits: .sizeThatFitsLayout) {
    pills().previewEnvironment().dynamicTypeSize(.accessibility3)
}
