import Foundation

protocol ConnectivityChecking: Sendable {
    func isOnline() -> Bool
}

struct AlwaysOnlineConnectivity: ConnectivityChecking {
    func isOnline() -> Bool { true }
}
