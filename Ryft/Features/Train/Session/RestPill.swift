import SwiftUI

/// The rest timer of the Focused layout (design.md §2.7), a single button pinned at the bottom: an outline with the
/// exercise's rest when idle, the only filled pill while a rest runs, "Rest over" for a moment after it. A tap opens the
/// rest sheet. `RestBar` stays for List.
///
/// VoiceOver: one button, "Rest, 1 minute 55 seconds left, next Bench press set 2 of 4"; while running also adjustable
/// (±15 s) with a Skip action, so a rest can be changed without the sheet.
struct RestPill: View {
    var controller: SessionController
    var onOpen: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = false

    static func height(_ typeSize: DynamicTypeSize) -> CGFloat { typeSize >= .accessibility3 ? 56 : 48 }
    /// The space a pill takes on the screen.
    static let rowPadding: CGFloat = 8
    static func rowHeight(_ typeSize: DynamicTypeSize) -> CGFloat { height(typeSize) + 2 * rowPadding }

    private var isLarge: Bool { typeSize >= .accessibility3 }

    var body: some View {
        Group {
            switch controller.restPillState {
            case .hidden:
                EmptyView()
            case .idle:
                button(at: .now) { outline(Text(Fmt.clock(TimeInterval(controller.pageExercise?.restSec ?? 0)))
                        .font(.ryftNumber(size: isLarge ? 26 : 20))) }
            case .finished:
                button(at: .now) { outline(Text("Rest over").font(.ryft(.headline))) }
            case .running:
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    button(at: context.date) { running(at: context.date) }
                        .modifier(RunningRestActions(controller: controller))
                }
            }
        }
        // Only the end of a rest: the pill is off screen for any other change of `restsEnded`.
        .onChange(of: controller.restsEnded) { _, _ in flashOnce() }
    }

    /// Once, on Theme.Motion.quick. Reduce Motion: no flash, the text alone changes.
    private func flashOnce() {
        guard !reduceMotion else { return }
        withAnimation(Theme.Motion.quick) {
            flash = true
        } completion: {
            withAnimation(Theme.Motion.quick) { flash = false }
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

    private func outline(_ text: some View) -> some View {
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
        .frame(minWidth: 112, minHeight: Self.height(typeSize))
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().fill(Theme.accent.opacity(flash ? 0.25 : 0)))
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
        .contentShape(Capsule())
    }

    private func running(at date: Date) -> some View {
        HStack(spacing: 10) {
            ring(at: date)
            Text(Fmt.clock(controller.rest.remaining(at: date).rounded(.up)))
                .font(.ryftNumber(size: isLarge ? 30 : 24))
                .monospacedDigit()
                .foregroundStyle(Theme.onAccent)
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .frame(minWidth: 144, minHeight: Self.height(typeSize))
        .background(Theme.accent, in: Capsule())
        .contentShape(Capsule())
    }

    private func ring(at date: Date) -> some View {
        ZStack {
            Circle().stroke(Theme.onAccent.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: controller.rest.fraction(at: date))
                .stroke(Theme.onAccent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 24, height: 24)
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

@MainActor
private func pills() -> some View {
    SchemePair {
        VStack(spacing: 12) {
            RestPill(controller: FocusedPreview.controller(.midSession)) {}
            RestPill(controller: FocusedPreview.controller(.restRunning)) {}
            RestPill(controller: FocusedPreview.controller(.restOver)) {}
        }
    }
}

#Preview("Rest pill · dark and light", traits: .sizeThatFitsLayout) {
    pills().previewEnvironment()
}

#Preview("Rest pill · AX3", traits: .sizeThatFitsLayout) {
    pills().previewEnvironment().dynamicTypeSize(.accessibility3)
}
