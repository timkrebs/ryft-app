// The widget's wrapper around the shared `OrbitGaugeDrawing` (ADR 0010): the number in the system face (the widget has no
// Satoshi; F21), Light from 20 pt up and never the dot grid (D6C-8), the marks accentable for tinted and clear home screens,
// the tracks quiet where the system renders the widget in one colour. What the centre holds and in which ink is
// `ReadinessWidgetLook`'s (`Shared/WidgetLook.swift`). No VoiceOver of its own: the family's view reads `Words.spoken`.
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
    /// The lock screen's circle: the number Medium, in the system's hierarchical inks (its vibrant rendering).
    var prominentNumber = false

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redaction

    /// On a locked device and in the placeholder: the tracks only, no arcs or dots, and a constant number under the
    /// redaction (the real one would show through by its width).
    private var hidden: Bool { redaction.hidesValues }

    var body: some View {
        OrbitGaugeDrawing(mode: hidden ? nil : mode, size: size, palette: palette, marks: { $0.widgetAccentable() }) {
            if showsNumber, size.dial >= OrbitGaugeGeometry.minDialForNumber {
                centreText
                    .font(.system(size: pointSize, weight: weight))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .privacySensitive()
        .accessibilityHidden(true)
    }

    private var pointSize: CGFloat { OrbitGaugeGeometry.numberPointSize(forDial: size.dial) }

    private var weight: Font.Weight {
        if prominentNumber { return .medium }
        return pointSize >= ReadinessWidgetLook.lightNumberFrom ? .light : .regular
    }

    private var centre: ReadinessWidgetLook.Centre {
        ReadinessWidgetLook.centre(mode, readiness: readiness, previousReadiness: previousReadiness, hidden: hidden)
    }

    private var centreText: Text {
        let centre = centre
        let words: String
        switch centre {
        case .hidden: words = Words.lockedNumber
        case .readiness(let readiness, _): words = String(readiness)
        case .baselines(let counted): words = String(counted)
        case .dash: words = "–"
        }
        return Text(verbatim: words).foregroundStyle(style(ReadinessWidgetLook.ink(of: centre)))
    }

    /// The ladder's ink; the circle's hierarchical styles, which the lock screen's vibrant rendering keeps apart.
    private func style(_ ink: WidgetInk) -> AnyShapeStyle {
        if prominentNumber { return ink == .primary ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary) }
        return AnyShapeStyle(ink.colour)
    }

    /// The app's colours in full colour, the v3 tracks included. Tinted, clear and lock-screen renderings turn every
    /// colour into one ink whose opacity is all that's left: there the tracks are one faint white (as before v3), so the
    /// 7 % middle ring doesn't vanish and no track outshines the arcs.
    private var palette: OrbitGaugePalette {
        var p = OrbitGaugePalette.assets
        if renderingMode != .fullColor { p.flatTrack = Color.white.opacity(0.25) }
        return p
    }
}

#Preview("WidgetOrbitGauge", traits: .sizeThatFitsLayout) {
    VStack(spacing: 12) {
        WidgetOrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)),
                         size: .custom(dial: 104))
        WidgetOrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, strain: 6.2)), size: .custom(dial: 104))
        WidgetOrbitGauge(mode: nil, size: .custom(dial: 104), readiness: 71)
        WidgetOrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .custom(dial: 104))
        WidgetOrbitGauge(mode: .pending(previous: OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)),
                         size: .custom(dial: 104))
        WidgetOrbitGauge(mode: .pending(previous: nil), size: .custom(dial: 104))
        WidgetOrbitGauge(mode: .pending(previous: nil), size: .custom(dial: 104), previousReadiness: 64)
        WidgetOrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)),
                         size: .custom(dial: 62), prominentNumber: true)
        WidgetOrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)),
                         size: .custom(dial: ReadinessWidgetLook.rectangularDial), showsNumber: false)
    }
    .padding(16)
    .background(Brand.background)
    .environment(\.colorScheme, .dark)
}
