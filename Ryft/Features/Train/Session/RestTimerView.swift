import SwiftUI

/// The prominent rest timer: big countdown, ring, −15 s / +15 s / Skip, next set.
struct RestTimerView: View {
    var controller: SessionController

    var body: some View {
        switch controller.rest.phase {
        case .idle:
            EmptyView()
        case .running:
            running
        case .finished:
            finished
        }
    }

    private var running: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let remaining = controller.rest.remaining(at: context.date)
            VStack(spacing: 14) {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(Theme.accent.opacity(0.14), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: controller.rest.fraction(at: context.date))
                            .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "timer")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Rest")
                            .ryftLabelStyle()
                        Text(Fmt.clock(remaining.rounded(.up)))
                            .font(.ryftNumber(size: 46))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText(countsDown: true))
                        Text("Next: \(controller.nextLabel())")
                            .font(.ryft(.caption))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Rest timer"))
                .accessibilityValue(Text("\(Int(remaining.rounded(.up))) seconds left. Next: \(controller.nextLabel())"))
                HStack(spacing: 10) {
                    restButton("−15 s", label: "Fifteen seconds less") { controller.adjustRest(by: -RestTimer.step) }
                    restButton("+15 s", label: "Fifteen seconds more") { controller.adjustRest(by: RestTimer.step) }
                    restButton("Skip", label: "Skip rest", prominent: true) { controller.skipRest() }
                }
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: Theme.Metrics.hairline))
        }
    }

    private var finished: some View {
        Button {
            controller.dismissRestBanner()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rest over")
                        .font(.ryft(.headline))
                    Text(controller.nextLabel())
                        .font(.ryft(.caption))
                }
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Theme.onAccent)
            .padding(16)
            .frame(minHeight: 56)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text("Rest over. \(controller.nextLabel())"))
        .accessibilityHint(Text("Dismisses the banner"))
    }

    private func restButton(_ title: LocalizedStringKey, label: LocalizedStringKey, prominent: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.ryftNumber(size: 17))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7) // "Überspringen" in German
                .padding(.horizontal, 8)
                .foregroundStyle(prominent ? Theme.onAccent : Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(prominent ? Theme.accent : Theme.surfaceRaised, in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// Number entry for kg / reps / RPE: 56 pt keys, ±2.5 kg or ±1 rep steps,
/// Next moves kg → reps → the next set. Plate calculator for barbell weights.
struct NumberPad: View {
    var controller: SessionController
    var onPlates: (Double) -> Void

    private var field: SetFocus.Field { controller.focus?.field ?? .kg }

    var body: some View {
        VStack(spacing: 10) {
            header
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { digit("1"); digit("2"); digit("3"); stepKey(-1) }
                GridRow { digit("4"); digit("5"); digit("6"); stepKey(1) }
                GridRow { digit("7"); digit("8"); digit("9"); key("Next", systemImage: "arrow.right", prominent: false) { controller.advance() } }
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
                    let n = (target.exercise.orderedSets.firstIndex { $0.id == target.set.id } ?? 0) + 1
                    Text("\(target.exercise.name) · set \(n)")
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
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
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
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .foregroundStyle(prominent ? Theme.onAccent : Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(prominent ? Theme.accent : Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(Text(title))
    }
}

/// What goes on the bar: 20 kg bar, 2.5–25 kg plates, kg only.
struct PlateCalculatorSheet: View {
    @State var target: Double
    var onUse: ((Double) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss

    private var load: PlateLoad { PlateCalculator.load(for: target) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                HStack(spacing: 10) {
                    stepper("−2.5", -2.5)
                    VStack(spacing: 2) {
                        Text(Fmt.kgNumber(target))
                            .font(.ryftNumber(size: 48))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText())
                        Text("kg target").ryftLabelStyle()
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    stepper("+2.5", 2.5)
                }
                BarView(load: load)
                    .frame(height: 120)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        StatRow(title: "Each side", value: perSideText)
                        StatRow(title: "Bar", value: Fmt.kg(load.bar))
                        StatRow(title: "Loaded", value: Fmt.kg(load.total),
                                valueColor: load.total == target ? Theme.textPrimary : Theme.warning)
                        if load.total != target {
                            Text("\(Fmt.kg(target)) can't be loaded with 2.5–25 kg plates; this is the closest below.")
                                .font(.ryft(.caption))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                Spacer()
                if let onUse {
                    Button("Use \(Fmt.kg(load.total))") {
                        onUse(load.total)
                        dismiss()
                    }
                    .buttonStyle(TealButtonStyle())
                }
            }
            .padding(Theme.Metrics.screenPadding)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Plate calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var perSideText: String {
        load.perSide.isEmpty ? String(localized: "Empty bar") : load.perSide.map(Fmt.kgNumber).joined(separator: " + ")
    }

    private func stepper(_ title: String, _ delta: Double) -> some View {
        Button {
            withAnimation(.snappy) { target = max(PlateCalculator.barKg, min(500, target + delta)) }
        } label: {
            Text(title)
                .font(.ryftNumber(size: 19))
                .foregroundStyle(Theme.accent)
                .frame(width: 72, height: 56)
                .background(Theme.accent.opacity(0.14), in: Capsule())
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
                        .fill(Self.color(for: plate))
                        .frame(width: plate >= 10 ? 16 : 11, height: h * Self.height(for: plate))
                        .overlay {
                            Text(Fmt.kgNumber(plate))
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .rotationEffect(.degrees(-90))
                                .fixedSize()
                                .foregroundStyle(Theme.graphite)
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

    /// Calibrated-plate colours, muted into the palette.
    static func color(for plate: Double) -> Color {
        switch plate {
        case 25: return Theme.alert
        case 20: return Theme.stageLight
        case 15: return Theme.warning
        case 10: return Theme.accent
        case 5: return Theme.mist
        default: return Theme.sage
        }
    }
}

#Preview("Rest timer & keypad", traits: .sizeThatFitsLayout) {
    let c = TrainPreview.liveController()
    let set = c.exercises[0].orderedSets[2]
    c.edit(set, .kg)
    return SchemePair {
        VStack(spacing: 16) {
            RestTimerView(controller: c)
            NumberPad(controller: c, onPlates: { _ in })
        }
    }
}

#Preview("Plate calculator · dark") {
    PlateCalculatorSheet(target: 102.5, onUse: { _ in })
        .preferredColorScheme(.dark)
}

#Preview("Plate calculator · light") {
    PlateCalculatorSheet(target: 140, onUse: { _ in })
        .preferredColorScheme(.light)
}
