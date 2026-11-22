import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// What a disabled `RyftToggleStyle` dims. By default the whole row goes to 35 %, as every disabled toggle in the app does.
/// With `dimsLabel: false` only the track dims, and the label stays at full ink, for a held switch whose label says why
/// (Profile's Demo data while a consent withdrawal is on its way, D6). Hosted and read from the drawn pixels.
@MainActor
@Suite("RyftToggleStyle: what a disabled toggle dims")
struct RyftToggleDimTests {
    /// The style under test: the app's (`.ryft`, what every toggle gets from the root) or one that keeps its label.
    enum Look: String, CaseIterable, Sendable { case app, labelKept }

    private struct Board: View {
        let look: Look

        var body: some View {
            Toggle(isOn: .constant(false)) {
                Text(verbatim: "Demo data").font(.ryft(.callout)).foregroundStyle(Theme.textPrimary)
            }
            .toggleStyle(look == .app ? .ryft : RyftToggleStyle(dimsLabel: false))
            .disabled(true)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background)
        }
    }

    /// On `background` (#0A0C0B): the `textPrimary` label 0.95, 0.36 at 35 %; the off track (`textTertiary`) 0.48, 0.19 at 35 %.
    @Test("Disabled: the whole row at 35 % with the app's style; with dimsLabel false the track alone, the label at full ink",
          arguments: Look.allCases)
    func dims(_ look: Look) async throws {
        try await HostedWindow.run(width: 390, height: 300, Board(look: look)) { w in
            try await w.settle()
            let node = try #require(w.node("Demo data", exactly: true))
            #expect(!node.isEnabled, "disabled either way")
            let pixels = try WindowPixels(w, scale: 2)
            let row = node.frame, size = RyftToggleStyle.trackSize
            let track = CGRect(x: row.maxX - size.width, y: row.midY - size.height / 2, width: size.width, height: size.height)
            let label = CGRect(x: row.minX, y: row.minY, width: row.width - size.width - RyftToggleStyle.labelSpacing,
                               height: row.height)
            let labelInk = pixels.brightest(in: label), trackInk = pixels.brightest(in: track)
            if look == .app {
                #expect(labelInk > 0.2 && labelInk < 0.45, "the label dimmed with the row: \(labelInk)")
            } else {
                #expect(labelInk > 0.85, "the label at full ink: \(labelInk)")
            }
            #expect(trackInk > 0.1 && trackInk < 0.3, "the track dimmed: \(trackInk)")
        }
    }
}
