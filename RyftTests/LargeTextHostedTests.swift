import SwiftUI
import Testing
import UIKit
@testable import Ryft

/// Welcome, the Start workout sheet and the live workout (the List layout, what a session opens in while
/// `train.focused_session` is off) at the largest text sizes, in a window the size of an iPhone 17 Pro and read through
/// the accessibility tree (`HostedWindow`): the frames VoiceOver uses. A line that was cut short or a word that broke has a
/// frame smaller than its text needs, measured here on its own in the same font at the same size. Synthetic values only.
///
/// Not covered here: how VoiceOver reads it aloud, and a real tap on the link (a device with VoiceOver, or a UI test).
@MainActor
@Suite("Largest text sizes: Welcome and the live workout, hosted", .serialized)
struct LargeTextHostedTests {
    struct SizeCase: Sendable, CustomTestStringConvertible {
        let size: DynamicTypeSize
        let category: UIContentSizeCategory
        var testDescription: String { "\(size)" }
    }

    nonisolated static let ax3 = SizeCase(size: .accessibility3, category: .accessibilityExtraLarge)
    nonisolated static let ax5 = SizeCase(size: .accessibility5, category: .accessibilityExtraExtraExtraLarge)
    private static let width: CGFloat = 402, height: CGFloat = 874, bottomInset: CGFloat = 34

    /// What `view` takes on its own at `size`, offered `width` (nil: as wide as it likes).
    private func needs(_ view: some View, width: CGFloat? = nil, size: DynamicTypeSize) -> CGSize {
        let host = UIHostingController(rootView: view.environment(\.dynamicTypeSize, size))
        return host.sizeThatFits(in: CGSize(width: width ?? 10000, height: 10000))
    }

    private func run(_ s: SizeCase, _ content: some View, body: (HostedWindow) async throws -> Void) async throws {
        try await HostedWindow.run(width: Self.width, height: Self.height, bottomInset: Self.bottomInset, typeSize: s.size,
                                   category: s.category, content, body: body)
    }

    // MARK: Welcome

    private static let privacyLine = "Your data is stored on the RYFT platform."

    @Test("Welcome: the privacy line wraps whole, scrolls into view, and VoiceOver's Links rotor reaches its link",
          arguments: [ax3, ax5])
    func welcomePrivacyLine(_ s: SizeCase) async throws {
        try await run(s, WelcomeView().environment(AuthService.preview(signedIn: false))) { w in
            try await w.settle()
            let line = try #require(w.node(Self.privacyLine), "\(w.nodes().map(\.label))")
            let text = Text("Your data is stored on the RYFT platform. [Privacy Policy](https://ryftapp.de/privacy)")
                .font(.ryft(.caption))
                .multilineTextAlignment(.center)
            let whole = needs(text, width: line.frame.width, size: s.size).height
            #expect(line.frame.height >= whole - 1, "cut short: \(line.frame), the line needs \(whole)")

            // The page scrolls, and at its end the whole line is on screen, above the home indicator.
            let scroll = try #require(w.pageScrollView(), "the content scrolls")
            let end = scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, end)), animated: false)
            try await w.settle()
            let shown = try #require(w.node(Self.privacyLine))
            #expect(shown.frame.minY >= 0 && shown.frame.maxY <= Self.height - Self.bottomInset, "\(shown.frame)")

            // VoiceOver: the link is an element of its own on the Links rotor, inside the line's frame.
            let links = shown.links
            #expect(links.map(\.label) == ["Privacy Policy"], "\(links.map { "\($0.label) \($0.frame) \($0.traits.rawValue)" })")
            if let link = links.first {
                #expect(link.traits.contains(.link), "traits \(link.traits.rawValue)")
                #expect(shown.frame.insetBy(dx: -1, dy: -1).contains(link.frame), "link \(link.frame), line \(shown.frame)")
            }
        }
    }

    /// The ways in and the privacy line share no point: nothing is drawn over anything else, even at AX5.
    @Test("Welcome: no two elements overlap", arguments: [ax3, ax5])
    func welcomeHasNoOverlap(_ s: SizeCase) async throws {
        try await run(s, WelcomeView().environment(AuthService.preview(signedIn: false))) { w in
            try await w.settle()
            let nodes = w.nodes()
            #expect(nodes.count >= 7, "\(nodes.map(\.label))")
            for (i, a) in nodes.enumerated() {
                for b in nodes[(i + 1)...] {
                    let overlap = a.frame.intersection(b.frame)
                    #expect(overlap.isNull || overlap.width < 1 || overlap.height < 1,
                            "'\(a.label)' \(a.frame) overlaps '\(b.label)' \(b.frame)")
                }
            }
        }
    }

    // MARK: Start workout

    @Test("Start workout: an option's detail line wraps whole", arguments: [ax3, ax5])
    func startSheetDetailWraps(_ s: SizeCase) async throws {
        let detail = try #require(TrainPreview.library.today.map { "\($0.day.name) · \(TodayPlanText.detail($0))" })
        try await run(s, StartWorkoutSheet()) { w in
            try await w.settle()
            let option = try #require(w.nodes().first { $0.label.contains("From today's plan") }, "\(w.nodes().map(\.label))")
            // The option as `StartWorkoutSheet.option` lays it out (icon, title over detail, the room after them), with the
            // detail free to take every line it needs.
            let whole = HStack(spacing: 14) {
                Color.clear.frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("From today's plan").font(.ryft(.headline))
                    Text(verbatim: detail).font(.ryft(.caption))
                }
                Spacer()
            }
            .padding(14)
            .frame(minHeight: 64)
            let height = needs(whole, width: option.frame.width, size: s.size).height
            #expect(option.frame.height >= height - 1, "cut short: \(option.frame), the option needs \(height)")
        }
    }

    // MARK: the live workout

    /// Finish is a word in a capsule 18 pt a side: broken over two lines, the capsule is narrower than the word.
    @Test("Live workout: Finish is one whole word, and the session's title has room", arguments: [ax3, ax5])
    func sessionHeader(_ s: SizeCase) async throws {
        let c = TrainPreview.liveController()
        defer { c.stop() }
        #expect(c.layout == .list)
        let title = c.session.title
        try await run(s, SessionView(controller: c)) { w in
            try await w.settle()
            let finish = try #require(w.node("Finish", exactly: true), "\(w.nodes().map(\.label).prefix(8))")
            let word = needs(Text("Finish").font(.ryft(.headline)), size: s.size)
            #expect(finish.frame.width >= word.width + 2 * 18 - 1, "\(finish.frame), the word is \(word.width)")
            #expect(finish.frame.minX >= 0 && finish.frame.maxX <= Self.width, "\(finish.frame)")

            // The title and the clock are one element, whose frame is the room the title has.
            let header = try #require(w.node("\(title), elapsed time"), "\(w.nodes().map(\.label).prefix(8))")
            let line = needs(Text(verbatim: title).font(.ryft(.callout)), size: s.size).width
            #expect(header.frame.width >= line - 0.5, "\(header.frame), the title is \(line)")
            #expect(header.frame.minX >= 0 && header.frame.maxX <= Self.width, "\(header.frame)")
        }
    }

    /// The column titles sit between the card's header and its first set, 10 pt from each: what's left between them is the
    /// titles' row, which is one line of text unless a word broke ("S/et", "Rep/s", "RP/E").
    @Test("Live workout: the set table's column titles are one line", arguments: [ax3, ax5])
    func setTableTitles(_ s: SizeCase) async throws {
        let c = TrainPreview.liveController()
        defer { c.stop() }
        let exercise = try #require(c.exercises.first)
        try await HostedWindow.run(width: Self.width, height: 1600, bottomInset: Self.bottomInset, typeSize: s.size,
                                   category: s.category, SessionView(controller: c)) { w in
            try await w.settle()
            let name = try #require(w.node(exercise.name, exactly: true), "\(w.nodes().map(\.label).prefix(12))")
            let firstSet = try #require(w.node("Set 1 of"), "\(w.nodes().map(\.label).prefix(12))")
            let cardHeader = w.nodes().filter { $0.frame.minY >= name.frame.minY - 0.5 && $0.frame.maxY <= firstSet.frame.minY + 0.5 }
            let headerBottom = cardHeader.map(\.frame.maxY).max() ?? name.frame.maxY
            let titles = firstSet.frame.minY - headerBottom - 2 * 10
            let line = needs(Text("Reps").font(.ryft(.label)), size: s.size).height
            #expect(titles < 1.5 * line, "the titles' row is \(titles) high, a line \(line): \(cardHeader.map(\.label))")
        }
    }
}
