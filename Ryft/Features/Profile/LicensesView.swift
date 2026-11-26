import SwiftUI

/// Profile → About → Licences in Nocturne (PR 6 C §4.9): the open-source packages and the typeface in the app, one group of
/// link-out rows (the name, "MIT · Supabase" under it, ↗) that open the licence in Safari. The legal wording, names,
/// licences and holders are unchanged; no group title.
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
        Entry(name: "Satoshi typeface (Light, Regular, Medium, Bold)", license: "ITF Free Font License", holder: "Indian Type Foundry (Fontshare)",
              url: "https://www.fontshare.com/fonts/satoshi"),
        Entry(name: "Google Sans Medium", license: "SIL Open Font License 1.1", holder: "The Google Sans Project Authors",
              url: "https://github.com/googlefonts/googlesans"),
    ]

    var body: some View {
        SubpageScaffold(Text("Licences")) {
            GroupedCard {
                ForEach(Self.entries) { entry in
                    if let url = URL(string: entry.url) {
                        GroupedRow.linkOut(Text(verbatim: entry.name), detail: Text(verbatim: "\(entry.license) · \(entry.holder)"),
                                           hint: Text("Opens the licence in Safari"), url: url)
                    }
                }
            }
        }
    }
}

// MARK: - previews (dark only)

#Preview("Licences") {
    NavigationStack { LicensesView() }.preferredColorScheme(.dark)
}

#Preview("Licences · AX3") {
    NavigationStack { LicensesView() }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}
