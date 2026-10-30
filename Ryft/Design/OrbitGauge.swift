import SwiftUI

/// The RYFT mark as the readiness gauge: the centre ring is Readiness (its number inside), the inner orbit
/// carries Recovery (counter-clockwise from the top) and Sleep (clockwise), the outer orbit carries Strain
/// (clockwise, 21 = a whole turn). Arc length is the score, the dot at its head is where you are today. A score
/// that is missing is a hollow dot at the start, never an arc and never a zero. Nothing rotates on its own.
///
/// Calibrating draws the outer orbit as seven segments that fill night by night (a count, "3 / 7", where the readiness
/// number goes); pending draws the previous day's gauge dimmed and breathing. Both are in design.md, "PR 2".
///
/// The app's wrapper around the shared `OrbitGaugeDrawing` (ADR 0010): the number in the app's font, the caption
/// and band line under it, VoiceOver, the `Theme.Motion` value animation and Reduce Motion. Geometry, mapping and
/// colours: `OrbitGaugeGeometry`, `OrbitGaugePalette`, docs/work/2026-10-29-orbit-gauge/design.md.
struct OrbitGauge: View {
    typealias Size = OrbitGaugeSize

    /// What Today puts under the gauge: the caption ("OVERALL READINESS") and, under a readiness, the band word and
    /// the change against the week (the line `MetricGauge` drew there). Shown at `.large` only.
    struct Caption: Equatable {
        var title: String
        /// "vs 7 d", row A only.
        var delta: MetricDelta?
        /// Off where a calibration note takes the band word's line (S2, N1). Speech follows what is shown.
        var showsBand = true
    }

    let mode: OrbitGaugeMode
    var size: Size = .large
    var caption: Caption?
    /// Read after the value, e.g. a `GaugeNote` shown under the gauge ("Recalculating your baselines").
    var accessibilityNote: String?
    /// Today uses `today.readinessGauge`.
    var identifier: String = "orbitGauge"
    /// Calibrating: the segments fill one after another (60 ms each) when the gauge appears and when `nights` grows.
    /// Off, or under Reduce Motion, they are all at their count from the first frame. Snapshots and previews pass
    /// `false`: nothing in them depends on time.
    var animatesFill = true
    /// Pending: the dimmed marks breathe (1.4 s) while the night is scored. Pass `false` once it takes longer than
    /// usual (nothing implies progress). Always off under Reduce Motion.
    var breathes = true

    /// Below this dial the gauge is the mark only (VoiceOver still has the value); the widget uses the same.
    static let minDialForNumber = OrbitGaugeGeometry.minDialForNumber

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Calibrating: the segments filled so far while they step in; nil before the first step.
    @State private var shownNights: Int?

    private var values: OrbitGaugeValues? { mode.scoredValues }
    private var shownCaption: Caption? { size == .large ? caption : nil }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                drawing
                    // Reduce Motion: no arc moves; a new value cross-fades (250 ms) instead.
                    .id(reduceMotion ? AnyHashable(mode) : AnyHashable(0))
                    .transition(.opacity)
            }
            .frame(width: size.frame, height: size.frame)
            // The arcs and the dots ride the same animation; the number rolls with it.
            .animation(reduceMotion ? Theme.Motion.quick : Theme.Motion.slow, value: mode)
            if let shownCaption { captionLines(shownCaption) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityValue(Text(spokenValue))
        .accessibilityIdentifier(identifier)
        .task(id: FillKey(counted: mode.calibratingValue?.counted, steps: animatesFill && !reduceMotion)) {
            await stepFill()
        }
    }

    // MARK: calibrating fill

    /// The mode the drawing gets: while calibrating, with the nights stepped in so far.
    private var displayedMode: OrbitGaugeMode {
        guard case .calibrating(var calibration) = mode, animatesFill, !reduceMotion else { return mode }
        calibration.nights = min(shownNights ?? 0, calibration.counted)
        return .calibrating(calibration)
    }

    /// What restarts the fill: the count, and whether the segments step at all (Reduce Motion turned off while the
    /// app is open must run it again, or the count would show over empty segments).
    private struct FillKey: Hashable {
        var counted: Int?
        var steps: Bool
    }

    /// The next displayed count: `target` at once when nothing steps or the count went down; otherwise one night
    /// further from `current` (nil: none shown yet, so 1 after the first tick), never past `target`.
    static func nextShown(current: Int?, target: Int, steps: Bool) -> Int {
        guard steps, (current ?? 0) <= target else { return target }
        return min((current ?? 0) + 1, target)
    }

    /// One segment per 60 ms up to the count; otherwise the state follows the count at once.
    private func stepFill() async {
        guard let target = mode.calibratingValue?.counted else { return }
        let steps = animatesFill && !reduceMotion
        guard steps, (shownNights ?? 0) <= target else { shownNights = target; return }
        var current = shownNights ?? 0
        shownNights = current
        while current < target {
            try? await Task.sleep(for: .milliseconds(60))
            if Task.isCancelled { return }
            current = Self.nextShown(current: current, target: target, steps: true)
            withAnimation(.easeOut(duration: 0.06)) { shownNights = current }
        }
    }

    // MARK: drawing

    private var drawing: some View {
        OrbitGaugeDrawing(mode: displayedMode, size: size, palette: .assets, marks: { marks in
            // Pending: the dimmed marks breathe. One phase (no motion) otherwise.
            marks.phaseAnimator(mode.isPending && breathes && !reduceMotion ? [1.0, 0.75] : [1.0]) { marks, opacity in
                marks.compositingGroup().opacity(opacity)
            } animation: { _ in .easeInOut(duration: 1.4) }
        }, centre: { centre })
    }

    @ViewBuilder
    private var centre: some View {
        if size.dial >= Self.minDialForNumber {
            switch mode {
            case .scored(let values, _):
                Text(values.readiness.map { String($0) } ?? Fmt.placeholder)
                    .font(.ryftNumber(size: size.dial * 0.19))
                    .monospacedDigit()
                    .foregroundStyle(values.readiness == nil ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(values.readiness ?? 0)))
            case .pending(let previous):
                // Yesterday's number in the tertiary ink, or the dash: never a number that pretends to be today's.
                Text(previous?.readiness.map { String($0) } ?? Fmt.placeholder)
                    .font(.ryftNumber(size: size.dial * 0.19))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            case .calibrating(let calibration):
                calibrationCount(calibration)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            case .assembling:
                EmptyView()
            }
        }
    }

    /// "3 / 7" at the readiness number's size and style, the "/ 7" smaller and tertiary; from a 100 pt dial up.
    /// Below it ("small") only the count: the seven segments around it already say "of 7", and the slot there is
    /// 23 pt wide. The count is the one the segments draw (`counted`, never past the requirement), not the stepping.
    private func calibrationCount(_ calibration: OrbitGaugeCalibration) -> Text {
        let pointSize = size.dial * 0.19
        let count = Text(verbatim: String(calibration.counted))
            .font(.ryftNumber(size: pointSize)).monospacedDigit().foregroundStyle(Theme.textPrimary)
        guard size.dial >= 100 else { return count }
        return count + Text(verbatim: " / \(calibration.required)")
            .font(.ryftNumber(size: pointSize * 0.55)).monospacedDigit().foregroundStyle(Theme.textTertiary)
    }

    // MARK: caption

    /// The caption as a section label (it scales with Dynamic Type; the gauge doesn't), then the band word and the
    /// change in one line when it fits; at large text sizes (German at AX3) the band word over the change, wrapping:
    /// never cut off.
    private func captionLines(_ caption: Caption) -> some View {
        VStack(spacing: 4) {
            Text(caption.title)
                .ryftLabelStyle()
                .multilineTextAlignment(.center)
                .neverBreaksAWord(caption.title)
            let band = bandLabel(caption)
            if band != nil || caption.delta != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        bandText(band)
                        if band != nil, caption.delta != nil {
                            Text(verbatim: "·").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                        }
                        DeltaLabel(spec: .readiness, delta: caption.delta, reference: Self.deltaReference)
                    }
                    .lineLimit(1)
                    VStack(spacing: 2) {
                        bandText(band)
                        DeltaLabel(spec: .readiness, delta: caption.delta, reference: Self.deltaReference)
                    }
                    .multilineTextAlignment(.center)
                }
            }
        }
    }

    @ViewBuilder
    private func bandText(_ band: String?) -> some View {
        if let band {
            Text(band)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .neverBreaksAWord(band)
        }
    }

    private func bandLabel(_ caption: Caption) -> String? {
        guard caption.showsBand, let readiness = values?.readiness else { return nil }
        return MetricSpec.scoreBand(Double(readiness)).label
    }

    private static var deltaReference: String { String(localized: "vs 7 d") }

    // MARK: VoiceOver

    /// "71, High. Recovery 71 percent, Sleep 88 percent, Strain 9.6 of 21." plus the note. A missing score is
    /// named as not scored ("Sleep, not scored"), never skipped.
    private var spokenLabel: String {
        if case .calibrating = mode { return String(localized: "Baselines") }
        return caption?.title ?? String(localized: "Overall readiness")
    }

    private var spokenValue: String {
        let spoken: String
        switch mode {
        case .scored(let v, _):
            spoken = Self.spokenValue(v, showsBand: caption?.showsBand ?? true, delta: caption?.delta)
        case .calibrating(let calibration):
            spoken = Self.spokenValue(calibration)
        case .pending(let previous):
            spoken = Self.spokenPending(previous)
        case .assembling:
            // PR 3 gives it its own sentence.
            spoken = String(localized: "Not scored yet")
        }
        return accessibilityNote.map { "\(spoken). \($0)" } ?? spoken
    }

    /// "3 of 7 nights." and which nights count where that isn't all of them.
    /// The two signals that fill alone (F3) leave out "Readiness appears…": the note under the gauge says what
    /// recovery uses meanwhile.
    static func spokenValue(_ c: OrbitGaugeCalibration) -> String {
        let counted = c.counted, required = c.required
        switch c.signal {
        case .restingHR:
            return String(localized: "\(counted) of \(required) nights with resting heart rate.")
        case .hrv:
            return String(localized: "\(counted) of \(required) nights with HRV.")
        case .heartRateNights:
            return String(localized: "\(counted) of \(required) nights with heart-rate data. Readiness appears once the baselines are complete.")
        case .anyNight:
            return String(localized: "\(counted) of \(required) nights. Readiness appears once the baselines are complete.")
        }
    }

    /// "Not scored yet. Last scored: 71. Recovery 71 percent, ..." or just "Not scored yet" without a previous day.
    /// The day itself and "Scoring your night…" arrive as the gauge's `accessibilityNote`.
    static func spokenPending(_ previous: OrbitGaugeValues?) -> String {
        let notScored = String(localized: "Not scored yet")
        guard let previous, !previous.isEmpty else { return notScored }
        let last = String(localized: "Last scored: \(spokenValue(previous, showsBand: false))")
        return "\(notScored). \(last)"
    }

    /// The readiness part ("71, High, Up 4 vs 7 d"), then the three scores.
    static func spokenValue(_ v: OrbitGaugeValues, showsBand: Bool = true, delta: MetricDelta? = nil) -> String {
        if v.isEmpty { return String(localized: "No data") }
        let noData = { (title: String) in String(localized: "\(title), not scored") }
        var scores: [String] = []
        scores.append(v.recoveryFraction.map { String(localized: "Recovery \(Self.percent($0)) percent") }
                      ?? noData(String(localized: "Recovery")))
        scores.append(v.sleepFraction.map { String(localized: "Sleep \(Self.percent($0)) percent") }
                      ?? noData(String(localized: "Sleep")))
        scores.append(v.strain.map { String(localized: "Strain \(Self.strainText($0)) of 21") }
                      ?? noData(String(localized: "Strain")))
        let readiness: String
        if let r = v.readiness {
            var parts = [String(r)]
            if showsBand { parts.append(MetricSpec.scoreBand(Double(r)).label) }
            if let delta { parts.append(DeltaLabel.spoken(delta, spec: .readiness, reference: Self.deltaReference)) }
            readiness = parts.joined(separator: ", ")
        } else {
            readiness = String(localized: "Overall readiness, no data")
        }
        return "\(readiness). \(scores.joined(separator: ", "))"
    }

    private static func percent(_ fraction: Double) -> String {
        Int((fraction * 100).rounded()).formatted()
    }

    private static func strainText(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)))
    }
}

private extension View {
    /// Wraps between words but never inside one: as many lines as the text has words, and a word wider than the
    /// line shrinks the text (down to half) instead of breaking ("AUSGANGSWERT" / "E" at AX3 in German).
    func neverBreaksAWord(_ text: String) -> some View {
        lineLimit(max(text.split(whereSeparator: \.isWhitespace).count, 1))
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: previews (synthetic values only)

extension OrbitGaugeValues {
    /// 71 / 71 % / 88 % / 9.6, the values the previews, the screenshots and the tests share.
    static let previewScored = OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: 9.6)
}

private struct OrbitCaption: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
    }
}

#Preview("OrbitGauge · sizes", traits: .sizeThatFitsLayout) {
    SchemePair {
        HStack(alignment: .center, spacing: 12) {
            OrbitGauge(mode: .scored(.previewScored), size: .large)
            VStack(spacing: 8) {
                OrbitGauge(mode: .scored(.previewScored), size: .medium)
                OrbitGauge(mode: .scored(.previewScored), size: .small)
            }
        }
    }
}

#Preview("OrbitGauge · missing and edges", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                VStack { OrbitGauge(mode: .scored(OrbitGaugeValues()), size: .medium); OrbitCaption(text: "all missing") }
                VStack {
                    // A watch without HRV: Recovery from what the platform scored, no sleep yet.
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, strain: 6.2)), size: .medium)
                    OrbitCaption(text: "sleep missing")
                }
                VStack {
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, sleep: 0.81)), size: .medium)
                    OrbitCaption(text: "strain missing")
                }
            }
            HStack(spacing: 8) {
                VStack {
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 0, recovery: 0, sleep: 0, strain: 0)), size: .medium)
                    OrbitCaption(text: "0")
                }
                VStack {
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)), size: .medium)
                    OrbitCaption(text: "100")
                }
                VStack {
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 28, recovery: 0.24, sleep: 0.41, strain: 17.8)), size: .medium)
                    OrbitCaption(text: "low")
                }
            }
        }
    }
}

#Preview("OrbitGauge · bands and stubs", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 82, recovery: 0.8, sleep: 0.9, strain: 12)), size: .small)
                OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 50, recovery: 0.5, sleep: 0.7, strain: 12)), size: .small)
                OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 20, recovery: 0.2, sleep: 0.3, strain: 12)), size: .small)
            }
            HStack(spacing: 8) {
                OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .small, animatesFill: false)
                OrbitGauge(mode: .assembling, size: .small)
                OrbitGauge(mode: .pending(previous: .previewScored), size: .small, breathes: false)
            }
        }
    }
}

/// Dark over light like `SchemePair`, wide enough for three large gauges side by side.
private struct WidePair<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                content()
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Theme.background)
                    .environment(\.colorScheme, scheme)
            }
        }
        .frame(width: 600)
    }
}

#Preview("OrbitGauge · calibrating 0 / 3 / 7", traits: .sizeThatFitsLayout) {
    // Static (`animatesFill: false`): the previews and the shots never depend on time.
    WidePair {
        HStack(alignment: .top, spacing: 12) {
            ForEach([0, 3, 7], id: \.self) { nights in
                VStack(spacing: 8) {
                    OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: nights)), size: .large, animatesFill: false)
                    OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: nights)), size: .medium, animatesFill: false)
                    OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: nights)), size: .small, animatesFill: false)
                }
            }
        }
    }
}

#Preview("OrbitGauge · pending, with and without previous", traits: .sizeThatFitsLayout) {
    WidePair {
        HStack(alignment: .top, spacing: 12) {
            ForEach([true, false], id: \.self) { hasPrevious in
                VStack(spacing: 8) {
                    let mode = OrbitGaugeMode.pending(previous: hasPrevious ? .previewScored : nil)
                    OrbitGauge(mode: mode, size: .large, breathes: false)
                    OrbitGauge(mode: mode, size: .medium, breathes: false)
                    OrbitGauge(mode: mode, size: .small, breathes: false)
                }
            }
        }
    }
}

#Preview("OrbitGauge · calibrating and pending · AX3", traits: .sizeThatFitsLayout) {
    // The gauge keeps its size at accessibility sizes; only text around it scales. Spoken sentences below.
    SchemePair {
        VStack(spacing: 8) {
            OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .large, animatesFill: false)
            Text(OrbitGauge.spokenValue(OrbitGaugeCalibration(nights: 3)))
                .font(.ryft(.caption)).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
            OrbitGauge(mode: .pending(previous: .previewScored), size: .medium, breathes: false)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

extension OrbitGauge.Caption {
    /// Today's caption over the preview values: "OVERALL READINESS", then "High · ▲ +4 vs 7 d".
    static var preview: OrbitGauge.Caption {
        OrbitGauge.Caption(title: String(localized: "Overall readiness"), delta: MetricDelta(current: 71, reference: 67))
    }
}

#Preview("OrbitGauge · Today caption", traits: .sizeThatFitsLayout) {
    SchemePair {
        HStack(alignment: .top, spacing: 16) {
            OrbitGauge(mode: .scored(.previewScored), size: .large, caption: .preview)
            // S2 / N1: a calibration note takes the band word's line.
            OrbitGauge(mode: .scored(.previewScored), size: .large,
                       caption: OrbitGauge.Caption(title: String(localized: "Overall readiness"), showsBand: false))
        }
    }
}

#Preview("OrbitGauge · AX3", traits: .sizeThatFitsLayout) {
    // The gauge keeps its size; the caption under it scales.
    SchemePair {
        VStack(spacing: 8) {
            OrbitGauge(mode: .scored(.previewScored), size: .large, caption: .preview)
            OrbitGauge(mode: .scored(.previewScored), size: .small)
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("OrbitGauge · de · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 8) {
            OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)), size: .large,
                       caption: .preview)
            Text(OrbitGauge.spokenValue(OrbitGaugeValues(readiness: 71, recovery: 0.71, strain: 9.6)))
                .font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
        }
    }
    .environment(\.locale, Locale(identifier: "de"))
    .environment(\.dynamicTypeSize, .accessibility3)
}
