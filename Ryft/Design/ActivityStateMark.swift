// A row's state in its value slot (ui.md §2.4; Nocturne, docs/work/2026-11-16-nocturne/design-pr6-b-train.md §9.1 "Row state
// marks", S6): scored is the number, the other states are a word (and, uploading, a small glyph), never a colour alone.
import SwiftUI

/// The mark's numbers (B §9.1).
enum ActivityStateMarkSpec {
    /// The uploading glyph (`arrow.up.circle`): 12 pt, 4 before its word.
    nonisolated static let glyphSize: CGFloat = 12, glyphGap: CGFloat = 4
    /// The number → the word under it.
    nonisolated static let wordGap: CGFloat = 2
    /// The word and the glyph: ink at 55 % (the board's row value text, about 5.6:1 on `surface`, B §1.6).
    nonisolated static let wordOpacity = 0.55
}

/// What a row shows at its trailing edge, in its value's place (B §9.1). Every state has its own shape and its own word:
///
/// | State | Drawn |
/// |---|---|
/// | scored | the strain, 20 Light in ink (`StrainPill`), over "Strain" (as the pending row's "Strain pending": a bare number didn't say what it was) |
/// | uploading | `arrow.up.circle` 12 and "Uploading" in `caption` at 55 % (no spinner); the platform's last strain above it while an edit uploads |
/// | strain pending | "–" in `textTertiary` over "Strain pending" |
/// | not uploaded | "Not uploaded", and a 44 pt-high text button "Retry" when the uploader offers one; the last strain above it |
/// | no heart rate | "No heart rate" |
/// | none (sleep, a recording) | nothing |
///
/// Trailing-aligned beside the row's text; leading-aligned under it from AX1 (`alignment`). The row speaks the state
/// (`State.spoken`); the views here are for sighted users.
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

        /// The number drawn: the strain, the last strain beside an upload, or the pending state's dash; nil draws none.
        var number: Number? {
            switch self {
            case .scored(let value): return .strain(value)
            case .uploading(let last), .failed(let last): return last.map(Number.strain)
            case .strainPending: return .dash
            case .noHeartRate, .none: return nil
            }
        }

        /// The word drawn under the number: what the number is for a scored row ("Strain"), the state's word for the others,
        /// none for none.
        var shownWord: String? {
            switch self {
            case .scored:
                return String(localized: "myday.state.strain", defaultValue: "Strain",
                              comment: "My Day row: the word under a scored activity's strain (\"10.6\" over \"Strain\").")
            case .none: return nil
            default: return word
            }
        }

        /// Which state, for the cross-fade between them (not their values).
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

    /// The number a state draws.
    enum Number: Equatable {
        case strain(Double)
        /// "–" in `textTertiary`: at RYFT, not scored yet.
        case dash
    }

    let state: State
    /// R4's Retry (the uploader's, A2); nil shows no button.
    var retry: (() -> Void)?
    /// Trailing beside the row's text; leading under it (AX1+).
    var alignment: HorizontalAlignment = .trailing
    /// The number of the state; off where the row draws its own value above the mark (a night that uploads).
    var showsNumber = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: alignment, spacing: ActivityStateMarkSpec.wordGap) {
            if showsNumber, let number = state.number {
                switch number {
                case .strain(let value): StrainPill(strain: value)
                case .dash: StrainPill(strain: nil)
                }
            }
            if let word = state.shownWord {
                HStack(alignment: .firstTextBaseline, spacing: ActivityStateMarkSpec.glyphGap) {
                    if case .uploading = state {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: ActivityStateMarkSpec.glyphSize, weight: .regular))
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: word)
                        .font(.ryft(.caption))
                        .multilineTextAlignment(alignment == .leading ? .leading : .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.textPrimary.opacity(ActivityStateMarkSpec.wordOpacity))
            }
            if state.isFailed, let retry {
                Button(action: retry) {
                    Text("Retry", comment: "My Day: send a failed upload again.")
                }
                .ryftLink()
            }
        }
        .transition(.opacity)
        .id(state.kind)
        // One state to another (pending to scored): a 250 ms cross-fade, instant under Reduce Motion.
        .animation(Theme.Motion.respecting(reduceMotion, Theme.Motion.quick), value: state)
    }
}

// MARK: - previews (dark only; verbatim words beside them: the states own the strings)

private struct ActivityStateMarkPreviewList: View {
    static let states: [ActivityStateMark.State] = [.scored(10.6), .uploading(lastStrain: nil), .uploading(lastStrain: 10.6),
                                                    .strainPending, .failed(lastStrain: nil), .failed(lastStrain: 7.2),
                                                    .noHeartRate]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(Self.states.enumerated()), id: \.offset) { _, state in
                HStack(alignment: .top) {
                    Text(verbatim: state.spoken ?? "").font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    ActivityStateMark(state: state, retry: state.isFailed ? {} : nil)
                }
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: ActivityListRowSpec.radius, style: .continuous))
    }
}

#Preview("State marks", traits: .sizeThatFitsLayout) {
    DarkPreview { ActivityStateMarkPreviewList() }
}

#Preview("State marks · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { ActivityStateMarkPreviewList() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
