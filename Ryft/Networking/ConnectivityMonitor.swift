import Foundation
import Observation
import Network

/// Whether there's a network path. Offline the app sends nothing (screens keep
/// their cached data, Today shows "Offline"); on reconnect sync and refresh resume.
@MainActor
@Observable
final class ConnectivityMonitor {
    static let shared = ConnectivityMonitor()

    /// Optimistic until the first path update arrives (a request then fails normally).
    private(set) var isOnline = true

    private let monitor = NWPathMonitor()
    private var handlers: [(Bool) -> Void] = []

    init(start: Bool = true) {
        guard start else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online) }
        }
        monitor.start(queue: DispatchQueue(label: "dev.timkrebs.ryft.connectivity"))
    }

    /// Called on every change with the new state (on the main actor).
    func onChange(_ handler: @escaping (Bool) -> Void) {
        handlers.append(handler)
    }

    func update(_ online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        for h in handlers { h(online) }
    }
}

extension ConnectivityMonitor {
    /// Fixed state for previews and tests (no NWPathMonitor).
    static func preview(online: Bool) -> ConnectivityMonitor {
        let m = ConnectivityMonitor(start: false)
        m.isOnline = online
        return m
    }
}
