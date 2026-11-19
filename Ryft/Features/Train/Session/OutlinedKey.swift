import SwiftUI

/// The live workout's outlined key (PR 6 B §4.5, §4.6): the rest sheet's −15 s / +15 s, the keypad's steps and the plate
/// calculator's. No fill: a 1 pt ink edge at the secondary pill's 20 % (10 % while off) and the row's radius, 14. The caller
/// sets the size and the label's ink; all of the key takes the tap.
struct OutlinedKey: ViewModifier {
    var isEnabled = true

    /// The edge: `PillButton`'s outline, so a key and a secondary pill read as one family. Off: half of it.
    static let edge = PillButton.outlineOpacity, disabledEdge = 0.10
    static let radius = LiveSessionSpec.rowRadius

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                    .strokeBorder(Theme.textPrimary.opacity(isEnabled ? Self.edge : Self.disabledEdge), lineWidth: Theme.Metrics.hairline)
            }
            .contentShape(Rectangle())
    }
}

extension View {
    /// `OutlinedKey`: the live workout's outlined key.
    func outlinedKey(isEnabled: Bool = true) -> some View {
        modifier(OutlinedKey(isEnabled: isEnabled))
    }
}
