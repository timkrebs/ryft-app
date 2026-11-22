import Observation
import SwiftUI

/// What a coach mark points at. Views mark themselves with `.coachMarkTarget(_:)`.
enum CoachMarkTarget: Int, CaseIterable, Hashable, Sendable {
    case gauges, physiology, trends

    var title: String {
        switch self {
        case .gauges: return String(localized: "Your readiness")
        case .physiology: return String(localized: "Sleep, recovery, strain")
        case .trends: return String(localized: "Trends")
        }
    }

    var body: String {
        switch self {
        case .gauges:
            return String(localized: "Recovery and last night's sleep, against your own baseline. The ticks mark the usual ranges; the line underneath compares with the 7 days before.")
        case .physiology:
            return String(localized: "Tap a tile for the details. The word under recovery is its level, so the colour is never the only cue.")
        case .trends:
            return String(localized: "The last 7 days. Tap for every metric over 7, 30 or 90 days.")
        }
    }
}

/// First-run coach marks on Today: three steps, shown once per install.
@MainActor
@Observable
final class CoachMarks {
    static let doneKey = "coachMarks.today.done"

    private let defaults: UserDefaults
    private(set) var step: CoachMarkTarget?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // `-coachMarks.today.done YES` (UI tests) lands here too, via the argument domain.
        step = defaults.bool(forKey: Self.doneKey) ? nil : .gauges
    }

    var isLast: Bool { step == CoachMarkTarget.allCases.last }
    var position: String {
        guard let step else { return "" }
        return String(localized: "\(step.rawValue + 1) of \(CoachMarkTarget.allCases.count)")
    }

    func next() {
        guard let step else { return }
        if let following = CoachMarkTarget(rawValue: step.rawValue + 1) {
            self.step = following
        } else {
            finish()
        }
    }

    func finish() {
        step = nil
        defaults.set(true, forKey: Self.doneKey)
    }
}

private struct CoachMarkAnchors: PreferenceKey {
    static let defaultValue: [CoachMarkTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachMarkTarget: Anchor<CGRect>], nextValue: () -> [CoachMarkTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Registers this view's frame as a coach-mark target.
    func coachMarkTarget(_ target: CoachMarkTarget) -> some View {
        anchorPreference(key: CoachMarkAnchors.self, value: .bounds) { [target: $0] }
    }

    /// Draws `marks` over this view: a dimmed screen with the target cut out, and a card.
    func coachMarks(_ marks: CoachMarks, enabled: Bool) -> some View {
        overlayPreferenceValue(CoachMarkAnchors.self) { anchors in
            if enabled, let step = marks.step, let anchor = anchors[step] {
                GeometryReader { proxy in
                    CoachMarkOverlay(marks: marks, step: step, rect: proxy[anchor], size: proxy.size)
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
    }
}

private struct CoachMarkOverlay: View {
    let marks: CoachMarks
    let step: CoachMarkTarget
    let rect: CGRect
    let size: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hole: CGRect { rect.insetBy(dx: -8, dy: -8) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The screen dimmed, the target cut out (even-odd), moving between steps.
            Path { p in
                p.addRect(CGRect(origin: .zero, size: size))
                p.addRoundedRect(in: hole, cornerSize: CGSize(width: 20, height: 20))
            }
            .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
            .contentShape(Rectangle())
            .onTapGesture { advance() }
            .accessibilityHidden(true)

            card
                .frame(maxWidth: 340)
                .position(x: size.width / 2, y: cardY)
        }
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.slow), value: step)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// Below the target when there's room, else above.
    private var cardY: CGFloat {
        let below = hole.maxY + 110
        return below + 90 < size.height ? below : max(hole.minY - 110, 120)
    }

    /// A `Card` (radius 22, 16 inside: the gate's D8): the position, the title, the text, then Skip and the compact primary
    /// pill ("Next", "Done" on the last step; no icon circle).
    private var card: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(marks.position).ryftLabelStyle()
                Text(step.title)
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(step.body)
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Skip") { marks.finish() }
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("coach.skip")
                    Spacer()
                    PillButton(marks.isLast ? Text("Done") : Text("Next"), size: .compact) { advance() }
                        .accessibilityIdentifier("coach.next")
                }
            }
        }
        .padding(.horizontal, Theme.Metrics.screenPadding)
    }

    private func advance() {
        withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.slow)) { marks.next() }
    }
}

// MARK: previews (dark only)

/// The overlay over a stand-in page, on step `step` (a throwaway defaults suite: nothing is remembered).
private struct CoachMarksPreview: View {
    @State private var marks: CoachMarks

    init(step: Int) {
        let defaults = UserDefaults(suiteName: "preview.coachMarks") ?? .standard
        defaults.removeObject(forKey: CoachMarks.doneKey)
        let marks = CoachMarks(defaults: defaults)
        for _ in 0..<step { marks.next() }
        _marks = State(initialValue: marks)
    }

    var body: some View {
        VStack(spacing: 24) {
            RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius).fill(Theme.surface).frame(height: 220)
                .coachMarkTarget(.gauges)
            RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius).fill(Theme.surface).frame(height: 124)
                .coachMarkTarget(.physiology)
            RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius).fill(Theme.surface).frame(height: 120)
                .coachMarkTarget(.trends)
            Spacer(minLength: 0)
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .coachMarks(marks, enabled: true)
        .preferredColorScheme(.dark)
    }
}

#Preview("Coach marks · first step") { CoachMarksPreview(step: 0) }
#Preview("Coach marks · last step") { CoachMarksPreview(step: 2) }
#Preview("Coach marks · first step · AX3") {
    CoachMarksPreview(step: 0).dynamicTypeSize(.accessibility3)
}
