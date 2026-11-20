import UIKit

/// A hosted window drawn top to bottom at 3x, however long its page. A window over about 2,700 pt draws black (its own 3x
/// backing passes the 8,192 px texture limit), so the window stays short and its page scroll view (`pageScrollView()`) is
/// scrolled one screen at a time; the parts are joined under each other. What sits over the page (a floating button) shows
/// once per part. For T5.0-B's comparison shots (`StructuresScreenShotsTests`, `NocturneStructuresShotsTests`), not a
/// golden-file test.
@MainActor
enum PagedWindowShot {
    /// The longest output, in pixels: a taller page is drawn at less than 3x.
    static let maxPixels: CGFloat = 8_000

    static func image(_ w: HostedWindow) async throws -> UIImage {
        let bounds = w.window.bounds
        guard let scroll = w.pageScrollView() else { return draw(w, scale: 3) }
        let frame = scroll.convert(scroll.bounds, to: w.window)
        let inset = scroll.adjustedContentInset
        let start = -inset.top
        let end = max(start, scroll.contentSize.height + inset.bottom - scroll.bounds.height)
        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: start), animated: false)
        try await w.settle()
        var pages = [(image: draw(w, scale: 3), offset: start)]
        var offset = start
        while offset < end - 0.5 {
            offset = min(offset + frame.height, end)
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
            try await w.settle()
            pages.append((draw(w, scale: 3), offset))
        }
        let extra = offset - start
        let size = CGSize(width: bounds.width, height: bounds.height + extra)
        let format = UIGraphicsImageRendererFormat()
        format.scale = min(3, maxPixels / size.height)
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            // The first part down to the scroll view's bottom; each later one adds the content under the part before;
            // the last one gives what sits under the scroll view.
            var drawnTo = frame.maxY
            for (index, page) in pages.enumerated() {
                let shift = page.offset - start
                let top = index == 0 ? 0 : drawnTo
                let bottom = index == pages.count - 1 ? size.height : frame.maxY + shift
                guard bottom > top else { continue }
                ctx.cgContext.saveGState()
                ctx.cgContext.clip(to: CGRect(x: 0, y: top, width: size.width, height: bottom - top))
                page.image.draw(at: CGPoint(x: 0, y: shift))
                ctx.cgContext.restoreGState()
                drawnTo = bottom
            }
        }
    }

    private static func draw(_ w: HostedWindow, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
    }
}
