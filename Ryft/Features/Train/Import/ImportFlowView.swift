import SwiftUI
import UniformTypeIdentifiers

/// The training import (ui.md §2): a full-screen cover with one pushed screen per step. Step 1 has Cancel; steps 2 to 5
/// have the back chevron and a Cancel that asks first (N1); step 6 only Close. Swipe-down is off from step 2 on.
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
        .tint(Theme.accent)
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

/// A step's frame (ui.md §2, §10): the step rule pinned under the bar, the content (560 pt at most, centred), and a
/// pinned bottom bar with a hairline above it. The bar grows with Dynamic Type; the scroll view keeps room for it.
struct ImportStepScaffold<Content: View, Bottom: View>: View {
    let model: ImportFlowModel
    let step: ImportFlowModel.Step
    @ViewBuilder var content: () -> Content
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Metrics.sectionSpacing) {
                content()
            }
            .padding(.horizontal, Theme.Metrics.screenPadding)
            .padding(.vertical, 16)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            StepRule(step: step.rawValue, count: ImportFlowModel.stepCount)
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 8)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(Theme.background)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) { bottom() }
                .padding(.horizontal, Theme.Metrics.screenPadding)
                .padding(.vertical, 12)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .background(Theme.background)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.separator).frame(height: Theme.Metrics.hairline)
                }
        }
        .navigationTitle(step.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbar { toolbar }
        .navigationBarBackButtonHidden(step == .result)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        switch step {
        case .pick:
            ToolbarItem(placement: .cancellationAction) { cancelButton }
        case .detected, .choose, .map, .preview:
            ToolbarItem(placement: .topBarTrailing) { cancelButton }
        case .result:
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    model.finish(.close)
                } label: {
                    Text("Close")
                }
                .accessibilityIdentifier("import.close")
            }
        }
    }

    private var cancelButton: some View {
        Button {
            model.cancel()
        } label: {
            Text("Cancel")
        }
        .accessibilityIdentifier("import.cancel")
    }
}

/// The pinned teal button of a step (ui.md §0: one accent per screen), full width, growing with Dynamic Type.
struct ImportPrimaryButton: View {
    let title: String
    var identifier = "import.continue"
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .buttonStyle(TealButtonStyle(prominent: true))
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityIdentifier(identifier)
    }
}

/// The caption over a disabled button that says why (ui.md C3, C4, M3), or a footnote under one.
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

/// A plain text button in the flow ("Add another file", "Accept 3 likely matches"): accent, 44 pt tall.
struct ImportTextButton: View {
    let title: String
    var systemImage: String?
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
                Text(verbatim: title).fixedSize(horizontal: false, vertical: true)
            }
            .font(.ryft(.callout))
            .foregroundStyle(Theme.accent)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier ?? "")
    }
}

/// A caption line with a glyph (the time-zone line, footnotes): glyph `textSecondary`, text as given.
struct ImportNoteLine: View {
    let systemImage: String
    let text: String
    var tertiary = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .font(.ryft(.caption))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: text)
                .font(.ryft(.caption))
                .foregroundStyle(tertiary ? Theme.textTertiary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Import flow · step 1 · dark") {
    ImportFlowView(model: ImportMockData.flow(.pick))
        .previewEnvironment()
}

#Preview("Import flow · step 2 · light") {
    ImportFlowView(model: ImportMockData.flow(.detected))
        .previewEnvironment(scheme: .light)
}

/// "Open in" with `train.import` off (ui.md E10): a calm sheet, nothing was read.
struct ImportUnavailableSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textSecondary)
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
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("OK", comment: "Training import E10: close the sheet.")
            }
            .buttonStyle(TealButtonStyle())
            .accessibilityIdentifier("import.unavailable.ok")
        }
        .padding(Theme.Metrics.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
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

#Preview("Import unavailable · dark") {
    Color.clear.sheet(isPresented: .constant(true)) { ImportUnavailableSheet() }
        .preferredColorScheme(.dark)
}

#Preview("Import unavailable · light") {
    Color.clear.sheet(isPresented: .constant(true)) { ImportUnavailableSheet() }
        .preferredColorScheme(.light)
}
