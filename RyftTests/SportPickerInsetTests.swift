import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// R2 V1 S3 (PR 6 B §1.2): the Sport picker is pushed inside the Add activity sheet, so its header starts where the sheet's
/// own header does, 26 under the sheet's top edge (14 under the grabber), not against the grabber. Measured on the
/// presented sheet, from its top edge on screen to the Back circle's 40 pt circle (its 44 pt box reaches 2 above).
@MainActor
@Suite("R2 V1: the Sport picker's header under the grabber", .serialized)
struct SportPickerInsetTests {
    private struct Picker: View {
        @State private var sport = Sport.running

        var body: some View {
            NavigationStack { SportPicker(selection: $sport, recents: [.running, .cycling]) }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Theme.background)
                .presentedRoot()
        }
    }

    @Test("The header starts 26 under the sheet's edge, at the default size and at AX3",
          arguments: [(DynamicTypeSize.large, UIContentSizeCategory.large), (.accessibility3, .accessibilityExtraLarge)])
    func headerInset(_ size: DynamicTypeSize, _ category: UIContentSizeCategory) async throws {
        try await HostedWindow.run(width: 402, height: 874, typeSize: size, category: category, SheetHost { Picker() }) { w in
            try await w.wait("the picker") { w.presentedNodes()?.contains { $0.identifier == "sportPicker.back" } == true }
            try await w.settle()
            let sheet = try #require(w.host.presentedViewController?.view)
            let edge = sheet.convert(sheet.bounds, to: nil)
            // A presented sheet can be drawn scaled; the spec's points are the sheet's own.
            let scale = edge.width / sheet.bounds.width
            let back = try #require(w.presentedNodes()?.first { $0.identifier == "sportPicker.back" })
            let inset = (back.frame.minY - edge.minY) / scale
            #expect(abs(inset - (SheetHeaderSpec.topInset - ScreenHeaderSpec.buttonOverhang)) < 1,
                    "Back's box \(inset) under the sheet's edge (\(back.frame), sheet \(edge))")
        }
    }
}
