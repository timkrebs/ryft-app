import SwiftUI

/// Renders its content twice — dark above light — for component previews.
struct SchemePair<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                content()
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .background(Theme.background)
                    .environment(\.colorScheme, scheme)
            }
        }
        .frame(width: 390)
    }
}

extension View {
    /// Injects the environment objects every screen expects, backed by mock data.
    @MainActor
    func previewEnvironment(_ state: AppState? = nil, scheme: ColorScheme = .dark) -> some View {
        environmentObject(Settings.shared)
            .environmentObject(SyncService.shared)
            .environmentObject(state ?? AppState.preview())
            .preferredColorScheme(scheme)
            .tint(Theme.accent)
    }
}
