import SwiftUI

/// Profile → About → Licences: the open-source packages and the typeface in the app.
struct LicensesView: View {
    struct Entry: Identifiable {
        let name: String
        let license: String
        let holder: String
        let url: String
        var id: String { name }
    }

    static let entries: [Entry] = [
        Entry(name: "supabase-swift", license: "MIT", holder: "Supabase",
              url: "https://github.com/supabase/supabase-swift"),
        Entry(name: "swift-crypto", license: "Apache 2.0", holder: "Apple Inc.",
              url: "https://github.com/apple/swift-crypto"),
        Entry(name: "swift-asn1", license: "Apache 2.0", holder: "Apple Inc.",
              url: "https://github.com/apple/swift-asn1"),
        Entry(name: "swift-http-types", license: "Apache 2.0", holder: "Apple Inc.",
              url: "https://github.com/apple/swift-http-types"),
        Entry(name: "swift-clocks", license: "MIT", holder: "Point-Free",
              url: "https://github.com/pointfreeco/swift-clocks"),
        Entry(name: "swift-concurrency-extras", license: "MIT", holder: "Point-Free",
              url: "https://github.com/pointfreeco/swift-concurrency-extras"),
        Entry(name: "xctest-dynamic-overlay", license: "MIT", holder: "Point-Free",
              url: "https://github.com/pointfreeco/swift-issue-reporting"),
        Entry(name: "Satoshi typeface", license: "ITF Free Font License", holder: "Indian Type Foundry (Fontshare)",
              url: "https://www.fontshare.com/fonts/satoshi"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(Self.entries) { e in
                    Link(destination: URL(string: e.url)!) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(verbatim: e.name)
                                    .font(.ryft(.body))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(verbatim: "\(e.license) · \(e.holder)")
                                    .font(.ryft(.caption))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textTertiary)
                                .accessibilityHidden(true)
                        }
                        .padding(14)
                        .frame(minHeight: 56)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text("Opens the licence in Safari"))
                }
            }
            .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Licences")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

#Preview("Licences · dark") {
    NavigationStack { LicensesView() }.preferredColorScheme(.dark)
}

#Preview("Licences · light") {
    NavigationStack { LicensesView() }.preferredColorScheme(.light)
}
