import SwiftUI

// The rest timer itself is the pinned `RestBar` (RestBar.swift); the large card that scrolled with the list is gone.

/// Number entry for kg / reps / RPE: 56 pt keys, ±2.5 kg or ±1 rep steps,
/// Next moves kg → reps → the next set. Plate calculator for barbell weights. Nocturne (PR 6 B §4.6, `b-06`): digits, Next and
/// Delete raised; the steps outlined; Done the one ink key.
struct NumberPad: View {
    var controller: SessionController
    var onPlates: (Double) -> Void

    /// The keys: 56 high, radius 14 (the row's). The step keys are `OutlinedKey`s.
    static let keyHeight: CGFloat = 56, keyRadius = LiveSessionSpec.rowRadius

    private var field: SetFocus.Field { controller.focus?.field ?? .kg }

    var body: some View {
        VStack(spacing: 10) {
            header
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { digit("1"); digit("2"); digit("3"); stepKey(-1) }
                GridRow { digit("4"); digit("5"); digit("6"); stepKey(1) }
                GridRow { digit("7"); digit("8"); digit("9"); key("Next", systemImage: "arrow.right", prominent: false) { controller.nextField() } }
                GridRow {
                    if field == .reps { Color.clear.frame(height: 56) } else { digit(".") }
                    digit("0")
                    key("Delete", systemImage: "delete.left") { controller.backspace() }
                    key("Done", systemImage: nil, prominent: true) { controller.focus = nil }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(fieldTitle).ryftLabelStyle()
                if let target = controller.focusedSet {
                    let at = controller.position(of: target.set, in: target.exercise)
                    (at.isWarmup
                        ? Text("\(target.exercise.name) · warm-up \(at.number)",
                               comment: "Number pad header on a warm-up, e.g. Bench press · warm-up 1.")
                        : Text("\(target.exercise.name) · set \(at.number)"))
                        .font(.ryft(.caption))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(controller.buffer.isEmpty ? Fmt.placeholder : controller.displayBuffer)
                .font(.ryftNumber(size: 30))
                .monospacedDigit()
                .foregroundStyle(controller.buffer.isEmpty ? Theme.textTertiary : Theme.textPrimary)
                .padding(.trailing, 6)
                .accessibilityLabel(Text("Current value"))
                .accessibilityValue(Text(controller.buffer.isEmpty ? String(localized: "empty") : controller.displayBuffer))
            if field == .kg, let target = controller.focusedSet, target.exercise.kind == .barbell {
                Button {
                    let g = controller.ghost(for: target.set, in: target.exercise)
                    onPlates(target.set.weightKg ?? g.kg ?? PlateCalculator.barKg)
                } label: {
                    Label("Plates", systemImage: "circle.grid.cross")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(minHeight: Theme.Metrics.minHitTarget)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var fieldTitle: LocalizedStringKey {
        switch field {
        case .kg: return "Weight (kg)"
        case .reps: return "Reps"
        case .rpe: return "RPE"
        }
    }

    private func digit(_ d: String) -> some View {
        Button {
            controller.type(d)
        } label: {
            Text(d == "." ? Locale.current.decimalSeparator ?? "." : d)
                .font(.ryftNumber(size: 26))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Self.keyRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(d == "." ? String(localized: "Decimal point") : d))
    }

    private func stepKey(_ direction: Double) -> some View {
        let label: String = switch field {
        case .kg: direction > 0 ? "+2.5" : "−2.5"
        case .reps: direction > 0 ? "+1" : "−1"
        case .rpe: direction > 0 ? "+0.5" : "−0.5"
        }
        return Button {
            controller.step(direction)
        } label: {
            Text(label)
                .font(.ryftNumber(size: 19))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                .outlinedKey()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(direction > 0 ? "Increase" : "Decrease"))
    }

    private func key(_ title: LocalizedStringKey, systemImage: String?, prominent: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 20, weight: .semibold))
                } else {
                    Text(title).font(.ryft(.headline))
                }
            }
            .foregroundStyle(prominent ? Theme.background : Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
            .background(prominent ? Theme.textPrimary : Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: Self.keyRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(title))
    }
}

/// What goes on the bar: 20 kg bar, 2.5–25 kg plates, kg only. Nocturne (PR 6 B §4.6): the sheet header, outlined steps, every
/// plate in ink (height and its label tell them apart), the numbers in a grouped card, "Use" the primary pill at the bottom.
struct PlateCalculatorSheet: View {
    @State var target: Double
    var onUse: ((Double) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The steps: 72 × 56 `OutlinedKey`s.
    static let stepWidth: CGFloat = 72, stepHeight: CGFloat = 56

    private var load: PlateLoad { PlateCalculator.load(for: target) }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(Text("Plate calculator"))
                .padding(.horizontal, SheetHeaderSpec.sidePadding)
                .padding(.top, SheetHeaderSpec.topInset)
            ScrollView {
                VStack(spacing: 22) {
                    HStack(spacing: 10) {
                        stepper("−2.5", -2.5)
                        VStack(spacing: 2) {
                            Text(Fmt.kgNumber(target))
                                .font(.ryftNumber(size: 48))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                                .contentTransition(reduceMotion ? .identity : .numericText())
                            Text("kg target").ryftLabelStyle()
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                        stepper("+2.5", 2.5)
                    }
                    BarView(load: load)
                        .frame(height: 120)
                    GroupedCard(footer: load.total == target ? nil
                                : Text("\(Fmt.kg(target)) can't be loaded with 2.5–25 kg plates; this is the closest below.")) {
                        GroupedRow.value(Text("Each side"), value: Text(verbatim: perSideText))
                        GroupedRow.value(Text("Bar"), value: Text(verbatim: Fmt.kg(load.bar)))
                        GroupedRow.value(Text("Loaded"), value: Text(verbatim: Fmt.kg(load.total)))
                    }
                }
                .padding(Theme.Metrics.screenPadding)
            }
            .scrollBounceBehavior(.basedOnSize)
            if let onUse {
                PillButton(Text("Use \(Fmt.kg(load.total))")) {
                    onUse(load.total)
                    dismiss()
                }
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.bottom, 8)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .sheetDetents()
    }

    private var perSideText: String {
        load.perSide.isEmpty ? String(localized: "Empty bar") : load.perSide.map(Fmt.kgNumber).joined(separator: " + ")
    }

    private func stepper(_ title: String, _ delta: Double) -> some View {
        Button {
            withAnimation(Theme.Motion.respecting(reduceMotion)) { target = max(PlateCalculator.barKg, min(500, target + delta)) }
        } label: {
            Text(title)
                .font(.ryftNumber(size: 19))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: Self.stepWidth, height: Self.stepHeight)
                .outlinedKey()
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(delta > 0 ? "Add 2.5 kilograms" : "Remove 2.5 kilograms"))
    }
}

/// One side of the bar, plates drawn to scale by weight.
private struct BarView: View {
    let load: PlateLoad

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            HStack(spacing: 2) {
                Rectangle().fill(Theme.textTertiary).frame(width: 40, height: 10)
                Rectangle().fill(Theme.textSecondary).frame(width: 8, height: 28)
                ForEach(Array(load.perSide.enumerated()), id: \.offset) { _, plate in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Theme.textPrimary)
                        .frame(width: plate >= 10 ? 16 : 11, height: h * Self.height(for: plate))
                        .overlay {
                            Text(Fmt.kgNumber(plate))
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .rotationEffect(.degrees(-90))
                                .fixedSize()
                                .foregroundStyle(Theme.background)
                        }
                }
                Rectangle().fill(Theme.textTertiary).frame(maxWidth: .infinity).frame(height: 10)
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Plates per side"))
        .accessibilityValue(Text(load.perSide.isEmpty ? String(localized: "Empty bar")
                                 : load.perSide.map { Fmt.kg($0) }.joined(separator: ", ")))
    }

    static func height(for plate: Double) -> CGFloat {
        switch plate {
        case 20...: return 1
        case 15: return 0.86
        case 10: return 0.72
        case 5: return 0.52
        default: return 0.4
        }
    }
}

/// `b-06`: the keypad on a barbell's kg, with Plates.
#Preview("Keypad", traits: .sizeThatFitsLayout) {
    let c = FocusedPreview.controller(.draft)
    if let ex = c.pageExercise { c.edit(ex.orderedSets[1], .kg) }
    return DarkPreview {
        NumberPad(controller: c, onPlates: { _ in })
    }
}

#Preview("Keypad · reps", traits: .sizeThatFitsLayout) {
    let c = FocusedPreview.controller(.draft)
    if let ex = c.pageExercise { c.edit(ex.orderedSets[1], .reps) }
    return DarkPreview {
        NumberPad(controller: c, onPlates: { _ in })
    }
}

/// 102.5 can't be loaded: the closest below, and the sentence under the card.
#Preview("Plate calculator") {
    PlateCalculatorSheet(target: 102.5, onUse: { _ in })
        .previewEnvironment()
}

#Preview("Plate calculator · from the menu") {
    PlateCalculatorSheet(target: 140)
        .previewEnvironment()
}
