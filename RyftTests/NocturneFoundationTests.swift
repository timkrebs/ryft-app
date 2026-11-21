import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// T6.0's numbers and decisions without a window (docs/work/2026-11-16-nocturne/build-plan.md §2): the subpage, sheet header,
/// field, chip, stepper and legend specs; the stepper's arithmetic and spoken value; the legend mark's geometry; the step
/// rule's inks; the sheet header's centring; no teal left in the restyled parts; and the contrast each new look relies on.
/// A change to any number here is a design decision, not an accident.
@MainActor
@Suite("Nocturne foundation: specs and decisions")
struct NocturneFoundationTests {
    private typealias Tokens = NocturneTokenTests
    private typealias RGBA = NocturneTokenTests.RGBA

    // MARK: specs

    @Test("The subpage frame: a 40 pt header, 22 to the content, 20 at the sides, sheets 26 down, the `subpage` identifiers")
    func subpageNumbers() {
        #expect(SubpageSpec.headerHeight == 40 && SubpageSpec.contentGap == 22 && SubpageSpec.identifierPrefix == "subpage")
        #expect(SubpageSpec.sidePadding == 20 && SubpageSpec.bottomPadding == 32 && SubpageSpec.maxContentWidth == 560)
        #expect(SubpageSpec.sheetTopInset == 26 && SubpageSpec.trailingSpacing == 8 && SubpageSpec.stackedGap == 12)
        #expect(PinnedBarSpec.topPadding == 12 && PinnedBarSpec.sidePadding == 20 && PinnedBarSpec.bottomPadding == 12)
        #expect(SheetHeaderSpec.height == 40 && SheetHeaderSpec.topInset == 26 && SheetHeaderSpec.sidePadding == 20)
    }

    @Test("A field row is 56 with a 2 × 28 focus bar 6 in; a chip is 36; a stepper row 56 with a 22 pt value")
    func fieldAndStepperNumbers() {
        #expect(FormFieldSpec.minHeight == 56 && FormFieldSpec.focusBar == CGSize(width: 2, height: 28))
        #expect(FormFieldSpec.focusInset == 6 && FormFieldSpec.horizontalPadding == 16 && FormFieldSpec.largeValueSize == 22)
        #expect(ValueChipSpec.height == 36 && ValueChipSpec.horizontalPadding == 14)
        #expect(RyftStepperSpec.valueSize == 22 && RyftStepperSpec.rowMinHeight == 56 && RyftStepperSpec.heroSpacing == 18)
    }

    @Test("Cards, banners and tiles share the grouped card's radius 22; a card is 16 inside")
    func radii() {
        #expect(CardSpec.radius == 22 && CardSpec.padding == 16)
        #expect(InlineMessageSpec.radius == 22 && InlineMessageSpec.topPadding == 14 && InlineMessageSpec.horizontalPadding == 16)
        #expect(InlineMessageSpec.glyphSize == 16 && InlineMessageSpec.buttonSpacing == 18)
        #expect(SelectableTileSpec.radius == 22 && SelectableTileSpec.minHeight == 56 && SelectableTileSpec.borderWidth == 1.5)
        #expect(GroupedListSpec.cardRadius == CardSpec.radius)
        #expect(NumberedStepSpec.badge == 22 && NumberedStepSpec.strokeWidth == 1)
    }

    // MARK: the stepper

    @Test("A step moves by the step and stops at the ends", arguments: [
        (4, 1, 1, 1...7, 5), (7, 1, 1, 1...7, 7), (1, -1, 1, 1...7, 1), (465, -1, 15, 240...720, 450), (715, 1, 15, 240...720, 720),
        (3, 5, 1, 1...7, 4),
    ])
    func stepping(_ value: Int, _ direction: Int, _ step: Int, _ range: ClosedRange<Int>, _ expected: Int) {
        #expect(RyftStepperSpec.stepped(value, direction: direction, step: step, in: range) == expected)
    }

    @Test("VoiceOver hears the value, and at either end that it is the end")
    func spokenValue() {
        #expect(RyftStepperSpec.spokenValue("4", canDecrement: true, canIncrement: true) == "4")
        #expect(RyftStepperSpec.spokenValue("1", canDecrement: false, canIncrement: true) == "1, minimum")
        #expect(RyftStepperSpec.spokenValue("7", canDecrement: true, canIncrement: false) == "7, maximum")
    }

    @Test("A bound Int: the text by its format, its ends, and a step written back")
    func boundValue() {
        var stored = 240
        let binding = Binding(get: { stored }, set: { stored = $0 })
        let value = RyftStepperValue(binding, in: 240...720, step: 15, format: { "\($0 / 60):\(String(format: "%02d", $0 % 60))" })
        #expect(value.text == "4:00" && !value.canDecrement && value.canIncrement)
        #expect(value.accessibilityValue == "4:00, minimum")
        value.step(1)
        #expect(stored == 255)
        value.step(-1)
        value.step(-1)
        #expect(stored == 240, "never under the range")
        let spoken = RyftStepperValue(text: "3:00", spoken: "3 minutes", canDecrement: true, canIncrement: true) { _ in }
        #expect(spoken.accessibilityValue == "3 minutes")
    }

    // MARK: the legend mark

    @Test("The legend ring: the dot's ring touches the frame; the arc ends 62 % round from 12 o'clock")
    func legendGeometry() {
        #expect(LegendMarkSpec.side == 28 && LegendMarkSpec.maxSide == 44 && LegendMarkSpec.fraction == 0.62)
        let radius = LegendMarkSpec.radius(side: 28)
        #expect(abs(radius - 9) < 0.001, "14 less the dot (3.5) and its ring (1.5)")
        #expect(abs(LegendMarkSpec.radius(side: 44) - 44.0 / 28 * 9) < 0.001, "the dot scales with the mark")
        let centre = CGPoint(x: 14, y: 14)
        let top = LegendMarkSpec.endPoint(centre: centre, radius: 9, fraction: 0)
        #expect(abs(top.x - 14) < 0.001 && abs(top.y - 5) < 0.001, "0 is 12 o'clock")
        let quarter = LegendMarkSpec.endPoint(centre: centre, radius: 9, fraction: 0.25)
        #expect(abs(quarter.x - 23) < 0.001 && abs(quarter.y - 14) < 0.001, "a quarter is 3 o'clock: clockwise")
        let end = LegendMarkSpec.endPoint(centre: centre, radius: 9)
        #expect(end.x < 14 && end.y > 14, "62 % ends in the lower left")
    }

    // MARK: the step rule

    @Test("The step rule: done at 55 %, the current step in full, the rest at the track's 16 %")
    func stepRule() {
        #expect([1, 2, 3, 4, 5, 6].map { StepRuleSpec.opacity(index: $0, step: 3) } == [0.55, 0.55, 1, 0.16, 0.16, 0.16])
        #expect(StepRuleSpec.height == 3 && StepRuleSpec.spacing == 4)
    }

    // MARK: the sheet header

    @Test("The sheet header's title gets the width between the wider slot on both sides, so it stays centred")
    func sheetHeaderCentring() {
        let layout = SheetHeaderLayout(minHeight: 40, minGap: 8)
        #expect(layout.centreWidth(350, side: 70) == CGFloat(350 - 2 * 78))
        #expect(layout.centreWidth(100, side: 70) == 0, "never negative")
        #expect(!layout.isStacked(350, side: 71), "a 40 pt circle against a 71 pt Save: in the row")
        #expect(layout.isStacked(350, side: 140), "a pill too wide at AX3: the title under the slots")
    }

    // MARK: the chip

    @Test("A date chip reads the locale's short date, a time chip its clock")
    func chipFormat() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Berlin"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 10, minute: 12)))
        let us = Locale(identifier: "en_US")
        let day = ValueChip.format(date, components: .date, locale: us)
        #expect(day.contains("Nov") && day.contains("2026"), "\(day)")
        let time = ValueChip.format(date, components: .hourAndMinute, locale: us)
        #expect(time.contains(":") && !time.contains("2026"), "\(time)")
        #expect(ValueChip.format(date, components: [.date, .hourAndMinute], locale: us) == "\(day) \(time)")
    }

    // MARK: no teal

    @Test("Arrived, 'Arrives', a neutral banner and the step badge are ink: no teal left in the restyled parts")
    func noTeal() {
        let ink = Tokens.resolve(Theme.textPrimary)
        let teal = Tokens.resolve(Theme.accent)
        for (name, colour) in [("CheckRow.ok", CheckRow.Kind.ok.color), ("CapabilityState.yes", CapabilityState.yes.tint),
                               ("InlineMessage.neutral", InlineMessage.Severity.neutral.glyphColor)] {
            let c = Tokens.resolve(colour)
            #expect(Self.same(c, ink), "\(name) is ink")
            #expect(!Self.same(c, teal), "\(name) isn't teal")
        }
        let kinds: [CheckRow.Kind] = [.waiting, .checking, .ok, .expected, .neutral, .late, .fix]
        #expect(!kinds.contains { Self.same(Tokens.resolve($0.color), teal) })
        #expect(Self.same(Tokens.resolve(CheckRow.Kind.fix.color), Tokens.resolve(Theme.warning)), "amber only for the fix")
        #expect(Self.same(Tokens.resolve(InlineMessage.Severity.attention.glyphColor), Tokens.resolve(Theme.warning)))
        #expect(Self.same(Tokens.resolve(InlineMessage.Severity.destructive.glyphColor), Tokens.resolve(Theme.alert)))
    }

    // MARK: contrast

    @Test("Each new look holds its contrast: the tile's border 3:1, the chip's text, a field's prompt and a banner's caption 4.5:1")
    func contrast() {
        let background = Tokens.resolve(Theme.background), surface = Tokens.resolve(Theme.surface)
        var border = Tokens.resolve(Theme.textPrimary)
        border.a = SelectableTileSpec.borderOpacity
        #expect(Tokens.ratio(border, on: background) >= 3 && Tokens.ratio(border, on: surface) >= 3, "the selected border")
        #expect(Tokens.ratio(Tokens.resolve(Theme.textPrimary), on: Tokens.resolve(Theme.surfaceRaised)) >= 4.5, "chip text")
        #expect(Tokens.ratio(Tokens.resolve(FormFieldSpec.promptColor), on: surface) >= 4.5, "the prompt")
        #expect(Tokens.ratio(Tokens.resolve(Theme.textSecondary), on: surface) >= 4.5, "the banner's caption, Details")
        #expect(Tokens.ratio(Tokens.resolve(Theme.textTertiary), on: surface) >= 4.5, "a section title, an unchosen mark")
        var done = Tokens.resolve(Theme.textPrimary)
        done.a = StepRuleSpec.doneOpacity
        #expect(Tokens.ratio(done, on: background) >= 3, "a done segment is told from the track by more than its ink")
    }

    private static func same(_ a: RGBA, _ b: RGBA) -> Bool {
        abs(a.r - b.r) < 1.5 / 255 && abs(a.g - b.g) < 1.5 / 255 && abs(a.b - b.b) < 1.5 / 255
    }
}
