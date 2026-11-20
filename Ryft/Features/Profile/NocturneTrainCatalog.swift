#if DEBUG
import SwiftUI

/// The catalog's "Nocturne · train" section (docs/work/2026-11-16-nocturne/design-pr6-b-train.md §2, T6B.0): what PR 6 B adds
/// to the foundation for Train, My Day and the Journal. The pushed header of B's pages, the search field of its sheets, and
/// the activity row's two new options (the filled disc of the chosen row, a caption under the value). Its own file, so the
/// other sections merge beside it. Verbatim words: the screens own the strings.
struct NocturneTrainCatalog: View {
    /// The catalog's parts, in order.
    enum Part: String, CaseIterable {
        case pushedHeader = "pushed-header", searchField = "search-field", rows, discs
    }

    var parts: [Part] = Part.allCases

    @State private var query = ""
    @State private var typed = "row"

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(parts, id: \.self) { part($0) }
        }
        .environment(\.locale, Locale(identifier: "en_US"))
    }

    @ViewBuilder private func part(_ part: Part) -> some View {
        switch part {
        case .pushedHeader: pushedHeaders
        case .searchField: searchFields
        case .rows: rows
        case .discs: discs
        }
    }

    private var pushedHeaders: some View {
        VStack(alignment: .leading, spacing: 18) {
            caption("pushed header · title only · a subtitle · a trailing circle · a long title that wraps")
            PushedHeader(Text(verbatim: "Plans"))
            PushedHeader(Text(verbatim: "Upper A"), subtitle: Text(verbatim: "Fri, Nov 13 · 55 min · 17 sets"),
                         spokenSubtitle: Text(verbatim: "Friday 13 November, 55 minutes, 17 sets"))
            PushedHeader(Text(verbatim: "My Day"), subtitle: Text(verbatim: "Today · Wed, Nov 18")) {
                CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add")) {}
            }
            PushedHeader(Text(verbatim: "Upper/Lower 4× (copy) for the winter block"),
                         subtitle: Text(verbatim: "Hypertrophy · 4 days/week · repeating")) {
                CircleButton(systemImage: "ellipsis", accessibilityLabel: Text(verbatim: "More")) {}
            }
        }
    }

    private var searchFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            caption("search field · empty · with text and its clear button")
            SearchField(text: $query, prompt: Text(verbatim: "Search exercises"))
            SearchField(text: $typed, prompt: Text(verbatim: "Search sports"))
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 8) {
            caption("activity row · the enrolled plan (filled disc) · a built-in plan · a session with its load")
            ForEach(Self.rows.indices, id: \.self) { i in
                ActivityListRow(content: Self.rows[i], accessory: .chevron)
            }
        }
    }

    private var discs: some View {
        VStack(alignment: .leading, spacing: 12) {
            caption("icon disc · outline · filled, regular and large")
            HStack(spacing: 12) {
                IconDisc(systemImage: "list.bullet.rectangle")
                IconDisc(systemImage: "checkmark", style: .filled)
                IconDisc(systemImage: "list.bullet.rectangle", size: .large)
                IconDisc(systemImage: "checkmark", size: .large, style: .filled)
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(verbatim: text).font(.ryft(.caption)).foregroundStyle(Theme.textTertiary)
    }

    private static let rows: [ActivityListRow.Content] = [
        .init(systemImage: "checkmark", title: "Upper/Lower 4×", meta: "Hypertrophy · 4 days/week · repeating", value: nil,
              spoken: "Upper/Lower 4×, active, Hypertrophy, 4 days a week, repeating", showsValue: false, filledDisc: true),
        .init(systemImage: "list.bullet.rectangle", title: "Full Body 3×", meta: "Strength · 3 days/week · 12 weeks",
              value: nil, spoken: "Full Body 3×, Strength, 3 days a week, 12 weeks", showsValue: false),
        .init(systemImage: "dumbbell.fill", title: "Upper A", meta: "Fri, Nov 13 · 55m · 7,500 kg", value: "85.0",
              spoken: "Upper A, Friday 13 November, 55 minutes, 7,500 kilograms, muscular load 85", valueCaption: "load"),
        .init(systemImage: "dumbbell.fill", title: "Workout", meta: "Tue, Nov 10 · 39m", value: nil,
              spoken: "Workout, Tuesday 10 November, 39 minutes, no muscular load", valueCaption: "load"),
    ]
}

#Preview("Nocturne · train") {
    NavigationStack {
        ScrollView {
            NocturneTrainCatalog()
                .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background)
    }
    .previewEnvironment()
}

#Preview("Nocturne · train · AX3") {
    NavigationStack {
        ScrollView {
            NocturneTrainCatalog()
                .padding(Theme.Metrics.screenPadding)
        }
        .background(Theme.background)
    }
    .previewEnvironment()
    .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
