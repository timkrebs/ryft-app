import SwiftUI

/// A short message at the bottom of a screen, with an optional Undo (ui.md §4; Nocturne PR 6 B §4.8). Who shows it owns the
/// timing; the toast only draws, announces itself to VoiceOver and reports Undo or a swipe down. A raised card, radius 22, no
/// edge; Undo is a text button in ink (`ryftLink`), not a colour.
struct UndoToast: View {
    let message: String
    /// Read by VoiceOver when the toast appears ("Replaced with Bench press. Undo available."); focus isn't moved.
    var announcement: String?
    /// nil: a note without Undo.
    var onUndo: (() -> Void)?
    /// Swiped down.
    var onDismiss: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // At accessibility sizes the message gets the full width and Undo goes under it.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .trailing, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Text(message)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                // Not cut: the longest replace message takes three lines (four with a long exercise name).
                .lineLimit(typeSize.isAccessibilitySize ? nil : 4)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onUndo {
                Button(action: onUndo) {
                    Text("Undo", comment: "Toast button that takes back the last change, e.g. a replaced exercise.")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .ryftLink()
                .accessibilityIdentifier("session.undo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            if value.translation.height > 20 { onDismiss() }
        })
        .accessibilityElement(children: .contain)
        // The two-finger Z (and Switch Control's Escape) close it, as a swipe down does.
        .accessibilityAction(.escape) { onDismiss() }
        .onAppear {
            guard let announcement else { return }
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    /// The card's corners: a grouped card's.
    static let radius = CardSpec.radius

    /// Fade with a 12 pt rise; opacity only with Reduce Motion.
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12))
    }
}

#Preview("Undo toast", traits: .sizeThatFitsLayout) {
    DarkPreview {
        VStack(spacing: 12) {
            UndoToast(message: "Replaced with Dumbbell bench press", onUndo: {})
            UndoToast(message: "Replaced with Dumbbell bench press. Your 2 done sets stay with Bench press.",
                      onUndo: {})
            UndoToast(message: "Restored Bench press. Your plan still has the new exercise.")
        }
    }
}

#Preview("Undo toast · AX3", traits: .sizeThatFitsLayout) {
    DarkPreview {
        UndoToast(message: "Replaced with Dumbbell bench press. Changed in your plan from the next Upper day.",
                  onUndo: {})
    }
    .dynamicTypeSize(.accessibility3)
}

#Preview("Undo toast · plan, no history weight", traits: .sizeThatFitsLayout) {
    DarkPreview {
        UndoToast(message: "Replaced with Dumbbell bench press. Changed in your plan from the next Upper day. Check its target weight there.",
                  onUndo: {})
    }
}
