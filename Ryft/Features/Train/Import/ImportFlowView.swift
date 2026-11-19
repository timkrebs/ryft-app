import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The training import (ui.md §2; PR 6 C §4.14): a full-screen cover with one pushed page per step. Step 1 has Close; steps
/// 2 to 5 have Back and a Close that asks first (N1); step 6 only Close. Swipe-down is off from step 2 on. The controls take
/// the app's ink (the root's tint and toggle style).
struct ImportFlowView: View {
    @Bindable var model: ImportFlowModel
    @Environment(ScreenModels.self) private var screens

    var body: some View {
        NavigationStack(path: $model.path) {
            ImportPickView(model: model)
                .navigationDestination(for: ImportFlowModel.Step.self) { step in
                    switch step {
                    case .pick: ImportPickView(model: model)
                    case .detected: ImportDetectedView(model: model)
                    case .choose: ImportChooseView(model: model)
                    case .map: ImportMapView(model: model)
                    case .preview: ImportPreviewView(model: model)
                    case .result: ImportResultView(model: model)
                    }
                }
        }
        .interactiveDismissDisabled(model.step != .pick)
        .modifier(ImportReplaceAlert(importer: screens.importer))
        .fileImporter(isPresented: $model.showsPicker, allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: true) { result in
            Task { await model.picked(result) }
        }
        .alert(Text("Discard this import?", comment: "Training import: the cancel confirmation's title (N1)."),
               isPresented: $model.confirmsDiscard) {
            Button(role: .destructive) {
                model.discard()
            } label: {
                Text("Discard", comment: "Training import: forget the files and choices (N1).")
            }
            .accessibilityIdentifier("import.discard")
            Button(role: .cancel) {} label: {
                Text("Keep going", comment: "Training import: stay in the flow (N1).")
            }
        } message: {
            Text("RYFT forgets what it read from the file and your choices here. The file itself is not changed.",
                 comment: "Training import: the cancel confirmation's message (N1).")
        }
    }
}

/// The import's numbers (PR 6 C §4.14; drafts c-23 … c-23d). The header, the sides, the column and the pinned bar are the
/// subpage's (`SubpageSpec`, `PinnedBarSpec`).
enum ImportLayout {
    /// The header → the step rule, and the rule's "Step 3 of 6" → the content.
    static let ruleGap: CGFloat = 20, contentGap: CGFloat = 20
    /// Between the blocks of a step (a group, a notice, a tile): the grouped list's 18.
    static let blockSpacing = GroupedListSpec.groupSpacing
    /// Inside a block: a headline → its paragraph, an outline slot → the next, a tile's lines.
    static let lineGap: CGFloat = 8, slotSpacing: CGFloat = 12
    /// Step 1's outline slots and the outline rows while something loads: 64 high, the card's radius.
    static let slotHeight: CGFloat = 64
    /// A file's glyph in a slot: 18 pt, ink 55 % (a row action's glyph).
    static let slotGlyph: CGFloat = 18
    /// Step 6's lead line: a 44 pt ring with the glyph, 12 to the 20 Light word.
    static let leadCircle: CGFloat = 44, leadGap: CGFloat = 12, leadSize: CGFloat = 20
}

/// A step's frame (ui.md §2, §10; PR 6 C §4.14): the subpage's header without a bar (the step's title at 26 Light; Back on
/// steps 2 to 5; a Close circle on every step but the Back-only ones), the step rule 20 below it, the content 20 below the
/// rule (560 pt at most, centred), and the pinned bar: one primary pill, a caption above it that says why it's off, a
/// footnote under it. Close on steps 1 to 5 is `cancel()` (which asks first from step 2, N1); on step 6 it is `close()`.
/// Steps 2 to 5 keep the back swipe; step 6 has no way back (the import has started).
struct ImportStepScaffold<Content: View, Bottom: View>: View {
    let model: ImportFlowModel
    let step: ImportFlowModel.Step
    /// false: no pinned bar (step 6 while it uploads has nothing to press).
    var showsBar = true
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SubpageHeader(Text(verbatim: step.title), navigation: navigation) { closeButton }
                StepRule(step: step.rawValue, count: ImportFlowModel.stepCount)
                    .padding(.top, ImportLayout.ruleGap)
                VStack(alignment: .leading, spacing: ImportLayout.blockSpacing) {
                    content()
                }
                .padding(.top, ImportLayout.contentGap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: SubpageSpec.maxContentWidth)
            .padding(.horizontal, SubpageSpec.sidePadding)
            .padding(.bottom, SubpageSpec.bottomPadding)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        // Step 6 has no way back: the subpages' keeper refuses a back swipe on a page that hides its Back button.
        .navigationBarBackButtonHidden(step == .result)
        .modifier(ImportBackSwipe(allowed: step != .result))
        .modifier(ImportPinnedBar(shows: showsBar, bar: bottom))
    }

    private var navigation: SubpageNavigation {
        switch step {
        case .pick, .result: .none
        case .detected, .choose, .map, .preview: .back()
        }
    }

    private var closeButton: some View {
        CircleButton(systemImage: "xmark", accessibilityLabel: Text("Close")) {
            // Step 6: the import continues; a finished result without refused items counts as seen.
            if step == .result { model.close() } else { model.cancel() }
        }
        .accessibilityIdentifier(step == .result ? "import.close" : "import.cancel")
    }
}

/// The pinned bar, or none.
private struct ImportPinnedBar<Bar: View>: ViewModifier {
    let shows: Bool
    @ViewBuilder let bar: () -> Bar

    func body(content: Content) -> some View {
        if shows {
            content.pinnedBar { bar() }
        } else {
            content
        }
    }
}

/// Steps 2 to 5 go back with a swipe (`keepsBackSwipe`, as every subpage). Step 6 switches both swipes off while it shows
/// (the edge's and iOS 26's from anywhere in the content), as well as hiding its Back button: the import has started, so
/// popping back to step 5 would offer it a second time.
private struct ImportBackSwipe: ViewModifier {
    let allowed: Bool

    func body(content: Content) -> some View {
        if allowed {
            content.keepsBackSwipe()
        } else {
            content.background { NoBackSwipe().accessibilityHidden(true) }
        }
    }

    private struct NoBackSwipe: UIViewControllerRepresentable {
        func makeUIViewController(context: Context) -> Probe { Probe() }
        func updateUIViewController(_ controller: Probe, context: Context) {}

        final class Probe: UIViewController {
            override func viewDidLoad() {
                super.viewDidLoad()
                view.isUserInteractionEnabled = false
            }

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                switchOff()
            }

            override func viewDidAppear(_ animated: Bool) {
                super.viewDidAppear(animated)
                switchOff()
            }

            private func switchOff() {
                guard let navigationController else { return }
                navigationController.interactivePopGestureRecognizer?.isEnabled = false
                if #available(iOS 26.0, *) {
                    navigationController.interactiveContentPopGestureRecognizer?.isEnabled = false
                }
            }
        }
    }
}

/// A step's primary action: the pinned pill (`PillButton`, `.primary`), full width, growing with Dynamic Type. Off, it dims
/// (the caption above says why); busy, a spinner takes the glyph's place.
struct ImportPrimaryButton: View {
    let title: String
    var identifier = "import.continue"
    var isEnabled = true
    var systemImage: String?
    var busy = false
    let action: () -> Void

    var body: some View {
        PillButton(Text(verbatim: title), systemImage: systemImage, busy: busy, action: action)
            .disabled(!isEnabled)
            .accessibilityIdentifier(identifier)
    }
}

/// The bar's one secondary action under the primary ("Open plan", "Done"): the outline pill; `.destructive` for
/// "Discard import".
struct ImportSecondaryButton: View {
    let title: String
    let identifier: String
    var style: PillButton.Style = .secondary
    let action: () -> Void

    var body: some View {
        PillButton(Text(verbatim: title), style: style, action: action)
            .accessibilityIdentifier(identifier)
    }
}

/// The caption over a disabled pill that says why (ui.md C3, C4, M3), or (`tertiary`) a footnote under one: the pinned
/// bar's caption and footnote (`PinnedActionBar`).
struct ImportBarCaption: View {
    let text: String
    var tertiary = false

    var body: some View {
        Text(verbatim: text)
            .font(.ryft(.caption))
            .monospacedDigit()
            .foregroundStyle(tertiary ? Theme.textTertiary : Theme.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
    }
}

/// A text action on its own line ("Accept 3 likely matches", "Import these too"): the underlined ink link (`ryftLink`),
/// 44 pt tall.
struct ImportTextButton: View {
    let title: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ryftLink()
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// A destructive action that isn't the page's next step (step 6's "Discard import" while the upload waits): a text control
/// on its own line, under the pill, as `ryftLink()` but in `alert` (6.09:1 on `background`), underlined at 50 % of it, at
/// least 44 pt and all of it tappable. The caller confirms (S2).
struct ImportDestructiveTextButton: View {
    let title: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .buttonStyle(Style())
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier(identifier)
    }

    private struct Style: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            Look(label: configuration.label, isPressed: configuration.isPressed)
        }
    }

    private struct Look<Content: View>: View {
        let label: Content
        let isPressed: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            label
                .font(.ryft(.callout))
                .foregroundStyle(Theme.alert)
                .underline(true, pattern: .solid, color: Theme.alert.opacity(InlineLink.underlineOpacity))
                .frame(minWidth: InlineLink.minTarget, minHeight: InlineLink.minTarget)
                .contentShape(Rectangle())
                .opacity(isEnabled ? (isPressed ? InlineLink.pressedOpacity : 1) : InlineLink.disabledOpacity)
        }
    }
}

/// A footer line with a glyph (the time-zone line, a plan's notes): a 12 pt glyph and the caption, `textSecondary`, or
/// `textTertiary` for the quiet ones; `attention` draws the glyph in `warning` (the words say what to fix).
struct ImportNoteLine: View {
    let systemImage: String
    let text: String
    var tertiary = false
    var attention = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.ryft(.caption))
                .foregroundStyle(attention ? Theme.warning : tertiary ? Theme.textTertiary : Theme.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.ryft(.caption))
                .foregroundStyle(tertiary ? Theme.textTertiary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A note inside a grouped card, under the row it concerns ("Already in RYFT", why a plan can't be imported): a caption with
/// its glyph, 16 from the sides, read with that row's group. `attention`: the glyph in `warning` (the words say why).
struct ImportCardNote: View {
    let systemImage: String
    let text: String
    var attention = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ImportLayout.lineGap) {
            Image(systemName: systemImage)
                .font(.ryft(.caption))
                .foregroundStyle(attention ? Theme.warning : Theme.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GroupedListSpec.rowInset)
        .padding(.bottom, GroupedListSpec.textPadding + 2)
        .accessibilityElement(children: .combine)
    }
}

/// A list's place while it loads (step 4's library, step 5's build): outline rows at the slot's height and the card's
/// radius, nothing inside, no spinner; VoiceOver hears `label` once.
struct ImportLoadingRows: View {
    let count: Int
    let label: Text

    var body: some View {
        VStack(spacing: ImportLayout.slotSpacing) {
            ForEach(0..<count, id: \.self) { _ in
                PlaceholderRow(height: ImportLayout.slotHeight, radius: GroupedListSpec.cardRadius)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

#Preview("Import flow · step 1") {
    ImportFlowView(model: ImportMockData.flow(.pick))
        .previewEnvironment()
        .toggleStyle(.ryft)
}

#Preview("Import flow · step 2") {
    ImportFlowView(model: ImportMockData.flow(.detected))
        .previewEnvironment()
        .toggleStyle(.ryft)
}

/// "Open in" with `train.import` off (ui.md E10; PR 6 C §4.14): a calm medium sheet, nothing was read. The document glyph
/// (28 pt, `textSecondary`), the headline, the sentence, and one primary OK pill at the bottom.
struct ImportUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: ImportLayout.lineGap) {
                Image(systemName: "doc.text")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, ImportLayout.lineGap)
                    .accessibilityHidden(true)
                Text("Importing isn't available on this account yet", comment: "Training import E10: Open in with the import off.")
                    .font(.ryft(.headline))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("RYFT can't import training files for your account right now. The file wasn't read or changed.",
                     comment: "Training import E10.")
                    .font(.ryft(.callout))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: ImportLayout.blockSpacing)
            PillButton(Text("OK", comment: "Training import E10: close the sheet."), systemImage: PillButton.Icon.confirm) {
                dismiss()
            }
            .accessibilityIdentifier("import.unavailable.ok")
        }
        .padding(.horizontal, SubpageSpec.sidePadding)
        .padding(.top, SubpageSpec.sheetTopInset)
        .padding(.bottom, PinnedBarSpec.bottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationBackground(Theme.background)
        .presentationDragIndicator(.visible)
    }
}

/// E8: a file arrived while another import is being set up; one of the two must win.
struct ImportReplaceAlert: ViewModifier {
    let importer: ImportCoordinator

    func body(content: Content) -> some View {
        content.alert(Text("Replace the import you're setting up?", comment: "Training import E8."),
                      isPresented: Binding(get: { importer.replacement != nil }, set: { if !$0 { importer.keepCurrent() } })) {
            Button {
                Task { await importer.replaceCurrent() }
            } label: {
                Text("Replace", comment: "Training import E8: start over with the new file.")
            }
            Button(role: .cancel) {
                importer.keepCurrent()
            } label: {
                Text("Keep current", comment: "Training import E8: drop the new file.")
            }
        } message: {
            Text("You're in the middle of another import. Opening this file starts over.", comment: "Training import E8.")
        }
    }
}

#Preview("Import unavailable") {
    Theme.background.ignoresSafeArea().sheet(isPresented: .constant(true)) { ImportUnavailableSheet().presentedRoot() }
        .preferredColorScheme(.dark)
}
