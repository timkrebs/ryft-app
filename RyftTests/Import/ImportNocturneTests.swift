import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// The training import in Nocturne (PR 6 C5, design-pr6-c-settings.md §4.14 and §6 test 14): the frame by step (title,
/// step rule, Close and Back), the pinned pill per state, selection, the match rows' status words, the progress bar and its
/// VoiceOver value, the result with refused items, the offline-first rule (2026-11-19: a step that needs the platform says
/// so offline; nothing claims done before the platform confirmed it), AX3 and 44 pt targets, and L27 (no teal). Hosted at
/// 390 pt from `ImportNocturneShotsTests.screen`, synthetic files only (ImportMockData, MockTrainImport), US English.
@MainActor
@Suite("C5: Import in Nocturne", .serialized)
struct ImportNocturneTests {
    // MARK: decisions

    @Test("Step titles as the spec names them; the rule counts six")
    func stepTitles() {
        #expect(ImportFlowModel.Step.allCases.map(\.title)
            == ["Import training data", "Detected", "What to import", "Match exercises", "Preview", "Import"])
        #expect(ImportFlowModel.stepCount == 6)
    }

    @Test("Match rows: Likely, Check and Question in warning, New in textSecondary, Skipped in textTertiary, a match a checkmark")
    func matchMarks() {
        typealias S = ExerciseMatchStatus
        #expect(S.mark(.check(likely: true)) == .word("Likely", .attention))
        #expect(S.mark(.check(likely: false)) == .word("Check", .attention))
        #expect(S.mark(.new(ready: false)) == .word("New", .secondary))
        #expect(S.mark(.new(ready: true)) == .word("New", .secondary))
        #expect(S.mark(.skipped) == .word("Skipped", .tertiary))
        #expect(S.mark(.matched(remembered: false)) == .checkmark)
        #expect(S.mark(.matched(remembered: true)) == .checkmark)
        #expect(S.mark(.yourChoice) == .checkmark)
        #expect(S.mark(.matched(remembered: false), questionOpen: true) == .word("Question", .attention), "the bodyweight question")
        #expect(S.mark(.new(ready: true), questionOpen: true) == .word("Question", .attention))
    }

    @Test("Step 6's pinned bar: none while getting ready or uploading; there for every pause and the result")
    func step6Bar() {
        #expect(!ImportResultView.hasButtons(nil))
        #expect(!ImportResultView.hasButtons(MockTrainImport.status(.preparing, sessions: 0)))
        #expect(!ImportResultView.hasButtons(MockTrainImport.uploading))
        let paused: [ImportPause] = [.gated(.gate(.consentRequired)), .held, .needsAttention, .waitingForAccount]
        for job in [MockTrainImport.offline, MockTrainImport.retrying, MockTrainImport.savedOnPhone, MockTrainImport.done,
                    MockTrainImport.partlyDone] + paused.map({ MockTrainImport.status(.paused($0)) }) {
            #expect(ImportResultView.hasButtons(job), "\(job.phase)")
        }
    }

    /// `ProfileSubpagesTests.noTeal`'s tokens (less its page-specific `ProfileSection`), and the tint and system teals.
    nonisolated static let tealTokens = [
        "Theme.accent", "Theme.onAccent", "Theme.teal", "Theme.recovery", "Theme.signal", "Color.accentColor", "accentColor",
        "TealButtonStyle", ".tint(", ".teal", ".mint", ".cyan", "Color(\"Accent", "Color(\"Teal", "Color(\"Recovery",
        "Locale(identifier: \"de\")", "preferredColorScheme(.light)",
    ]

    @Test("L27: the import's views and its progress bar name no teal, accent or tint, in code (comments may)")
    func noTeal() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Ryft/Features/Train/Import")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" } + [root.appendingPathComponent("Ryft/Design/ImportProgressBar.swift")]
        #expect(files.count >= 20, "the folder was found: \(files.count)")
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            // The code only, as ProfileSubpagesTests: a comment may name a token to say why it isn't used. `//` after a
            // colon is a URL's.
            let code = source.replacing(#/(^|[^:])//.*/#) { String($0.output.1) }
            for token in Self.tealTokens {
                #expect(!code.contains(token), "\(file.lastPathComponent) names \(token)")
            }
            // The old teal pill, as a word: `ImportPrimaryButton` is a `PillButton`.
            #expect(code.firstMatch(of: #/\bPrimaryButton\b/#) == nil, "\(file.lastPathComponent) names PrimaryButton")
        }
    }

    @Test("C §2.8: the import animates only with Theme.Motion, through respecting (none under Reduce Motion); no curve of its own")
    func motion() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = root.appendingPathComponent("Ryft/Features/Train/Import")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(files.count >= 20, "the folder was found: \(files.count)")
        var animated = 0
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8).replacing(#/(^|[^:])//.*/#) { String($0.output.1) }
            for curve in [".easeOut(", ".easeIn(", ".easeInOut(", ".linear(", ".spring(", ".smooth", ".snappy", ".bouncy",
                          "Animation."] {
                #expect(!code.contains(curve), "\(file.lastPathComponent) names \(curve)")
            }
            #expect(!code.contains("reduceMotion ? nil"), "\(file.lastPathComponent): Theme.Motion.respecting, not its own test")
            animated += code.matches(of: #/withAnimation\(|\.animation\(/#).count
        }
        #expect(animated >= 5, "the scan saw the import's animations: \(animated)")
    }

    // MARK: the frame by step

    struct FrameCase: CustomTestStringConvertible, Sendable {
        let screen: String, step: Int, title: String, close: String, back: Bool
        var testDescription: String { "step \(step)" }
    }

    nonisolated static let frames = [
        FrameCase(screen: "1-pick", step: 1, title: "Import training data", close: "import.cancel", back: false),
        FrameCase(screen: "2-detected", step: 2, title: "Detected", close: "import.cancel", back: true),
        FrameCase(screen: "3-choose", step: 3, title: "What to import", close: "import.cancel", back: true),
        FrameCase(screen: "4-map", step: 4, title: "Match exercises", close: "import.cancel", back: true),
        FrameCase(screen: "5-preview-plan", step: 5, title: "Preview", close: "import.cancel", back: true),
        FrameCase(screen: "6-done-plan", step: 6, title: "Import", close: "import.close", back: false),
    ]

    @Test("Test 14: the title is the header, the rule reads Step N of 6 under it; Close on every step, Back on 2 to 5",
          arguments: Self.frames)
    func frame(_ c: FrameCase) async throws {
        try await host(c.screen) { w in
            let nodes = w.nodes()
            let title = try #require(nodes.first { $0.label == c.title && $0.traits.contains(.header) }, "the title")
            let rule = try #require(nodes.first { $0.label == "Step \(c.step) of 6" }, "the step rule")
            #expect(rule.frame.minY >= title.frame.maxY, "the rule under the title: \(rule.frame) \(title.frame)")
            let close = try #require(nodes.first { $0.identifier == c.close })
            #expect(close.label == "Close" && close.frame.width >= 44 && close.frame.height >= 44, "\(close.frame)")
            #expect(close.frame.maxX > 300, "Close trails: \(close.frame)")
            let otherClose = c.close == "import.close" ? "import.cancel" : "import.close"
            #expect(!nodes.contains { $0.identifier == otherClose })
            #expect(nodes.contains { $0.identifier == "subpage.back" } == c.back, "Back")
        }
    }

    @Test("Step 6 has no way back: its Back is hidden and both back swipes are off; step 5 keeps them")
    func step6NoWayBack() async throws {
        try await host("6-done") { w in
            let nav = try #require(Self.navigationController(w), "a navigation controller")
            #expect(nav.viewControllers.count > 1, "step 6 is pushed: \(nav.viewControllers.count)")
            #expect(nav.topViewController?.navigationItem.hidesBackButton == true, "the Back button is hidden")
            try await w.wait("the swipes off") { nav.interactivePopGestureRecognizer?.isEnabled == false }
            if #available(iOS 26.0, *) {
                let content = try #require(nav.interactiveContentPopGestureRecognizer, "iOS 26's content swipe")
                #expect(!content.isEnabled, "iOS 26's content swipe")
            }
        }
        try await host("5-preview-plan") { w in
            let nav = try #require(Self.navigationController(w), "a navigation controller")
            #expect(nav.topViewController?.navigationItem.hidesBackButton == false)
            #expect(nav.interactivePopGestureRecognizer?.isEnabled == true, "step 5 goes back with a swipe")
            if #available(iOS 26.0, *) {
                // On by default: step 6 is what turns it off.
                #expect(nav.interactiveContentPopGestureRecognizer?.isEnabled == true, "iOS 26's content swipe on step 5")
            }
        }
    }

    private static func navigationController(_ w: HostedWindow) -> UINavigationController? {
        func find(_ controller: UIViewController) -> UINavigationController? {
            if let nav = controller as? UINavigationController { return nav }
            return controller.children.lazy.compactMap(find).first ?? controller.presentedViewController.flatMap(find)
        }
        return find(w.host)
    }

    // MARK: the pinned pill per state

    struct PillCase: CustomTestStringConvertible, Sendable {
        let screen: String
        /// identifier → title, in the bar.
        let pills: [String: String]
        var disabled: [String] = []
        /// Identifiers that must not show.
        var absent: [String] = []
        var caption: String?
        var testDescription: String { screen }
    }

    nonisolated static let pills = [
        PillCase(screen: "1-pick", pills: ["import.choose": "Choose files"]),
        PillCase(screen: "2-detected", pills: ["import.continue": "Continue"]),
        PillCase(screen: "2-detected-not-supported", pills: ["import.chooseAnother": "Choose another file"], absent: ["import.continue"]),
        PillCase(screen: "3-choose", pills: ["import.continue": "Continue"]),
        PillCase(screen: "3-choose-nothing", pills: ["import.continue": "Continue"], disabled: ["import.continue"],
                 caption: "Turn on at least one to continue."),
        PillCase(screen: "5-preview-keep", pills: ["import.keep": "Keep on this iPhone"], absent: ["import.import"]),
        PillCase(screen: "5-preview-already", pills: ["import.done": "Done"], absent: ["import.import"]),
        PillCase(screen: "6-uploading", pills: [:], absent: ["import.openHistory", "import.done", "import.discardJob"]),
        PillCase(screen: "6-preparing", pills: [:], absent: ["import.openHistory", "import.done", "import.discardJob"]),
        PillCase(screen: "6-done-plan", pills: ["import.openHistory": "Open history", "import.openPlan": "Open plan"]),
        PillCase(screen: "6-rejections", pills: ["import.retryRejected": "Retry 4", "import.done": "Done"],
                 absent: ["import.openHistory"]),
        PillCase(screen: "6-saved", pills: ["import.done": "Done", "import.discardJob": "Discard import"]),
        PillCase(screen: "6-gated", pills: ["import.continueInApp": "Continue in RYFT", "import.discardJob": "Discard import"],
                 absent: ["import.done"]),
        PillCase(screen: "6-offline", pills: ["import.done": "Done", "import.discardJob": "Discard import"],
                 absent: ["import.openHistory"]),
        PillCase(screen: "6-retrying", pills: ["import.done": "Done", "import.discardJob": "Discard import"],
                 absent: ["import.openHistory"]),
        PillCase(screen: "6-attention", pills: ["import.done": "Done", "import.discardJob": "Discard import"],
                 absent: ["import.openHistory"]),
        PillCase(screen: "6-account", pills: ["import.done": "Done"], absent: ["import.discardJob"]),
    ]

    @Test("Test 14: the pinned pill's title per state; one primary and at most one secondary", arguments: Self.pills)
    func pill(_ c: PillCase) async throws {
        try await host(c.screen) { w in
            let nodes = w.nodes()
            for (identifier, title) in c.pills {
                let pill = try #require(nodes.first { $0.identifier == identifier }, "\(identifier)")
                #expect(pill.label == title, "\(identifier): \(pill.label)")
                #expect(pill.isEnabled == !c.disabled.contains(identifier), "\(identifier) enabled")
                #expect(pill.frame.height >= 44, "\(identifier): \(pill.frame)")
            }
            for identifier in c.absent {
                #expect(!nodes.contains { $0.identifier == identifier }, "\(identifier) shows")
            }
            if let caption = c.caption {
                let line = try #require(nodes.first { $0.label == caption }, "the caption")
                let pill = try #require(nodes.first { $0.identifier == c.pills.keys.first })
                #expect(line.frame.maxY <= pill.frame.minY + 0.5, "the caption above the pill: \(line.frame) \(pill.frame)")
            }
        }
    }

    @Test("Saved on this iPhone, a gate, paused (offline, a retry, a hold, refused): one pill; Discard a quieter text action under it")
    func pausedBar() async throws {
        // C §2.6: a destructive pill only where it is a page's only action; here Done or Continue in RYFT is the pill.
        for screen in ["6-saved", "6-gated", "6-offline", "6-retrying", "6-attention"] {
            try await host(screen) { w in
                let nodes = w.nodes()
                let pill = nodes.first { $0.identifier == "import.done" || $0.identifier == "import.continueInApp" }
                let done = try #require(pill, "\(screen)")
                let discard = try #require(nodes.first { $0.identifier == "import.discardJob" }, "\(screen)")
                #expect(discard.frame.minY >= done.frame.maxY - 0.5, "\(screen): under the pill \(discard.frame) \(done.frame)")
                #expect(discard.frame.height >= 43.5, "\(screen): \(discard.frame)")
                #expect(discard.frame.width < done.frame.width / 2, "\(screen): a text action, not a pill: \(discard.frame)")
            }
        }
    }

    @Test("Discard import (paused): the tap asks first; the job stays until Discard is confirmed")
    func discardAsks() async throws {
        let h = ImportUploadHarness(online: false)
        #expect(await h.run(ImportUploadPlan(sessions: ImportUploadHarness.sessions(2))))
        #expect(h.uploader.status?.phase == .paused(.offline))
        let model = ImportMockData.flow(.result, uploader: h.uploader)
        try await host(ImportFlowView(model: model).previewEnvironment()) { w in
            let discard = try #require(w.nodes().first { $0.identifier == "import.discardJob" })
            #expect(discard.activate())
            try await w.wait("the question") { model.confirmsDiscardJob }
            #expect(model.job != nil && h.jobs().count == 1, "nothing discarded yet")
        }
    }

    // MARK: selection

    @Test("Step 3: the plan's toggle row turns it off and on; history's toggle shows the range only while on")
    func selection() async throws {
        let model = ImportMockData.flow(.choose, enrolled: false)
        try await host(ImportFlowView(model: model).previewEnvironment()) { w in
            let plan = try #require(w.nodes().first { $0.identifier == "import.plan.0" })
            #expect(plan.value == "1", "on: \(plan.value ?? "nil")")
            #expect(plan.frame.height >= 44)
            plan.activate()
            try await w.wait("the plan off") { model.selection?.plans.first?.isOn == false }
            try await w.settle()
            #expect(w.nodes().first { $0.identifier == "import.plan.0" }?.value == "0")
            #expect(w.nodes().contains { $0.identifier == "import.range" }, "history on: the range shows")
            let history = try #require(w.nodes().first { $0.identifier == "import.history" })
            history.activate()
            try await w.wait("history off") { model.selection?.includesHistory == false }
            try await w.settle()
            #expect(!w.nodes().contains { $0.identifier == "import.range" }, "history off: no range")
        }
    }

    @Test("Step 3, a range without workouts: VoiceOver reads the words, not the glyph")
    func emptyRangeSpeech() async throws {
        try await host("3-choose-range-empty") { w in
            let range = try #require(w.nodes().first { $0.identifier == "import.range" })
            let spoken = range.value ?? ""
            let detail = spoken.components(separatedBy: ", ").last?.trimmingCharacters(in: .whitespaces)
            #expect(detail == "0 workouts in this range", "\(spoken)")
        }
    }

    // MARK: step 4

    @Test("Step 4: each row says its status in words and keeps its actions; the count line is one sentence")
    func matchRows() async throws {
        try await host("4-map") { w in
            let nodes = w.nodes()
            let rows = nodes.filter { $0.identifier?.hasPrefix("import.row.") == true }
            #expect(rows.count >= 4, "\(rows.count) rows")
            let words = ["Matched", "Check", "New", "Your choice", "Skipped", "question open"]
            for row in rows {
                #expect(words.contains { row.label.contains($0) }, "a status word: \(row.label)")
                #expect(row.frame.height >= 44, "\(row.label): \(row.frame)")
            }
            #expect(rows.contains { $0.actionNames.contains("Use suggestion") }, "the actions stay")
            #expect(nodes.contains { $0.identifier == "import.mapCount" })
            #expect(nodes.contains { $0.label == "Needs your attention" && $0.traits.contains(.header) })
        }
    }

    // MARK: progress

    @Test("The progress bar: ink to the fraction, the dim track after it; paused, the track stays 3 pt under its cap")
    func progressBarFill() async throws {
        // Each bar in a labelled container, so the test reads where it landed.
        func marked(_ bar: ImportProgressBar, _ name: String) -> some View {
            bar.frame(width: 300).accessibilityElement(children: .ignore).accessibilityLabel(Text(verbatim: name))
        }
        let bars = VStack(alignment: .leading, spacing: 50) {
            marked(ImportProgressBar(fraction: 40.0 / 120.0), "running")
            marked(ImportProgressBar(fraction: 40.0 / 120.0, isPaused: true), "paused")
        }
        .padding(45)
        try await HostedWindow.run(width: 390, height: 400, Theme.background.overlay(alignment: .topLeading) { bars }) { w in
            try await w.settle()
            let running = try #require(w.node("running", exactly: true)).frame
            let paused = try #require(w.node("paused", exactly: true)).frame
            #expect(abs(running.height - 3) < 0.5 && abs(paused.height - 7.5) < 0.5, "\(running) \(paused)")
            let ink = try #require(w.pixel(at: CGPoint(x: running.minX + 50, y: running.midY)))
            let track = try #require(w.pixel(at: CGPoint(x: running.minX + 200, y: running.midY)))
            let ground = try #require(w.pixel(at: CGPoint(x: running.minX + 200, y: running.maxY + 25)))
            #expect(ink.r > 0.8 && ink.g > 0.8 && ink.b > 0.8, "the fill is ink: \(ink)")
            #expect(track.r < 0.4 && track.r > ground.r + 0.03, "the track is a dim ink: \(track) on \(ground)")
            #expect(abs(track.r - track.b) < 0.05, "no colour in the track: \(track)")
            // Paused: 7.5 pt high (its cap), the track 3 pt in its middle.
            let pausedTrack = try #require(w.pixel(at: CGPoint(x: paused.minX + 200, y: paused.midY)))
            let besideTrack = try #require(w.pixel(at: CGPoint(x: paused.minX + 200, y: paused.minY + 1)))
            #expect(pausedTrack.r > ground.r + 0.03, "the paused track: \(pausedTrack)")
            #expect(abs(besideTrack.r - ground.r) < 0.02, "nothing above the track: \(besideTrack) vs \(ground)")
        }
    }

    @Test("Step 6 uploading: one progress element, Import progress, its value 40 of 120 workouts; no buttons")
    func progressValue() async throws {
        let job = MockTrainImport.status(.uploading, sessions: 40, of: 120)
        let model = ImportMockData.flow(.result, uploader: ImportMockData.uploader(job))
        try await host(ImportFlowView(model: model).previewEnvironment()) { w in
            let nodes = w.nodes()
            let progress = try #require(nodes.first { $0.identifier == "import.progress" })
            #expect(progress.label == "Import progress")
            #expect(progress.value?.hasSuffix("40 of 120 workouts") == true, "\(progress.value ?? "nil")")
            #expect(nodes.contains { $0.label == "Importing…" && $0.traits.contains(.header) }, "the lead line")
            #expect(!nodes.contains { $0.label.hasPrefix("Imported") || $0.label == "Done" }, "nothing claims done")
        }
    }

    // MARK: the result

    @Test("Done on a result with refused items marks it seen (I4) and closes")
    func doneMarksSeen() async throws {
        let h = ImportUploadHarness()
        let sessions = ImportUploadHarness.sessions(3)
        h.live.trainImportSource.rejectIDs = [sessions[1].id: "exercise not found"]
        #expect(await h.run(ImportUploadPlan(sessions: sessions)))
        #expect(h.uploader.status?.isFinished == true && h.uploader.status?.hasRejected == true)
        let model = ImportMockData.flow(.result, uploader: h.uploader)
        var finished: [ImportFlowModel.Finish] = []
        model.onFinish = { finished.append($0) }
        try await host(ImportFlowView(model: model).previewEnvironment()) { w in
            #expect(h.uploader.status?.resultSeen == false, "shown isn't seen while items were refused")
            let done = try #require(w.nodes().first { $0.identifier == "import.done" })
            #expect(done.activate())
            try await w.wait("seen") { h.uploader.status?.resultSeen == true }
            #expect(finished == [.close])
        }
    }

    @Test("Open plan opens the plan the import wrote")
    func openPlanFinishes() async throws {
        let model = ImportMockData.flow(.result, uploader: ImportMockData.uploader(MockTrainImport.done))
        var finished: [ImportFlowModel.Finish] = []
        model.onFinish = { finished.append($0) }
        try await host(ImportFlowView(model: model).previewEnvironment()) { w in
            let open = try #require(w.nodes().first { $0.identifier == "import.openPlan" })
            #expect(open.activate())
            try await w.wait("the finish") { !finished.isEmpty }
            #expect(finished == [.openPlan(MockTrainImport.planID)])
        }
    }

    @Test("Refused items: the lead says so, Not imported opens to each reason with Details, the sentence stays")
    func rejections() async throws {
        try await host("6-rejections") { w in
            var nodes = w.nodes()
            #expect(nodes.contains { $0.label == "Some items weren't imported" && $0.traits.contains(.header) })
            #expect(nodes.contains { $0.identifier == "import.result" && $0.label.hasPrefix("Imported") })
            let header = try #require(nodes.first { $0.identifier == "import.rejected" })
            #expect(header.label == "Not imported (4)" && header.value == "Collapsed")
            #expect(header.frame.height >= 44)
            header.activate()
            try await w.wait("the reasons") { w.nodes().filter { $0.label == "Details" }.count >= 1 }
            try await w.settle()
            nodes = w.nodes()
            #expect(nodes.first { $0.identifier == "import.rejected" }?.value == "Expanded")
            for details in nodes where details.label == "Details" {
                #expect(details.frame.height >= 44 && details.frame.width >= 44, "\(details.frame)")
            }
        }
    }

    @Test("Done: the lead line, the counts as value rows, the strain footer")
    func done() async throws {
        try await host("6-done") { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.label == "Done" && $0.traits.contains(.header) })
            let workouts = try #require(nodes.first { $0.label == "Workouts imported" })
            #expect(workouts.value == "\(MockTrainImport.leftAsIsDone.sessionsImported)", "\(workouts.value ?? "nil")")
            let plans = try #require(nodes.first { $0.label == "Plans imported" }, "the plan was written")
            #expect(plans.value == "1, Upper/Lower · 6 weeks", "\(plans.value ?? "nil")")
            let left = try #require(nodes.first { $0.label == "Left as it is in RYFT" })
            #expect(left.value?.hasPrefix("3") == true, "\(left.value ?? "nil")")
            #expect(nodes.contains { $0.label.hasPrefix("Past strain on these days is being recalculated") })
        }
        // The plan changed in RYFT since (`newer_on_server`): not imported, so no Plans imported row; it's left as it is.
        let job = MockTrainImport.planLeftAsIsDone
        #expect(job.plansImported == 0 && job.planSummaries.allSatisfy { !$0.isImported })
        try await host("6-done-plan-left") { w in
            let nodes = w.nodes()
            #expect(!nodes.contains { $0.label == "Plans imported" }, "no plan was imported")
            #expect(!nodes.contains { $0.label.contains("Upper/Lower") || ($0.value ?? "").contains("Upper/Lower") })
            let left = try #require(nodes.first { $0.label == "Left as it is in RYFT" })
            #expect(left.value?.hasPrefix("1") == true, "\(left.value ?? "nil")")
            let result = try #require(nodes.first { $0.identifier == "import.result" })
            #expect(result.label.hasPrefix("Imported 12 workouts"), "\(result.label)")
            #expect(!result.label.contains("plan"), "\(result.label)")
        }
    }

    // MARK: offline-first

    @Test("Offline, step 6: waiting for a connection, the notice under the progress; nothing claims done")
    func offlineResult() async throws {
        try await host("6-offline") { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.label == "Waiting for a connection" && $0.traits.contains(.header) })
            let progress = try #require(nodes.first { $0.identifier == "import.progress" })
            let notice = try #require(nodes.first { $0.label.hasPrefix("You're offline.") })
            #expect(notice.frame.minY >= progress.frame.maxY, "under the progress: \(notice.frame) \(progress.frame)")
            // The Done pill closes; nothing *says* done: no Done lead, no Imported, no Importing….
            #expect(!nodes.contains { $0.label.hasPrefix("Imported") || $0.label == "Importing…" })
            #expect(!nodes.contains { $0.label == "Done" && $0.traits.contains(.header) })
        }
    }

    @Test("Saved on this iPhone: says so calmly; no Imported, no error, no Retry")
    func savedResult() async throws {
        try await host("6-saved") { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.label == "Saved on this iPhone" && $0.traits.contains(.header) })
            #expect(nodes.contains { $0.identifier == "import.result" && $0.label == "Your import is saved on this iPhone." })
            #expect(!nodes.contains { $0.label.hasPrefix("Imported") || $0.label.hasPrefix("Retry") || $0.label == "Try again" })
        }
    }

    @Test("Offline, step 5: the duplicate check says it waits, above the months")
    func offlinePreview() async throws {
        try await host("5-preview-unchecked") { w in
            let nodes = w.nodes()
            let rows = nodes.filter { $0.identifier?.hasPrefix("import.session.") == true }
            let notice = try #require(nodes.first { $0.label.hasPrefix("You're offline, so RYFT couldn't check for duplicates yet.") })
            let top = notice.frame.maxY
            let firstRow = rows.map(\.frame.minY).min() ?? 0
            #expect(!rows.isEmpty)
            #expect(firstRow >= top, "the notice first: \(top) \(firstRow)")
        }
    }

    @Test("Step 5: Import with uploads available (demo's binding, the flag on); Keep on this iPhone without")
    func previewUploads() async throws {
        #expect(ImportMockData.uploader(nil).uploadsAvailable)
        #expect(!ImportMockData.uploader(nil, available: false).uploadsAvailable)
        try await host("5-preview-plan") { w in
            let nodes = w.nodes()
            let pill = try #require(nodes.first { $0.identifier == "import.import" }, "the Import pill")
            #expect(pill.label.hasPrefix("Import "), "\(pill.label)")
            #expect(pill.isEnabled)
            #expect(!nodes.contains { $0.identifier == "import.keep" })
        }
    }

    @Test("Offline, step 4: the library can't load and the page says so, no spinner")
    func offlineMap() async throws {
        try await host("4-map-offline") { w in
            let nodes = w.nodes()
            #expect(nodes.contains { $0.traits.contains(.staticText) && $0.label.localizedCaseInsensitiveContains("offline")
                || $0.label.localizedCaseInsensitiveContains("couldn't load") }, "\(nodes.map(\.label))")
            #expect(!nodes.contains { $0.traits.contains(.updatesFrequently) }, "no spinner")
        }
    }

    // MARK: the unavailable sheet

    @Test("Test 14: the unavailable sheet: its headline, one OK pill that closes it")
    func unavailableSheet() async throws {
        try await host(SheetHost { ImportUnavailableSheet() }) { w in
            try await w.wait("the sheet") { sheetNodes(w).contains { $0.identifier == "import.unavailable.ok" } }
            try await w.settle()
            let nodes = sheetNodes(w)
            #expect(nodes.contains { $0.label == "Importing isn't available on this account yet" && $0.traits.contains(.header) })
            let ok = try #require(nodes.first { $0.identifier == "import.unavailable.ok" })
            #expect(ok.label == "OK")
            ok.activate()
            try await w.wait("dismissed") { w.nodes().contains { $0.identifier == SheetHost<EmptyView>.closed } }
        }
    }

    // MARK: VoiceOver on step 6

    @Test("VoiceOver hears the lead line as the phase changes (not twice for one line), and the result as it arrives")
    func announcements() {
        typealias T = ImportResultText
        let at = MockTrainImport.createdAt
        let cases: [(from: ImportJobStatus.Phase?, to: ImportJobStatus.Phase, said: String?)] = [
            (.uploading, .paused(.offline), "Waiting for a connection"),
            (.uploading, .paused(.retrying(at: at)), "Import paused"),
            (.uploading, .paused(.held), "Import paused"),
            (.uploading, .paused(.gated(.gate(.consentRequired))), "Import paused"),
            (.uploading, .paused(.needsAttention), "Some items weren't imported"),
            (.uploading, .paused(.notAvailable), "Saved on this iPhone"),
            (.uploading, .paused(.waitingForAccount), "Import needs attention"),
            (.paused(.offline), .uploading, "Importing…"),
            (.preparing, .uploading, "Importing…"),
            (.paused(.retrying(at: at)), .paused(.retrying(at: at.addingTimeInterval(30))), nil),
            (.paused(.retrying(at: at)), .paused(.held), nil),
            (nil, .preparing, nil),
            (.uploading, .uploading, nil),
        ]
        for c in cases {
            #expect(T.announcement(from: c.from, to: MockTrainImport.status(c.to)) == c.said, "\(String(describing: c.from)) → \(c.to)")
        }
        for job in [MockTrainImport.done, MockTrainImport.partlyDone, MockTrainImport.planLeftAsIsDone] {
            #expect(T.announcement(from: .uploading, to: job) == "Import finished. " + T.sentence(job))
        }
        #expect(T.announcement(from: .finished, to: MockTrainImport.done) == nil)
        #expect(T.announcement(from: .uploading, to: nil) == nil, "the job went (discarded)")
    }

    @Test("VoiceOver, hosted: a state change on step 6 is said once; the state it opened on isn't")
    func announcesPhase() async throws {
        let h = ImportUploadHarness(online: false)
        #expect(await h.run(ImportUploadPlan(sessions: ImportUploadHarness.sessions(3))))
        #expect(h.uploader.status?.phase == .paused(.offline))
        let seeded = ImportMockData.flow(.result, uploader: h.uploader)
        let spoken = Spoken()
        var deps = seeded.deps
        deps.announce = { spoken.lines.append($0) }
        let model = ImportFlowModel(deps: deps)
        model.path = seeded.path
        try await host(ImportFlowView(model: model).previewEnvironment()) { w in
            #expect(w.node("Waiting for a connection", exactly: true) != nil)
            // Back online, but importing isn't enabled for the account: saved on this iPhone.
            h.live.trainImportSource.notEnabled = true
            h.connectivity.update(true)
            try await w.wait("saved on this iPhone") { spoken.lines.contains("Saved on this iPhone") }
            // Enabled when the app opens again: it goes, and the result is said.
            h.live.trainImportSource.notEnabled = false
            await h.uploader.appBecameActive()
            let job = try #require(h.uploader.status)
            #expect(job.isFinished)
            let result = "Import finished. " + ImportResultText.sentence(job)
            try await w.wait("the result") { spoken.lines.last == result }
            let leads = spoken.lines.filter { $0 != "Importing…" && $0 != "Getting ready" }
            #expect(leads == ["Saved on this iPhone", result], "\(spoken.lines)")
        }
    }

    @MainActor final class Spoken {
        var lines: [String] = []
    }

    // MARK: AX3 and targets

    nonisolated static let everyScreen = ImportNocturneShotsTests.names.filter { !$0.hasPrefix("sheet") }

    @Test("AX3: nothing leaves the 390 pt page", arguments: Self.everyScreen)
    func ax3(_ screen: String) async throws {
        try await host(screen, typeSize: .accessibility3, category: .accessibilityExtraLarge, height: 9_000) { w in
            let nodes = w.nodes()
            #expect(!nodes.isEmpty)
            for node in nodes where node.frame.width > 0 {
                #expect(node.frame.minX >= -0.5 && node.frame.maxX <= 390.5, "\(node.label) \(node.frame)")
            }
        }
    }

    @Test("AX3: a value row's value goes under its title; the row stays one element")
    func ax3ValueStacks() async throws {
        var defaultHeight: CGFloat = 0
        try await host("6-done") { w in
            defaultHeight = try #require(w.nodes().first { $0.label == "Workouts imported" }).frame.height
        }
        try await host("6-done", typeSize: .accessibility3, category: .accessibilityExtraLarge, height: 9_000) { w in
            let row = try #require(w.nodes().first { $0.label == "Workouts imported" })
            #expect(row.value == "\(MockTrainImport.leftAsIsDone.sessionsImported)")
            #expect(row.frame.height > defaultHeight * 1.6, "the value on its own line: \(row.frame.height) vs \(defaultHeight)")
        }
    }

    nonisolated static let targetScreens = ["1-pick", "1-pick-problem", "2-detected", "3-choose", "3-choose-existing", "4-map",
                                            "5-preview-plan", "5-preview-history", "6-done-plan", "6-rejections", "6-offline",
                                            "6-retrying", "6-attention", "6-saved", "rows-profile", "rows-resume"]

    @Test("44 pt: every button on the page", arguments: Self.targetScreens)
    func targets(_ screen: String) async throws {
        try await host(screen) { w in
            let buttons = w.nodes().filter { $0.traits.contains(.button) && $0.frame.width > 0 }
            #expect(!buttons.isEmpty)
            for button in buttons {
                #expect(button.frame.height >= 43.5 && button.frame.width >= 43.5, "\(button.label) \(button.frame)")
            }
        }
    }

    // MARK: hosting

    private func host(_ screen: String, typeSize: DynamicTypeSize = .large, category: UIContentSizeCategory = .large,
                      height: CGFloat = 2_600, _ body: (HostedWindow) async throws -> Void) async throws {
        try await host(ImportNocturneShotsTests.screen(screen), typeSize: typeSize, category: category, height: height, body)
    }

    /// The page in a 390 pt window with the app's toggle style, settled, in US English.
    private func host(_ view: some View, typeSize: DynamicTypeSize = .large, category: UIContentSizeCategory = .large,
                      height: CGFloat = 2_600, _ body: (HostedWindow) async throws -> Void) async throws {
        let page = view.toggleStyle(.ryft).environment(\.locale, Locale(identifier: "en_US"))
        try await HostedWindow.run(width: 390, height: height, typeSize: typeSize, category: category, page) { w in
            try await w.settle()
            try await body(w)
        }
    }
}
