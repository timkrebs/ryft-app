// Renders the RYFT app icons (1024 x 1024 PNG, no alpha) from the app's own RyftMarkShape
// path, filled with Core Graphics into an opaque sRGB bitmap.
//
// Compiled together with scripts/icon-spec.swift and Ryft/Design/RyftMark.swift so the icon
// and the in-app mark can never drift apart; `make icon` builds and runs it:
//
//   .build/render-icon [--ring-span <x>] [--suffix <s>] [dir]
//
//   --ring-span  the outer ring's span (outer edge to outer edge) / tile width; default
//                IconSpec.defaultRingSpan (0.915, 95 % of the reference's 0.963)
//   --suffix     appended to each file name, e.g. "-0.80" -> AppIcon-Light-0.80.png
//   --dots       (comparison) monochrome rings, gauge-coloured dots only
//   --mono       the mark in one colour (Graphite on Mist, Mist on Graphite) instead of the gauge colours
//   dir          default Ryft/Assets.xcassets/AppIcon.appiconset
//
// Writes AppIcon-Light (the default appearance: the mark in the gauge's light colours on Mist),
// AppIcon-Dark (its dark colours on Graphite) and AppIcon-Tinted (white on black, monochrome: the
// grayscale source iOS tints). The part colours come from the asset catalog (IconSpec). Run from
// the repo root. Exits 1 if a dot would leave the tile, a colour is under 3:1 on its tile, or a
// written PNG has an alpha channel.
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@main
struct RenderIcon {
    struct Variant {
        let name: String
        let background: CGColor
        /// The colour of each part of the mark.
        let mark: (RyftMarkGeometry.Part) -> CGColor
        /// Background and mark hex, for the contrast report; nil = tinted (no check).
        let hexes: (background: String, mark: (RyftMarkGeometry.Part) -> String)?
    }

    static func color(_ hex: String) -> CGColor {
        let c = IconSpec.rgb(hex)
        return CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }

    static func variants(mono: Bool, dotsOnly: Bool = false) -> [Variant] {
        func variant(_ name: String, background: String, mark: String, dark: Bool) -> Variant {
            let dots: Set<RyftMarkGeometry.Part> = [.strainDot, .sleepDot, .recoveryDot]
            let hex: (RyftMarkGeometry.Part) -> String = {
                (mono || (dotsOnly && !dots.contains($0))) ? mark : IconSpec.partHex($0, dark: dark)
            }
            return Variant(name: name, background: color(background), mark: { color(hex($0)) },
                           hexes: (background, hex))
        }
        return [
            variant("AppIcon-Light", background: IconSpec.mistHex, mark: IconSpec.graphiteHex, dark: false),
            variant("AppIcon-Dark", background: IconSpec.graphiteHex, mark: IconSpec.mistHex, dark: true),
            Variant(name: "AppIcon-Tinted", background: color("000000"), mark: { _ in color("FFFFFF") }, hexes: nil),
        ]
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("render-icon: \(message)\n".utf8))
        exit(1)
    }

    static func main() {
        var ringSpan = IconSpec.defaultRingSpan
        var suffix = ""
        var mono = false
        var dotsOnly = false
        var dir = "Ryft/Assets.xcassets/AppIcon.appiconset"
        var args = Array(CommandLine.arguments.dropFirst())
        while !args.isEmpty {
            let arg = args.removeFirst()
            switch arg {
            case "--ring-span":
                guard let value = args.first.flatMap(Double.init), value > 0, value <= 1 else {
                    fail("--ring-span needs a number in (0, 1]")
                }
                args.removeFirst()
                ringSpan = value
            case "--dots":
                dotsOnly = true
            case "--mono":
                mono = true
            case "--suffix":
                guard let value = args.first else { fail("--suffix needs a value") }
                args.removeFirst()
                suffix = value
            default:
                if arg.hasPrefix("-") { fail("unknown option \(arg)") }
                dir = arg
            }
        }

        let tile = IconSpec.tile
        let frame = IconSpec.markFrame(ringSpan: ringSpan)
        // The span maths uses the nominal stroke; make sure the optical rule really is off.
        guard RyftMarkGeometry.metrics(forSide: frame).stroke == RyftMarkGeometry.stroke else {
            fail("mark frame \(frame) px is in the optical-size range")
        }
        let margin = IconSpec.dotMargin(ringSpan: ringSpan)
        let ringMargin = (tile - tile * ringSpan) / 2
        print(String(format: "ring span %.3f: mark frame %.2f px, ring margin %.2f px, dot margin %.2f px",
                     ringSpan, frame, ringMargin, margin))
        guard margin >= 0 else { fail("a dot leaves the tile by \(-margin) px") }

        let rect = CGRect(x: (tile - frame) / 2, y: (tile - frame) / 2, width: frame, height: frame)
        let paths = RyftMarkGeometry.Part.allCases.map { ($0, RyftMarkShape(part: $0).path(in: rect).cgPath) }
        for v in variants(mono: mono, dotsOnly: dotsOnly) {
            if let h = v.hexes {
                for part in RyftMarkGeometry.Part.allCases {
                    let ratio = IconSpec.contrast(h.mark(part), h.background)
                    print(String(format: "  %@ %@ %@ on %@: %.2f:1", v.name, "\(part)", h.mark(part), h.background, ratio))
                    guard ratio >= IconSpec.minContrast else { fail("\(part) is under 3:1 on the \(v.name) tile") }
                }
            }
            let url = URL(fileURLWithPath: dir).appendingPathComponent("\(v.name)\(suffix).png")
            write(render(paths, variant: v, side: Int(tile)), to: url)
            print("wrote \(url.path) (\(Int(tile))x\(Int(tile)), no alpha)")
        }
    }

    /// An opaque bitmap (App Store icons must not have an alpha channel), y pointing down like
    /// SwiftUI so the mark keeps its handedness.
    static func render(_ paths: [(RyftMarkGeometry.Part, CGPath)], variant v: Variant, side: Int) -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { fail("cannot create a bitmap context") }
        ctx.setShouldAntialias(true)
        ctx.setFillColor(v.background)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        ctx.translateBy(x: 0, y: CGFloat(side))
        ctx.scaleBy(x: 1, y: -1)
        for (part, path) in paths {
            ctx.addPath(path)
            ctx.setFillColor(v.mark(part))
            ctx.fillPath(using: .winding)
        }
        guard let image = ctx.makeImage() else { fail("render failed for \(v.name)") }
        return image
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
