import SwiftUI
import UIKit
@testable import Ryft

/// Real views in a real window, measured through the accessibility tree: the frames VoiceOver would use, in screen points.
/// SwiftUI builds that tree only while the system's accessibility automation is on, which a test process has to switch on
/// itself (the same switch UI tests flip from outside); it is off again when the last window closes. One window at a time:
/// `run` waits for the one before, so suites running side by side can't read each other's frames.
@MainActor
final class HostedWindow {
    /// UIKit's accessibility calls are main-actor: nesting in the class doesn't carry its isolation over.
    @MainActor
    struct Node {
        let label: String
        let value: String?
        let frame: CGRect
        let traits: UIAccessibilityTraits
        fileprivate let object: NSObject

        var isEnabled: Bool { !traits.contains(.notEnabled) }
        var isSelected: Bool { traits.contains(.selected) }

        /// A tap as VoiceOver's double tap does it.
        @discardableResult
        func activate() -> Bool { object.accessibilityActivate() }

        var isAdjustable: Bool { traits.contains(.adjustable) }
        /// What Voice Control takes for this element.
        var inputLabels: [String] { object.accessibilityUserInputLabels ?? [] }
        func increment() { object.accessibilityIncrement() }
        func decrement() { object.accessibilityDecrement() }

        /// The names VoiceOver's actions rotor offers.
        var actionNames: [String] { (object.accessibilityCustomActions ?? []).map(\.name) }

        @discardableResult
        func perform(action name: String) -> Bool {
            guard let action = object.accessibilityCustomActions?.first(where: { $0.name == name }) else { return false }
            if let handler = action.actionHandler { return handler(action) }
            if let target = action.target { _ = (target as AnyObject).perform(action.selector, with: action) }
            return true
        }
    }

    let window: UIWindow
    let host: UIHostingController<AnyView>
    private static var busy = false
    private static var automation = 0

    /// `content` gets the preview environment. `typeSize`: the Dynamic Type size, as the shots set it.
    static func run<Content: View>(width: CGFloat, height: CGFloat, bottomInset: CGFloat = 34, dark: Bool = true,
                                   typeSize: DynamicTypeSize = .large, category: UIContentSizeCategory = .large,
                                   _ content: Content, body: (HostedWindow) async throws -> Void) async throws {
        while busy { try await Task.sleep(for: .milliseconds(25)) }
        busy = true
        defer { busy = false }
        let scene = try await windowScene()
        let root = AnyView(content.previewEnvironment(scheme: dark ? .dark : .light).environment(\.dynamicTypeSize, typeSize))
        let hosted = HostedWindow(scene: scene, root: root, size: CGSize(width: width, height: height),
                                  bottomInset: bottomInset, dark: dark, category: category)
        defer { hosted.close() }
        try await body(hosted)
    }

    private init(scene: UIWindowScene, root: AnyView, size: CGSize, bottomInset: CGFloat, dark: Bool, category: UIContentSizeCategory) {
        Self.setAutomation(on: true)
        host = UIHostingController(rootView: root)
        host.traitOverrides.preferredContentSizeCategory = category
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: bottomInset, right: 0)
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = dark ? .dark : .light
        window.rootViewController = host
        window.isHidden = false
    }

    private func close() {
        window.isHidden = true
        window.rootViewController = nil
        Self.setAutomation(on: false)
    }

    private static func windowScene() async throws -> UIWindowScene {
        for _ in 0..<100 {
            if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first { return scene }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw HostError.noScene
    }

    enum HostError: Error { case noScene, timeout(String) }

    /// Reference-counted: the symbol is looked up at run time, so a runtime without it fails every hosted test at its first
    /// `nodes()` (no elements) instead of skipping quietly.
    private static func setAutomation(on: Bool) {
        automation += on ? 1 : -1
        guard on ? automation == 1 : automation == 0, let lib = dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW),
              let symbol = dlsym(lib, "_AXSSetAutomationEnabled") else { return }
        unsafeBitCast(symbol, to: (@convention(c) (Bool) -> Void).self)(on)
    }

    // MARK: the accessibility tree

    /// Every named element on screen, in tree order.
    func nodes() -> [Node] {
        var found: [Node] = []
        var seen = Set<ObjectIdentifier>()
        func walk(_ object: NSObject, depth: Int) {
            guard depth < 40, seen.insert(ObjectIdentifier(object)).inserted else { return }
            if String(describing: type(of: object)) == "AccessibilityNode", let label = object.accessibilityLabel, !label.isEmpty {
                found.append(Node(label: label, value: object.accessibilityValue, frame: object.accessibilityFrame,
                                  traits: object.accessibilityTraits, object: object))
            }
            if let elements = object.accessibilityElements {
                for case let child as NSObject in elements { walk(child, depth: depth + 1) }
            } else {
                let count = object.accessibilityElementCount()
                if count != NSNotFound, count > 0 {
                    for i in 0..<count { if let child = object.accessibilityElement(at: i) as? NSObject { walk(child, depth: depth + 1) } }
                }
            }
            if let view = object as? UIView { for sub in view.subviews { walk(sub, depth: depth + 1) } }
        }
        walk(host.view, depth: 0)
        return found
    }

    /// The first element whose label is `label` (`exactly`) or starts with it.
    func node(_ label: String, exactly: Bool = false) -> Node? {
        nodes().first { exactly ? $0.label == label : $0.label.hasPrefix(label) }
    }

    /// The page's vertical scroll view: the tall one as wide as the window, not the pager.
    func pageScrollView() -> UIScrollView? {
        var best: UIScrollView?
        func walk(_ view: UIView) {
            if let scroll = view as? UIScrollView, !(view is UICollectionView) {
                let frame = scroll.convert(scroll.bounds, to: window)
                if frame.width >= window.bounds.width - 1, frame.height >= 90, frame.minX >= -0.5, frame.minX < 1,
                   scroll.contentSize.height > 0, best == nil || frame.height > best!.convert(best!.bounds, to: window).height {
                    best = scroll
                }
            }
            for sub in view.subviews { walk(sub) }
        }
        walk(host.view)
        return best
    }

    /// The page's viewport in screen points: where the pill row, the toast or the keypad begins is its bottom edge.
    func pageViewport() -> CGRect? {
        pageScrollView().map { $0.convert($0.bounds, to: window) }
    }

    // MARK: waiting

    /// Waits until `condition` holds, polling the run loop (SwiftUI lays out between turns; a window gives no event).
    func wait(_ what: String, timeout: Duration = .seconds(5), until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw HostError.timeout(what) }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    /// Waits until the layout stopped moving: every frame and the page's scroll offset the same for 500 ms, twice a scroll's
    /// 250 ms animation, so a runner that stalls in the middle of one doesn't read as quiet.
    func settle(timeout: Duration = .seconds(6)) async throws {
        func snapshot() -> String {
            nodes().map { "\($0.label)@\($0.frame)" }.joined(separator: "|") + "|\(pageScrollView()?.contentOffset ?? .zero)"
        }
        var last = snapshot(), same = 0
        let deadline = ContinuousClock.now + timeout
        while same < 10 {
            guard ContinuousClock.now < deadline else { throw HostError.timeout("the layout to settle") }
            try await Task.sleep(for: .milliseconds(50))
            let now = snapshot()
            same = now == last ? same + 1 : 0
            last = now
        }
    }
}
