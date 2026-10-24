import SwiftUI

/// A row's state at its trailing edge (ui.md §2.4): pending is an outline, scored is a number, failed is a word.
/// Every state has its own glyph and its own word; the word shows in the detail and from the largest text sizes
/// on, and VoiceOver always speaks it.
struct ActivityStateMark: View {
    enum State: Equatable {
        /// R1: on this iPhone, not at RYFT yet. `lastStrain`: an edit of a scored activity keeps the platform's
        /// last strain beside the mark until the edit is confirmed (design.md §2.5 rule 4).
        case uploading(lastStrain: Double?)
        /// R2: at RYFT, heart rate may still arrive.
        case strainPending
        /// R3.
        case scored(Double)
        /// R4: retries ran out or the platform refused it; `lastStrain` as for `uploading`.
        case failed(lastStrain: Double?)
        /// R5: scored without heart rate for the time.
        case noHeartRate
        /// Sleep, a recording in progress: no mark.
        case none

        /// What the row's item says: the upload state first (it isn't at RYFT yet), with the platform's last
        /// strain beside it; then the strain.
        init(_ item: MyDayItem) {
            var last: Double? {
                if case .scored(let value) = item.strain { return value }
                return nil
            }
            switch item.upload {
            case .pending?: self = .uploading(lastStrain: last)
            case .failed?: self = .failed(lastStrain: last)
            case .confirmed?, nil:
                if item.isRecording {
                    self = .none
                    return
                }
                switch item.strain {
                case .scored(let value): self = .scored(value)
                case .pending: self = .strainPending
                case .noHeartRate: self = .noHeartRate
                case .notApplicable: self = .none
                }
            }
        }

        /// The state's word, as shown; nil without a mark.
        var word: String? {
            switch self {
            // Its own key: Today's first-import step "Uploading" reads differently in German.
            case .uploading: return String(localized: "myday.state.uploading", defaultValue: "Uploading",
                                           comment: "My Day row: saved on this iPhone, not at RYFT yet (the upload is queued).")
            case .strainPending: return String(localized: "Strain pending", comment: "My Day row: at RYFT, strain not scored yet.")
            case .scored(let value): return String(localized: "Strain \(Fmt.strain(value))")
            case .failed: return String(localized: "Not uploaded", comment: "My Day row: the upload failed; the data is still on the iPhone.")
            case .noHeartRate: return String(localized: "No heart rate", comment: "My Day row: scored, but there was no heart rate for the time.")
            case .none: return nil
            }
        }

        /// The platform's last strain shown beside an upload mark.
        var lastStrain: Double? {
            switch self {
            case .uploading(let value), .failed(let value): return value
            default: return nil
            }
        }

        /// As spoken: the word, then the last strain beside it ("Uploading, Strain 10.6").
        var spoken: String? {
            guard let word else { return nil }
            return lastStrain.map { "\(word), \(String(localized: "Strain \(Fmt.strain($0))"))" } ?? word
        }

        var isFailed: Bool {
            if case .failed = self { return true }
            return false
        }

        /// Which glyph, for the cross-fade between them (not their values).
        fileprivate var kind: Int {
            switch self {
            case .uploading: return 0
            case .strainPending: return 1
            case .scored: return 2
            case .failed: return 3
            case .noHeartRate: return 4
            case .none: return 5
            }
        }
    }

    let state: State
    /// The word under the glyph (the detail screen); otherwise it shows from `xxxLarge` on.
    var showsWord = false
    /// R4's Retry (the uploader's, A2); nil shows no button.
    var retry: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var wordVisible: Bool { showsWord || typeSize >= .xxxLarge }

    var body: some View {
        VStack(alignment: wordVisible ? .leading : .trailing, spacing: 4) {
            HStack(spacing: 8) {
                glyph
                if let last = state.lastStrain { StrainPill(strain: last) }
            }
            .transition(.opacity)
            .id(state.kind)
            if wordVisible, let word = state.word, !state.isFailed, !isScored {
                Text(word)
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state.isFailed {
                failedLine
            }
        }
        // Pending to scored: a 250 ms cross-fade, instant under Reduce Motion.
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: state)
    }

    private var isScored: Bool {
        if case .scored = state { return true }
        return false
    }

    @ViewBuilder
    private var glyph: some View {
        switch state {
        case .uploading:
            Image(systemName: "icloud.and.arrow.up")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel(Text(state.spoken ?? ""))
        case .strainPending:
            Circle()
                .strokeBorder(Theme.textTertiary, lineWidth: 1.5)
                .frame(width: 12, height: 12)
                .frame(minHeight: 16)
                .accessibilityElement()
                .accessibilityLabel(Text(state.word ?? ""))
        case .scored(let value):
            StrainPill(strain: value)
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
        case .noHeartRate:
            Image(systemName: "minus.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityLabel(Text(state.word ?? ""))
        case .none:
            EmptyView()
        }
    }

    /// "Not uploaded" (from the large sizes on, and in the detail) and Retry, 44 × 44 pt.
    @ViewBuilder
    private var failedLine: some View {
        if wordVisible, let word = state.word {
            Text(word)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let retry {
            Button(action: retry) {
                Text("Retry", comment: "My Day: send a failed upload again.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview("State marks", traits: .sizeThatFitsLayout) {
    let states: [ActivityStateMark.State] = [.uploading(lastStrain: nil), .uploading(lastStrain: 10.6), .strainPending,
                                             .scored(8.4), .failed(lastStrain: nil), .failed(lastStrain: 7.2), .noHeartRate]
    SchemePair {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                HStack {
                    Text(state.spoken ?? "").font(.ryft(.callout)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    ActivityStateMark(state: state, retry: state.isFailed ? {} : nil)
                }
            }
            Divider()
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                ActivityStateMark(state: state, showsWord: true, retry: state.isFailed ? {} : nil)
            }
        }
    }
}

#Preview("State marks · AX3", traits: .sizeThatFitsLayout) {
    let states: [ActivityStateMark.State] = [.uploading(lastStrain: 10.6), .strainPending, .scored(8.4),
                                             .failed(lastStrain: nil), .noHeartRate]
    SchemePair {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                ActivityStateMark(state: state, retry: state.isFailed ? {} : nil)
            }
        }
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}
