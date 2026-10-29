import SwiftUI

/// The session's toast at the bottom of the list, above the number pad (ui.md §4): the replace's Undo while its
/// window lasts, or a short notice. Leaving the session screen commits a pending replace.
struct SessionToastOverlay: View {
    var controller: SessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack {
            if let undo = controller.undo {
                UndoToast(message: undo.message,
                          announcement: String(localized: "Replaced with \(undo.newName). Undo available.",
                                               comment: "VoiceOver when the replace toast appears. 1: new exercise."),
                          onUndo: { Self.undo(undo, in: controller) },
                          onDismiss: { controller.dismissUndo() })
                    .id(undo.id)
                    .transition(UndoToast.transition(reduceMotion: reduceMotion))
            } else if let notice = controller.notice {
                UndoToast(message: notice.message, announcement: notice.message,
                          onDismiss: { controller.notice = nil })
                    .id(notice.id)
                    .transition(UndoToast.transition(reduceMotion: reduceMotion))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: controller.undo?.id)
        .animation(reduceMotion ? nil : Theme.Motion.quick, value: controller.notice?.id)
        .onDisappear { controller.commitUndo() }
    }

    static func undo(_ undo: ReplaceUndo, in controller: SessionController) {
        controller.undoReplace()
        AccessibilityNotification.Announcement(
            String(localized: "Restored \(undo.restoredName).",
                   comment: "VoiceOver after Undo of a replaced exercise. 1: exercise name.")).post()
    }
}
