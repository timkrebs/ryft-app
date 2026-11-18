// The search field of a sheet with a `SheetHeader` (Nocturne PR 6 B §4.8 Add exercise, §10.1 the sport picker; T6B.0). Those
// sheets have no navigation bar for `.searchable` to sit in, and the system field's glass and teal would not follow the
// grammar anyway.
import SwiftUI

/// The search field's numbers.
enum SearchFieldSpec {
    /// A `surface` capsule at least 46 high (a list row's height); it grows with the text.
    nonisolated static let minHeight = Theme.Metrics.listRowHeight
    /// 16 at the leading side, the glyph, 10, the text; the clear button's 44 pt box reaches the trailing edge.
    nonisolated static let leadingPadding: CGFloat = 16, spacing: CGFloat = 10
    /// The magnifying glass and the clear glyph: 15 pt, `textTertiary` (decoration: the field's label says what it is).
    nonisolated static let glyphSize: CGFloat = 15
}

/// `SearchField(text: $query, prompt: Text("Search exercises"))`: `magnifyingglass` · the text (`body`, `textPrimary`; the
/// prompt in the field prompt's `textSecondary`) · a clear button while there is text. One line; the keyboard's return key
/// reads "Search", and corrections are off (exercise and sport names). VoiceOver reads a search field labelled with the prompt;
/// the clear button is "Clear search". `identifier` goes on the text field.
struct SearchField: View {
    @Binding private var text: String
    private let prompt: Text
    private let identifier: String?

    init(text: Binding<String>, prompt: Text, identifier: String? = nil) {
        _text = text
        self.prompt = prompt
        self.identifier = identifier
    }

    var body: some View {
        HStack(spacing: SearchFieldSpec.spacing) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: SearchFieldSpec.glyphSize, weight: .regular))
                .foregroundStyle(Theme.textTertiary)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt.fieldPrompt()) { prompt }
                .font(.ryft(.body))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityAddTraits(.isSearchField)
                .accessibilityIdentifier(identifier ?? "")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: SearchFieldSpec.glyphSize, weight: .regular))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: Theme.Metrics.minHitTarget, height: Theme.Metrics.minHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search", comment: "VoiceOver label of the button that empties a search field."))
            }
        }
        .padding(.leading, SearchFieldSpec.leadingPadding)
        // The clear button's box ends at the capsule's edge; without it the text keeps the leading side's room.
        .padding(.trailing, text.isEmpty ? SearchFieldSpec.leadingPadding : 0)
        .frame(maxWidth: .infinity, minHeight: SearchFieldSpec.minHeight, alignment: .leading)
        .background(Theme.surface, in: Capsule())
        .contentShape(Capsule())
    }
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

private struct SearchFieldPreviewList: View {
    @State private var empty = ""
    @State private var typed = "bench"

    var body: some View {
        VStack(spacing: 12) {
            SearchField(text: $empty, prompt: Text(verbatim: "Search exercises"))
            SearchField(text: $typed, prompt: Text(verbatim: "Search exercises"))
        }
    }
}

#Preview("SearchField", traits: .sizeThatFitsLayout) {
    DarkPreview { SearchFieldPreviewList() }
}

#Preview("SearchField · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview { SearchFieldPreviewList() }
        .environment(\.dynamicTypeSize, .accessibility3)
}
