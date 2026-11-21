import Testing
import UIKit
@testable import Ryft

/// The back swipe on pages without a bar (`SubpageScaffold`'s `InteractivePopGestureKeeper`, PR 6 A D6A-6): when it may
/// begin, as values (`BackSwipeRule`), and that the keeper decides only that, leaving every other answer to UIKit's
/// delegate (so the content swipe still yields to a list's swipe actions and to controls).
@MainActor
@Suite("The back swipe without a bar")
struct BackSwipeKeeperTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        var pages = 2
        var transitioning = false
        var hidesBackButton = false
        var swipe = BackSwipeRule.Swipe.edge
        let begins: Bool
        var testDescription: String { name }
    }

    nonisolated private static func content(_ x: CGFloat, _ y: CGFloat = 0, rightToLeft: Bool = false,
                                            onBackScroller: Bool = false) -> BackSwipeRule.Swipe {
        .content(velocity: CGPoint(x: x, y: y), rightToLeft: rightToLeft, startsOnBackScroller: onBackScroller)
    }

    nonisolated static let cases: [Case] = [
        Case(name: "the edge on a pushed page", begins: true),
        Case(name: "the edge on the root", pages: 1, begins: false),
        Case(name: "the edge during a push or pop", transitioning: true, begins: false),
        Case(name: "the edge on a page that hides Back", hidesBackButton: true, begins: false),
        Case(name: "the content, sideways to the trailing edge", swipe: content(300, 40), begins: true),
        Case(name: "the content, towards the leading edge", swipe: content(-300), begins: false),
        Case(name: "the content, still", swipe: content(0), begins: false),
        Case(name: "the content, more down than sideways", swipe: content(200, 260), begins: false),
        Case(name: "the content, right to left: towards the left", swipe: content(-300, rightToLeft: true), begins: true),
        Case(name: "the content, right to left: towards the right", swipe: content(300, rightToLeft: true), begins: false),
        Case(name: "the content, started on a scroller that can scroll back", swipe: content(300, onBackScroller: true),
             begins: false),
        Case(name: "the content on the root", pages: 1, swipe: content(300), begins: false),
        Case(name: "the content during a push or pop", transitioning: true, swipe: content(300), begins: false),
        Case(name: "the content on a page that hides Back", hidesBackButton: true, swipe: content(300), begins: false),
    ]

    @Test("When the back swipe may begin", arguments: cases)
    func mayBegin(_ c: Case) {
        #expect(BackSwipeRule.mayBegin(pages: c.pages, transitioning: c.transitioning, hidesBackButton: c.hidesBackButton,
                                       swipe: c.swipe) == c.begins)
    }

    @Test("A scroller can scroll back when it is wider than its frame and not at its leading end, in either direction")
    func canScrollBack() {
        let none = UIEdgeInsets.zero, inset = UIEdgeInsets(top: 0, left: 20, bottom: 0, right: 20)
        func back(_ content: CGFloat, _ offset: CGFloat, _ insets: UIEdgeInsets = .zero, rtl: Bool = false) -> Bool {
            BackSwipeRule.canScrollBack(contentWidth: content, width: 390, offset: offset, insets: insets, rightToLeft: rtl)
        }
        #expect(!back(390, 0), "not wider than its frame")
        #expect(!back(390.4, 0.4), "half a point is rounding")
        #expect(!back(800, 0, none), "at the leading end")
        #expect(back(800, 120, none))
        #expect(!back(800, -20, inset), "at the leading end, past the inset")
        #expect(back(800, 0, inset), "the inset still to go")
        // Right to left the leading end is the far one: content + right inset − width.
        #expect(!back(800, 410, none, rtl: true))
        #expect(back(800, 0, none, rtl: true))
        #expect(!back(800, 430, inset, rtl: true))
    }

    /// UIKit's delegate, as far as the keeper sees it: what it was asked.
    private final class UIKitStandIn: NSObject, UIGestureRecognizerDelegate {
        private(set) var asked: [String] = []

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            asked.append("begin")
            return false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            asked.append("requireFailure")
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            asked.append("simultaneously")
            return false
        }

        /// As UIKit's own: a private question outside the protocol, which refuses every event without a bar.
        @objc(_gestureRecognizer:shouldReceiveEvent:)
        func privateShouldReceive(_ gestureRecognizer: UIGestureRecognizer, event: UIEvent) -> Bool {
            asked.append("private")
            return false
        }
    }

    private static let privateEventGate = NSSelectorFromString("_gestureRecognizer:shouldReceiveEvent:")

    private static let requireFailure = #selector(UIGestureRecognizerDelegate.gestureRecognizer(_:shouldRequireFailureOf:))
    private static let requiredToFail = #selector(UIGestureRecognizerDelegate.gestureRecognizer(_:shouldBeRequiredToFailBy:))

    @Test("The keeper decides only the start: UIKit's delegate still answers the protocol's other questions, also after the keeper is set again")
    func uikitAnswersTheRest() throws {
        let nav = UINavigationController(rootViewController: UIViewController())
        nav.loadViewIfNeeded()
        let pop = try #require(nav.interactivePopGestureRecognizer)
        let uikit = UIKitStandIn()
        pop.delegate = uikit
        InteractivePopGestureKeeper.keep(nav)
        let keeper = try #require(pop.delegate as? InteractivePopGestureKeeper)
        let delegate: UIGestureRecognizerDelegate = keeper
        let other = UIPanGestureRecognizer()

        #expect(keeper.responds(to: Self.requireFailure))
        #expect(!keeper.responds(to: Self.requiredToFail), "nothing UIKit's delegate doesn't answer")
        #expect(uikit.responds(to: Self.privateEventGate) && !keeper.responds(to: Self.privateEventGate),
                "nothing outside the protocol: UIKit's private event check refuses every event without a bar")
        #expect(keeper.forwardingTarget(for: Self.privateEventGate) == nil)
        #expect(delegate.gestureRecognizer?(pop, shouldRequireFailureOf: other) == true)
        #expect(delegate.gestureRecognizer?(pop, shouldRecognizeSimultaneouslyWith: other) == false)
        #expect(uikit.asked == ["requireFailure", "simultaneously"])

        // The start is the keeper's own (UIKit's would refuse it without a bar): the root, no; pushed, yes; a page that
        // hides Back, no.
        #expect(!keeper.gestureRecognizerShouldBegin(pop))
        nav.pushViewController(UIViewController(), animated: false)
        #expect(keeper.gestureRecognizerShouldBegin(pop))
        nav.topViewController?.navigationItem.hidesBackButton = true
        #expect(!keeper.gestureRecognizerShouldBegin(pop))
        #expect(!uikit.asked.contains("begin"))

        // Each appearance sets it again: the same keeper, still answering through UIKit's delegate, not through itself.
        InteractivePopGestureKeeper.keep(nav)
        #expect(pop.delegate === keeper)
        #expect(delegate.gestureRecognizer?(pop, shouldRequireFailureOf: other) == true)
        #expect(uikit.asked.count == 3)
    }

    @Test("iOS 26's content swipe gets a keeper of its own, which answers the protocol's other questions through UIKit's delegate")
    func contentSwipeKeepsUIKitsAnswers() throws {
        guard #available(iOS 26.0, *) else { return }
        let nav = UINavigationController(rootViewController: UIViewController())
        nav.loadViewIfNeeded()
        let content = try #require(nav.interactiveContentPopGestureRecognizer)
        let original = try #require(content.delegate as? NSObject, "UIKit's delegate of the content swipe")
        InteractivePopGestureKeeper.keep(nav)
        let keeper = try #require(content.delegate as? InteractivePopGestureKeeper)
        #expect(keeper !== nav.interactivePopGestureRecognizer?.delegate, "one keeper per swipe")
        let questions = [
            Self.requireFailure, Self.requiredToFail,
            #selector(UIGestureRecognizerDelegate.gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)),
            NSSelectorFromString("gestureRecognizer:shouldReceiveTouch:"),
        ]
        for question in questions {
            #expect(keeper.responds(to: question) == original.responds(to: question), "\(question)")
            if original.responds(to: question) {
                #expect(keeper.forwardingTarget(for: question) as AnyObject? === original, "\(question)")
            }
        }
        // UIKit's private event check isn't asked: it would refuse the swipe on every page without a bar.
        #expect(!keeper.responds(to: Self.privateEventGate))
    }
}
