import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// A hosted window drawn once (`drawHierarchy`, so presented sheets and live controls show) and read as 8-bit sRGB, in the
/// window's points. For colour checks on real screens: an ink fill, no teal, where a text's ink starts.
@MainActor
struct WindowPixels {
    typealias RGBA = NocturneTokenTests.RGBA

    let width: Int, height: Int, scale: CGFloat
    private let bytes: [UInt8]

    init(_ w: HostedWindow, scale: CGFloat = 3) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: w.window.bounds, format: format).image { _ in
            w.window.drawHierarchy(in: w.window.bounds, afterScreenUpdates: true)
        }
        let cg = try #require(image.cgImage)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        (width, height, self.scale) = (cg.width, cg.height, scale)
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        let ctx = try #require(CGContext(data: &bytes, width: cg.width, height: cg.height, bitsPerComponent: 8,
                                         bytesPerRow: cg.width * 4, space: space,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        self.bytes = bytes
    }

    private func px(_ ix: Int, _ iy: Int) -> RGBA {
        let i = (iy * width + ix) * 4
        return RGBA(r: Double(bytes[i]) / 255, g: Double(bytes[i + 1]) / 255, b: Double(bytes[i + 2]) / 255, a: 1)
    }

    /// The pixel that covers the point.
    func at(_ x: CGFloat, _ y: CGFloat) -> RGBA {
        px(min(max(Int(x * scale), 0), width - 1), min(max(Int(y * scale), 0), height - 1))
    }

    private func pixels(in rect: CGRect) -> (xs: Range<Int>, ys: Range<Int>) {
        let x0 = max(Int(rect.minX * scale), 0), x1 = min(Int(rect.maxX * scale), width)
        let y0 = max(Int(rect.minY * scale), 0), y1 = min(Int(rect.maxY * scale), height)
        return (x0..<max(x0, x1), y0..<max(y0, y1))
    }

    /// The pixels in `rect` for which `match` holds.
    func count(in rect: CGRect, where match: (RGBA) -> Bool) -> Int {
        let (xs, ys) = pixels(in: rect)
        var n = 0
        for iy in ys { for ix in xs where match(px(ix, iy)) { n += 1 } }
        return n
    }

    /// The box (points) around the pixels in `rect` for which `match` holds; nil when none does.
    func box(in rect: CGRect, where match: (RGBA) -> Bool) -> CGRect? {
        let (xs, ys) = pixels(in: rect)
        var (minX, minY, maxX, maxY) = (Int.max, Int.max, Int.min, Int.min)
        for iy in ys {
            for ix in xs where match(px(ix, iy)) {
                minX = min(minX, ix); maxX = max(maxX, ix); minY = min(minY, iy); maxY = max(maxY, iy)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }
}
