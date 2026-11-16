// Renders the RYFT app icon "M1" (1024 x 1024 PNG, no alpha): "RYFT" in Satoshi Light on the near-black tile, no mark.
//
// Compiled together with scripts/icon-spec.swift; `make icon` builds and runs it from the repo root:
//
//   .build/render-icon [--previews <dir>] [dir]
//
//   --previews  also write the icon scaled to IconSpec.previewSizes (180, 120, 60, 40 px) into <dir>, for review at
//               the sizes where the word has to stay legible; `make icon` passes build/icon-preview
//   dir         default Ryft/Assets.xcassets/AppIcon.appiconset
//
// Writes AppIcon-Light, AppIcon-Dark and AppIcon-Tinted: the same image three times (the brief asks for one icon in
// every appearance). The colours come from the asset catalog (IconSpec): the tile is Background, the word TextPrimary.
// The word is drawn with CoreText from Ryft/Resources/Fonts/Satoshi-Light.otf, which is git-ignored (`make fonts`).
// There is no fallback face: a missing or wrong font file exits 1. It also exits 1 if the word is under 4.5:1 on the
// tile, if its ink is off-centre by more than half a pixel, or if a written PNG has an alpha channel.
//
// Placement: the ink (the letters' own outline, not their advance boxes) is centred horizontally, so the tracking after
// the last letter does not pull the word to the left; the cap height is centred vertically (R, Y, F and T are flat
// and have no overshoot, so the ink and the cap height are the same here).
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

@main
struct RenderIcon {
    static let names = ["AppIcon-Light", "AppIcon-Dark", "AppIcon-Tinted"]

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("render-icon: \(message)\n".utf8))
        exit(1)
    }

    static func color(_ hex: String) -> CGColor {
        let c = IconSpec.rgb(hex)
        return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    static func loadFont(size: Double) -> CTFont {
        guard FileManager.default.fileExists(atPath: IconSpec.fontFile) else {
            fail("\(IconSpec.fontFile) is missing: run make fonts (the icon is never drawn in another face)")
        }
        let url = URL(fileURLWithPath: IconSpec.fontFile)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first
        else { fail("cannot read a font from \(IconSpec.fontFile)") }
        let font = CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil)
        let name = CTFontCopyPostScriptName(font) as String
        guard name == IconSpec.fontPostScriptName else {
            fail("\(IconSpec.fontFile) is \(name), expected \(IconSpec.fontPostScriptName)")
        }
        return font
    }

    static func main() {
        var dir = "Ryft/Assets.xcassets/AppIcon.appiconset"
        var previews: String?
        var args = Array(CommandLine.arguments.dropFirst())
        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--previews":
                guard let value = args.first else { fail("--previews needs a folder") }
                args.removeFirst()
                previews = value
            default:
                if arg.hasPrefix("-") { fail("unknown option \(arg)") }
                dir = arg
            }
        }

        let tileHex = IconSpec.catalogHex(IconSpec.tileColorset)
        let wordHex = IconSpec.catalogHex(IconSpec.wordColorset)
        let ratio = IconSpec.contrast(wordHex, tileHex)
        print(String(format: "word %@ on tile %@: %.2f:1", wordHex, tileHex, ratio))
        guard ratio >= IconSpec.minContrast else { fail("the word is under \(IconSpec.minContrast):1 on the tile") }

        let image = render(tile: tileHex, word: wordHex)
        for name in names {
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
            write(image, to: url)
            print("wrote \(url.path) (\(image.width)x\(image.height), no alpha)")
        }
        if let previews {
            try? FileManager.default.createDirectory(atPath: previews, withIntermediateDirectories: true)
            for size in IconSpec.previewSizes {
                let url = URL(fileURLWithPath: previews).appendingPathComponent("AppIcon-\(size).png")
                write(scaled(image, to: size), to: url)
                print("wrote \(url.path) (\(size)x\(size))")
            }
        }
    }

    static func context(side: Int) -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { fail("cannot create a bitmap context") }
        return ctx
    }

    /// An opaque bitmap (App Store icons must not have an alpha channel), y pointing up as CoreText draws.
    static func render(tile tileHex: String, word wordHex: String) -> CGImage {
        let side = Int(IconSpec.tile)
        let size = IconSpec.fontSize
        let font = loadFont(size: size)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): size * IconSpec.trackingEm,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(wordHex),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: IconSpec.word, attributes: attributes))

        let ctx = context(side: side)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)
        // Plain grey-scale edges: font smoothing would embolden the Light strokes.
        ctx.setAllowsFontSmoothing(false)
        ctx.setShouldSmoothFonts(false)
        ctx.setFillColor(color(tileHex))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))

        let ink = CTLineGetImageBounds(line, ctx)
        let cap = Double(CTFontGetCapHeight(font))
        let x = Double(side) / 2 - Double(ink.midX)
        let baseline = Double(side) / 2 - cap / 2
        ctx.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, ctx)

        let left = x + Double(ink.minX), right = Double(side) - (x + Double(ink.maxX))
        let bottom = baseline + Double(ink.minY), top = Double(side) - (baseline + Double(ink.maxY))
        print(String(format: "font %@ %.1f px (%.2f%% of the tile), tracking %.2f em, cap height %.1f px",
                     IconSpec.fontPostScriptName, size, 100 * size / IconSpec.tile, IconSpec.trackingEm, cap))
        print(String(format: "ink margins: left %.1f, right %.1f, top %.1f, bottom %.1f px (ink %.1f x %.1f px)",
                     left, right, top, bottom, ink.width, ink.height))
        guard abs(left - right) <= 1, abs(top - bottom) <= 1 else {
            fail("the word is off-centre: left \(left) / right \(right), top \(top) / bottom \(bottom) px")
        }
        guard let image = ctx.makeImage() else { fail("render failed") }
        return image
    }

    /// The icon scaled to `side` px with high-quality interpolation (what the Home Screen shows at 60 pt and below).
    static func scaled(_ image: CGImage, to side: Int) -> CGImage {
        let ctx = context(side: side)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let out = ctx.makeImage() else { fail("scaling to \(side) px failed") }
        return out
    }

    static func write(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fail("cannot write \(url.path)")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { fail("cannot finalise \(url.path)") }
        // Read it back: the store rejects icons with an alpha channel.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let written = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { fail("cannot read back \(url.path)") }
        let opaque: Set<CGImageAlphaInfo> = [.none, .noneSkipLast, .noneSkipFirst]
        guard written.width == image.width, written.height == image.height, opaque.contains(written.alphaInfo) else {
            fail("\(url.path) is \(written.width)x\(written.height), alpha \(written.alphaInfo.rawValue)")
        }
    }
}
