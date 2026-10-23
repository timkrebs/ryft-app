import Foundation
import Testing
@testable import Ryft

@Suite("Import scanners and tokens")
struct ImportScannerTests {
    private let tokens = AlphaProgressionTokens.standard

    @Test func decimals() {
        let cases: [(String, Double?)] = [
            ("60", 60), ("62.5", 62.5), ("62,5", 62.5), ("0", 0), ("1.125", 1.125), ("007", 7), ("123456789", 123_456_789),
            ("1234567890", nil), ("1.2345", nil), ("1.234,5", nil), ("7e2", nil), ("1e309", nil), ("nan", nil),
            ("inf", nil), ("", nil), (".5", nil), ("5.", nil), ("5,", nil), (",,", nil), ("1 000", nil),
            ("\u{0663}\u{0660}", nil), ("+5", nil), ("-5", nil), ("６０", nil),
        ]
        for (text, expected) in cases {
            #expect(ImportScan.decimal(text) == expected, "\(text)")
        }
    }

    @Test func integers() {
        let cases: [(String, Int?)] = [("10", 10), ("0", 0), ("999999999", 999_999_999), ("1000000000", nil), ("10.0", nil),
                                       ("", nil), ("1a", nil), ("\u{0661}", nil), (" 1", nil)]
        for (text, expected) in cases {
            #expect(ImportScan.integer(text) == expected, "\(text)")
        }
    }

    @Test func loads() {
        let kg: [(String, ImportScanResult<ImportedLoad>)] = [
            ("60", .value(.weight(kg: 60))), ("62,5", .value(.weight(kg: 62.5))), ("+84", .value(.plus(kg: 84))),
            ("+7,5", .value(.plus(kg: 7.5))), ("-20", .value(.minus(kg: 20))), ("\u{2212}20", .value(.minus(kg: 20))),
            ("-0", .value(.minus(kg: 0))), ("-", .absent), ("", .absent), ("\u{2013}", .absent), ("+", .unreadable),
            ("--5", .unreadable), ("1e3", .unreadable), ("1000", .value(.weight(kg: 1_000))), ("1000.5", .implausible),
            ("+2000", .implausible), ("9999999999999", .unreadable),
        ]
        for (text, expected) in kg {
            #expect(ImportScan.load(text, unit: .kg) == expected, "\(text)")
        }
        let pounds: [(String, ImportScanResult<ImportedLoad>)] = [
            ("135", .value(.weight(kg: 61.23))), ("185.5", .value(.weight(kg: 84.14))), ("+25", .value(.plus(kg: 11.34))),
            ("2204", .value(.weight(kg: 999.72))), ("2205", .implausible),
        ]
        for (text, expected) in pounds {
            #expect(ImportScan.load(text, unit: .lb) == expected, "\(text) lb")
        }
    }

    @Test func reps() {
        let cases: [(String, ImportScanResult<Int>)] = [("10", .value(10)), ("0", .value(0)), ("-", .absent), ("", .absent),
                                                        ("1000", .value(1_000)), ("1001", .implausible), ("10.5", .unreadable),
                                                        ("ten", .unreadable)]
        for (text, expected) in cases {
            #expect(ImportScan.reps(text) == expected, "\(text)")
        }
    }

    @Test func dates() {
        let cases: [(String, String?)] = [
            ("2026-05-14", "2026-05-14"), ("2026-5-4", "2026-05-04"), ("14.05.2026", "2026-05-14"), ("4.5.2026", "2026-05-04"),
            ("2024-02-29", "2024-02-29"), ("2026-02-29", nil), ("2026-02-30", nil), ("2026-13-01", nil), ("2026-00-10", nil),
            ("26-05-14", nil), ("2026/05/14", nil), ("05/14/2026", nil), ("2026-05-14-01", nil), ("", nil),
            ("1899-12-31", nil), ("2100-02-29", nil), ("2000-02-29", "2000-02-29"),
        ]
        for (text, expected) in cases {
            #expect(ImportScan.date(text)?.key == expected, "\(text)")
        }
    }

    @Test func clocks() {
        let cases: [(String, Int, Int, Bool)] = [
            ("4:41 pm", 16, 41, false), ("4:41 PM", 16, 41, false), ("6:52 am", 6, 52, false), ("12:05 am", 0, 5, false),
            ("12:10 pm", 12, 10, false), ("11:59 p.m.", 23, 59, false), ("9:15 a. m.", 9, 15, false), ("16:41", 16, 41, false),
            ("07:05", 7, 5, false), ("18:30 Uhr", 18, 30, false), ("0:00", 0, 0, false), ("16:41 pm", 16, 41, true),
            ("0:30 am", 0, 30, true), ("16:41:44", 16, 41, false),
        ]
        for (text, hour, minute, conflict) in cases {
            #expect(ImportScan.clock(text, tokens: tokens) == ImportScan.Clock(hour: hour, minute: minute, meridiemConflict: conflict),
                    "\(text)")
        }
        for text in ["24:00", "13:60", "3:5 pm", "3 pm", "4:41 xm", "", ":30", "1234567890:00", "16:41:4"] {
            #expect(ImportScan.clock(text, tokens: tokens) == nil, "\(text)")
        }
    }

    @Test func dateTimes() throws {
        let afternoon = try time("2026-05-14", 16, 41)
        let conflicted = try time("2026-04-02", 16, 41)
        let day = try #require(ImportScan.date("2026-05-14"))
        #expect(ImportScan.dateTime("2026-05-14 4:41 pm", tokens: tokens) == .dateTime(afternoon, meridiemConflict: false))
        #expect(ImportScan.dateTime("14.05.2026, 16:41", tokens: tokens) == .dateTime(afternoon, meridiemConflict: false))
        #expect(ImportScan.dateTime("2026-05-14T16:41", tokens: tokens) == .dateTime(afternoon, meridiemConflict: false))
        #expect(ImportScan.dateTime("2026-04-02 16:41 pm", tokens: tokens) == .dateTime(conflicted, meridiemConflict: true))
        #expect(ImportScan.dateTime("2026-05-14", tokens: tokens) == .dateOnly(day))
        #expect(ImportScan.dateTime("2026-02-30 9:00 am", tokens: tokens) == .unreadable)
        #expect(ImportScan.dateTime("2026-05-14 noon", tokens: tokens) == .unreadable)
        // Any whitespace separates the date and the time, a no-break space too (and U+202F before am/pm).
        #expect(ImportScan.dateTime("2026-05-14\u{00A0}4:41\u{202F}pm", tokens: tokens) == .dateTime(afternoon, meridiemConflict: false))
        #expect(ImportScan.dateTime("2026-05-14\t16:41", tokens: tokens) == .dateTime(afternoon, meridiemConflict: false))
        #expect(ImportScan.dateTime("37 min", tokens: tokens) == .unreadable)
    }

    @Test func durations() {
        let cases: [(String, ImportScanResult<Int>)] = [
            ("37 min", .value(37)), ("37min", .value(37)), ("1:12 hr", .value(72)), ("1:12hr", .value(72)), ("2 hr", .value(120)),
            ("1 hr 5 min", .value(65)), ("1h 5min", .value(65)), ("0 min", .value(0)), ("42 Min.", .value(42)),
            ("1:05 Std.", .value(65)), ("1 Std. 10 Min.", .value(70)), ("90 Minuten", .value(90)), ("2 Stunden", .value(120)),
            ("24 hr", .value(1_440)), ("25 hr", .implausible), ("1500 min", .implausible), ("", .absent), ("-", .absent),
            ("about an hour", .unreadable), ("37", .unreadable), ("1:12", .unreadable), ("37:20 min", .unreadable),
            ("1:75 hr", .unreadable), ("5 min 5 min", .unreadable), ("min 5", .unreadable), ("9999999999 min", .unreadable),
            ("1 hr 5", .unreadable),
        ]
        for (text, expected) in cases {
            #expect(ImportScan.duration(text, tokens: tokens) == expected, "\(text)")
        }
    }

    @Test func numberedTokens() {
        #expect(tokens.count("5 weeks", tokens.weeks) == 5)
        #expect(tokens.count("1 week", tokens.weeks) == 1)
        #expect(tokens.count("5weeks", tokens.weeks) == 5)
        #expect(tokens.count("6 Wochen", tokens.weeks) == 6)
        #expect(tokens.count("3 Sätze", tokens.sets) == 3)
        #expect(tokens.count("3 Sa\u{0308}tze", tokens.sets) == 3) // decomposed umlaut
        #expect(tokens.count("4 SETS", tokens.sets) == 4)
        #expect(tokens.count("4 reps", tokens.sets) == nil)
        #expect(tokens.count("weeks", tokens.weeks) == nil)
        #expect(tokens.numbered("Day 1", tokens.day) == 1)
        #expect(tokens.numbered("day12", tokens.day) == 12)
        #expect(tokens.numbered("Tag 2", tokens.day) == 2)
        #expect(tokens.numbered("Woche 3", tokens.week) == 3)
        #expect(tokens.numbered("Week 4", tokens.day) == nil)
        #expect(tokens.numbered("Day", tokens.day) == nil)
        #expect(tokens.numbered("Day 1a", tokens.day) == nil)
        #expect(tokens.numbered("Holiday 1", tokens.day) == nil)
        // At most 9 digits, found within 10 scalars of the end; a long word before them is no token.
        #expect(tokens.numbered("Day 123456789", tokens.day) == 123_456_789)
        #expect(tokens.numbered("Day 1234567890", tokens.day) == nil)
        #expect(tokens.numbered(String(repeating: "7", count: 4_000), tokens.day) == nil)
        #expect(tokens.numbered(String(repeating: "x", count: 41) + " 1", tokens.day) == nil)
        #expect(tokens.count("4 " + String(repeating: "s", count: 41), tokens.sets) == nil)
        #expect(tokens.targetReps("8 " + String(repeating: "r", count: 41)) == nil)
    }

    @Test func targetReps() {
        #expect(tokens.targetReps("10 reps") == .value(10...10))
        #expect(tokens.targetReps("1 rep") == .value(1...1))
        #expect(tokens.targetReps("8-12 reps") == .value(8...12))
        #expect(tokens.targetReps("8 – 12 reps") == .value(8...12))
        #expect(tokens.targetReps("12-8 reps") == .value(8...12))
        #expect(tokens.targetReps("6 Wdh.") == .value(6...6))
        #expect(tokens.targetReps("6–8 Wiederholungen") == .value(6...8))
        #expect(tokens.targetReps("5000 reps") == .implausible)
        #expect(tokens.targetReps("Barbell") == nil)
        #expect(tokens.targetReps("10 kg") == nil)
        #expect(tokens.targetReps("8- reps") == nil)
        #expect(tokens.targetReps("AMRAP") == nil)
    }

    @Test func orderedNames() {
        #expect(tokens.ordered("1. Floor Press · Barbell")?.order == 1)
        #expect(tokens.ordered("12.Row")?.rest == "Row")
        #expect(tokens.ordered("1.") == nil)
        #expect(tokens.ordered("1 Bench") == nil)
        #expect(tokens.ordered("Bench") == nil)
    }

    // MARK: Helpers

    private func time(_ day: String, _ hour: Int, _ minute: Int) throws -> LocalDateTime {
        let date = try #require(ImportScan.date(day))
        return try #require(LocalDateTime(date: date, hour: hour, minute: minute))
    }
}
