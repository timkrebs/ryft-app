import SwiftUI

/// The RYFT mark as the readiness gauge: the inner tick ring is Readiness (lit up to the value, the Volt dot at it,
/// its number inside), the middle orbit carries Recovery (counter-clockwise from the top) and Sleep (clockwise), the
/// outer orbit carries Strain (clockwise, 21 = a whole turn). Arc length is the score, the dot at its head is where you
/// are today. A score that is missing is a hollow dot at the start, never an arc and never a zero. Nothing rotates on
/// its own.
///
/// Calibrating draws the outer orbit as seven segments that fill night by night (a count, "3 / 7", where the readiness
/// number goes); pending draws the previous day's gauge dimmed and breathing.
///
/// The app's wrapper around the shared `OrbitGaugeDrawing` (ADR 0010): the numeral (the dot grid, or Light digits), the
/// caption and band line under it, VoiceOver, the `Theme.Motion` value animation and Reduce Motion. Geometry, mapping
/// and colours: `OrbitGaugeGeometry`, `OrbitGaugePalette`; gauge v3 is docs/work/2026-11-16-nocturne/design.md §P3.
struct OrbitGauge: View {
    typealias Size = OrbitGaugeSize

    /// What Today puts under the gauge: the caption ("Overall readiness") and, under a readiness, the band word and
    /// the change against the week. Shown from the `.large` dial up.
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
    /// Draws `caption` under the gauge. Nocturne's Today passes `false` and draws the band and the change in its own
    /// label row (design.md §P4-1, row 7); the caption still makes the spoken sentence (band, change).
    var showsCaption = true
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
    /// The numeral: the dot grid where it fits (`.dots`), or Light digits always (`.light`, Today's thin-digit switch,
    /// brief §1). Additive (plan.md L7).
    var numeral: DotNumeral.Style = .dots

    /// Below this dial the gauge is the mark only (VoiceOver still has the value); the widget uses the same.
    static let minDialForNumber = OrbitGaugeGeometry.minDialForNumber

    @Environment(\.dynamicTypeSize) private var typeSize
    /// The Light numeral grows with Dynamic Type as `DotNumeral`'s Light digits do (relative to the large title), never
    /// below its size at the default text size; the slot's minimum scale keeps it inside the ring.
    @ScaledMetric(relativeTo: .largeTitle) private var numeralScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    /// Previews only: `accessibilityReduceMotion` cannot be set in an environment.
    @Environment(\.orbitForcesReducedMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    /// Calibrating: the segments filled so far while they step in; nil before the first step.
    @State private var shownNights: Int?
    /// Latched at the first appearance (`entrance` of the initialiser): this instance plays the entrance, once. Later
    /// values of the parameter are ignored, so Today consuming its flag right after the first frame cannot cut it short.
    @State private var staged: Bool
    /// Latched with `staged`: `Entrance.assembleOverTracks`, the tracks were already on screen (Today's placeholder).
    @State private var overTracks: Bool
    /// When the entrance started (its first appearance); the clock is the time since, read by a `TimelineView`, so no
    /// transaction animates anything but what the view draws from it (a layout change around the gauge is never
    /// dragged along for 850 ms).
    @State private var start: Date?
    /// The entrance has run to its end (or never ran): the calibrating fill may start.
    @State private var entranceDone: Bool
    /// Low Power Mode is read once at the start; it is treated like Reduce Motion (plan.md decision 7).
    @State private var lowPower: Bool
    /// Previews and tests: draw the entrance frozen at this many seconds; nothing animates.
    private let frozenAt: Double?

    /// `entrance: .assemble` plays the launch entrance once for this view instance, from its first frame, into the
    /// real mode (design.md section 10). `frozenAt` is for previews and tests only.
    init(mode: OrbitGaugeMode, size: Size = .large, caption: Caption? = nil, showsCaption: Bool = true,
         accessibilityNote: String? = nil, identifier: String = "orbitGauge", animatesFill: Bool = true,
         breathes: Bool = true, numeral: DotNumeral.Style = .dots, entrance: Entrance = .none, frozenAt: Double? = nil) {
        self.mode = mode
        self.size = size
        self.caption = caption
        self.showsCaption = showsCaption
        self.accessibilityNote = accessibilityNote
        self.identifier = identifier
        self.animatesFill = animatesFill
        self.breathes = breathes
        self.numeral = numeral
        let plays = entrance.plays
        self.frozenAt = plays ? frozenAt : nil
        _staged = State(initialValue: plays)
        _overTracks = State(initialValue: entrance == .assembleOverTracks)
        _entranceDone = State(initialValue: !plays)
        _lowPower = State(initialValue: plays && frozenAt == nil && ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    /// Reduce Motion or Low Power Mode: the entrance is a cross-fade.
    private var reducesEntrance: Bool { reduceMotion || lowPower }

    private var values: OrbitGaugeValues? { mode.scoredValues }
    /// `.large` and the larger custom sizes (the 260 board); never under a medium or small gauge, nor with
    /// `showsCaption` off.
    private var shownCaption: Caption? { showsCaption && size.dial >= Size.large.dial ? caption : nil }

    var body: some View {
        Group {
            if staged {
                TimelineView(.animation(paused: frozenAt != nil || entranceDone)) { context in
                    let seconds = clock(at: context.date)
                    column(elapsed: seconds)
                        .onChange(of: entranceIsOver(at: seconds)) { _, over in
                            if over { entranceDone = true }
                        }
                }
            } else {
                column(elapsed: OrbitEntranceFrame.end)
            }
        }
        .onAppear(perform: startEntrance)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenLabel))
        .accessibilityValue(Text(spokenValue))
        .accessibilityIdentifier(identifier)
        .task(id: FillKey(counted: mode.calibratingValue?.counted, steps: animatesFill && !reduceMotion,
                          waiting: !entranceDone)) {
            await stepFill()
        }
    }

    /// The gauge and its caption. `elapsed` is the entrance's clock (only read when `staged`).
    private func column(elapsed: Double) -> some View {
        VStack(spacing: 8) {
            ZStack {
                shownDrawing(elapsed: elapsed)
                    // Reduce Motion: no arc moves; a new value cross-fades (250 ms) instead.
                    .id(reduceMotion ? AnyHashable(mode) : AnyHashable(0))
                    .transition(.opacity)
            }
            .frame(width: size.frame, height: size.frame)
            // The arcs and the dots ride the same animation; the number rolls with it.
            .animation(reduceMotion ? Theme.Motion.quick : Theme.Motion.slow, value: mode)
            if let shownCaption {
                // Over the placeholder its caption title was already there: only what comes with the score fades in.
                captionLines(shownCaption, titleOpacity: overTracks ? 1 : captionOpacity(elapsed),
                             detailOpacity: captionOpacity(elapsed))
            }
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
        /// The entrance is still running: the segments start when it ends.
        var waiting: Bool
    }

    /// The next displayed count: `target` at once when nothing steps or the count went down; otherwise one night
    /// further from `current` (nil: none shown yet, so 1 after the first tick), never past `target`.
    static func nextShown(current: Int?, target: Int, steps: Bool) -> Int {
        guard steps, (current ?? 0) <= target else { return target }
        return min((current ?? 0) + 1, target)
    }

    /// One segment per 60 ms up to the count; otherwise the state follows the count at once.
    private func stepFill() async {
        guard entranceDone, let target = mode.calibratingValue?.counted else { return }
        let steps = animatesFill && !reduceMotion
        // Every decision is `nextShown`'s: a step of one night is animated after 60 ms, anything else (not stepping,
        // a lower count, a target of 0) is taken at once.
        while shownNights != target {
            let next = Self.nextShown(current: shownNights, target: target, steps: steps)
            guard steps, next == (shownNights ?? 0) + 1 else { shownNights = next; return }
            try? await Task.sleep(for: .milliseconds(60))
            if Task.isCancelled { return }
            withAnimation(.easeOut(duration: 0.06)) { shownNights = next }
        }
    }

    // MARK: entrance

    /// The static drawing, or the entrance stage whose last frame is that drawing. Fixed for the life of the view.
    @ViewBuilder
    private func shownDrawing(elapsed: Double) -> some View {
        if staged {
            OrbitEntranceStage(elapsed: elapsed, reduced: reducesEntrance, overTracks: overTracks, done: entranceDone,
                               mode: displayedMode, size: size, palette: .assets,
                               settled: drawing(marksOpacity: marksFade(elapsed)), centre: centre)
        } else {
            drawing()
        }
    }

    /// Seconds since the entrance started: the frozen moment of previews and tests, 0 before the first appearance.
    private func clock(at date: Date) -> Double {
        if let frozenAt { return frozenAt }
        return start.map { max(date.timeIntervalSince($0), 0) } ?? 0
    }

    private var entranceDuration: Double {
        reducesEntrance ? OrbitEntranceFrame.fadeDuration : OrbitEntranceFrame.end
    }

    private func entranceIsOver(at seconds: Double) -> Bool {
        frozenAt == nil && start != nil && seconds >= entranceDuration
    }

    /// The caption arrives with the score (the glide), never with the tracks: the title, band word and change in the full
    /// entrance; over a placeholder's tracks the title is already there, so only the band word and change. Full once done,
    /// and in the static path, so the last frame is the static render.
    private func captionOpacity(_ elapsed: Double) -> Double {
        guard staged, !entranceDone else { return 1 }
        if reducesEntrance { return OrbitEntranceFrame.eased(elapsed, 0, OrbitEntranceFrame.fadeDuration) }
        return OrbitEntranceFrame(seconds: elapsed).glide
    }

    /// Reduce Motion or Low Power Mode over tracks already on screen: the marks and the number fade in, the tracks
    /// stay. 1 otherwise, and once done, so the last frame is the static render.
    private func marksFade(_ elapsed: Double) -> Double {
        guard staged, overTracks, reducesEntrance, !entranceDone else { return 1 }
        return OrbitEntranceFrame.eased(elapsed, 0, OrbitEntranceFrame.fadeDuration)
    }

    /// On the first appearance only: the clock starts. The curves are in `OrbitEntranceFrame`.
    private func startEntrance() {
        guard staged, start == nil, frozenAt == nil else { return }
        start = Date()
    }

    // MARK: drawing

    /// `marksOpacity`: the marks and the number, not the tracks (`marksFade`); 1 in the static drawing.
    private func drawing(marksOpacity: Double = 1) -> some View {
        OrbitGaugeDrawing(mode: displayedMode, size: size, palette: .assets, marks: { marks in
            // Pending: the dimmed marks breathe. One phase (no motion) otherwise.
            marks.phaseAnimator(mode.isPending && breathes && !reduceMotion ? [1.0, 0.75] : [1.0]) { marks, opacity in
                marks.compositingGroup().opacity(opacity)
            } animation: { _ in .easeInOut(duration: 1.4) }
                .opacity(marksOpacity)
        }, centre: { centre.opacity(marksOpacity) })
    }

    @ViewBuilder
    private var centre: some View {
        if size.dial >= Self.minDialForNumber {
            switch mode {
            case .scored(let values, _):
                numeralView(values.readiness.map { String($0) }, pending: false)
            case .pending(let previous):
                // Yesterday's number dimmed, or the unlit grid: never a number that pretends to be today's.
                numeralView(previous?.readiness.map { String($0) }, pending: true)
            case .calibrating(let calibration):
                calibrationCount(calibration)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    /// How the centre draws a numeral (design.md §P3-1, "Centre").
    enum CentreLook: Equatable { case dots, light }

    /// The gauge's size decides, not the value: the dot grid only on a gauge whose slot holds two digits
    /// (`DotNumeral.size(of: "00")`, 74 pt, from S 205.2: the 260 board, not `.large`), so "7" and "84" on one gauge
    /// look alike. Below that every value is Light, single digits included. On such a gauge, `.dots` below AX1 (the
    /// numeral's own fallback), for characters the grid has and a value that fits ("100", 115 pt, never does: Light).
    /// `text` nil is the unlit grid of "00", by the same rule.
    static func centreLook(_ text: String?, side: CGFloat, style: DotNumeral.Style, typeSize: DynamicTypeSize) -> CentreLook {
        let slot = OrbitGaugeGeometry.metrics(forSide: side).centreSlotWidth
        guard let twoDigits = DotNumeral.size(of: "00", glyphGap: DotNumeral.glyphGapToday), twoDigits.width <= slot,
              DotNumeral.rendersDots(text, style: style, typeSize: typeSize),
              let grid = DotNumeral.size(of: text, glyphGap: DotNumeral.glyphGapToday) else { return .light }
        return grid.width <= slot ? .dots : .light
    }

    /// The Light numeral's size: 0.2 x S, 52 pt at 260 (the board's "Light 52"), times `scale` (Dynamic Type, never
    /// under 1: about 78 pt at AX3 on the board, as `DotNumeral`'s own fallback). The gauge keeps its size; the
    /// numeral's frame and minimum scale (0.5) keep the digits inside the ring. `ryftNumber`'s weight rule makes them
    /// Light from 20 pt and Regular below.
    static func lightNumeralSize(side: CGFloat, scale: CGFloat = 1) -> CGFloat { side * 0.2 * max(scale, 1) }

    /// The previous day's numeral while pending: 48 %, `textTertiary` on `background`.
    static let pendingNumeralOpacity = 0.48

    /// The readiness as the dot grid or in Light; nil is the unlit grid ("pending is an outline") or the Light dash. A new
    /// number cross-fades in the grid (`Theme.Motion.quick`, its own animation) and rolls in Light with the arcs (the
    /// column's `slow`, no animation of its own); neither moves under Reduce Motion.
    private func numeralView(_ text: String?, pending: Bool) -> some View {
        Group {
            switch Self.centreLook(text, side: size.frame, style: numeral, typeSize: typeSize) {
            case .dots:
                DotNumeral(text, glyphGap: DotNumeral.glyphGapToday, accessibilityLabel: Text(verbatim: text ?? ""))
                    .opacity(pending && text != nil ? Self.pendingNumeralOpacity : 1)
                    .id(text)
                    .transition(reduceMotion ? .identity : .opacity)
                    .animation(reduceMotion ? nil : Theme.Motion.quick, value: text)
            case .light:
                Text(verbatim: text ?? Fmt.placeholder)
                    .font(.ryftNumber(size: Self.lightNumeralSize(side: size.frame, scale: numeralScale)))
                    .monospacedDigit()
                    .foregroundStyle(text == nil || pending ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(reduceMotion ? .identity : .numericText(value: Double(text.flatMap { Int($0) } ?? 0)))
            }
        }
    }

    /// "3 / 7" at the Light numeral's size, the "/ 7" smaller and tertiary; from a 100 pt dial up. Below it ("small")
    /// only the count: the seven segments around it already say "of 7". The count is the one the segments draw
    /// (`counted`, never past the requirement), not the stepping.
    private func calibrationCount(_ calibration: OrbitGaugeCalibration) -> Text {
        let pointSize = Self.lightNumeralSize(side: size.frame, scale: numeralScale)
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
    private func captionLines(_ caption: Caption, titleOpacity: Double = 1, detailOpacity: Double = 1) -> some View {
        VStack(spacing: 4) {
            Text(caption.title)
                .ryftLabelStyle()
                .multilineTextAlignment(.center)
                .neverBreaksAWord(caption.title)
                .opacity(titleOpacity)
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
                .opacity(detailOpacity)
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

    private static var deltaReference: String { String(localized: "vs 7\u{00A0}d") }

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
            return String(localized: "\(counted) of \(required)\u{00A0}nights with resting heart rate.")
        case .hrv:
            return String(localized: "\(counted) of \(required)\u{00A0}nights with HRV.")
        case .heartRateNights:
            return String(localized: "\(counted) of \(required)\u{00A0}nights with heart-rate data. Readiness appears once the baselines are complete.")
        case .anyNight:
            return String(localized: "\(counted) of \(required)\u{00A0}nights. Readiness appears once the baselines are complete.")
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
        scores.append(v.recoveryFraction.map { String(localized: "Recovery \(Self.percent($0))\u{00A0}percent") }
                      ?? noData(String(localized: "Recovery")))
        scores.append(v.sleepFraction.map { String(localized: "Sleep \(Self.percent($0))\u{00A0}percent") }
                      ?? noData(String(localized: "Sleep")))
        scores.append(v.strain.map { spokenStrain($0, band: v.strainBand) } ?? noData(String(localized: "Strain")))
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

    /// "Strain 9.6 of 21", and with a usable band "Strain 9.6 of 21, today's recommended range 8 to 13" (the band as drawn: clamped to
    /// 0 to 21; an empty one is not mentioned). Unreachable until the platform serves the band.
    static func spokenStrain(_ strain: Double, band: ClosedRange<Double>?) -> String {
        guard let band = OrbitGaugeGeometry.clampedBand(band) else {
            return String(localized: "Strain \(strainText(strain)) of 21")
        }
        // Above the band the sentence says so: the arc's colour is never the only carrier.
        if OrbitGaugeGeometry.strainPastBandDegrees(strain: strain, band: band) != nil {
            return String(localized: "Strain \(strainText(strain)) of 21, above today's recommended range \(bandText(band.lowerBound)) to \(bandText(band.upperBound))")
        }
        return String(localized: "Strain \(strainText(strain)) of 21, today's recommended range \(bandText(band.lowerBound)) to \(bandText(band.upperBound))")
    }

    private static func bandText(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)))
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

    /// The Today board's values (design.md §P3-1): readiness 84, recovery 82 %, sleep 94 % (7:48), strain 12.4 of 21.
    static let previewBoard = OrbitGaugeValues(readiness: 84, recovery: 0.82, sleep: 0.94, strain: 12.4)

    /// The synthetic band the previews and shots use: 8 to 13 on the 0-21 scale.
    static let previewBand: ClosedRange<Double> = 8...13

    /// 71 / 71 % / 88 % with the given strain and the synthetic band.
    static func previewBanded(strain: Double?) -> OrbitGaugeValues {
        OrbitGaugeValues(readiness: 71, recovery: 0.71, sleep: 0.88, strain: strain, strainBand: previewBand)
    }
}

extension OrbitGauge.Size {
    /// The Today board's gauge: S = 260 (a 248 dial).
    static let previewBoard = OrbitGauge.Size.custom(dial: 248)
}

extension OrbitGauge.Caption {
    /// Today's caption over the preview values: "OVERALL READINESS", then "High · ▲ +4 vs 7 d".
    static var preview: OrbitGauge.Caption {
        OrbitGauge.Caption(title: String(localized: "Overall readiness"), delta: MetricDelta(current: 71, reference: 67))
    }

    /// The same over the board's 84: "High · ▲ +8 vs 7 d".
    static var previewBoard: OrbitGauge.Caption {
        OrbitGauge.Caption(title: String(localized: "Overall readiness"), delta: MetricDelta(current: 84, reference: 76))
    }
}

#if DEBUG
/// The gauge's preview groups, one view so the previews, `DebugComponentCatalog` ("Nocturne · gauge") and
/// `OrbitGaugeShotsTests` show the same thing. Dark only (the app has one appearance). Static: no fill steps, no
/// breathing, nothing that depends on time.
struct OrbitGaugePreviewBoard: View {
    enum Part: CaseIterable {
        /// The 260 board with its caption; the app's three sizes; the widget's dials (home tile, circular, rectangular).
        case sizes
        /// Every state of design.md §P3-2 at `.large`.
        case states
        /// Calibrating 0 / 3 / 7 and pending with and without a previous day.
        case calibratingAndPending
        /// The centre rule: the dot grid where it fits, Light where it does not or when asked.
        case numeral
    }

    var parts: [Part] = Part.allCases

    private let columns = [GridItem(.adaptive(minimum: OrbitGauge.Size.large.frame), spacing: 6, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(parts, id: \.self) { part in
                switch part {
                case .sizes: sizes
                case .states: states
                case .calibratingAndPending: calibratingAndPending
                case .numeral: numeral
                }
            }
        }
    }

    private var sizes: some View {
        VStack(spacing: 12) {
            OrbitGauge(mode: .scored(.previewBoard), size: .previewBoard, caption: .previewBoard)
            HStack(alignment: .center, spacing: 12) {
                OrbitGauge(mode: .scored(.previewBoard), size: .large)
                OrbitGauge(mode: .scored(.previewBoard), size: .medium)
            }
            // The widget's dials: its home tile, then (with `.small`) its circular and rectangular complications.
            OrbitGauge(mode: .scored(.previewBoard), size: .custom(dial: 143))
            HStack(alignment: .center, spacing: 12) {
                OrbitGauge(mode: .scored(.previewBoard), size: .small)
                OrbitGauge(mode: .scored(.previewBoard), size: .custom(dial: 60))
                OrbitGauge(mode: .scored(.previewBoard), size: .custom(dial: 44))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var states: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            labelled("sleep missing", .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, strain: 6.2)))
            labelled("no readiness", .scored(OrbitGaugeValues(recovery: 0.82, sleep: 0.94, strain: 12.4)))
            labelled("zeros", .scored(OrbitGaugeValues(readiness: 0, recovery: 0, sleep: 0, strain: 0)))
            labelled("100 / 21", .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)))
            labelled("out of range", .scored(OrbitGaugeValues(readiness: 120, recovery: 1.4, sleep: -0.2, strain: 25)))
            labelled("band, below", .scored(.previewBanded(strain: 4)))
            labelled("band, inside", .scored(.previewBanded(strain: 9.6)))
            labelled("band, past", .scored(.previewBanded(strain: 16.5)))
            labelled("no data", .scored(.empty))
        }
    }

    private var calibratingAndPending: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach([0, 3, 7], id: \.self) { nights in
                    labelled("calibrating \(nights)", .calibrating(OrbitGaugeCalibration(nights: nights)))
                }
                labelled("pending, previous", .pending(previous: .previewBoard))
                labelled("pending, none", .pending(previous: nil))
            }
            HStack(spacing: 12) {
                OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .medium, animatesFill: false)
                OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .small, animatesFill: false)
                OrbitGauge(mode: .pending(previous: .previewBoard), size: .small, breathes: false)
            }
        }
    }

    private var numeral: some View {
        VStack(spacing: 12) {
            // "84" fits the 260 board's slot in dots; at `.large` it is Light.
            OrbitGauge(mode: .scored(.previewBoard), size: .previewBoard)
            OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)), size: .previewBoard)
            OrbitGauge(mode: .scored(.previewBoard), size: .previewBoard, numeral: .light)
            OrbitGauge(mode: .pending(previous: .previewBoard), size: .previewBoard, breathes: false)
            OrbitGauge(mode: .pending(previous: nil), size: .previewBoard, breathes: false)
            OrbitGauge(mode: .scored(.previewBoard), size: .large)
        }
        .frame(maxWidth: .infinity)
    }

    private func labelled(_ label: String, _ mode: OrbitGaugeMode) -> some View {
        VStack(spacing: 4) {
            OrbitGauge(mode: mode, size: .large, animatesFill: false, breathes: false)
            Text(verbatim: label)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

#Preview("OrbitGauge", traits: .sizeThatFitsLayout) {
    DarkPreview { OrbitGaugePreviewBoard(parts: [.sizes]) }
}

#Preview("OrbitGauge · states", traits: .sizeThatFitsLayout) {
    DarkPreview { OrbitGaugePreviewBoard(parts: [.states]) }
}

#Preview("OrbitGauge · calibrating and pending", traits: .sizeThatFitsLayout) {
    DarkPreview { OrbitGaugePreviewBoard(parts: [.calibratingAndPending]) }
}

#Preview("OrbitGauge · numeral", traits: .sizeThatFitsLayout) {
    DarkPreview { OrbitGaugePreviewBoard(parts: [.numeral]) }
}

#Preview("OrbitGauge · caption hidden", traits: .sizeThatFitsLayout) {
    // Nocturne's Today: the 260 gauge without its caption (the label row under it is the screen's); the sentence keeps
    // the band and the change.
    DarkPreview {
        OrbitGauge(mode: .scored(.previewBoard), size: .previewBoard, caption: .previewBoard, showsCaption: false)
            .border(Theme.separator)
    }
}

#Preview("OrbitGauge · AX3", traits: .sizeThatFitsLayout) {
    // The gauge keeps its size; the caption under it scales and the numeral falls back to Light.
    DarkPreview { OrbitGaugePreviewBoard() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
