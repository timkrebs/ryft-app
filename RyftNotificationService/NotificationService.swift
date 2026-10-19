import UserNotifications

/// Runs for every alert with `mutable-content` (API.md → Push notifications).
/// iOS has already filled the title and body from the loc-keys in the app's
/// `Localizable.xcstrings`; this only adds the recovery ring to `MORNING_SCORE`.
/// Needs `Ryft/Push/NotificationRing.swift` in its target membership.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        bestAttempt = content
        if let ring = NotificationRing.attachment(for: content.userInfo) {
            content.attachments = [ring]
        }
        contentHandler(content)
    }

    /// Out of time: deliver the text without the ring.
    override func serviceExtensionTimeWillExpire() {
        if let contentHandler, let bestAttempt { contentHandler(bestAttempt) }
    }
}
