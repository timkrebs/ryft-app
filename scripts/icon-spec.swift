// The app icon "M1" (docs/work/2026-11-16-nocturne/brief.md §1): "RYFT" in Satoshi Light on the near-black tile, no
// mark. The tile, the word and its numbers live here; scripts/render-icon.swift (`make icon`) draws them into the PNGs
// in the asset catalog. The colours are read from the catalog so the icon can't drift from the app.
//
// The mock-up was a 220 px tile with the word at 60 px, letter-spacing 0.02 em and a left padding of 0.02 em (which
// cancels the tracking after the last letter, so the word sits centred). Everything below is that mock-up scaled to 1024.
import Foundation

enum IconSpec {
    /// The App Store icon tile, px.
    static let tile = 1024.0

    static let word = "RYFT"

    /// The face. The font files are git-ignored (`make fonts`); the renderer never falls back to another face.
    static let fontFile = "Ryft/Resources/Fonts/Satoshi-Light.otf"
    static let fontPostScriptName = "Satoshi-Light"

    /// Font size / tile edge: 60 px on the mock-up's 220 px tile, i.e. 27.27 %, 279.3 px on 1024.
    static let sizeRatio = 60.0 / 220.0
    static var fontSize: Double { tile * sizeRatio }

    /// Letter-spacing in em (the mock-up's 0.02 em), added after every letter. The renderer centres the ink, which
    /// is what the mock-up's equal left padding did: the trailing space does not pull the word to the left.
    static let trackingEm = 0.02

    /// The colours, by colour set in the catalog: the tile is `Background`, the word `TextPrimary`.
    static let catalog = "Ryft/Assets.xcassets"
    static let tileColorset = "Background"
    static let wordColorset = "TextPrimary"

    /// sRGB components 0...1 of a six-digit hex colour.
    static func rgb(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let v = UInt32(hex, radix: 16) ?? 0
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// A colour set's hex ("0A0C0B"), read from its Contents.json. Run from the repo root (the Makefile does). The
    /// app is dark-only, so a colour set has exactly one value; an icon must be opaque, so its alpha must be 1.
    static func catalogHex(_ name: String) -> String {
        let url = URL(fileURLWithPath: "\(catalog)/\(name).colorset/Contents.json")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let colors = root["colors"] as? [[String: Any]]
        else { fatalError("icon-spec: cannot read \(url.path)") }
        guard colors.count == 1, colors[0]["appearances"] == nil else {
            fatalError("icon-spec: \(url.path) must carry one value without appearances (the app is dark-only)")
        }
        guard let comps = (colors[0]["color"] as? [String: Any])?["components"] as? [String: String] else {
            fatalError("icon-spec: no components in \(url.path)")
        }
        guard Double(comps["alpha"] ?? "") == 1 else { fatalError("icon-spec: \(name) is not opaque") }
        func byte(_ key: String) -> String {
            let v = Int((comps[key] ?? "0").dropFirst(2), radix: 16) ?? 0
            return String(format: "%02X", v)
        }
        return byte("red") + byte("green") + byte("blue")
    }

    /// WCAG contrast ratio of two hex colours.
    static func contrast(_ a: String, _ b: String) -> Double {
        func lum(_ hex: String) -> Double {
            let c = rgb(hex)
            func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
        }
        let (x, y) = (lum(a), lum(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// The word is text on the tile: 4.5:1.
    static let minContrast = 4.5

    /// Sizes (px) the renderer also scales the icon to for review, into the previews folder: 180 px is 60 pt at 3x
    /// (the Home Screen), 60 px and 40 px the small sizes where the word has to stay legible.
    static let previewSizes = [180, 120, 60, 40]
}
