// The toggle (Nocturne, docs/work/2026-11-16-nocturne/design.md §P5-1.4): a light track with a dark knob when on, an outline
// with a grey knob when off. Hue never carries the state: the fill and the knob's side do.
import SwiftUI

/// `Toggle(isOn:) { label }.toggleStyle(.ryft)`: the label leading, a 51 × 31 track trailing, the whole row (at least 44
/// high) the target.
///
/// - On: a `textPrimary` track, a 25 pt `background` knob at the trailing end (17.35:1).
/// - Off: a 1.5 pt `textTertiary` outline on the ground and a 25 pt `textTertiary` knob at the leading end (4.54:1; the
///   system's filled grey off track would be 2.5:1).
/// - The knob is inset 3 and slides in 250 ms; under Reduce Motion it moves without an animation.
/// - Disabled dims the row to 35 %.
///
/// It stays a `Toggle` for VoiceOver, Voice Control and Switch Control: the row's accessibility is a system switch's
/// (the label, the on/off value, the toggle trait), not hand-made traits. The label keeps the caller's font and colour.
struct RyftToggleStyle: ToggleStyle {
    static let trackSize = CGSize(width: 51, height: 31)
    static let knobDiameter: CGFloat = 25
    static let knobInset: CGFloat = 3
    /// The off track's outline: `Theme.Metrics.controlOutline`.
    static let offOutlineWidth = Theme.Metrics.controlOutline
    static let disabledOpacity = 0.35
    /// The row's minimum height: the tap target (`Theme.Metrics.minHitTarget`).
    static let minRowHeight = Theme.Metrics.minHitTarget
    /// Between the label and the track (`Theme.Metrics.itemSpacing`).
    static let labelSpacing = Theme.Metrics.itemSpacing

    func makeBody(configuration: Configuration) -> some View {
        RyftToggleRow(configuration: configuration)
    }
}

extension ToggleStyle where Self == RyftToggleStyle {
    /// The app's toggle (design.md §P5-1.4).
    static var ryft: RyftToggleStyle { RyftToggleStyle() }
}

private struct RyftToggleRow: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: RyftToggleStyle.labelSpacing) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)
                RyftToggleTrack(isOn: configuration.isOn)
                    .animation(Theme.Motion.respecting(reduceMotion), value: configuration.isOn)
            }
            .frame(minHeight: RyftToggleStyle.minRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RyftToggleButtonStyle())
        .opacity(isEnabled ? 1 : RyftToggleStyle.disabledOpacity)
        // A system switch stands in for the row in the accessibility tree; `.switch` so it never draws (or resolves) this
        // style again.
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
        }
    }
}

/// The 51 × 31 track and its knob, on or off (internal for the render tests).
struct RyftToggleTrack: View {
    let isOn: Bool

    var body: some View {
        let size = RyftToggleStyle.trackSize
        let travel = size.width - 2 * RyftToggleStyle.knobInset - RyftToggleStyle.knobDiameter
        ZStack(alignment: .leading) {
            Capsule()
                .fill(isOn ? Theme.textPrimary : Color.clear)
            Capsule()
                .strokeBorder(Theme.textTertiary, lineWidth: RyftToggleStyle.offOutlineWidth)
                .opacity(isOn ? 0 : 1)
            Circle()
                .fill(isOn ? Theme.background : Theme.textTertiary)
                .frame(width: RyftToggleStyle.knobDiameter, height: RyftToggleStyle.knobDiameter)
                .offset(x: RyftToggleStyle.knobInset + (isOn ? travel : 0))
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }
}

/// No pressed look: the knob's move is the feedback.
private struct RyftToggleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

// MARK: previews (dark only; verbatim labels: the screens own the strings)

private struct RyftTogglePreviewBoard: View {
    @State private var reminder = true
    @State private var alarm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $reminder) { Text(verbatim: "Bedtime reminder").font(.ryft(.body)).foregroundStyle(Theme.textPrimary) }
            Toggle(isOn: $alarm) { Text(verbatim: "Wake alarm").font(.ryft(.body)).foregroundStyle(Theme.textPrimary) }
            Toggle(isOn: .constant(true)) { Text(verbatim: "Disabled, on").font(.ryft(.body)).foregroundStyle(Theme.textPrimary) }
                .disabled(true)
            Toggle(isOn: .constant(false)) { Text(verbatim: "Disabled, off").font(.ryft(.body)).foregroundStyle(Theme.textPrimary) }
                .disabled(true)
            // In a row on `surface`, as a grouped list's toggle row.
            VStack(alignment: .leading, spacing: 0) {
                Toggle(isOn: $reminder) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "Save workouts to Apple Health").font(.ryft(.body)).foregroundStyle(Theme.textPrimary)
                        Text(verbatim: "Sessions you log in Train").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.neutralTileRadius, style: .continuous))
        }
        .toggleStyle(.ryft)
    }
}

#Preview("RyftToggleStyle", traits: .sizeThatFitsLayout) {
    DarkPreview { RyftTogglePreviewBoard() }
}

#Preview("RyftToggleStyle · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { RyftTogglePreviewBoard() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
