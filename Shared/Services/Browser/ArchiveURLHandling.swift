import Foundation

protocol ArchiveURLHandling: Sendable {
    func canOpenInApp(_ url: URL) -> Bool
    func requiresConfirmationToOpen(_ url: URL) -> Bool
}

struct ArchiveURLHandler: ArchiveURLHandling {
    func canOpenInApp(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        return url.host?.isEmpty == false
    }

    func requiresConfirmationToOpen(_ url: URL) -> Bool {
        !canOpenInApp(url)
    }
}
