import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Writes T5.0-B's parts (`NocturneStructuresCatalog.Part`: the grouped list, the tiles and placeholders, the date strip, the
/// segmented picker, the titled header, the zones and idea tiles, the trend line, the delta colours) as 3x PNGs, dark, at the
/// default size and at AX3, when `STRUCTURES_SHOTS_DIR` is set; otherwise does nothing. Drawn from a real window, the whole
/// page (`PagedWindowShot`), so the zone block's measured arrangement and the strip's scroll have settled. Run it with
/// `TEST_RUNNER_STRUCTURES_SHOTS_DIR=<dir> xcodebuild … -only-testing:RyftTests/NocturneStructuresShotsTests test`. For the
/// design note and ui-validator, not a golden-file test.
@MainActor
@Suite("Nocturne structures: shots", .serialized)
struct NocturneStructuresShotsTests {
    @Test func writeShots() async throws {
        guard let dir = ProcessInfo.processInfo.environment["STRUCTURES_SHOTS_DIR"] else { return }
        for part in NocturneStructuresCatalog.Part.allCases {
            for (name, typeSize, category) in [("default", DynamicTypeSize.large, UIContentSizeCategory.large),
                                               ("ax3", .accessibility3, .accessibilityExtraLarge)] {
                let content = NavigationStack {
                    ScrollView {
                        NocturneStructuresCatalog(parts: [part])
                            .padding(Theme.Metrics.screenPadding)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .background(Theme.background)
                    .toolbar(.hidden, for: .navigationBar)
                }
                try await HostedWindow.run(width: 390, height: 2_600, bottomInset: 0, typeSize: typeSize, category: category,
                                           content) { w in
                    try await w.settle()
                    let png = try await Self.croppedPNG(w)
                    let data = try #require(png)
                    try data.write(to: URL(fileURLWithPath: "\(dir)/\(part.rawValue)-\(name).png"))
                }
            }
        }
    }

    /// The whole page, cut 60 px below the last row that is not the screen colour.
    private static func croppedPNG(_ w: HostedWindow) async throws -> Data? {
        let image = try await PagedWindowShot.image(w)
        guard let cg = image.cgImage, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let (width, height) = (cg.width, cg.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ground = (bytes[0], bytes[1], bytes[2])
        var last = 0
        for y in stride(from: height - 1, through: 0, by: -1) {
            let row = y * width * 4
            if (0..<width).contains(where: { x in
                let i = row + x * 4
                return abs(Int(bytes[i]) - Int(ground.0)) > 2 || abs(Int(bytes[i + 1]) - Int(ground.1)) > 2
                    || abs(Int(bytes[i + 2]) - Int(ground.2)) > 2
            }) {
                last = y
                break
            }
        }
        let cut = min(height, last + 60)
        guard let cropped = cg.cropping(to: CGRect(x: 0, y: 0, width: width, height: cut)) else { return nil }
        return UIImage(cgImage: cropped).pngData()
    }
}
