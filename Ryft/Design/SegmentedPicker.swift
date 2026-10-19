import SwiftUI

/// Pill-style segmented control ("Day · Week · Month") as on the board.
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    withAnimation(Theme.Motion.quick) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.ryft(.callout))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Theme.surfaceRaised)
                                    .matchedGeometryEffect(id: "selection", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surface, in: Capsule())
    }
}

#Preview("SegmentedPicker", traits: .sizeThatFitsLayout) {
    struct Demo: View {
        @State private var mode = "Day"
        var body: some View {
            SegmentedPicker(selection: $mode, options: ["Day", "Week", "Month"], title: { $0 })
        }
    }
    return SchemePair { Demo() }
}
