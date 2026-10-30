import SwiftUI
import Testing
import CoreImage
import UIKit
@testable import Ryft

/// Writes the gauge's screenshots (light and dark) when `ORBIT_SHOTS_DIR` is set; otherwise does nothing.
/// `make orbit-shots` runs it. The images are for the design note, not a golden-file test.
@MainActor
@Suite struct OrbitGaugeShotsTests {
    private func write<V: View>(_ name: String, scheme: ColorScheme, dir: String, @ViewBuilder _ content: () -> V) {
        let view = content()
            .padding(20)
            .background(Theme.background)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let image = renderer.uiImage, let data = image.pngData() else { return }
        try? data.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(scheme == .dark ? "dark" : "light").png"))
        // Colour-vision simulation (Machado et al. 2009, severity 1.0) of the shots that show the three orbits.
        if name == "large" || name == "sizes" {
            for (kind, m) in Self.deficiencies {
                if let out = Self.simulate(image, matrix: m)?.pngData() {
                    try? out.write(to: URL(fileURLWithPath: "\(dir)/\(name)-\(kind)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
    }

    /// Rows of the 3 x 3 matrix applied to (r, g, b).
    private static let deficiencies: [(String, [CGFloat])] = [
        ("protanopia", [0.152286, 1.052583, -0.204868, 0.114503, 0.786281, 0.099216, -0.003882, -0.048116, 1.051998]),
        ("deuteranopia", [0.367322, 0.860646, -0.227968, 0.280085, 0.672501, 0.047413, -0.011820, 0.042940, 0.968881]),
        ("tritanopia", [1.255528, -0.076749, -0.178779, -0.078411, 0.930809, 0.147602, 0.004733, 0.691367, 0.303900]),
    ]

    private static func simulate(_ image: UIImage, matrix m: [CGFloat]) -> UIImage? {
        guard let input = CIImage(image: image), let filter = CIFilter(name: "CIColorMatrix") else { return nil }
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: m[0], y: m[1], z: m[2], w: 0), forKey: "inputRVector")
        filter.setValue(CIVector(x: m[3], y: m[4], z: m[5], w: 0), forKey: "inputGVector")
        filter.setValue(CIVector(x: m[6], y: m[7], z: m[8], w: 0), forKey: "inputBVector")
        guard let output = filter.outputImage, let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.ryft(.caption)).foregroundStyle(Theme.textSecondary)
    }

    @Test func writeShots() throws {
        guard let dir = ProcessInfo.processInfo.environment["ORBIT_SHOTS_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.dark, .light] {
            write("sizes", scheme: scheme, dir: dir) {
                HStack(alignment: .center, spacing: 16) {
                    OrbitGauge(mode: .scored(.previewScored), size: .large)
                    OrbitGauge(mode: .scored(.previewScored), size: .medium)
                    OrbitGauge(mode: .scored(.previewScored), size: .small)
                }
            }
            write("large", scheme: scheme, dir: dir) { OrbitGauge(mode: .scored(.previewScored), size: .large) }
            write("states", scheme: scheme, dir: dir) {
                HStack(spacing: 8) {
                    VStack { OrbitGauge(mode: .scored(OrbitGaugeValues()), size: .medium); caption("all missing") }
                    VStack {
                        OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, strain: 6.2)), size: .medium)
                        caption("sleep missing")
                    }
                    VStack {
                        OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 0, recovery: 0, sleep: 0, strain: 0)), size: .medium)
                        caption("0")
                    }
                    VStack {
                        OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 100, recovery: 1, sleep: 1, strain: 21)), size: .medium)
                        caption("100")
                    }
                }
            }
            write("bands", scheme: scheme, dir: dir) {
                HStack(spacing: 8) {
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 82, recovery: 0.8, sleep: 0.9, strain: 12)), size: .medium)
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 50, recovery: 0.5, sleep: 0.7, strain: 12)), size: .medium)
                    OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 20, recovery: 0.2, sleep: 0.3, strain: 12)), size: .medium)
                }
            }
            write("stubs", scheme: scheme, dir: dir) {
                HStack(spacing: 8) {
                    OrbitGauge(mode: .calibrating(OrbitGaugeCalibration(nights: 3)), size: .medium)
                    OrbitGauge(mode: .assembling, size: .medium)
                    OrbitGauge(mode: .pending(previous: .previewScored), size: .medium)
                }
            }
            // The 44 pt check: the app icon's tile (mark on Graphite / Mist, as scripts/icon-spec.swift) beside the
            // gauge at 44 pt and at 88 pt, and the icon at both.
            write("icon-44", scheme: scheme, dir: dir) {
                let tile = { (side: CGFloat) in
                    RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                        .strokeBorder(Theme.separator, lineWidth: 0.5)
                        .background(RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                            .fill(scheme == .dark ? Theme.graphite : Theme.mist))
                        .frame(width: side, height: side)
                        .overlay(RyftMark().foregroundStyle(scheme == .dark ? Theme.mist : Theme.graphite)
                            .frame(width: side * 0.963 / 0.9116, height: side * 0.963 / 0.9116))
                }
                VStack(spacing: 14) {
                    HStack(spacing: 20) {
                        tile(44)
                        OrbitGauge(mode: .scored(.previewScored), size: .custom(dial: 44)).frame(width: 44, height: 44)
                        OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, sleep: 0.55, strain: 14)),
                                   size: .custom(dial: 44)).frame(width: 44, height: 44)
                    }
                    HStack(spacing: 20) {
                        tile(88)
                        OrbitGauge(mode: .scored(.previewScored), size: .custom(dial: 88)).frame(width: 88, height: 88)
                        OrbitGauge(mode: .scored(OrbitGaugeValues(readiness: 64, recovery: 0.62, sleep: 0.55, strain: 14)),
                                   size: .custom(dial: 88)).frame(width: 88, height: 88)
                    }
                }
            }
        }
    }
}
