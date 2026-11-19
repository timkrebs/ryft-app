import SwiftUI

/// Drag to reorder (the list is in edit mode; PR 6 B §4.8). `SheetHeader("Reorder")` with a compact "Done" and no close circle:
/// each move is made at once, so a close beside Done would say the same twice (the drag down still closes). Rows on `surface`, at least 56 high, the name 15 pt ink and a
/// superset's `link` in grey (named for VoiceOver). The handles are the system's ("Reorder Bench press").
struct ReorderSheet: View {
    var controller: SessionController
    @Environment(\.dismiss) private var dismiss

    /// A row: at least 56 high (B §1.3, a row holding a control).
    static let rowHeight: CGFloat = 56
    /// Header → the first row.
    static let topGap: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(Text("Reorder")) {
                PillButton(Text("Done"), size: .compact) { dismiss() }
                    .accessibilityIdentifier("reorder.done")
            }
            .closeHidden()
            .padding(.horizontal, SheetHeaderSpec.sidePadding)
            .padding(.top, SheetHeaderSpec.topInset)
            List {
                ForEach(controller.exercises) { ex in
                    HStack(spacing: Theme.Metrics.itemSpacing) {
                        Text(ex.name)
                            .font(.ryft(.callout))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        if ex.supersetGroup != nil {
                            Image(systemName: "link")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Theme.textSecondary)
                                .accessibilityLabel(Text("In a superset"))
                        }
                    }
                    .frame(minHeight: Self.rowHeight)
                    // The row is its content: 56, not 56 plus the list's own insets above and below.
                    .listRowInsets(EdgeInsets(top: 0, leading: GroupedListSpec.rowInset, bottom: 0,
                                              trailing: GroupedListSpec.rowInset))
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.separator)
                }
                .onMove { controller.move(from: $0, to: $1) }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
            .environment(\.defaultMinListRowHeight, Self.rowHeight)
            // 12 under the header, as the other sheets' bodies (the list's own top margin is about 35).
            .contentMargins(.top, Self.topGap, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .tint(Theme.textPrimary)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }
}

// MARK: - previews (dark only)

/// The plan's Upper A: five exercises, the last two a superset.
#Preview("Reorder") {
    let c = SessionSheetsPreview.listDraft()
    return Color.clear
        .sheet(isPresented: .constant(true)) { ReorderSheet(controller: c) }
        .previewEnvironment()
}

#Preview("Reorder · AX3") {
    ReorderSheet(controller: SessionSheetsPreview.listDraft())
        .previewEnvironment()
        .dynamicTypeSize(.accessibility3)
}
