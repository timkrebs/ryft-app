import UIKit
import UserNotifications

/// The recovery ring a `MORNING_SCORE` notification carries as its image, drawn
/// by the Notification Service Extension (`RyftNotificationService`; this file
/// is a member of both targets). The extension can't read the asset catalog,
/// so the brand's dark-mode colours are spelled out here (Graphite, Slate, and
/// the Teal / Warning / Alert bands of `Theme.band(forScore:)`).
enum NotificationRing {
    /// "82%", "82 %" → 82 (the platform formats the argument for the locale).
    static func score(fromArgument argument: String) -> Int? {
        let digits = argument.prefix { $0.isNumber || $0 == " " }.filter(\.isNumber)
        guard let value = Int(digits), (0...100).contains(value) else { return nil }
        return value
    }

    /// The recovery in an alert's `title-loc-args`, for `MORNING_SCORE` only.
    static func score(in userInfo: [AnyHashable: Any]) -> Int? {
        guard let aps = userInfo["aps"] as? [String: Any],
              aps["category"] as? String == "MORNING_SCORE",   // standalone: no Models.swift in the extension
              let alert = aps["alert"] as? [String: Any],
              let first = (alert["title-loc-args"] as? [String])?.first else { return nil }
        return score(fromArgument: first)
    }

    /// The same bands as the app: 67+ high, 34+ moderate, else low.
    static func bandColor(_ score: Int) -> UIColor {
        switch score {
        case 67...: return UIColor(red: 0x3F / 255, green: 0xD1 / 255, blue: 0xB4 / 255, alpha: 1)
        case 34...: return UIColor(red: 0xE3 / 255, green: 0xC2 / 255, blue: 0x5B / 255, alpha: 1)
        default: return UIColor(red: 0xE3 / 255, green: 0x6B / 255, blue: 0x5B / 255, alpha: 1)
        }
    }

    private static let graphite = UIColor(red: 0x0B / 255, green: 0x0F / 255, blue: 0x0E / 255, alpha: 1)
    private static let slate = UIColor(red: 0x1A / 255, green: 0x22 / 255, blue: 0x26 / 255, alpha: 1)

    /// Square, Graphite, the arc from 12 o'clock clockwise, the number in the middle.
    static func image(score: Int, side: CGFloat = 180) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            graphite.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let line = side * 0.09
            let center = CGPoint(x: side / 2, y: side / 2)
            let radius = side / 2 - line - side * 0.06
            let track = UIBezierPath(arcCenter: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            track.lineWidth = line
            slate.setStroke()
            track.stroke()
            let start = -CGFloat.pi / 2
            let arc = UIBezierPath(arcCenter: center, radius: radius, startAngle: start,
                                   endAngle: start + 2 * .pi * CGFloat(score) / 100, clockwise: true)
            arc.lineWidth = line
            arc.lineCapStyle = .round
            bandColor(score).setStroke()
            arc.stroke()
            let text = "\(score)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: side * 0.3, weight: .medium),
                .foregroundColor: UIColor.white,
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attributes)
        }
    }

    /// The ring as a PNG attachment, or `nil` when the notification has no score.
    static func attachment(for userInfo: [AnyHashable: Any], directory: URL = FileManager.default.temporaryDirectory)
        -> UNNotificationAttachment? {
        guard let score = score(in: userInfo), let png = image(score: score).pngData() else { return nil }
        let url = directory.appendingPathComponent("ring-\(UUID().uuidString).png")
        do {
            try png.write(to: url)
            return try UNNotificationAttachment(identifier: "ring", url: url, options: nil)
        } catch {
            return nil
        }
    }
}
