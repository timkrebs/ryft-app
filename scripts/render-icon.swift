// Renders the RYFT app icons (1024×1024 PNG, no alpha) from the app's own
// RyftMark geometry with SwiftUI's ImageRenderer.
//
// Compiled together with Ryft/Design/RyftMark.swift so the icon and the in-app
// mark can never drift apart (`make icon` does exactly this):
//
//   mkdir -p .build && swiftc -parse-as-library -o .build/render-icon \
//     scripts/render-icon.swift Ryft/Design/RyftMark.swift && .build/render-icon
//
// Writes AppIcon-Light / -Dark / -Tinted.png into Ryft/Assets.xcassets/AppIcon.appiconset/.
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@main
struct RenderIcon {
    static let size: CGFloat = 1024
    static let markScale: CGFloat = 0.6

    static let graphite = Color(red: 0x0B / 255, green: 0x0F / 255, blue: 0x0E / 255)
    static let mist = Color(red: 0xE8 / 255, green: 0xE7 / 255, blue: 0xE3 / 255)

    struct Variant {
        let file: String
        let background: Color
        let mark: Color
    }

    // Light = default ("any") appearance, Dark = iOS dark icon, Tinted = grayscale
    // source the system tints (white mark on black).
    static let variants = [
        Variant(file: "AppIcon-Light.png", background: mist, mark: graphite),
        Variant(file: "AppIcon-Dark.png", background: graphite, mark: mist),
        Variant(file: "AppIcon-Tinted.png", background: .black, mark: .white),
    ]

    @MainActor
    static func main() throws {
        let dir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                      ?? "Ryft/Assets.xcassets/AppIcon.appiconset")
        for v in variants {
            let view = ZStack {
                v.background
                RyftMark()
                    .foregroundStyle(v.mark)
                    .frame(width: size * markScale, height: size * markScale)
            }
            .frame(width: size, height: size)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let rendered = renderer.cgImage, let opaque = flatten(rendered) else {
                throw NSError(domain: "render-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "render failed"])
            }
            let url = dir.appendingPathComponent(v.file)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw NSError(domain: "render-icon", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot write \(url.path)"])
            }
            CGImageDestinationAddImage(dest, opaque, nil)
            CGImageDestinationFinalize(dest)
            print("wrote \(url.path)")
        }
    }

    /// App Store icons must not have an alpha channel.
    static func flatten(_ image: CGImage) -> CGImage? {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx?.makeImage()
    }
}
