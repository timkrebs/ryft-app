import SwiftUI

/// The live workout's offline line, the one both layouts show while there's no network (PR 6 B §4.7, §4.9; Nocturne gate
/// §6 G2): "Offline — every set is saved on this phone and syncs later." with `wifi.slash`, `caption` `textSecondary`, at
/// least 28 high, wrapping, leading. One grey line, not a banner: nothing is lost and there's nothing to do. The caller
/// shows it only offline and gives its horizontal inset (Focused: the table's `columns.padding`; List: none, it sits in the
/// list's 16 pt sides). One element, `session.offlineLine`.
struct SessionOfflineLine: View {
    nonisolated static let minHeight: CGFloat = 28

    var body: some View {
        Label("Offline — every set is saved on this phone and syncs later.", systemImage: "wifi.slash")
            .font(.ryft(.caption))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: Self.minHeight, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("session.offlineLine")
    }
}

#Preview("Session offline line", traits: .sizeThatFitsLayout) {
    DarkPreview { SessionOfflineLine() }
}

#Preview("Session offline line · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { SessionOfflineLine() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
