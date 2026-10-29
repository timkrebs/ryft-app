import SwiftUI

/// The rest timer, pinned under the session header outside the list (ui.md §6): ring, time, the next set,
/// −15 / +15 / Skip. One home for the timer, so a jump to the next exercise never scrolls it away.
/// At AX sizes it can shrink to a one-line pill (`pill`); a tap on the pill asks for the full bar (`onExpand`).
struct RestBar: View {
    var controller: SessionController
    var pill = false
    var onExpand: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var timeSize: CGFloat = 28

    var body: some View {
        Group {
            switch controller.rest.phase {
            case .idle:
                EmptyView()
            case .running:
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    if pill { pillBar(at: context.date) } else { running(at: context.date) }
                }
                .modifier(RestBarAccessibility(controller: controller))
            case .finished:
                finished
            }
        }
        .accessibilityIdentifier("session.restBar")
    }

    // MARK: running

    private var isAX: Bool { typeSize.isAccessibilitySize }
    /// XL and up: the buttons get a full-width row of their own and the next set wraps.
    private var isLarge: Bool { typeSize >= .xLarge }

    private func running(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ring(at: date)
                if isLarge {
                    VStack(alignment: .leading, spacing: 2) {
                        time(at: date)
                        nextText.lineLimit(isAX ? 3 : 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            time(at: date)
                            nextText.lineLimit(1)
                        }
                        buttons
                    }
                }
            }
            if isLarge { buttons }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: Theme.Metrics.hairline))
    }

    /// AX sizes while the list is in use: ring, time, Skip. A tap elsewhere on it shows the full bar.
    private func pillBar(at date: Date) -> some View {
        HStack(spacing: 12) {
            ring(at: date)
            time(at: date)
            Spacer(minLength: 0)
            skipButton.fixedSize()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.35), lineWidth: Theme.Metrics.hairline))
        .contentShape(Capsule())
        .onTapGesture(perform: onExpand)
    }

    private func ring(at date: Date) -> some View {
        let size: CGFloat = isAX ? 28 : 36
        return ZStack {
            Circle().stroke(Theme.accent.opacity(0.14), lineWidth: 4)
            Circle()
                .trim(from: 0, to: controller.rest.fraction(at: date))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func time(at date: Date) -> some View {
        Text(Fmt.clock(controller.rest.remaining(at: date).rounded(.up)))
            .font(.ryftNumber(size: timeSize))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: true))
            .lineLimit(1)
            .fixedSize()
    }

    private var nextText: some View {
        Text("Next: \(controller.nextLabel())",
             comment: "The rest bar's next set, e.g. Next: Bench press · set 1 of 4.")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var buttons: some View {
        // AX3 and up: one full-width button per row.
        let layout = typeSize >= .accessibility3
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            adjustButton(by: -RestTimer.step)
            adjustButton(by: RestTimer.step)
            skipButton
        }
    }

    private func adjustButton(by delta: TimeInterval) -> some View {
        Button {
            controller.adjustRest(by: delta)
        } label: {
            // A true minus (U+2212); VoiceOver uses the bar's actions instead.
            Text(verbatim: delta < 0 ? "−15" : "+15")
                .font(.ryft(.headline))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: buttonHeight)
                .background(Theme.surfaceRaised, in: Capsule())
                .contentShape(Capsule().inset(by: -2))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityInputLabels(delta < 0 ? [Text("Minus 15", comment: "Voice Control name of the rest bar's −15 button.")]
                                            : [Text("Plus 15", comment: "Voice Control name of the rest bar's +15 button.")])
    }

    private var skipButton: some View {
        Button {
            controller.skipRest()
        } label: {
            Text("Skip")
                .font(.ryft(.headline))
                .lineLimit(1)
                .minimumScaleFactor(0.7) // "Überspringen" in German
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12)
                .frame(maxWidth: pill ? nil : .infinity, minHeight: buttonHeight)
                .background(Theme.accent, in: Capsule())
                .contentShape(Capsule().inset(by: -2))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var buttonHeight: CGFloat { typeSize >= .accessibility3 ? 48 : 44 }

    // MARK: finished

    private var finished: some View {
        Button {
            controller.dismissRestBanner()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest over")
                        .font(.ryft(.headline))
                    Text(controller.nextLabel())
                        .font(.ryft(.caption))
                        .lineLimit(isAX ? 3 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Theme.onAccent)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Rest over. \(controller.nextLabel())"))
        .accessibilityHint(Text("Dismisses the banner"))
    }
}

/// VoiceOver: the running bar is one element. Value = time left (in 5 s steps, so it doesn't chatter) and the next
/// set; ±15 s and Skip are actions, and swiping up or down adjusts like a slider.
private struct RestBarAccessibility: ViewModifier {
    var controller: SessionController

    func body(content: Content) -> some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let left = Int((controller.rest.remaining(at: context.date) / 5).rounded(.up)) * 5
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Rest timer"))
                .accessibilityValue(Text("\(left) seconds left. Next: \(controller.nextLabel())"))
        }
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: controller.adjustRest(by: RestTimer.step)
            case .decrement: controller.adjustRest(by: -RestTimer.step)
            @unknown default: break
            }
        }
        .accessibilityAction(named: Text("Fifteen seconds less")) { controller.adjustRest(by: -RestTimer.step) }
        .accessibilityAction(named: Text("Fifteen seconds more")) { controller.adjustRest(by: RestTimer.step) }
        .accessibilityAction(named: Text("Skip rest")) { controller.skipRest() }
    }
}

// MARK: - previews

#Preview("Rest bar · running, pill", traits: .sizeThatFitsLayout) {
    let running = TrainPreview.liveController()
    return SchemePair {
        VStack(spacing: 12) {
            RestBar(controller: running)
            RestBar(controller: running, pill: true)
        }
    }
}

#Preview("Rest bar · XL", traits: .sizeThatFitsLayout) {
    SchemePair {
        RestBar(controller: TrainPreview.liveController())
    }
    .dynamicTypeSize(.xLarge)
}

#Preview("Rest bar · AX3", traits: .sizeThatFitsLayout) {
    let c = TrainPreview.liveController()
    return SchemePair {
        VStack(spacing: 12) {
            RestBar(controller: c)
            RestBar(controller: c, pill: true)
        }
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Rest bar · rest over", traits: .sizeThatFitsLayout) {
    let c = TrainPreview.liveController()
    c.adjustRest(by: -RestTimer.maxRest)
    return SchemePair {
        RestBar(controller: c)
    }
}
