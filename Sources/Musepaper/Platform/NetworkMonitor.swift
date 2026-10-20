import Foundation
import Network

final class NetworkMonitor: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "dev.musepaper.network")
    private let lock = NSLock()
    private var available: Bool?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.lock.withLock { self?.available = path.status == .satisfied }
        }
        monitor.start(queue: queue)
    }

    var isOnline: Bool { lock.withLock { available ?? true } }
    deinit { monitor.cancel() }
}
