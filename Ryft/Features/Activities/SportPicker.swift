import SwiftUI

/// "Sport" (ui.md §3.2): pushed from Add activity. Recent sports first (hidden while searching), then every sport
/// alphabetically in the app's language. Search matches a word's start in the name and a few synonyms ("jog",
/// "bike", "laufen", "rad"); nothing found offers "Use Other".
struct SportPicker: View {
    @Binding var selection: Sport
    /// What may be chosen (a recorded activity: its family only).
    var sports: [Sport] = Sport.allCases
    /// Newest first (`ActivityPreferences.recentSports`).
    var recents: [Sport] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""

    var body: some View {
        List {
            if query.isEmpty, !recentSports.isEmpty {
                Section {
                    ForEach(recentSports) { row($0, idPrefix: "sportPicker.recent") }
                } header: {
                    Text("Recent", comment: "Sport picker: the sports used last.").ryftLabelStyle()
                }
            }
            Section {
                ForEach(results) { row($0, idPrefix: "sportPicker.sport") }
            } header: {
                if query.isEmpty, !recentSports.isEmpty {
                    Text("All sports", comment: "Sport picker: every sport, alphabetically.").ryftLabelStyle()
                }
            }
            if results.isEmpty {
                noMatch
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("Search sports", comment: "Sport picker: the search field's prompt."))
        .navigationTitle(Text("Sport"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("sportPicker")
    }

    private var recentSports: [Sport] { recents.filter(sports.contains) }

    /// Alphabetical in the app's language; filtered by the query.
    private var results: [Sport] {
        let sorted = sports.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !query.isEmpty else { return sorted }
        return sorted.filter { Self.matches($0, query) }
    }

    /// A word of the name, or a synonym, starts with the query (case- and accent-insensitive).
    static func matches(_ sport: Sport, _ query: String) -> Bool {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        guard !q.isEmpty else { return true }
        let words = fold(sport.name).split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        return words.contains { $0.hasPrefix(q) } || fold(sport.name).hasPrefix(q)
            || (synonyms[sport] ?? []).contains { $0.hasPrefix(q) }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// What people type for a sport, in English and German (ui.md §3.2).
    static let synonyms: [Sport: [String]] = [
        .running: ["run", "jog", "laufen", "joggen", "lauf"],
        .trailRunning: ["run", "trail", "jog", "laufen", "lauf"],
        .indoorRunning: ["run", "treadmill", "jog", "laufen", "laufband", "lauf"],
        .walking: ["walk", "gehen", "spazieren"],
        .hiking: ["hike", "wandern"],
        .cycling: ["bike", "cycle", "ride", "rad", "fahrrad", "radfahren"],
        .mountainBiking: ["bike", "mtb", "rad", "fahrrad"],
        .gravel: ["bike", "rad", "fahrrad"],
        .indoorCycling: ["bike", "spin", "rad", "ergometer"],
        .skiing: ["ski"],
        .skiTouring: ["ski", "skitour"],
        .swimming: ["swim", "schwimm"],
        .rowing: ["row", "ruder"],
        .strength: ["gym", "weights", "kraft"],
        .football: ["soccer", "fussball"],
    ]

    private func row(_ sport: Sport, idPrefix: String) -> some View {
        Button {
            selection = sport
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: sport.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                Text(verbatim: sport.name)
                    .font(.ryft(.body))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                if sport == selection {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 56 pt rows (ui.md §3.2): the list's own vertical insets would add 30 pt.
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Theme.surface)
        .accessibilityAddTraits(sport == selection ? .isSelected : [])
        .accessibilityIdentifier("\(idPrefix).\(sport.rawValue)")
    }

    /// "No sport matches “kite”" and Use Other.
    private var noMatch: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No sport matches “\(query)”", comment: "Sport picker: the search found nothing; the search text.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
            if sports.contains(.other) {
                Button {
                    selection = .other
                    dismiss()
                } label: {
                    Text("Use Other", comment: "Sport picker: choose the sport 'Other' when nothing matched.")
                        .font(.ryft(.callout))
                        .foregroundStyle(Theme.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sportPicker.useOther")
            }
        }
        .listRowBackground(Color.clear)
    }
}

#Preview("Sport picker") {
    struct Host: View {
        @State var sport = Sport.cycling
        var body: some View {
            NavigationStack { SportPicker(selection: $sport, recents: [.cycling, .running, .yoga]) }
        }
    }
    return Host().preferredColorScheme(.dark)
}

#Preview("Sport picker · light · de") {
    struct Host: View {
        @State var sport = Sport.running
        var body: some View {
            NavigationStack { SportPicker(selection: $sport, recents: [.running, .strength]) }
        }
    }
    return Host().preferredColorScheme(.light).environment(\.locale, Locale(identifier: "de"))
}
