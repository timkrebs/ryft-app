import SwiftUI

/// Profile → Display → "Hero numbers": a two-way menu, Dots or Thin, in `SettingRow`'s type; the title and the menu are
/// read one after the other, as Birth year's are. At accessibility sizes the menu goes under the title.
struct HeroNumeralsRow: View {
    @Binding var selection: HeroNumerals
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Text("Hero numbers", comment: "Profile → Display: how the large numbers on Today, Sleep and Strain are drawn.")
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Picker(selection: $selection) {
                ForEach(HeroNumerals.allCases) { Text($0.title).tag($0) }
            } label: {
                Text("Hero numbers", comment: "Profile → Display: how the large numbers on Today, Sleep and Strain are drawn.")
            }
            .pickerStyle(.menu)
            .tint(Theme.accent)
            .accessibilityIdentifier("profile.heroNumerals")
        }
        .frame(minHeight: 44)
    }
}

#Preview("Hero numbers row", traits: .sizeThatFitsLayout) {
    DarkPreview { Card { HeroNumeralsRow(selection: .constant(.dots)) } }
}

#Preview("Hero numbers row · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { Card { HeroNumeralsRow(selection: .constant(.thin)) } }
        .environment(\.dynamicTypeSize, .accessibility3)
}
