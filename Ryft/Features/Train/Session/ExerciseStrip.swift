import SwiftUI

extension ExerciseKind {
    /// The strip's glyph (L8, design.md §4b): `kind` is on every row, offline, custom and replaced exercises included.
    /// Unknown kinds decode to `machine`, so there is always one.
    var tileSymbol: String {
        switch self {
        case .barbell: return "figure.strengthtraining.traditional"
        case .dumbbell: return "dumbbell.fill"
        case .kettlebell: return "figure.strengthtraining.functional"
        case .bodyweight: return "figure.arms.open"
        case .machine: return "gearshape.2.fill"
        case .cable: return "figure.rower"
        case .cardio: return "figure.run"
        }
    }
}

/// How far an exercise is, in the strip's words. Derived, never stored: an unchecked set takes the badge away at once.
enum ExerciseProgress: Equatable {
    case done, inProgress, notStarted

    /// `isDone`: it has working sets and none is open. Otherwise the page on screen, or any checked set, is under way.
    init(isDone: Bool, isCurrent: Bool, hasCheckedSet: Bool) {
        if isDone {
            self = .done
        } else {
            self = isCurrent || hasCheckedSet ? .inProgress : .notStarted
        }
    }

    var label: String {
        switch self {
        case .done: return String(localized: "done", comment: "Exercise strip, VoiceOver: all of an exercise's working sets are checked.")
        case .inProgress: return String(localized: "in progress", comment: "Exercise strip, VoiceOver: the exercise on screen, or one with a set checked.")
        case .notStarted: return String(localized: "not started", comment: "Exercise strip, VoiceOver: an exercise with no set checked.")
        }
    }
}

/// One exercise on the strip: its kind's glyph over its position (design.md §4a, PR 6 B §4.2). A `surface` tile with a 1 pt ink
/// edge at 10 %. Dimming is by token, never opacity. The current tile has the only ring (2 pt ink) and the only `textPrimary`
/// content; a done one has the ink badge with its check: state is the ring, the number's brightness and the badge, never colour.
struct ExerciseTile: View {
    let symbol: String
    let number: Int
    let isCurrent: Bool
    let isDone: Bool
    var size: CGFloat = ExerciseTile.size

    static let size: CGFloat = LiveSessionSpec.tile
    /// From AX3 (design.md §5.1).
    static let largeSize: CGFloat = LiveSessionSpec.largeTile
    private static let corner = LiveSessionSpec.tileRadius
    /// The tile's edge, ink at 10 %, and the current tile's ring.
    static let edge = Theme.textPrimary.opacity(0.10), ringWidth: CGFloat = 2
    /// The done badge: a 16 pt ink disc with a 9 pt check in the screen's colour, 4 pt past the corner.
    static let badge: CGFloat = 16, badgeOffset: CGFloat = 4

    private var isLarge: Bool { size >= Self.largeSize }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: isLarge ? 24 : 20, weight: .medium))
                // A fixed box, so the numbers below it share one baseline.
                .frame(width: isLarge ? 26 : 22, height: isLarge ? 26 : 22)
            Text(verbatim: "\(number)")
                .font(.ryftNumber(size: isLarge ? 14 : 11))
                .monospacedDigit()
        }
        .foregroundStyle(isCurrent ? Theme.textPrimary : Theme.textSecondary)
        .frame(width: size, height: size)
        .background(Theme.surface, in: shape)
        .overlay {
            shape.strokeBorder(isCurrent ? Theme.textPrimary : Self.edge,
                               lineWidth: isCurrent ? Self.ringWidth : Theme.Metrics.hairline)
        }
        .overlay(alignment: .bottomTrailing) {
            if isDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .frame(width: Self.badge, height: Self.badge)
                    .background(Theme.textPrimary, in: Circle())
                    .offset(x: Self.badgeOffset, y: Self.badgeOffset)
            }
        }
    }
}

/// Every exercise of the session as a tile, then a + tile (design.md §2.2). Tap a tile for its page (no set changes),
/// long press to reorder. For VoiceOver the strip is one adjustable element; without it the tiles stay separate, so
/// Voice Control, Switch Control and the UI tests reach each one. Reads `pageExerciseID`, writes `jump(to:)`.
struct ExerciseStrip: View {
    var controller: SessionController
    var inset: CGFloat = 16
    var onAdd: () -> Void
    var onReorder: () -> Void
    /// VoiceOver's double tap: focus goes to that page's title.
    var onActivate: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let gap: CGFloat = 8
    /// 8 top, 56 tile, 3 gap, 3 bar, 6 bottom.
    static let height: CGFloat = LiveSessionSpec.strip
    /// A superset's bar under its tiles: 3 pt of ink at 55 %.
    static let supersetInk = Theme.textPrimary.opacity(0.55)
    /// The + tile's dashed edge: ink at 16 %.
    static let addEdge = Theme.textPrimary.opacity(0.16)

    static func tileSize(_ typeSize: DynamicTypeSize) -> CGFloat {
        typeSize >= .accessibility3 ? ExerciseTile.largeSize : ExerciseTile.size
    }

    static func height(_ typeSize: DynamicTypeSize) -> CGFloat {
        height + tileSize(typeSize) - ExerciseTile.size
    }

    private var page: UUID? { controller.pageExerciseID }
    private var motion: Animation? { Theme.Motion.respecting(reduceMotion) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.gap) {
                    ForEach(controller.exerciseGroups, id: \.first?.id) { group($0) }
                    addTile
                }
                .padding(.horizontal, inset)
                .padding(.top, LiveSessionSpec.stripTop)
                // Top-aligned, so a strip without a superset's bar doesn't sit 3 pt lower.
                .frame(height: Self.height(typeSize), alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .frame(height: Self.height(typeSize))
            .onAppear {
                if let page { proxy.scrollTo(page, anchor: .center) }
            }
            .onChange(of: page) { _, id in
                guard let id else { return }
                withAnimation(motion) { proxy.scrollTo(id, anchor: .center) }
            }
            // Reorder moves the tile without changing the page.
            .onChange(of: controller.exerciseGroups.flatMap { $0.map(\.id) }) {
                guard let page else { return }
                withAnimation(motion) { proxy.scrollTo(page, anchor: .center) }
            }
        }
        .accessibilityElement(children: voiceOver ? .ignore : .contain)
        .accessibilityLabel(Text("Exercises", comment: "Exercise strip in a workout, VoiceOver: the adjustable element's label."))
        .accessibilityValue(Text(pageValue))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(by: 1)
            case .decrement: move(by: -1)
            @unknown default: break
            }
        }
        .accessibilityAction {
            if let page { onActivate(page) }
        }
        .accessibilityAction(named: Text("Add exercise")) { onAdd() }
        .accessibilityAction(named: Text("Reorder exercises")) { onReorder() }
        .accessibilityIdentifier("session.strip")
    }

    /// One tile, or a superset's tiles over the bar that joins them.
    private func group(_ members: [LocalSessionExercise]) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: Self.gap) {
                ForEach(members) { tile($0) }
            }
            if members.count > 1 {
                Capsule()
                    .fill(Self.supersetInk)
                    .frame(height: 3)
                    .accessibilityHidden(true)
            }
        }
    }

    private func tile(_ ex: LocalSessionExercise) -> some View {
        let number = (controller.exercises.firstIndex { $0.id == ex.id } ?? 0) + 1
        let done = Self.isDone(ex)
        return ExerciseTile(symbol: ex.kind.tileSymbol, number: number, isCurrent: ex.id == page, isDone: done,
                            size: Self.tileSize(typeSize))
            .contentShape(RoundedRectangle(cornerRadius: LiveSessionSpec.tileRadius, style: .continuous))
            .onTapGesture {
                withAnimation(motion) { controller.jump(to: ex.id) }
            }
            .onLongPressGesture { onReorder() }
            .id(ex.id)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "\(ex.name), \(progress(of: ex).label)"))
            .accessibilityAddTraits(ex.id == page ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { withAnimation(motion) { controller.jump(to: ex.id) } }
            .accessibilityAction(named: Text("Reorder exercises")) { onReorder() }
            .accessibilityIdentifier("session.strip.\(ex.position)")
    }

    private var addTile: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Self.tileSize(typeSize), height: Self.tileSize(typeSize))
                .overlay {
                    RoundedRectangle(cornerRadius: LiveSessionSpec.tileRadius, style: .continuous)
                        .strokeBorder(Self.addEdge, style: StrokeStyle(lineWidth: Theme.Metrics.hairline, dash: [4, 3]))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Add exercise"))
        .accessibilityIdentifier("session.strip.add")
    }

    // MARK: VoiceOver

    /// Every working set checked; an exercise with none isn't done.
    static func isDone(_ ex: LocalSessionExercise) -> Bool {
        ex.sets.contains { !$0.isWarmup } && !SessionController.hasOpenWorkingSet(ex)
    }

    private func progress(of ex: LocalSessionExercise) -> ExerciseProgress {
        ExerciseProgress(isDone: Self.isDone(ex), isCurrent: ex.id == page, hasCheckedSet: ex.sets.contains(where: \.isCompleted))
    }

    /// "Exercise 2 of 6, Incline dumbbell press, in progress", and ", superset with Cable row" in one.
    private var pageValue: String {
        let list = controller.exercises
        guard let ex = controller.pageExercise, let i = list.firstIndex(where: { $0.id == ex.id }) else { return "" }
        let value = String(localized: "Exercise \(i + 1) of \(list.count), \(ex.name), \(progress(of: ex).label)",
                           comment: "Exercise strip, VoiceOver. 1: position, 2: exercises, 3: name, 4: done, in progress or not started.")
        let partners = controller.supersetPartners(of: ex).map(\.name)
        guard !partners.isEmpty else { return value }
        return value + ", " + String(localized: "superset with \(partners.formatted())",
                                     comment: "Exercise strip, VoiceOver, after the exercise. 1: the other exercises of its superset.")
    }

    private func move(by step: Int) {
        let list = controller.exercises
        guard let i = list.firstIndex(where: { $0.id == page }), list.indices.contains(i + step) else { return }
        withAnimation(motion) { controller.jump(to: list[i + step].id) }
    }
}

#Preview("Strip", traits: .sizeThatFitsLayout) {
    let c = FocusedPreview.controller(.draft)
    return DarkPreview {
        ExerciseStrip(controller: c, onAdd: {}, onReorder: {}, onActivate: { _ in })
    }
}

#Preview("Strip · one exercise and empty", traits: .sizeThatFitsLayout) {
    let one = FocusedPreview.controller(.oneExercise), empty = FocusedPreview.controller(.empty)
    return DarkPreview {
        VStack(spacing: 0) {
            ExerciseStrip(controller: one, onAdd: {}, onReorder: {}, onActivate: { _ in })
            ExerciseStrip(controller: empty, onAdd: {}, onReorder: {}, onActivate: { _ in })
        }
    }
}

#Preview("Strip · 12 exercises", traits: .sizeThatFitsLayout) {
    let c = FocusedPreview.controller(.manyExercises)
    return DarkPreview {
        ExerciseStrip(controller: c, onAdd: {}, onReorder: {}, onActivate: { _ in })
    }
}

#Preview("Strip · AX3", traits: .sizeThatFitsLayout) {
    let c = FocusedPreview.controller(.draft)
    return DarkPreview {
        ExerciseStrip(controller: c, onAdd: {}, onReorder: {}, onActivate: { _ in })
    }
    .dynamicTypeSize(.accessibility3)
}
