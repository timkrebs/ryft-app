import SwiftUI

/// "Sport" (Nocturne PR 6 B §10.1): pushed inside Add activity. The pushed header, a search field, then Recent (hidden while
/// searching) and every sport alphabetically in the app's language, as rows in grouped cards: a 36 pt outline disc with the
/// sport's glyph, the name, and an ink checkmark on the current one. Search matches a word's start in the name and a few
/// synonyms ("jog", "bike"); nothing found offers "Use Other". The back swipe stays. Inside the sheet the header starts 26
/// under its edge, 14 under the grabber, as Add activity's own header does (`SheetHeaderSpec.topInset`).
struct SportPicker: View {
    @Binding var selection: Sport
    /// What may be chosen (a recorded activity: its family only).
    var sports: [Sport] = Sport.allCases
    /// Newest first (`ActivityPreferences.recentSports`).
    var recents: [Sport] = []

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PushedHeader(Text("Sport"), identifierPrefix: "sportPicker")
                    .padding(.top, SheetHeaderSpec.topInset)
                SearchField(text: $query, prompt: Text("Search sports", comment: "Sport picker: the search field's prompt."),
                            identifier: "sportPicker.search")
                    .padding(.top, ActivitiesLayout.pickerHeaderGap)
                VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
                    if query.isEmpty, !recentSports.isEmpty {
                        GroupedCard(Text("Recent", comment: "Sport picker: the sports used last.")) {
                            ForEach(recentSports) { row($0, idPrefix: "sportPicker.recent") }
                        }
                        GroupedCard(Text("All sports", comment: "Sport picker: every sport, alphabetically.")) {
                            ForEach(results) { row($0, idPrefix: "sportPicker.sport") }
                        }
                    } else if !results.isEmpty {
                        GroupedCard {
                            ForEach(results) { row($0, idPrefix: "sportPicker.sport") }
                        }
                    } else {
                        noMatch
                    }
                }
                .padding(.top, ActivitiesLayout.pickerSearchGap)
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.bottom, ActivitiesLayout.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .keepsBackSwipe()
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

    /// A select row: the disc, the name, the checkmark on the current sport (and the selected trait).
    private func row(_ sport: Sport, idPrefix: String) -> some View {
        GroupedRow.select(Text(verbatim: sport.name), icon: sport.symbol, isSelected: sport == selection) {
            selection = sport
            dismiss()
        }
        .accessibilityIdentifier("\(idPrefix).\(sport.rawValue)")
    }

    /// "No sport matches “curling”" and Use Other.
    private var noMatch: some View {
        VStack(alignment: .leading, spacing: ActivitiesLayout.blockSpacing) {
            Text("No sport matches “\(query)”", comment: "Sport picker: the search found nothing; the search text.")
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if sports.contains(.other) {
                PillButton(Text("Use Other", comment: "Sport picker: choose the sport 'Other' when nothing matched."),
                           style: .secondary) {
                    selection = .other
                    dismiss()
                }
                .accessibilityIdentifier("sportPicker.useOther")
            }
        }
    }
}

// MARK: - previews (dark only)

#Preview("Sport picker") {
    struct Host: View {
        @State var sport = Sport.cycling
        var body: some View {
            NavigationStack { SportPicker(selection: $sport, recents: [.cycling, .running, .yoga]) }
        }
    }
    return Host().previewEnvironment()
}

#Preview("Sport picker · AX3") {
    struct Host: View {
        @State var sport = Sport.running
        var body: some View {
            NavigationStack { SportPicker(selection: $sport, recents: [.running, .strength]) }
        }
    }
    return Host().previewEnvironment().environment(\.dynamicTypeSize, .accessibility3)
}
