import SwiftUI

/// A short message at the bottom of a screen, with an optional Undo (ui.md §4). Who shows it owns the timing; the
/// toast only draws, announces itself to VoiceOver and reports Undo or a swipe down. One accent: the Undo word.
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
        HStack(spacing: 12) {
            Text(message)
                .font(.ryft(.callout))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onUndo {
                Button(action: onUndo) {
                    Text("Undo", comment: "Toast button that takes back the last change, e.g. a replaced exercise.")
                        .font(.ryft(.headline))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("session.undo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(minHeight: 56)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.tileRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: Theme.Metrics.hairline))
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            if value.translation.height > 20 { onDismiss() }
        })
        .accessibilityElement(children: .contain)
        .onAppear {
            guard let announcement else { return }
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    /// Fade with a 12 pt rise; opacity only with Reduce Motion.
    static func transition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 12))
    }
}

#Preview("Undo toast", traits: .sizeThatFitsLayout) {
    SchemePair {
        VStack(spacing: 12) {
            UndoToast(message: "Replaced with Dumbbell bench press", onUndo: {})
            UndoToast(message: "Replaced with Dumbbell bench press. Your 2 done sets stay as Bench press.",
                      onUndo: {})
            UndoToast(message: "Restored Bench press. Your plan still has the new exercise.")
        }
    }
}

#Preview("Undo toast · AX3", traits: .sizeThatFitsLayout) {
    SchemePair {
        UndoToast(message: "Replaced with Dumbbell bench press. Changed in your plan from the next Upper day.",
                  onUndo: {})
    }
    .dynamicTypeSize(.accessibility3)
}
