import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// `DeltaLabel` laid out in a window (T5.8, the PR 5 fix round): the gap between the change and "vs 7 d" grows with Dynamic
/// Type as a word space does (N6: at AX3 "Steady vs 7 d" on Strain read as one word), and the stacked form Sleep's range uses
/// from AX1 (S1) keeps the change, then "vs 7 d", inside the width it is given.
@MainActor
@Suite("DeltaLabel: hosted layout", .serialized)
struct DeltaLabelLayoutTests {
    private static let flat = MetricDelta(current: 12.4, reference: 12.3)

    /// The label's width less its two parts' widths, each drawn on its own in the same font: the gap between them.
    private func gap(_ typeSize: DynamicTypeSize, _ category: UIContentSizeCategory) async throws -> CGFloat {
        let font = Font.ryft(.label)
        let reference = DeltaLabel.sevenDayReference
        let change = DeltaLabel.text(Self.flat, spec: .strain)
        let page = VStack(alignment: .leading, spacing: 20) {
            DeltaLabel(spec: .strain, delta: Self.flat, reference: reference, font: font)
                .fixedSize()
                .accessibilityIdentifier("label")
            Text(verbatim: change).font(font).monospacedDigit().fixedSize().accessibilityIdentifier("change")
            Text(verbatim: reference).font(font).fixedSize().accessibilityIdentifier("reference")
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        var gap = CGFloat.nan
        try await HostedWindow.run(width: 600, height: 600, bottomInset: 0, typeSize: typeSize, category: category, page) { w in
            try await w.wait("the label and its parts") { w.nodes().count >= 3 }
            try await w.settle()
            let nodes = w.nodes()
            var widths: [String: CGFloat] = [:]
            for id in ["label", "change", "reference"] {
                widths[id] = try #require(nodes.first { $0.identifier == id }, "\(id)").frame.width
            }
            gap = (widths["label"] ?? 0) - (widths["change"] ?? 0) - (widths["reference"] ?? 0)
        }
        return gap
    }

    @Test("N6: the gap is 4 at the default size and grows with the text (a word space at AX3 and AX5, not 4 pt)")
    func theGapScales() async throws {
        let regular = try await gap(.large, .large)
        #expect(abs(regular - DeltaLabel.referenceGap) < 0.5, "default \(regular)")
        for (typeSize, category) in [(DynamicTypeSize.accessibility3, UIContentSizeCategory.accessibilityExtraLarge),
                                     (.accessibility5, .accessibilityExtraExtraExtraLarge)] {
            let large = try await gap(typeSize, category)
            let scaled = UIFontMetrics(forTextStyle: .caption1)
                .scaledValue(for: DeltaLabel.referenceGap, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
            #expect(scaled > 2 * DeltaLabel.referenceGap, "\(typeSize): the metric \(scaled)")
            #expect(abs(large - scaled) < 0.5, "\(typeSize): \(large), the scaled 4 \(scaled)")
        }
    }

    @Test("S1: stacked at AX5, the change and then \"vs 7 d\" on a line of its own, inside the column, one element")
    func stackedStaysInside() async throws {
        let delta = MetricDelta(current: 466, reference: 478)
        let page = VStack {
            DeltaLabel(spec: .sleepMin, delta: delta, reference: DeltaLabel.sevenDayReference, stacked: true)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("stacked")
                .frame(maxWidth: .infinity)
            DeltaLabel(spec: .sleepMin, delta: delta, reference: DeltaLabel.sevenDayReference)
                .fixedSize()
                .accessibilityIdentifier("oneLine")
            Text(verbatim: DeltaLabel.text(delta, spec: .sleepMin)).font(.ryft(.caption)).monospacedDigit().fixedSize()
                .accessibilityIdentifier("change")
        }
        .frame(width: 362)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        try await HostedWindow.run(width: 402, height: 900, bottomInset: 0, typeSize: .accessibility5,
                                   category: .accessibilityExtraExtraExtraLarge, page) { w in
            try await w.wait("both labels and the change") { w.nodes().count >= 3 }
            try await w.settle()
            let stacked = try #require(w.nodes().first { $0.identifier == "stacked" }, "stacked")
            let oneLine = try #require(w.nodes().first { $0.identifier == "oneLine" }, "oneLine")
            let change = try #require(w.nodes().first { $0.identifier == "change" }, "change")
            // The one-line form is wider than the column at AX5 (399 against 362): the reason for the stacked form.
            #expect(oneLine.frame.width > 362, "one line \(oneLine.frame)")
            #expect(stacked.frame.width <= 362 + 0.5 && stacked.frame.minX >= 20 - 0.5, "stacked \(stacked.frame)")
            #expect(stacked.frame.height > 1.5 * oneLine.frame.height, "two lines: \(stacked.frame) / \(oneLine.frame)")
            // "vs 7 d" has its own line under the change: the label is as wide as the change, the widest line. Beside it,
            // squeezed into what the change leaves, it broke into "vs" over "7 d" and the label took the column.
            #expect(stacked.frame.width <= change.frame.width + 0.5, "stacked \(stacked.frame), the change \(change.frame)")
            #expect(stacked.label == DeltaLabel.spoken(delta, spec: .sleepMin, reference: DeltaLabel.sevenDayReference))
        }
    }
}
