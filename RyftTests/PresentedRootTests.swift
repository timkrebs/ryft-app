import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// S1 (T5.7, PR 5 review): the window root's `.toggleStyle(.ryft)` doesn't reach what it presents on iOS 27.2 (its `.tint`
/// does), so every presentation ends its content with `presentedRoot()`. First what crosses a sheet; then the real presenters,
/// under a root that carries the app root's two modifiers and nothing set on the presented view: no stock switch anywhere in
/// the window, and every control UIKit tints (bar buttons, text fields) in the ink, never in system blue. Then a scan of
/// `Ryft/` for a presentation whose content goes without it.
@MainActor
@Suite("T5.7: presented roots", .serialized)
struct PresentedRootTests {
    // MARK: the probes

    /// Every view under `root`, `root` first.
    static func views(under root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap { views(under: $0) }
    }

    /// Stock switches on screen: SwiftUI's `.switch` style is a `UISwitch`, the Nocturne toggle draws its own track.
    static func switches(in window: UIWindow) -> [UISwitch] {
        views(under: window).compactMap { $0 as? UISwitch }.filter { !$0.isHidden && $0.alpha > 0 }
    }

    /// The controls UIKit draws in the tint SwiftUI hands it: a navigation bar's buttons where UIKit draws them (not always:
    /// some are hosted SwiftUI views), text fields and text views.
    static func tinted(under root: UIView) -> [UIView] {
        let all = views(under: root)
        let barButtons = all.filter { $0 is UINavigationBar }.flatMap { views(under: $0).filter { $0 is UIControl } }
        return barButtons + all.filter { $0 is UITextField || $0 is UITextView }
    }

    /// "#RRGGBB" as drawn under `view`'s traits.
    static func hex(_ color: UIColor, for view: UIView) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.resolvedColor(with: view.traitCollection).getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// The ink (`Theme.textPrimary`) as drawn under `view`'s traits.
    static func ink(for view: UIView) throws -> String {
        hex(try #require(UIColor(named: "TextPrimary")), for: view)
    }

    /// The presented view once its elements satisfy `ready`.
    private static func presented(_ w: HostedWindow, _ what: String,
                                  ready: ([HostedWindow.Node]) -> Bool) async throws -> UIView {
        var found: UIView?
        try await w.wait(what, timeout: .seconds(10)) {
            guard let view = w.presentedView else { return false }
            found = view
            return ready(w.nodes(in: view))
        }
        return try #require(found)
    }

    /// No stock switch in the window; every tinted control under `sheet` in the ink, and at least one of them (a pushed
    /// page's bar items arrive after its content, so it waits for them).
    private static func expectNocturne(_ w: HostedWindow, _ sheet: UIView, _ screen: String) async throws {
        let stock = switches(in: w.window)
        #expect(stock.isEmpty, "\(screen): \(stock.count) stock switch(es)")
        var controls: [UIView] = []
        do {
            try await w.wait("\(screen): a bar button or text field") {
                controls = tinted(under: sheet)
                return !controls.isEmpty
            }
        } catch {
            let bars = views(under: sheet).filter { $0 is UINavigationBar }.flatMap { views(under: $0) }
            let classes = Set(bars.map { String(describing: type(of: $0)) }).sorted().joined(separator: ", ")
            Issue.record("\(screen): no bar button or text field to read the tint from; under the bar: \(classes)")
            return
        }
        let inkHex = try ink(for: sheet)
        let off = controls.filter { hex($0.tintColor, for: $0) != inkHex }
        #expect(off.isEmpty, "\(screen): tinted \(off.map { "\(type(of: $0)) \(hex($0.tintColor, for: $0))" }), not the ink \(inkHex)")
    }

    /// The app root's two modifiers (`RyftApp`), over the presenter; nothing on what it presents.
    private static func appRoot(_ presenter: some View) -> some View {
        presenter
            .tint(Theme.textPrimary)
            .toggleStyle(.ryft)
    }

    /// A page in the Nocturne frame (`SubpageScaffold`, PR 6 C): its own header (`header`, the close circle or Back) and no
    /// system bar, so there is no bar button to read the tint from; no stock switch in the window, and whatever UIKit draws
    /// tinted under `sheet` (a field) in the ink. That the content gets `presentedRoot()` is the scan's job
    /// (`everyPresentationHasIt`).
    private static func expectNocturneFrame(_ w: HostedWindow, _ sheet: UIView, _ screen: String, header: String) async throws {
        try await w.wait("\(screen): its header") { w.nodes(in: sheet).contains { $0.identifier == header } }
        let stock = switches(in: w.window)
        #expect(stock.isEmpty, "\(screen): \(stock.count) stock switch(es)")
        let bars = views(under: sheet).filter { $0 is UINavigationBar && !$0.isHidden && $0.alpha > 0.01 }
        #expect(bars.isEmpty, "\(screen): a system bar shows")
        let inkHex = try ink(for: sheet)
        let off = tinted(under: sheet).filter { hex($0.tintColor, for: $0) != inkHex }
        #expect(off.isEmpty, "\(screen): tinted \(off.map { "\(type(of: $0)) \(hex($0.tintColor, for: $0))" }), not the ink \(inkHex)")
    }

    /// Dismisses what's presented, so the next window starts without it.
    private static func dismiss(_ w: HostedWindow) async throws {
        w.host.dismiss(animated: false)
        try await w.wait("nothing presented") { w.host.presentedViewController == nil }
    }

    // MARK: the probes themselves, and what crosses a sheet

    @Test("The probe finds a stock switch (SwiftUI's .switch is a UISwitch) and none for the Nocturne toggle")
    func theProbeSeesStockSwitches() async throws {
        let stock = Toggle(isOn: .constant(true)) { Text(verbatim: "Stock") }.toggleStyle(.switch).padding()
        try await HostedWindow.run(width: 390, height: 200, stock) { w in
            try await w.wait("the stock switch") { !Self.switches(in: w.window).isEmpty }
        }
        let nocturne = Toggle(isOn: .constant(true)) { Text(verbatim: "Nocturne") }.toggleStyle(.ryft).padding()
        try await HostedWindow.run(width: 390, height: 200, nocturne) { w in
            try await w.wait("the Nocturne toggle") { w.node("Nocturne", exactly: true) != nil }
            #expect(Self.switches(in: w.window).isEmpty, "the Nocturne toggle draws its own track")
        }
    }

    /// A sheet under the app root's two modifiers, with a toggle and a text field (a `UITextField`: its caret takes the
    /// tint; a bar button here is a hosted SwiftUI view); `fixed`: its content ends with `presentedRoot()`.
    private struct ProbeSheet: View {
        let fixed: Bool

        var body: some View {
            Color.clear.sheet(isPresented: .constant(true)) {
                if fixed { content.presentedRoot() } else { content }
            }
        }

        private var content: some View {
            VStack {
                Toggle(isOn: .constant(true)) { Text(verbatim: "Probe") }
                TextField(String("Field"), text: .constant(String("Probe text")))
            }
            .padding()
        }
    }

    @Test("What crosses a sheet on iOS 27: the root's tint does, its toggle style doesn't; presentedRoot() brings it back")
    func whatCrossesASheet() async throws {
        try await HostedWindow.run(width: 390, height: 844, Self.appRoot(ProbeSheet(fixed: false))) { w in
            let sheet = try await Self.presented(w, "the probe sheet") { $0.contains { $0.label == "Probe" } }
            if #available(iOS 27, *) {
                // If this fails, SwiftUI now carries the style into presented content, and presentedRoot()'s toggle half
                // is redundant (not wrong).
                #expect(!Self.switches(in: w.window).isEmpty, "the root's toggle style reached the sheet")
            }
            let controls = Self.tinted(under: sheet)
            #expect(!controls.isEmpty)
            let inkHex = try Self.ink(for: sheet)
            #expect(controls.allSatisfy { Self.hex($0.tintColor, for: $0) == inkHex }, "the root's tint didn't reach the sheet")
            try await Self.dismiss(w)
        }
        try await HostedWindow.run(width: 390, height: 844, Self.appRoot(ProbeSheet(fixed: true))) { w in
            let sheet = try await Self.presented(w, "the probe sheet, fixed") { $0.contains { $0.label == "Probe" } }
            try await Self.expectNocturne(w, sheet, "Probe")
            try await Self.dismiss(w)
        }
    }

    // MARK: through the real presenters

    /// Today's error card as the app has it: Details' "Send to RYFT" pushes Report a problem (`RootView`'s destination).
    private struct ReportHost: View {
        @Environment(ScreenModels.self) private var screens

        var body: some View {
            RefreshIssueCard(issue: PresentedRootTests.issue)
                .padding(20)
                .environment(\.reportProblemDestination) { resource, status, code, requestID in
                    AnyView(ReportProblemView(model: screens.profile.report,
                                              context: ReportContext(resource: resource, status: status, requestID: requestID,
                                                                     code: code)))
                }
        }
    }

    /// Three 503s for today, data from 14:05.
    static var issue: RefreshIssue {
        let at = Calendar.current.date(bySettingHour: 14, minute: 7, second: 12, of: .now) ?? .now
        let error = ResourceError(kind: .transient, status: 503, code: nil, requestID: "01a14ffa-eb7c-73e3-9cf9-262c70d5ed9c",
                                  transport: nil, attempts: 3, at: at)
        return RefreshIssue(reason: .busy, resource: .today, dataFrom: at.addingTimeInterval(-120), failures: 3, error: error)
    }

    @Test("The error card's Details sheet and the Report a problem it pushes: the Nocturne switch, the ink tint")
    func refreshDetailsAndReport() async throws {
        try await HostedWindow.run(width: 390, height: 844, Self.appRoot(ReportHost())) { w in
            try await w.wait("the error card") { w.node("Details", exactly: true) != nil }
            try #require(w.node("Details", exactly: true)).activate()
            let sheet = try await Self.presented(w, "the Details sheet") { $0.contains { $0.label == "Send to RYFT" } }
            try await Self.expectNocturne(w, sheet, "Details")
            try #require(w.nodes(in: sheet).first { $0.label == "Send to RYFT" }).activate()
            try await w.wait("Report a problem, pushed") {
                w.nodes(in: sheet).contains { $0.label == "Reports are limited to 10 a day." }
            }
            try await Self.expectNocturne(w, sheet, "Report a problem")
            try await Self.dismiss(w)
        }
    }

    @Test("Sleep's need sheet and the baseline form it pushes: the Nocturne frame (no system bar), no stock switch")
    func sleepNeedAndItsForm() async throws {
        try await HostedWindow.run(width: 390, height: 2000, bottomInset: 0, Self.appRoot(SleepPreviewPage(.latest))) { w in
            try await w.wait("Sleep's need card") { w.nodes().contains { $0.identifier == "sleep.need" } }
            try #require(w.nodes().first { $0.identifier == "sleep.need" }).activate()
            let sheet = try await Self.presented(w, "the need sheet") {
                $0.contains { $0.identifier == "sleepNeed.changeBaseline" }
            }
            try await Self.expectNocturneFrame(w, sheet, "Sleep need", header: "subpage.close")
            try #require(w.nodes(in: sheet).first { $0.identifier == "sleepNeed.changeBaseline" }).activate()
            try await w.wait("the baseline form, pushed") {
                w.nodes(in: sheet).contains { $0.label.hasPrefix("Each night's sleep need starts from this baseline") }
            }
            try await Self.expectNocturneFrame(w, sheet, "Baseline sleep need", header: "subpage.back")
            try await Self.dismiss(w)
        }
    }

    @Test("Today's journal sheet: its rows are Nocturne switches, its bar in the ink")
    func todaysJournal() async throws {
        let state = AppState.preview()
        let today = TodayView().previewEnvironment(state).environment(\.locale, Locale(identifier: "en_US"))
        try await HostedWindow.run(width: 390, height: 2600, Self.appRoot(today)) { w in
            try await w.wait("the journal card", timeout: .seconds(10)) {
                w.nodes().contains { $0.hint == "Opens the journal" }
            }
            try #require(w.nodes().first { $0.hint == "Opens the journal" }).activate()
            let sheet = try await Self.presented(w, "the journal's groups") { $0.contains { $0.label == "Substances" } }
            try await Self.expectNocturne(w, sheet, "Journal")
            try await Self.dismiss(w)
        }
    }

    // MARK: PR 6 C's presenters

    /// The tab bar's import presentations (`RootView` carries `importPresentations`) over an empty page, showing `flow`.
    private struct ImportHost: View {
        let flow: ImportFlowModel
        @Environment(ScreenModels.self) private var screens

        var body: some View {
            Color.clear
                .importPresentations(screens.importer)
                .onAppear { screens.importer.flow = flow }
        }
    }

    @Test("The import cover, step 3: its switches are the Nocturne toggle, none a stock UISwitch (the integrated app's)")
    func importCoverStepThree() async throws {
        let flow = ImportMockData.flow(.choose, enrolled: false)
        let host = ImportHost(flow: flow).previewEnvironment().environment(\.locale, Locale(identifier: "en_US"))
        try await HostedWindow.run(width: 390, height: 844, Self.appRoot(host)) { w in
            let cover = try await Self.presented(w, "step 3 in the cover") { $0.contains { $0.identifier == "import.plan.0" } }
            // Not vacuous: step 3's rows are switches, on.
            let plan = try #require(w.nodes(in: cover).first { $0.identifier == "import.plan.0" })
            #expect(plan.value == "1", "the plan's switch: \(plan.value ?? "nil")")
            #expect(w.nodes(in: cover).contains { $0.identifier == "import.history" }, "history's switch")
            let stock = Self.switches(in: w.window)
            #expect(stock.isEmpty, "the import cover: \(stock.count) stock switch(es)")
            try await Self.dismiss(w)
        }
    }

    @Test("Journal settings' Add a habit sheet, through its + button: no stock switch, its field in the ink")
    func journalAddSheet() async throws {
        let state = AppState.preview()
        let page = NavigationStack { JournalSettingsView(store: journalPreviewStore(state)) }
            .previewEnvironment(state)
            .environment(\.locale, Locale(identifier: "en_US"))
        try await HostedWindow.run(width: 390, height: 1600, Self.appRoot(page)) { w in
            try await w.wait("the journal's + button", timeout: .seconds(10)) {
                w.nodes().contains { $0.identifier == "journal.add" }
            }
            #expect(try #require(w.nodes().first { $0.identifier == "journal.add" }).activate(), "+ took the tap")
            // The name field is one element with its FormField (no identifier of its own); Add is the sheet's.
            let sheet = try await Self.presented(w, "Add a habit") { $0.contains { $0.identifier == "addHabit.add" } }
            try await Self.expectNocturne(w, sheet, "Add a habit")
            try await Self.dismiss(w)
        }
    }

    // MARK: every presentation in Ryft/

    private static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Ryft")

    @Test("Every .sheet, .fullScreenCover and .popover content closure in Ryft/ applies presentedRoot()")
    func everyPresentationHasIt() throws {
        let root = Self.sources.resolvingSymlinksInPath().path
        let files = try #require(FileManager.default.enumerator(at: Self.sources, includingPropertiesForKeys: nil))
        var found = 0
        var missing: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(root.count + 1))
            for presentation in PresentationScan.presentations(in: try String(contentsOf: url, encoding: .utf8)) {
                found += 1
                if !presentation.hasPresentedRoot { missing.append("Ryft/\(path):\(presentation.line) \(presentation.kind)") }
            }
        }
        // About 57 on this branch; far fewer would mean the scan stopped seeing them.
        #expect(found >= 40, "only \(found) presentations found")
        #expect(missing.isEmpty, "content without .presentedRoot():\n\(missing.joined(separator: "\n"))")
    }

    @Test("The scan reads trailing and content: closures, skips comments and strings, and names what it can't read")
    func theScanItself() {
        let source = #"""
        // .sheet(isPresented: $x) { Commented() }
        let text = "a .sheet(isPresented: $y) { InAString() } and \(value ? "}" : "{")"
        Color.clear
            .sheet(isPresented: $a) {
                A(label: "}{ .presentedRoot()")
            }
            .fullScreenCover(item: $b, onDismiss: { done() }) { B(item: $0).presentedRoot() }
            .popover(isPresented: $c, content: { C().presentedRoot() })
            .sheet(item: $d, content: D.init)
        func sheet(isPresented: Binding<Bool>) -> some View { self }
        sheet(item: $e) { setting in
            NavigationStack { E(setting) }
                .presentedRoot()
        }
        """#
        let found = PresentationScan.presentations(in: source)
        #expect(found.map(\.line) == [4, 7, 8, 9, 11], "\(found)")
        #expect(found.map(\.hasPresentedRoot) == [false, true, true, false, true], "\(found)")
        #expect(found.map(\.kind) == ["sheet", "fullScreenCover", "popover", "sheet (no content closure)", "sheet"])
    }
}

/// Finds SwiftUI presentations in a Swift source: `.sheet(`, `.fullScreenCover(`, `.popover(` (or `sheet(` inside a `View`
/// extension), their content closure (the trailing one, or `content:`), and whether it applies `.presentedRoot()`.
/// Comments and string literals (with their interpolations) are blanked first, so neither counts.
enum PresentationScan {
    struct Presentation: CustomStringConvertible {
        /// "sheet", "fullScreenCover", "popover"; "… (no content closure)" when the content isn't a closure it can read.
        let kind: String
        let line: Int
        let hasPresentedRoot: Bool
        var description: String { "\(line) \(kind) \(hasPresentedRoot)" }
    }

    static func presentations(in source: String) -> [Presentation] {
        let code = blanked(Array(source.utf16))
        let text = String(decoding: code, as: UTF16.self) as NSString
        guard let regex = try? NSRegularExpression(pattern: #"(?:\.|(?<![\w.]))(sheet|fullScreenCover|popover)\s*\("#) else { return [] }
        var out: [Presentation] = []
        for match in regex.matches(in: text as String, range: NSRange(location: 0, length: text.length)) {
            let before = text.substring(to: match.range.location).trimmingCharacters(in: .whitespaces)
            if before.hasSuffix("func") { continue }
            let kind = text.substring(with: match.range(at: 1))
            let open = match.range.location + match.range.length - 1
            let line = code[..<open].filter { $0 == newline }.count + 1
            guard let close = matching(code, from: open, open: paren, close: closeParen) else {
                out.append(Presentation(kind: "\(kind) (no content closure)", line: line, hasPresentedRoot: false))
                continue
            }
            if let body = contentClosure(code, arguments: open, close: close) {
                let closure = String(decoding: code[body], as: UTF16.self)
                out.append(Presentation(kind: kind, line: line, hasPresentedRoot: closure.contains(".presentedRoot()")))
            } else {
                out.append(Presentation(kind: "\(kind) (no content closure)", line: line, hasPresentedRoot: false))
            }
        }
        return out
    }

    private static func unit(_ c: Unicode.Scalar) -> UInt16 { UInt16(c.value) }
    private static let newline = unit("\n"), space = unit(" "), tab = unit("\t")
    private static let paren = unit("("), closeParen = unit(")"), brace = unit("{"), closeBrace = unit("}")
    private static let quote = unit("\""), hash = unit("#"), slash = unit("/"), star = unit("*"), backslash = unit("\\")

    /// The closure the presentation's content is: `content: { … }` among the arguments, else the trailing `{ … }`.
    private static func contentClosure(_ code: [UInt16], arguments open: Int, close: Int) -> Range<Int>? {
        let arguments = String(decoding: code[(open + 1)..<close], as: UTF16.self) as NSString
        let label = arguments.range(of: #"(?<![\w])content\s*:\s*\{"#, options: .regularExpression)
        if label.location != NSNotFound {
            let start = open + 1 + label.location + label.length - 1
            return matching(code, from: start, open: brace, close: closeBrace).map { (start + 1)..<$0 }
        }
        var i = close + 1
        while i < code.count, code[i] == space || code[i] == newline || code[i] == tab { i += 1 }
        guard i < code.count, code[i] == brace else { return nil }
        return matching(code, from: i, open: brace, close: closeBrace).map { (i + 1)..<$0 }
    }

    /// The index of the bracket that closes the one at `from` (comments and strings already blanked).
    private static func matching(_ code: [UInt16], from: Int, open: UInt16, close: UInt16) -> Int? {
        var depth = 0
        for i in from..<code.count {
            if code[i] == open { depth += 1 } else if code[i] == close {
                depth -= 1
                if depth == 0 { return i }
            }
        }
        return nil
    }

    /// `code` with every comment and string literal (raw, multi-line, interpolated) turned into spaces; newlines stay, so
    /// line numbers and offsets do too.
    static func blanked(_ source: [UInt16]) -> [UInt16] {
        var out = source
        var i = 0
        while i < out.count { i = step(&out, i) }
        return out
    }

    private static func blank(_ out: inout [UInt16], _ range: Range<Int>) {
        for j in range where j < out.count && out[j] != newline { out[j] = space }
    }

    /// One token of code at `i`: a comment or a string literal, blanked whole, else one unit (`#`s together). Returns where
    /// the next token starts.
    private static func step(_ out: inout [UInt16], _ i: Int) -> Int {
        let c = out[i]
        let next = i + 1 < out.count ? out[i + 1] : 0
        if c == slash, next == slash {
            var j = i
            while j < out.count, out[j] != newline { j += 1 }
            blank(&out, i..<j)
            return j
        }
        if c == slash, next == star {
            var depth = 0, j = i
            while j < out.count {
                if out[j] == slash, j + 1 < out.count, out[j + 1] == star { depth += 1; j += 2; continue }
                if out[j] == star, j + 1 < out.count, out[j + 1] == slash {
                    depth -= 1; j += 2
                    if depth == 0 { break }
                    continue
                }
                j += 1
            }
            blank(&out, i..<min(j, out.count))
            return j
        }
        var hashes = 0
        while i + hashes < out.count, out[i + hashes] == hash { hashes += 1 }
        if i + hashes < out.count, out[i + hashes] == quote, hashes > 0 || c == quote {
            let end = stringEnd(&out, start: i, hashes: hashes)
            blank(&out, i..<end)
            return end
        }
        return i + max(1, hashes)
    }

    /// Where the string literal starting at `start` (its `#`s, then `"` or `"""`) ends, past its closing delimiter.
    private static func stringEnd(_ out: inout [UInt16], start: Int, hashes: Int) -> Int {
        var j = start + hashes
        let multiLine = j + 2 < out.count && out[j + 1] == quote && out[j + 2] == quote
        j += multiLine ? 3 : 1
        while j < out.count {
            if out[j] == backslash, (0..<hashes).allSatisfy({ j + 1 + $0 < out.count && out[j + 1 + $0] == hash }) {
                let after = j + 1 + hashes
                if after < out.count, out[after] == paren {
                    // An interpolation: code up to its closing parenthesis, with strings and comments of its own.
                    var depth = 1
                    var k = after + 1
                    while k < out.count, depth > 0 {
                        let unit = out[k]
                        let next = step(&out, k)
                        if next == k + 1 {
                            if unit == paren { depth += 1 } else if unit == closeParen { depth -= 1 }
                        }
                        k = next
                    }
                    j = k
                } else {
                    j = after + 1
                }
                continue
            }
            if out[j] == quote {
                let closes = multiLine ? (j + 2 < out.count && out[j + 1] == quote && out[j + 2] == quote) : true
                let width = multiLine ? 3 : 1
                if closes, (0..<hashes).allSatisfy({ j + width + $0 < out.count && out[j + width + $0] == hash }) {
                    return j + width + hashes
                }
            }
            if !multiLine, out[j] == newline { return j }
            j += 1
        }
        return j
    }
}
