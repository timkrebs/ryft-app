// The signed-out forms' parts (Nocturne, docs/work/2026-11-16-nocturne/design-pr6-a-onboarding.md §A-2 … A-6, G3, G4, G7): a
// pushed page with its own header (`SubpageScaffold`), the lead under it, the fields as rows of one grouped card
// (`FormField`), a hint, the banner and the primary pill. Errors are banners (`AuthErrorMessage`), never field states.
import SwiftUI

/// Where the Welcome flow can go. "Set new password" isn't here: it opens as a
/// sheet from a reset link or Profile.
enum AuthRoute: Hashable {
    case createAccount
    case logIn
    case forgotPassword(email: String)
    case checkInbox(InboxReason, email: String)
}

enum InboxReason: Hashable {
    case confirmSignUp
    case resetPassword
}

enum AuthValidation {
    static func isEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let at = t.firstIndex(of: "@"), at != t.startIndex else { return false }
        let domain = t[t.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !t.contains(" ")
    }

    static func isPassword(_ s: String) -> Bool { s.count >= AuthService.minimumPasswordLength }
}

/// The signed-out forms' numbers (A §A-2 … A-6). The header, the sides and the card are `SubpageScaffold`'s and
/// `GroupedCard`'s.
enum AuthScreenSpec {
    /// The header → the lead: 12 (the subpage's content starts 22 below its header; the lead is pulled up by the difference).
    static let leadGap: CGFloat = 12
    /// The lead (or, without one, the header) → the form: 24.
    static let formGap: CGFloat = 24
    /// A hint under the card ("At least 10 characters."): 8 below it, 4 in from its edge.
    static let hintGap: CGFloat = 8, hintInset: CGFloat = 4
    /// The banner → the primary, and the form → the banner: 12. Without a link or a hint between, the card → the primary: 20.
    static let actionGap: CGFloat = 12, primaryGap: CGFloat = 20
    /// The eye: a 15 pt glyph in a 44 × 44 button whose glyph sits on the row's 16 pt inset (the box reaches 12 into it).
    static let eyeSize: CGFloat = 15, eyeOverhang: CGFloat = 12, eyeVerticalOverhang: CGFloat = 4
    /// The first field takes the keyboard once the push has finished (UIKit's push runs 0.35 s), so the keyboard is part
    /// of the screen and doesn't slide in over the transition.
    static let focusDelay: Duration = .milliseconds(450)
}

/// A signed-out form's fields, for its `@FocusState`.
enum AuthField: Hashable {
    case name, email, password
}

/// The frame of a signed-out form: the subpage header (the pushed pages' row: "Back" circle, the title centred, the back
/// swipe kept), the lead in 16 pt `textSecondary` 12 below it, then the form 24 below that, 20 from the sides, scrolling,
/// the keyboard dismissed by a drag. A sheet (Set new password) passes `.close(…)` and `isSheet`: the sheet header, pinned.
struct AuthScreen<Content: View>: View {
    private let title: Text
    private let lead: Text?
    private let navigation: SubpageNavigation
    private let isSheet: Bool
    private let content: Content

    init(title: Text, lead: Text? = nil, navigation: SubpageNavigation = .back(), isSheet: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.lead = lead
        self.navigation = navigation
        self.isSheet = isSheet
        self.content = content()
    }

    var body: some View {
        SubpageScaffold(title, navigation: navigation, isSheet: isSheet) {
            VStack(alignment: .leading, spacing: 0) {
                if let lead {
                    lead
                        .font(.ryft(.body))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, AuthScreenSpec.leadGap - SubpageSpec.contentGap)
                        .padding(.bottom, AuthScreenSpec.formGap)
                } else {
                    Color.clear.frame(height: AuthScreenSpec.formGap - SubpageSpec.contentGap)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// A text row of a signed-out form (`FormField` in a `GroupedCard`): the label above the value, the focus bar while it has
/// the keyboard. VoiceOver reads it as one field named by its label.
struct AuthTextField: View {
    /// No placeholder: the label is above the value, and without a prompt iOS would repeat the label in the empty field.
    static var noPrompt: Text { Text(verbatim: "") }

    let title: LocalizedStringKey
    @Binding var text: String
    let field: AuthField
    let focus: FocusState<AuthField?>.Binding
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .never
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        FormField(Text(title), isFocused: focus.wrappedValue == field) {
            TextField(text: $text, prompt: Self.noPrompt) { Text(title) }
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled()
                .submitLabel(submitLabel)
                .focused(focus, equals: field)
                .onSubmit(onSubmit)
        }
    }
}

/// A password row with the eye (show / hide): `isNew` asks the system for a strong-password suggestion. The eye is a 44 pt
/// button labelled "Show password" / "Hide password"; it doesn't scale and shows the Large Content Viewer. Showing the
/// password keeps the keyboard where it was.
struct PasswordField: View {
    private static var noPrompt: Text { AuthTextField.noPrompt }

    let title: LocalizedStringKey
    @Binding var text: String
    let focus: FocusState<AuthField?>.Binding
    var isNew = false
    var submitLabel: SubmitLabel = .go
    var onSubmit: () -> Void = {}

    @State private var revealed = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        FormField(Text(title), isFocused: focus.wrappedValue == .password) {
            Group {
                if revealed {
                    TextField(text: $text, prompt: Self.noPrompt) { Text(title) }
                } else {
                    SecureField(text: $text, prompt: Self.noPrompt) { Text(title) }
                }
            }
            .textContentType(isNew ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(submitLabel)
            .focused(focus, equals: .password)
            .onSubmit(onSubmit)
        } trailing: {
            Button {
                let hadFocus = focus.wrappedValue == .password
                revealed.toggle()
                if hadFocus { focus.wrappedValue = .password }
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: AuthScreenSpec.eyeSize, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    // At the accessibility sizes FormField puts it under the field: the glyph on the text's leading edge.
                    .frame(width: Theme.Metrics.minHitTarget, height: Theme.Metrics.minHitTarget,
                           alignment: typeSize.isAccessibilitySize ? .leading : .center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The 44 pt box reaches into the row's trailing inset and its padding, so the glyph sits on the 16 pt inset and
            // the row stays 56.
            .padding(.trailing, -AuthScreenSpec.eyeOverhang)
            .padding(.vertical, -AuthScreenSpec.eyeVerticalOverhang)
            .accessibilityLabel(revealed ? Text("Hide password") : Text("Show password"))
            .accessibilityShowsLargeContentViewer {
                Label { revealed ? Text("Hide password") : Text("Show password") } icon: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                }
            }
        }
    }
}

/// The hint under a form's card ("At least 10 characters."): 13 pt `textSecondary`, because it explains a disabled button.
struct AuthHint: View {
    let text: Text

    var body: some View {
        text
            .font(.ryft(.label))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AuthScreenSpec.hintInset)
            .padding(.top, AuthScreenSpec.hintGap)
    }
}

/// Inline error from AuthService, if any: the neutral banner, the glyph and the words carry it.
struct AuthErrorMessage: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        if let message = auth.errorMessage {
            InlineMessage(message: message, systemImage: "exclamationmark.circle")
        }
    }
}

extension View {
    /// The first field of a pushed form takes the keyboard once the push has finished, on the form's first appearance
    /// only: coming back to it (Check your inbox → "Use another email") leaves the focus to the user. The wait is the
    /// environment's clock, so a test decides whether it ends.
    func authFocus(_ focus: FocusState<AuthField?>.Binding, on field: AuthField, clock: AppClock) -> some View {
        modifier(AuthFocus(focus: focus, field: field, clock: clock))
    }
}

private struct AuthFocus: ViewModifier {
    let focus: FocusState<AuthField?>.Binding
    let field: AuthField
    let clock: AppClock
    @State private var didFocus = false

    func body(content: Content) -> some View {
        content.task {
            guard !didFocus else { return }
            do { try await clock.sleep(for: AuthScreenSpec.focusDelay) } catch { return }
            didFocus = true
            focus.wrappedValue = field
        }
    }
}
