import SwiftUI

/// The rest timer, pinned under the session header outside the list (ui.md §6): ring, time, the next set,
/// −15 / +15 / Skip. One home for the timer, so a jump to the next exercise never scrolls it away.
/// At AX sizes it can shrink to a one-line pill (`pill`); a tap on the pill asks for the full bar (`onExpand`).
///
/// VoiceOver: a container. The time and the next set are one adjustable element (swipe up/down = ±15 s, actions
/// for ±15 s and Skip; only the pill has a default action, its expand); −15, +15 and Skip are buttons of their own,
/// which Voice Control can name.
struct RestBar: View {
    var controller: SessionController
    var pill = false
    var onExpand: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var timeSize: CGFloat = 28

    var body: some View {
        switch controller.rest.phase {
        case .idle:
            EmptyView()
        case .running:
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                if pill { pillBar(at: context.date) } else { running(at: context.date) }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("session.restBar")
        case .finished:
            finished
                .accessibilityIdentifier("session.restBar")
        }
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
                        nextText
                            .lineLimit(isAX ? 3 : 2)
                            // Its full height: inside the bar's HStack it would otherwise get one line.
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .modifier(RestTimeElement(controller: controller, date: date))
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            time(at: date)
                            nextText.lineLimit(1)
                        }
                        .modifier(RestTimeElement(controller: controller, date: date))
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
                .modifier(RestTimeElement(controller: controller, date: date, onActivate: onExpand))
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
        Text(Self.nextLine(controller.nextLabel()))
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Next: Bench press · set 1 of 4". Its own key: "Next: %@" elsewhere means the next plan day.
    static func nextLine(_ label: String) -> String {
        String(localized: "train.rest.next", defaultValue: "Next: \(label)",
               comment: "The rest bar's next set, e.g. Next: Bench press · set 1 of 4.")
    }

    /// AX3 and up: one full-width button per row. Otherwise −15 and +15 hug their label and Skip takes the rest,
    /// so "Überspringen" fits.
    private var stacksButtons: Bool { typeSize >= .accessibility3 }

    @ViewBuilder private var buttons: some View {
        let layout = stacksButtons
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
            // A true minus (U+2212).
            Text(verbatim: delta < 0 ? "−15" : "+15")
                .font(.ryft(.headline))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .frame(minWidth: 64, maxWidth: stacksButtons ? .infinity : nil, minHeight: buttonHeight)
                .background(Theme.surfaceRaised, in: Capsule())
                .contentShape(Capsule().inset(by: -2))
        }
        .buttonStyle(PressableButtonStyle())
        .fixedSize(horizontal: !stacksButtons, vertical: false)
        .accessibilityLabel(delta < 0 ? Text("Fifteen seconds less") : Text("Fifteen seconds more"))
        .accessibilityInputLabels(delta < 0
            ? [Text("Minus 15", comment: "Voice Control name of the rest bar's −15 button."), Text("Fifteen seconds less")]
            : [Text("Plus 15", comment: "Voice Control name of the rest bar's +15 button."), Text("Fifteen seconds more")])
    }

    private var skipButton: some View {
        Button {
            controller.skipRest()
        } label: {
            Text("Skip")
                .font(.ryft(.headline))
                .lineLimit(1)
                .minimumScaleFactor(0.7) // a last resort for "Überspringen" in a narrow bar
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 12)
                .frame(maxWidth: pill ? nil : .infinity, minHeight: buttonHeight)
                .background(Theme.accent, in: Capsule())
                .contentShape(Capsule().inset(by: -2))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Skip rest"))
        .accessibilityInputLabels([Text("Skip"), Text("Skip rest")])
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
                    Text(Self.nextLine(controller.nextLabel()))
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
        .accessibilityLabel(Text("Rest over. \(Self.nextLine(controller.nextLabel()))"))
        .accessibilityHint(Text("Dismisses the banner"))
    }
}

/// The time and the next set as one VoiceOver element, every modifier on this one level: label "Rest timer", value
/// "1 minute, 35 seconds left. Next: …" (in 5 s steps, so it doesn't chatter), adjustable by ±15 s, actions for
/// ±15 s and Skip. Only the pill gets a default action (its expand): an explicit default action makes SwiftUI add
/// the button trait, and the full bar's element should read as adjustable only.
private struct RestTimeElement: ViewModifier {
    var controller: SessionController
    var date: Date
    var onActivate: (() -> Void)?

    @ViewBuilder func body(content: Content) -> some View {
        if let onActivate {
            element(content).accessibilityAction(.default) { onActivate() }
        } else {
            element(content).accessibilityRemoveTraits(.isButton)
        }
    }

    private func element(_ content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Rest timer"))
            .accessibilityValue(Text(Self.value(remaining: controller.rest.remaining(at: date),
                                                next: controller.nextLabel())))
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

    /// "1 minute, 35 seconds left. Next: Bench press · set 1 of 4": the time rounded up to 5 s, spelled out in the
    /// user's language.
    static func value(remaining: TimeInterval, next: String) -> String {
        let seconds = Int((remaining / 5).rounded(.up)) * 5
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 60 ? [.minute, .second] : [.second]
        formatter.zeroFormattingBehavior = .dropAll
        let left = formatter.string(from: TimeInterval(max(seconds, 0))) ?? "\(seconds)"
        return String(localized: "train.rest.value", defaultValue: "\(left) left. Next: \(next)",
                      comment: "VoiceOver value of the rest timer, e.g. 1 minute, 35 seconds left. Next: Bench press · set 1 of 4.")
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
