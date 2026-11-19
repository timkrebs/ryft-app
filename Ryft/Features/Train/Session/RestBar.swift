import SwiftUI

/// The rest timer, pinned under the session header outside the list (ui.md §6; PR 6 B §4.5, `b-02`): ring, time, the next set,
/// −15 s / +15 s / Skip. One home for the timer, so a jump to the next exercise never scrolls it away.
/// At AX sizes it can shrink to a one-line pill (`pill`); a tap on the pill asks for the full bar (`onExpand`).
///
/// Nocturne: a `surface` card, radius 22, with a 1 pt edge of ink at 20 % (the running rest pill's). The ring is 36 pt, 4 pt of
/// Volt progress on an ink track at 16 % (the running rest is one of Volt's marks, D6B-1); the time is 28 pt Light ink; the
/// three buttons are compact outline pills under it, −15 s and +15 s leading and Skip trailing, one per line at AX3 or wherever
/// the line can't hold them. "Rest over" is the same card with the bell, the words and a compact "Dismiss" (under the words at AX
/// sizes). Nothing is filled: the active set's ✓ is the screen's one filled mark.
///
/// VoiceOver: a container. The time and the next set are one adjustable element (swipe up/down = ±15 s, actions
/// for ±15 s and Skip, and on the pill one more to show the full bar); −15, +15 and Skip are buttons of their own,
/// which Voice Control can name.
struct RestBar: View {
    var controller: SessionController
    var pill = false
    var onExpand: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var timeSize: CGFloat = 28

    /// The card: radius 22 (`CardSpec.radius`), a 1 pt edge of ink at 20 %; 12 above and below, 14 at the sides.
    static let radius = CardSpec.radius, edge = 0.20
    static let verticalPadding: CGFloat = 12, horizontalPadding: CGFloat = 14
    /// The ring: 36 pt (28 at AX sizes), a 4 pt stroke, Volt on an ink track at 16 %.
    static let ring: CGFloat = 36, compactRing: CGFloat = 28, ringLine: CGFloat = 4, ringTrack = 0.16
    static let ringInk = Theme.signal
    /// The buttons' titles: a true minus (U+2212), as the rest sheet's keys.
    static let lessTitle = "\u{2212}15 s", moreTitle = "+15 s"

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
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("session.restBar")
        }
    }

    // MARK: running

    private var isAX: Bool { typeSize.isAccessibilitySize }

    private func running(at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ring(at: date)
                VStack(alignment: .leading, spacing: 2) {
                    time(at: date)
                    nextText
                        .lineLimit(isAX ? 3 : 2)
                        // Its full height: inside the bar's HStack it would otherwise get one line.
                        .fixedSize(horizontal: false, vertical: true)
                }
                .modifier(RestTimeElement(controller: controller, date: date))
            }
            buttons
        }
        .padding(.vertical, Self.verticalPadding)
        .padding(.horizontal, Self.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RestBarCard(shape: RoundedRectangle(cornerRadius: Self.radius, style: .continuous)))
    }

    /// AX sizes while the list is in use: ring, time, Skip, in a capsule. A tap elsewhere on it shows the full bar.
    private func pillBar(at date: Date) -> some View {
        HStack(spacing: 12) {
            ring(at: date)
            time(at: date)
                .modifier(RestTimeElement(controller: controller, date: date, onExpand: onExpand))
            Spacer(minLength: 0)
            skipButton
        }
        .padding(.vertical, 6)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(RestBarCard(shape: Capsule()))
        .contentShape(Capsule())
        .onTapGesture(perform: onExpand)
    }

    /// Volt on an ink track. Under Reduce Motion it still draws, and jumps from tick to tick (it never eases).
    private func ring(at date: Date) -> some View {
        let size = isAX ? Self.compactRing : Self.ring
        return ZStack {
            Circle().stroke(Theme.textPrimary.opacity(Self.ringTrack), lineWidth: Self.ringLine)
            Circle()
                .trim(from: 0, to: controller.rest.fraction(at: date))
                .stroke(Self.ringInk, style: StrokeStyle(lineWidth: Self.ringLine, lineCap: .round))
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

    /// AX3 and up: one button per line, leading. Otherwise −15 s and +15 s leading and Skip at the end of the line, while the
    /// three fit on it; where they don't (AX1 and AX2, or XXL at 320 pt) they go one per line as at AX3.
    private var stacksButtons: Bool { typeSize >= .accessibility3 }

    @ViewBuilder private var buttons: some View {
        if stacksButtons {
            stackedButtons
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    adjustButton(by: -RestTimer.step)
                    adjustButton(by: RestTimer.step)
                    Spacer(minLength: 0)
                    skipButton
                }
                stackedButtons
            }
        }
    }

    private var stackedButtons: some View {
        VStack(alignment: .leading, spacing: 8) {
            adjustButton(by: -RestTimer.step)
            adjustButton(by: RestTimer.step)
            skipButton
        }
    }

    private func adjustButton(by delta: TimeInterval) -> some View {
        PillButton(verbatim: delta < 0 ? Self.lessTitle : Self.moreTitle, style: .secondary, size: .compact) {
            controller.adjustRest(by: delta)
        }
        .accessibilityLabel(delta < 0 ? Text("Fifteen seconds less") : Text("Fifteen seconds more"))
        .accessibilityInputLabels(delta < 0
            ? [Text("Minus 15", comment: "Voice Control name of the rest bar's −15 button."), Text("Fifteen seconds less")]
            : [Text("Plus 15", comment: "Voice Control name of the rest bar's +15 button."), Text("Fifteen seconds more")])
    }

    private var skipButton: some View {
        PillButton(Text("Skip"), style: .secondary, size: .compact) {
            controller.skipRest()
        }
        .accessibilityLabel(Text("Skip rest"))
        .accessibilityInputLabels([Text("Skip"), Text("Skip rest")])
    }

    // MARK: finished

    /// "Rest over", the next set, and a compact "Dismiss". The whole card still dismisses on a tap, as the banner did. At AX sizes
    /// the words take the card's width and Dismiss goes under them, leading, so the next set isn't cut beside the pill.
    private var finished: some View {
        Group {
            if isAX {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        bell
                        finishedWords
                    }
                    dismissButton
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    bell
                    finishedWords
                    dismissButton
                }
            }
        }
        .padding(.vertical, Self.verticalPadding)
        .padding(.leading, Self.horizontalPadding)
        .padding(.trailing, Self.horizontalPadding - 2)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .modifier(RestBarCard(shape: RoundedRectangle(cornerRadius: Self.radius, style: .continuous)))
        .contentShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .onTapGesture { controller.dismissRestBanner() }
    }

    private var bell: some View {
        Image(systemName: "bell")
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)
    }

    /// "Rest over" and the next set, one element. At AX sizes the next set takes the lines it needs (up to 3).
    private var finishedWords: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Rest over")
                .font(.ryft(.headline))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: isAX)
            Text(Self.nextLine(controller.nextLabel()))
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(isAX ? 3 : 1)
                .fixedSize(horizontal: false, vertical: isAX)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Rest over. \(Self.nextLine(controller.nextLabel()))"))
    }

    private var dismissButton: some View {
        PillButton(Text("Dismiss"), style: .secondary, size: .compact) {
            controller.dismissRestBanner()
        }
        .accessibilityHint(Text("Dismisses the banner"))
    }
}

/// The bar's ground: `surface` in `shape`, with the 1 pt edge of ink at 20 %.
private struct RestBarCard<S: InsettableShape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: shape)
            .overlay(shape.strokeBorder(Theme.textPrimary.opacity(RestBar.edge), lineWidth: Theme.Metrics.hairline))
    }
}

/// The time and the next set as one VoiceOver element, every modifier on this one level: label "Rest timer", value
/// "1 minute, 35 seconds left. Next: …" (in 5 s steps, so it doesn't chatter), adjustable by ±15 s, actions for
/// ±15 s and Skip; on the pill a named action shows the full bar. No default action: SwiftUI would add the button
/// trait, and the element should read as adjustable only.
private struct RestTimeElement: ViewModifier {
    var controller: SessionController
    var date: Date
    var onExpand: (() -> Void)?

    @ViewBuilder func body(content: Content) -> some View {
        if let onExpand {
            element(content)
                .accessibilityAction(named: Text(
                    "Show rest timer",
                    comment: "VoiceOver action on the rest bar's small pill (large text sizes): shows the full rest timer.")) {
                    onExpand()
                }
        } else {
            element(content)
        }
    }

    private func element(_ content: Content) -> some View {
        content
            .accessibilityElement(children: .ignore)
            .accessibilityRemoveTraits(.isButton)
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

// MARK: - previews (dark only)

/// `b-02`'s bar: 1:54 left of Bench press's rest, and the AX pill it shrinks to.
#Preview("Rest bar · running, pill", traits: .sizeThatFitsLayout) {
    let c = SessionSheetsPreview.listDraft()
    return VStack(spacing: 12) {
        RestBar(controller: c)
        RestBar(controller: c, pill: true)
    }
    .padding(LiveSessionSpec.sidePadding)
    .frame(width: 390)
    .background(Theme.background)
    .previewEnvironment()
}

#Preview("Rest bar · XL", traits: .sizeThatFitsLayout) {
    RestBar(controller: SessionSheetsPreview.listDraft())
        .padding(LiveSessionSpec.sidePadding)
        .frame(width: 390)
        .background(Theme.background)
        .previewEnvironment()
        .dynamicTypeSize(.xLarge)
}

#Preview("Rest bar · AX3", traits: .sizeThatFitsLayout) {
    let c = SessionSheetsPreview.listDraft()
    return VStack(spacing: 12) {
        RestBar(controller: c)
        RestBar(controller: c, pill: true)
    }
    .padding(LiveSessionSpec.sidePadding)
    .frame(width: 390)
    .background(Theme.background)
    .previewEnvironment()
    .dynamicTypeSize(.accessibility3)
}

#Preview("Rest bar · rest over", traits: .sizeThatFitsLayout) {
    RestBar(controller: SessionSheetsPreview.listFolded())
        .padding(LiveSessionSpec.sidePadding)
        .frame(width: 390)
        .background(Theme.background)
        .previewEnvironment()
}

#Preview("Rest bar · rest over, AX3", traits: .sizeThatFitsLayout) {
    RestBar(controller: SessionSheetsPreview.listFolded())
        .padding(LiveSessionSpec.sidePadding)
        .frame(width: 390)
        .background(Theme.background)
        .previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}

#Preview("Rest bar · AX2 at 320", traits: .sizeThatFitsLayout) {
    RestBar(controller: SessionSheetsPreview.listDraft())
        .padding(LiveSessionSpec.sidePadding)
        .frame(width: 320)
        .background(Theme.background)
        .previewEnvironment()
        .dynamicTypeSize(.accessibility2)
}
