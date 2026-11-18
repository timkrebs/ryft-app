import SwiftUI

/// Drag to reorder (the list is in edit mode).
struct ReorderSheet: View {
    var controller: SessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(controller.exercises) { ex in
                    HStack {
                        Text(ex.name).font(.ryft(.body))
                        Spacer()
                        if ex.supersetGroup != nil {
                            Image(systemName: "link").foregroundStyle(Theme.accent)
                                .accessibilityLabel(Text("In a superset"))
                        }
                    }
                    .frame(minHeight: 44)
                    .listRowBackground(Theme.surface)
                }
                .onMove { controller.move(from: $0, to: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
