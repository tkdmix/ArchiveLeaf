import Foundation
import Network

final class NetworkConnectivityMonitor: ConnectivityChecking, @unchecked Sendable {
    private let monitor: NWPathMonitor
    private let lock = NSLock()
    private var online = true

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self.lock.withLock {
                self.online = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "io.github.inadaman.ArchiveLeaf.connectivity"))
    }

    deinit { monitor.cancel() }

    func isOnline() -> Bool {
        lock.withLock { online }
    }
}
