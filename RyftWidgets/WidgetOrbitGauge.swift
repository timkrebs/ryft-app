// The widget's wrapper around the shared `OrbitGaugeDrawing` (ADR 0010): the number in the system's rounded face
// (the widget has no Satoshi), the marks accentable for tinted and clear home screens, the tracks quiet where the
// system renders the widget in one colour. No VoiceOver of its own: the family's view reads `Words.spoken` (the
// day's scores; while pending, only the last readiness).
import SwiftUI
import WidgetKit

struct WidgetOrbitGauge: View {
    /// `nil`: unknown (a snapshot written before the orbit): the tracks only, with `readiness` in the centre.
    let mode: OrbitGaugeMode?
    var size: OrbitGaugeSize = .small
    /// The centre number when the mode is unknown; a scored mode brings its own.
    var readiness: Int?
    /// The centre number while pending when the mode has no previous day's drawing (no orbit in the snapshot, e.g.
    /// row A's tiles or a calibrating file turned over): the latest readiness, dimmed, over the tracks and hollow dots.
    var previousReadiness: Int?
    /// The number inside the centre ring; off where the text beside it says it.
    var showsNumber = true
    /// The lock screen's circle: the number in the system's primary ink and a heavier weight.
    var prominentNumber = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redaction

    /// On a locked device: the tracks only, no arcs or dots, and a constant number under the redaction (the real
    /// one would show through by its width).
    private var locked: Bool { redaction.contains(.privacy) }

    var body: some View {
        OrbitGaugeDrawing(mode: locked ? nil : mode, size: size, palette: palette, marks: { $0.widgetAccentable() }) {
            if showsNumber, size.dial >= OrbitGaugeGeometry.minDialForNumber {
                centreText
                    .font(.system(size: pointSize, weight: prominentNumber ? .semibold : .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .privacySensitive()
        .accessibilityHidden(true)
    }

    private var pointSize: CGFloat { OrbitGaugeGeometry.numberPointSize(forDial: size.dial) }

    /// Locked: the constant. Calibrating: the count, with " / 7" from a 100 pt dial up as in the app (below it the
    /// segments say "of 7"). Pending: the previous day's readiness (or `previousReadiness`), dimmed, or the dash. Otherwise the readiness.
    private var centreText: Text {
        if locked { return Text(verbatim: Words.lockedNumber).foregroundStyle(numberStyle(dimmed: false)) }
        if case .calibrating(let calibration)? = mode {
            let count = Text(verbatim: String(calibration.counted)).foregroundStyle(numberStyle(dimmed: false))
            guard size.dial >= 100 else { return count }
            return count + Text(verbatim: " / \(calibration.required)")
                .font(.system(size: pointSize * 0.55, weight: .medium, design: .rounded))
                .foregroundStyle(numberStyle(dimmed: true))
        }
        return Text(verbatim: number.map(String.init) ?? "–")
            .foregroundStyle(numberStyle(dimmed: number == nil || mode?.isPending == true))
    }

    /// The readiness in the centre: the day's, the previous day's while pending (the drawing's, else
    /// `previousReadiness`), `readiness` when the mode is unknown.
    private var number: Int? {
        switch mode {
        case .scored(let values, _)?: return values.readiness
        case .pending(let previous)?: return previous?.readiness ?? previousReadiness
        case .calibrating?: return nil
        case nil: return readiness
        }
    }

    /// The ink of the centre: full, or dimmed for a dash, a previous day's number and the " / 7".
    private func numberStyle(dimmed: Bool) -> AnyShapeStyle {
        if locked { return prominentNumber ? AnyShapeStyle(.primary) : AnyShapeStyle(Brand.ink(scheme)) }
        if prominentNumber { return AnyShapeStyle(dimmed ? .secondary : .primary) }
        return AnyShapeStyle(dimmed ? Brand.ink(scheme).opacity(0.4) : Brand.ink(scheme))
    }

    /// The app's colours in full colour. Tinted, clear and lock-screen renderings turn every colour into one ink
    /// whose opacity is all that's left: an opaque track would outshine the arcs, so it becomes faint.
    private var palette: OrbitGaugePalette {
        var p = OrbitGaugePalette.assets
        if renderingMode != .fullColor { p.track = Color.white.opacity(0.25) }
        return p
    }
}

#Preview("WidgetOrbitGauge", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
            VStack(spacing: 12) {
                WidgetOrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)))
                WidgetOrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, strain: 6.2)))
                WidgetOrbitGauge(mode: nil, readiness: 71)
                WidgetOrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)))
                WidgetOrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .custom(dial: 104))
                WidgetOrbitGauge(mode: .pending(previous: OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88,
                                                                            strain: 9.6)))
                WidgetOrbitGauge(mode: .pending(previous: nil))
                WidgetOrbitGauge(mode: .pending(previous: nil), previousReadiness: 64)
                WidgetOrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)),
                                 size: .custom(dial: 56), prominentNumber: true)
                WidgetOrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)),
                                 size: .custom(dial: 44), showsNumber: false)
            }
            .padding(16)
            .background(Brand.background(scheme))
            .environment(\.colorScheme, scheme)
        }
    }
}
