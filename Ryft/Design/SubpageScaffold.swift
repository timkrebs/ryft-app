// The frame of a pushed page and of a sheet's own page (Nocturne, docs/work/2026-11-16-nocturne/build-plan.md §2; PR 6 A G3,
// A-2 "Swipe back", §3 `PinnedBar`; C §2.1, §3 row 3; Nocturne gate D4 and DG-6, docs/work/2026-11-20-nocturne-gate/design.md
// §2.4): the navigation bar hidden, one of the app's two headers, 22 below it the scrolling content 20 from the sides, and an
// optional pinned action bar. A pushed page has `PushedHeader`'s row (Back, the title centred, a trailing circle or the empty
// slot), scrolling with the page; a sheet's root has `SheetHeader` (the close circle leading, the title centred, the trailing
// slot), pinned above the scroll. The interactive back swipe keeps working although the bar is hidden.
import SwiftUI
import UIKit

/// The subpage frame's numbers.
enum SubpageSpec {
    /// The header row: 40 high (`ScreenHeaderSpec.height`); it grows only when the title wraps.
    static let headerHeight = ScreenHeaderSpec.height
    /// Between two trailing circles (circle edge to circle edge).
    static let trailingSpacing: CGFloat = 8
    /// The header → the content (the Strain board's 22).
    static let contentGap: CGFloat = 22
    /// Under the last group, above the safe area (or the pinned bar).
    static let bottomPadding: CGFloat = 32
    /// The content's sides: 350 pt of content on a 390 pt phone.
    static let sidePadding = Theme.Metrics.screenPadding
    /// On a wide window the column stays readable, centred (`ImportStepScaffold`'s 560).
    static let maxContentWidth: CGFloat = 560
    /// A sheet's page starts 26 below the sheet's top edge: 14 under the grabber (derived, PR 6 B §1.2, C §2.1).
    static let sheetTopInset: CGFloat = 26
    /// `PushedHeader` from AX1 (C §2.9): the buttons' row, 12, then the title.
    static let stackedGap: CGFloat = 12
    /// The header's identifiers: `subpage.back`, `subpage.close`, `subpage.header` (the title of a pushed page).
    static let identifierPrefix = "subpage"
}

/// What a header circle does when tapped.
enum SubpageButtonAction {
    /// The environment's `dismiss`: pops the page, or closes the sheet at its root.
    case dismiss
    /// The caller's: a sheet that would discard work asks first ("Discard this import?").
    case perform(() -> Void)

    /// The closure for a header's `onBack` / `onClose`: nil lets the header dismiss through its own environment.
    var handler: (() -> Void)? {
        if case .perform(let perform) = self { return perform }
        return nil
    }
}

/// The header's circle buttons, and so which of the two headers the page has (D4, DG-6).
enum SubpageNavigation {
    /// A pushed page: `PushedHeader`'s row. Back (`chevron.left`) leading, the title centred in `callout`, the trailing circles
    /// or the empty 40 pt slot; it scrolls with the page, and from AX1 the title goes under the buttons' row.
    case back(SubpageButtonAction = .dismiss)
    /// A sheet's root: `SheetHeader`, pinned above the scroll. The close circle leading, labelled "Close" (or the caller's:
    /// "Cancel" when it discards, "Done" when nothing is lost), the title centred, the trailing circles in the trailing slot.
    case close(label: Text? = nil, SubpageButtonAction = .dismiss)
    /// A step pushed inside a sheet that can be closed from any step (D4 rule 6): `PushedHeader`'s row with Back leading and
    /// the close circle trailing, after the trailing circles; the title stays centred on the row.
    case backAndClose(back: SubpageButtonAction = .dismiss, closeLabel: Text? = nil, close: SubpageButtonAction = .dismiss)
    /// No circle: a stack's root page (a Debug host) with its title centred and the trailing circles, if any.
    case none
}

/// A subpage: `SubpageScaffold(Text("Display")) { groups }`; a sheet's root: `SubpageScaffold(Text("What do you wear?"),
/// navigation: .close(), isSheet: true) { … }`. A pinned primary goes under it with `.pinnedBar { PillButton(…) }`.
///
/// - The navigation bar is hidden; the page draws its own header (`SubpageNavigation` says which).
/// - Trailing: 0–2 `CircleButton`s or `CircleMenu`s, laid out as their 40 pt circles 8 apart (their 44 pt boxes reach 2
///   past them). On a sheet's root they are `SheetHeader`'s trailing slot.
/// - From the header to the content 22; the content 20 from the sides, at most 560 wide, 32 above the bottom.
/// - The back swipe pops the page (`InteractivePopGesture`), as with the system bar.
/// - `isSheet`: 26 from the sheet's top edge, the sheet's background is `background` and its grabber shows.
/// - Identifiers: `subpage.back`, `subpage.close`, and `subpage.header` for a pushed page's title.
struct SubpageScaffold<Trailing: View, Content: View>: View {
    private let title: Text
    private let navigation: SubpageNavigation
    private let isSheet: Bool
    private let trailing: Trailing
    private let content: Content

    @Environment(\.dismiss) private var dismiss

    init(_ title: Text, navigation: SubpageNavigation = .back(), isSheet: Bool = false,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title
        self.navigation = navigation
        self.isSheet = isSheet
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        page
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .keepsBackSwipe()
            .modifier(SheetPresentation(isSheet: isSheet))
    }

    @ViewBuilder private var page: some View {
        if case .close(let label, let action) = navigation {
            // A sheet's root (D4): the header stays put while the page scrolls under it, so Close is always in reach.
            VStack(spacing: 0) {
                SheetHeader(title, closeLabel: label, onClose: action.handler) { sheetTrailing }
                    .closeIdentifier("\(SubpageSpec.identifierPrefix).close")
                    .frame(maxWidth: SubpageSpec.maxContentWidth)
                    .padding(.horizontal, SubpageSpec.sidePadding)
                    .padding(.top, isSheet ? SubpageSpec.sheetTopInset : 0)
                    .frame(maxWidth: .infinity)
                scroll(topInset: 0) { EmptyView() }
                    .underPinnedHeader()
            }
        } else {
            scroll(topInset: isSheet ? SubpageSpec.sheetTopInset : 0) { pageHeader }
        }
    }

    /// The content in its column, under `header` (a pushed page's, which scrolls with it).
    private func scroll<Header: View>(topInset: CGFloat, @ViewBuilder header: () -> Header) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header()
                content
                    .padding(.top, SubpageSpec.contentGap)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: SubpageSpec.maxContentWidth)
            .padding(.horizontal, SubpageSpec.sidePadding)
            .padding(.top, topInset)
            .padding(.bottom, SubpageSpec.bottomPadding)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    /// A pushed page's header (DG-6): `PushedHeader`'s row; a root without circles, the title centred.
    @ViewBuilder private var pageHeader: some View {
        switch navigation {
        case .back(let back):
            PushedHeader(title, identifierPrefix: SubpageSpec.identifierPrefix, onBack: back.handler) { trailingSlot(close: nil) }
        case .backAndClose(let back, let label, let close):
            PushedHeader(title, identifierPrefix: SubpageSpec.identifierPrefix, onBack: back.handler) {
                trailingSlot(close: (label ?? CircleButton.closeLabel, close))
            }
        case .none:
            SheetHeader(title) { sheetTrailing }
                .closeHidden()
        case .close:
            EmptyView()
        }
    }

    /// `PushedHeader`'s trailing slot: the caller's circles, then the close circle; with neither, the empty 40 pt slot that
    /// keeps the title centred.
    @ViewBuilder private func trailingSlot(close: (label: Text, action: SubpageButtonAction)?) -> some View {
        if close == nil && Trailing.self == EmptyView.self {
            PushedHeaderEmptySlot()
        } else {
            HStack(spacing: SubpageSpec.trailingSpacing - 2 * ScreenHeaderSpec.buttonOverhang) {
                trailing
                if let close {
                    CircleButton(systemImage: "xmark", accessibilityLabel: close.label) {
                        if let handler = close.action.handler { handler() } else { dismiss() }
                    }
                    .accessibilityIdentifier("\(SubpageSpec.identifierPrefix).close")
                }
            }
        }
    }

    /// `SheetHeader`'s trailing slot: the caller's circles laid out as their 40 pt circles, or nothing.
    @ViewBuilder private var sheetTrailing: some View {
        if Trailing.self != EmptyView.self {
            HStack(spacing: SubpageSpec.trailingSpacing - 2 * ScreenHeaderSpec.buttonOverhang) { trailing }
                .headerEdgeButton()
        }
    }
}

extension SubpageScaffold where Trailing == EmptyView {
    /// A subpage without trailing buttons.
    init(_ title: Text, navigation: SubpageNavigation = .back(), isSheet: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title, navigation: navigation, isSheet: isSheet, trailing: { EmptyView() }, content: content)
    }
}

/// A sheet's page: `background` behind it and the grabber visible (the detents are the presenter's).
private struct SheetPresentation: ViewModifier {
    let isSheet: Bool

    func body(content: Content) -> some View {
        if isSheet {
            content
                .presentationBackground(Theme.background)
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

// MARK: - pinned bar

/// The pinned bar's numbers (A §3 `PinnedBar`, C §2.1).
enum PinnedBarSpec {
    /// Above the first line, at the sides, under the last line (plus the safe area).
    static let topPadding: CGFloat = 12, sidePadding: CGFloat = 20, bottomPadding: CGFloat = 12
    /// Between the caption, the content and the footnote.
    static let spacing: CGFloat = 8
    /// The bar's content is as wide as the page's column.
    static let maxWidth = SubpageSpec.maxContentWidth
}

/// The bar under a long page that holds its one primary action, always reachable: `background`, a 1 pt `separator` rule on
/// top (the tab bar's), 12 above and below its content, 20 at the sides. An optional caption above says why the primary is
/// disabled (12 pt `textSecondary`); an optional footnote under it says what happens (12 pt `textTertiary`); a quiet text
/// action ("Not now") goes in the content under the pill. Use it with `.pinnedBar { … }`, which keeps the page scrollable
/// above it. (A §3 calls it `PinnedBar`; the type keeps this name, and onboarding uses it too.)
struct PinnedActionBar<Content: View>: View {
    private let caption: Text?
    private let footnote: Text?
    private let content: Content

    init(caption: Text? = nil, footnote: Text? = nil, @ViewBuilder content: () -> Content) {
        self.caption = caption
        self.footnote = footnote
        self.content = content()
    }

    var body: some View {
        VStack(spacing: PinnedBarSpec.spacing) {
            if let caption {
                caption
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
            if let footnote {
                footnote
                    .font(.ryft(.caption))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, PinnedBarSpec.topPadding)
        .padding(.horizontal, PinnedBarSpec.sidePadding)
        .padding(.bottom, PinnedBarSpec.bottomPadding)
        .frame(maxWidth: PinnedBarSpec.maxWidth)
        .frame(maxWidth: .infinity)
        .background(Theme.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: Theme.Metrics.hairline)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Pins `content` in a `PinnedActionBar` under the page (`safeAreaInset`): the page scrolls above it, and its last row stays
    /// reachable however tall the bar grows with the text.
    func pinnedBar<Bar: View>(caption: Text? = nil, footnote: Text? = nil, @ViewBuilder _ content: () -> Bar) -> some View {
        let bar = PinnedActionBar(caption: caption, footnote: footnote, content: content)
        return safeAreaInset(edge: .bottom, spacing: 0) { bar }
    }
}

/// The edge of a pinned header (Nocturne gate D4 rule 5): `PinnedActionBar`'s, turned over. While content has scrolled under
/// the header, the page stops `gap` below it (the bar's 12) on the screen colour, at a 1 pt `separator` rule; at rest nothing
/// shows. `SubpageScaffold`'s sheets, `SheetFrame`, the import's sheet roots and the sheets that pin their own `SheetHeader`
/// put it on the scroll view under the header.
private struct PinnedHeaderEdge: ViewModifier {
    let gap: CGFloat
    @State private var contentUnder = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 0.5
            } action: { _, under in
                contentUnder = under
            }
            .overlay(alignment: .top) {
                if contentUnder {
                    Theme.background
                        .frame(height: max(gap, Theme.Metrics.hairline))
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(height: Theme.Metrics.hairline)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    /// On the scroll view under a pinned `SheetHeader` (`PinnedHeaderEdge`): content scrolled under the header stops `gap`
    /// below it at the pinned bar's rule. `gap` no more than the content's own top gap at rest (8 for the journal's strip),
    /// so the first scroll hides nothing at once.
    func underPinnedHeader(gap: CGFloat = PinnedBarSpec.topPadding) -> some View {
        modifier(PinnedHeaderEdge(gap: gap))
    }
}

// MARK: - the back swipe

extension View {
    /// Keeps the edge swipe that pops this page while it hides the navigation bar (`InteractivePopGesture`): every page
    /// with its own header and `.toolbar(.hidden, for: .navigationBar)` (`SubpageScaffold`, the workout detail).
    func keepsBackSwipe() -> some View {
        background { InteractivePopGesture().accessibilityHidden(true) }
    }
}

/// Keeps the edge swipe that pops a page working while the navigation bar is hidden (A D6A-6, C §2.1). UIKit's own delegate
/// refuses the swipe without a bar, so each back-swipe recognizer of the page's navigation controller gets an
/// `InteractivePopGestureKeeper` as its delegate, kept alive with the recognizer: it decides only whether the swipe may
/// begin (`BackSwipeRule`). A page outside a navigation stack (a sheet's root) changes nothing.
private struct InteractivePopGesture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Probe { Probe() }
    func updateUIViewController(_ controller: Probe, context: Context) {}

    final class Probe: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            InteractivePopGestureKeeper.keep(navigationController)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            InteractivePopGestureKeeper.keep(navigationController)
        }
    }
}

/// When a back swipe may begin on a page without a bar (`InteractivePopGestureKeeper`), from plain values.
enum BackSwipeRule {
    enum Swipe: Equatable {
        /// The screen-edge swipe: its recognizer checks the direction itself.
        case edge
        /// iOS 26's swipe from anywhere in the content: its velocity so far, the page's layout direction, and whether it
        /// started on something that scrolls sideways and can still scroll back (`canScrollBack`).
        case content(velocity: CGPoint, rightToLeft: Bool, startsOnBackScroller: Bool)
    }

    /// A page to go back to, no push or pop running, and a Back button the page doesn't hide (Import's result has no way
    /// back): a swipe on the root page would leave the stack stuck. The content swipe also has to go sideways towards the
    /// trailing edge, and not start on a scroller that can scroll back (a carousel keeps its own swipe).
    static func mayBegin(pages: Int, transitioning: Bool, hidesBackButton: Bool, swipe: Swipe) -> Bool {
        guard pages > 1, !transitioning, !hidesBackButton else { return false }
        guard case let .content(velocity, rightToLeft, startsOnBackScroller) = swipe else { return true }
        let forward = rightToLeft ? -velocity.x : velocity.x
        return forward > 0 && abs(velocity.x) > abs(velocity.y) && !startsOnBackScroller
    }

    /// A scroll view wider than its frame and not at its leading end (half a point either way is rounding).
    static func canScrollBack(contentWidth: CGFloat, width: CGFloat, offset: CGFloat, insets: UIEdgeInsets,
                              rightToLeft: Bool) -> Bool {
        guard contentWidth > width + 0.5 else { return false }
        let leadingEnd = rightToLeft ? contentWidth + insets.right - width : -insets.left
        return abs(offset - leadingEnd) > 0.5
    }
}

/// The delegate of one back-swipe recognizer (the edge's, iOS 26's content one) of a navigation controller whose pages hide
/// the bar, retained by the recognizer. It answers only whether the swipe may begin; the protocol's other questions (which
/// touches it takes, what it waits for or runs with: a list's swipe actions, a control's drag) go to UIKit's delegate it
/// replaced.
@MainActor
final class InteractivePopGestureKeeper: NSObject, UIGestureRecognizerDelegate {
    private weak var navigationController: UINavigationController?
    /// UIKit's delegate: weak, as the recognizer held it (the navigation controller owns it).
    private let uikit = WeakObject()
    private static var associationKey: UInt8 = 0

    private init(_ navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    /// Enables `navigationController`'s back swipes and makes a keeper the delegate of each.
    static func keep(_ navigationController: UINavigationController?) {
        guard let navigationController, let pop = navigationController.interactivePopGestureRecognizer else { return }
        install(on: pop, of: navigationController)
        // iOS 26's swipe from anywhere in the content takes the drags the edge swipe doesn't (a slow one); UIKit's
        // delegate refuses it without a bar, too.
        if #available(iOS 26.0, *), let content = navigationController.interactiveContentPopGestureRecognizer {
            install(on: content, of: navigationController)
        }
    }

    private static func install(on recognizer: UIGestureRecognizer, of navigationController: UINavigationController) {
        let keeper: InteractivePopGestureKeeper
        if let existing = objc_getAssociatedObject(recognizer, &associationKey) as? InteractivePopGestureKeeper {
            keeper = existing
        } else {
            keeper = InteractivePopGestureKeeper(navigationController)
            objc_setAssociatedObject(recognizer, &associationKey, keeper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        recognizer.isEnabled = true
        guard recognizer.delegate !== keeper else { return }
        // The first time, or UIKit set its own again: that one keeps answering the rest.
        if let current = recognizer.delegate as? NSObject, !(current is InteractivePopGestureKeeper) { keeper.uikit.object = current }
        recognizer.delegate = keeper
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController else { return false }
        let swipe: BackSwipeRule.Swipe
        if gestureRecognizer === navigationController.interactivePopGestureRecognizer {
            swipe = .edge
        } else {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return false }
            swipe = .content(velocity: pan.velocity(in: view),
                             rightToLeft: view.effectiveUserInterfaceLayoutDirection == .rightToLeft,
                             startsOnBackScroller: Self.startsOnBackScroller(pan, in: view))
        }
        return BackSwipeRule.mayBegin(pages: navigationController.viewControllers.count,
                                      transitioning: navigationController.transitionCoordinator != nil,
                                      hidesBackButton: navigationController.topViewController?.navigationItem.hidesBackButton == true,
                                      swipe: swipe)
    }

    /// Under where `pan` started (where it is minus how far it moved), a scroll view that can scroll back.
    private static func startsOnBackScroller(_ pan: UIPanGestureRecognizer, in view: UIView) -> Bool {
        let now = pan.location(in: view), moved = pan.translation(in: view)
        var candidate = view.hitTest(CGPoint(x: now.x - moved.x, y: now.y - moved.y), with: nil)
        while let current = candidate, current !== view {
            if let scroll = current as? UIScrollView,
               BackSwipeRule.canScrollBack(contentWidth: scroll.contentSize.width, width: scroll.bounds.width,
                                           offset: scroll.contentOffset.x, insets: scroll.adjustedContentInset,
                                           rightToLeft: scroll.effectiveUserInterfaceLayoutDirection == .rightToLeft) {
                return true
            }
            candidate = current.superview
        }
        return false
    }

    // MARK: UIKit's delegate answers the rest

    /// The questions UIKit's delegate keeps answering: the protocol's, but the start. Its private ones aren't passed on:
    /// one of them (`_gestureRecognizer:shouldReceiveEvent:`) refuses every event on a page without a bar, as its start does.
    nonisolated private static let forwarded: Set<String> = [
        "gestureRecognizer:shouldReceiveTouch:", "gestureRecognizer:shouldReceivePress:", "gestureRecognizer:shouldReceiveEvent:",
        "gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:",
        "gestureRecognizer:shouldRequireFailureOfGestureRecognizer:",
        "gestureRecognizer:shouldBeRequiredToFailByGestureRecognizer:",
    ]

    nonisolated override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || uikitAnswering(aSelector) != nil
    }

    nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
        uikitAnswering(aSelector) ?? super.forwardingTarget(for: aSelector)
    }

    /// UIKit's delegate, when it answers `selector` and the keeper passes that question on.
    nonisolated private func uikitAnswering(_ selector: Selector?) -> NSObject? {
        guard let selector, let object = uikit.object, Self.forwarded.contains(NSStringFromSelector(selector)),
              object.responds(to: selector) else { return nil }
        return object
    }
}

/// A weak reference the keeper's forwarding (`NSObject`'s, not isolated) can read; UIKit sets and asks the delegate on the
/// main thread only.
private final class WeakObject: @unchecked Sendable {
    weak var object: NSObject?
}

// MARK: - previews (dark only; verbatim: the screens own the strings)

private struct SubpagePreviewList: View {
    @State private var choice = "Dots"

    var body: some View {
        VStack(alignment: .leading, spacing: GroupedListSpec.groupSpacing) {
            GroupedCard(Text(verbatim: "Hero numbers"), footer: Text(verbatim: "Large numbers on Today, Sleep and Strain.")) {
                ForEach(["Dots", "Thin"], id: \.self) { option in
                    GroupedRow.select(Text(verbatim: option), isSelected: choice == option) { choice = option }
                }
            }
            GroupedCard(Text(verbatim: "Help")) {
                GroupedRow.push(Text(verbatim: "Report a problem"), value: Text(verbatim: "2 waiting to send")) {}
                GroupedRow.push(Text(verbatim: "Licences")) {}
            }
        }
    }
}

#Preview("SubpageScaffold · pushed, pinned bar") {
    NavigationStack {
        SubpageScaffold(Text(verbatim: "Report a problem")) {
            SubpagePreviewList()
        }
        .pinnedBar(footnote: Text(verbatim: "Reports are limited to 10 a day.")) {
            PillButton(Text(verbatim: "Send"), systemImage: PillButton.Icon.send) {}
                .disabled(true)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("SubpageScaffold · sheet root, a trailing button") {
    SubpageScaffold(Text(verbatim: "Journal"), navigation: .close(), isSheet: true) {
        CircleButton(systemImage: "plus", accessibilityLabel: Text(verbatim: "Add a habit")) {}
    } content: {
        SubpagePreviewList()
    }
    .preferredColorScheme(.dark)
}

#Preview("SubpageScaffold · back and close") {
    NavigationStack {
        SubpageScaffold(Text(verbatim: "Match exercises"), navigation: .backAndClose()) {
            SubpagePreviewList()
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("SubpageScaffold · AX3") {
    NavigationStack {
        SubpageScaffold(Text(verbatim: "Report a problem")) {
            SubpagePreviewList()
        }
        .pinnedBar(caption: Text(verbatim: "Write a message first.")) {
            PillButton(Text(verbatim: "Send"), systemImage: PillButton.Icon.send) {}
        }
    }
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("SubpageScaffold · sheet root · AX3") {
    SubpageScaffold(Text(verbatim: "Sleep need"), navigation: .close(), isSheet: true) {
        SubpagePreviewList()
    }
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility3)
}
