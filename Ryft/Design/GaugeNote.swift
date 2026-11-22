// The line under a gauge and the way to its fix (ui.md §1.2 D, §1.7; design.md §7 rev. 2 §5): Today's calibration and
// blocked-baseline notes. Moved out of `MetricGauge.swift` when that gauge was deleted (Nocturne gate G2); unchanged.
import SwiftUI

/// A plain line under a gauge (ui.md §1.2 D, §1.7): a static symbol and a caption in secondary
/// ink, centred, wrapping. Not a card and not an action: it says why the gauge reads as it does.
struct GaugeNote: View {
    let text: String
    let systemImage: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                // Wrapped over several lines, the symbol leads the first one and the paragraph is centred as a whole,
                // instead of sitting at the edge beside short centred lines. A figure space doesn't break.
                (Text(Image(systemName: systemImage)) + Text(verbatim: "\u{2007}") + Text(text))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(text))
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                    Text(text)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.ryft(.caption))
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

/// The way to a fix under a `GaugeNote` (design.md §7 rev. 2 §5): "How to set up Garmin Connect ›", the app's link
/// (`.ryftLink()`: `callout` in `InlineLink.ink`, the words underlined, not the chevron; Nocturne gate accent map, class X),
/// centred and wrapping, at least 44 pt tall, its own VoiceOver button. It opens a sheet; nothing on it moves.
struct GaugeNoteLink: View {
    let title: String
    let action: () -> Void

    /// Above and below the title, scaled with the text: at large sizes the title outgrows the 44 pt minimum, which
    /// then no longer leaves room between the note and the link. At the default size the minimum still decides.
    @ScaledMetric(relativeTo: .callout) private var inset: CGFloat = 6

    var body: some View {
        Button(action: action) {
            // One text, so the chevron follows the last word when the title wraps (at AX3). `.ryftLink()` underlines
            // every run; the space and the chevron opt out, so the line is under the words only.
            (Text(title) + Text(verbatim: "\u{00A0}").underline(false)
                + Text(Image(systemName: "chevron.right")).font(.ryft(.caption)).underline(false))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, inset)
        }
        // The link's look and its 44 pt minimum; no press motion, the label dims.
        .ryftLink()
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .accessibilityLabel(Text(title))
    }
}

// MARK: - previews (dark only)

#Preview("Gauge notes", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 20) {
            GaugeNote(text: String(localized: "Recalculating your baselines"), systemImage: "arrow.triangle.2.circlepath")
            // Without a readiness, the baselines counting the nights that do count.
            VStack(spacing: 8) {
                OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 2, signal: .heartRateNights)), size: .large,
                           caption: OrbitGauge.Caption(title: String(localized: "Baselines")), animatesFill: false)
                GaugeNote(text: String(localized: "Baselines need heart-rate variability and resting heart rate from nights with your watch."),
                          systemImage: "info.circle")
            }
        }
    }
}

/// F3: only resting heart rate fills (no HRV arrives), no readiness yet: the gauge counts its nights and says so.
#Preview("Gauge note · one signal", traits: .sizeThatFitsLayout) {
    let progress = CalibrationProgress(nights: 3, signals: [.restingHR],
                                       absent: CalibrationBlocker(signals: [.hrv], source: .unknown, link: nil))
    DarkPreview {
        VStack(spacing: 8) {
            OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3, signal: .restingHR)), size: .large,
                       caption: OrbitGauge.Caption(title: String(localized: "Baselines")), animatesFill: false)
            GaugeNote(text: progress.text, systemImage: "info.circle")
        }
    }
}

#Preview("Gauge notes · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            GaugeNote(text: String(localized: "Recalculating your baselines"), systemImage: "arrow.triangle.2.circlepath")
            GaugeNote(text: String(localized: "Baselines need heart-rate variability and resting heart rate from nights with your watch."),
                      systemImage: "info.circle")
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

/// N1 under the gauge (design.md §7 rev. 2): Garmin chosen, no HRV in the window; the link opens Garmin Connect's card.
@MainActor
private func blockedNotePreview() -> some View {
    let blocker = CalibrationBlocker.resolve([.hrv], trackers: [MockData.tracker("garmin")], devicesSetup: true)
    return VStack(spacing: 8) {
        GaugeNote(text: blocker.text, systemImage: "info.circle")
        if let link = blocker.link { GaugeNoteLink(title: link.title) {} }
    }
}

#Preview("Gauge note · link", traits: .sizeThatFitsLayout) {
    DarkPreview { blockedNotePreview() }
}

#Preview("Gauge note · link · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { blockedNotePreview() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
