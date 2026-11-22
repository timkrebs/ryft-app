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
            return String(localized: "Recovery and last night's sleep, against your own baseline. The ticks mark the usual ranges; the line underneath compares with the 7\u{00A0}days before.")
        case .physiology:
            return String(localized: "Tap a tile for the details. The word under recovery is its level, so the colour is never the only cue.")
        case .trends:
            return String(localized: "The last 7\u{00A0}days. Tap for every metric over 7, 30 or 90\u{00A0}days.")
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

    /// Draws `marks` over this view: a dimmed screen with the target cut out, and a card. The dim covers the whole screen;
    /// the card is laid out in the safe area (`CoachCardPlacement`), never under the status bar or the home indicator.
    func coachMarks(_ marks: CoachMarks, enabled: Bool) -> some View {
        overlayPreferenceValue(CoachMarkAnchors.self) { anchors in
            if enabled, let step = marks.step, let anchor = anchors[step] {
                CoachMarkOverlay(marks: marks, step: step, anchor: anchor)
                    .transition(.opacity)
            }
        }
    }
}

private struct CoachMarkOverlay: View {
    let marks: CoachMarks
    let step: CoachMarkTarget
    let anchor: Anchor<CGRect>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The cut-out: the target and 8 around it.
    static func hole(_ rect: CGRect) -> CGRect { rect.insetBy(dx: -8, dy: -8) }

    var body: some View {
        ZStack {
            // The screen dimmed, the target cut out (even-odd), moving between steps.
            GeometryReader { proxy in
                let hole = Self.hole(proxy[anchor])
                Path { p in
                    p.addRect(CGRect(origin: .zero, size: proxy.size))
                    p.addRoundedRect(in: hole, cornerSize: CGSize(width: 20, height: 20))
                }
                .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture { advance() }
                .accessibilityHidden(true)
            }
            .ignoresSafeArea()
            // The card, in the safe area: this reader doesn't ignore it, so its space is the safe area's.
            GeometryReader { proxy in
                CoachCardPlacement(hole: Self.hole(proxy[anchor])) { card }
            }
        }
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.slow), value: step)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// A `Card` (radius 22, 16 inside: the gate's D8): the position, the title, the text, then Skip and the compact primary
    /// pill ("Next", "Done" on the last step; no icon circle). When the card is capped (`CoachCardPlacement`), the position,
    /// the title and the text scroll inside it and Skip and Next stay at its foot.
    private var card: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .vertical) {
                    words
                    ScrollView { words }
                        .scrollBounceBehavior(.basedOnSize)
                        // The text goes on below the card's foot: the indicator says so, on each step.
                        .scrollIndicatorsFlash(trigger: step)
                        .scrollIndicatorsFlash(onAppear: true)
                }
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

    private var words: some View {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func advance() {
        withAnimation(Theme.Motion.respecting(reduceMotion, Theme.Motion.slow)) { marks.next() }
    }
}

/// Lays the coach card out in its space, the safe area: below the hole when it fits there, else above it; taller than
/// either side, it is capped and its text scrolls (`CoachMarkOverlay.card`). It never leaves the safe area: the part 2
/// validation found the first step's card centred at 120 and only clamped there, its title under the status bar at AX3.
struct CoachCardPlacement: Layout {
    /// The cut-out, in this layout's space (the safe area's).
    let hole: CGRect

    /// The card's widest, its screen padding included.
    nonisolated static let maxWidth: CGFloat = 340
    /// The card to the safe area's edges, and to the hole.
    nonisolated static let margin: CGFloat = 12, gap: CGFloat = 12
    /// A capped card takes at least this share of the room, so a step whose hole leaves little room on either side overlaps
    /// the hole (half of it stays in view) rather than showing a sliver of text: at 280 pt the AX3 card showed under two lines.
    nonisolated static let minimumShare: CGFloat = 0.5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let card = subviews.first else { return }
        let width = min(bounds.width, Self.maxWidth)
        let natural = card.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        let room = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height).insetBy(dx: 0, dy: Self.margin)
        let frame = Self.frame(height: natural, hole: hole, room: room)
        card.place(at: CGPoint(x: bounds.midX, y: bounds.minY + frame.top), anchor: .top,
                   proposal: ProposedViewSize(width: width, height: frame.height))
    }

    /// Where a card `height` tall goes in `room` (the safe area less the margins) around `hole`: its top and its height.
    nonisolated static func frame(height: CGFloat, hole: CGRect, room: CGRect) -> (top: CGFloat, height: CGFloat) {
        let below = room.maxY - (hole.maxY + gap), above = (hole.minY - gap) - room.minY
        if height <= below { return (hole.maxY + gap, height) }
        if height <= above { return (hole.minY - gap - height, height) }
        // Taller than either side: capped to the larger one (but not below the minimum), its text scrolling.
        let capped = min(height, room.height, max(below, above, room.height * minimumShare))
        let top = below >= above ? min(hole.maxY + gap, room.maxY - capped) : max(hole.minY - gap - capped, room.minY)
        return (min(max(top, room.minY), room.maxY - capped), capped)
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
#Preview("Coach marks · first step · AX5") {
    CoachMarksPreview(step: 0).dynamicTypeSize(.accessibility5)
}
