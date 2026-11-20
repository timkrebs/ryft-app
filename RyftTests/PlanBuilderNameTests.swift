import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// R2 V1 S4 (PR 6 B §6.3, §12 "rows grow, never truncate"): the plan builder's Name wraps at large sizes instead of ending
/// in "…", and Return still ends editing without putting a line break into the name.
@MainActor
@Suite("R2 V1: the plan builder's name wraps", .serialized)
struct PlanBuilderNameTests {
    @Test("Return in the name: the break goes, the rest stays; a pasted break becomes a space; no break, no change")
    func nameOnOneLine() {
        #expect(PlanBuilderRules.nameOnOneLine("Upper/Lower 4×\n") == "Upper/Lower 4×")
        #expect(PlanBuilderRules.nameOnOneLine("Upper\nLower") == "Upper Lower")
        #expect(PlanBuilderRules.nameOnOneLine("Upper\r\n\nLower") == "Upper Lower")
        #expect(PlanBuilderRules.nameOnOneLine("Upper/Lower 4× (copy)") == nil)
        #expect(PlanBuilderRules.nameOnOneLine("") == nil)
        // A Return on an empty field leaves it empty: "Give the plan a name." still holds Save.
        #expect(PlanBuilderRules.nameOnOneLine("\n") == "")
        #expect(PlanValidation.issues(in: Plan.blank()).contains(.missingName))
    }

    /// What `text` needs in the field's font at `width`, at AX3: the field's 22 Light, scaled as `.title2`.
    private func needs(_ text: String, width: CGFloat) -> CGFloat {
        let ax3 = UITraitCollection(preferredContentSizeCategory: .accessibilityExtraLarge)
        let size = UIFontMetrics(forTextStyle: .title2).scaledValue(for: FormFieldSpec.largeValueSize, compatibleWith: ax3)
        let view = Text(verbatim: text).font(.ryftNumber(size: size, weight: .light))
            .environment(\.dynamicTypeSize, .accessibility3)
        return UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 10_000)).height
    }

    /// The text view in the window that holds `text`: a one-line field (`UITextField`) or a wrapping one (`UITextView`).
    private func field(holding text: String, in w: HostedWindow) -> UIView? {
        func find(_ view: UIView) -> UIView? {
            if let f = view as? UITextField, f.text == text { return f }
            if let t = view as? UITextView, t.text == text { return t }
            for sub in view.subviews { if let hit = find(sub) { return hit } }
            return nil
        }
        return find(w.window)
    }

    @Test("At AX3 a long name takes the lines it needs, whole")
    func wrapsAtAX3() async throws {
        let plan = MockTrain.upperLower.copy()
        try await HostedWindow.run(width: 402, height: 874, bottomInset: 0, typeSize: .accessibility3,
                                   category: .accessibilityExtraLarge, PlanBuilderView(plan: plan)) { w in
            try await w.settle()
            let field = try #require(field(holding: plan.name, in: w), "the name's field")
            let whole = needs(plan.name, width: field.bounds.width)
            let oneLine = needs("U", width: field.bounds.width)
            #expect(whole > oneLine * 1.5, "the name is longer than a line here: \(whole) vs \(oneLine)")
            #expect(field.bounds.height >= whole - 1,
                    "\(type(of: field)) \(field.bounds.height) tall; the name needs \(whole) at \(field.bounds.width)")
        }
    }
}
