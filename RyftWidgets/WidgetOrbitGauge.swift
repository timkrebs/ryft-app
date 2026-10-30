// The widget's wrapper around the shared `OrbitGaugeDrawing` (ADR 0010): the number in the system's rounded face
// (the widget has no Satoshi), the marks accentable for tinted and clear home screens, the tracks quiet where the
// system renders the widget in one colour. No VoiceOver of its own: the family's view reads `Words.spoken`, which
// carries the same scores.
import SwiftUI
import WidgetKit

struct WidgetOrbitGauge: View {
    /// `nil`: unknown (a snapshot written before the orbit): the tracks only, with `readiness` in the centre.
    let mode: OrbitGaugeMode?
    var size: OrbitGaugeSize = .small
    /// The centre number when the mode is unknown; a scored mode brings its own.
    var readiness: Int?
    /// The number inside the centre ring; off where the text beside it says it.
    var showsNumber = true
    /// The lock screen's circle: the number in the system's primary ink and a heavier weight.
    var prominentNumber = false

    @Environment(\.colorScheme) private var scheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redaction

    /// On a locked device: the tracks only, no arcs, dots or number.
    private var locked: Bool { redaction.contains(.privacy) }

    var body: some View {
        OrbitGaugeDrawing(mode: locked ? nil : mode, size: size, palette: palette, marks: { $0.widgetAccentable() }) {
            if showsNumber, !locked, size.dial >= OrbitGaugeGeometry.minDialForNumber {
                Text(verbatim: number.map(String.init) ?? "–")
                    .font(.system(size: OrbitGaugeGeometry.numberPointSize(forDial: size.dial),
                                  weight: prominentNumber ? .semibold : .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(numberStyle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .privacySensitive()
        .accessibilityHidden(true)
    }

    private var number: Int? { mode?.scoredValues?.readiness ?? (mode == nil ? readiness : nil) }

    private var numberStyle: AnyShapeStyle {
        if prominentNumber { return AnyShapeStyle(number == nil ? .secondary : .primary) }
        return AnyShapeStyle(number == nil ? Brand.ink(scheme).opacity(0.4) : Brand.ink(scheme))
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
