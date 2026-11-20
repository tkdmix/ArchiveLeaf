import SwiftUI

/// What one launch remembers about having been unlocked.
///
/// The Mac locks once and stays open, and a second window must not ask again — but each window
/// builds its own view, and state inside a view knows nothing about the window beside it. This is
/// the one fact that belongs to the launch rather than to a window.
@MainActor
final class ShelfLockSession {
    static let shared = ShelfLockSession()
    var hasUnlockedThisLaunch = false

    private init() {}
}

/// Closes the shelf behind the device's own lock, and covers it whenever the app is not in front.
///
/// Two jobs with two triggers, which is the whole design. The cover follows the scene going quiet,
/// because that is the moment the system photographs the screen for the app switcher — wait for the
/// app to reach the background and the picture has already been taken. The lock follows the reader
/// actually leaving, because the quiet moments are mostly not departures, and one of them is the
/// unlock sheet itself.
struct ShelfLockGate: ViewModifier {
    private let unlocker: any ShelfUnlocking
    private let settings: ShelfLockSettingsStore
    /// Called as the shelf closes, for whatever is on screen that this cover cannot reach.
    private let onLock: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var policy: ShelfLockPolicy
    @State private var isAuthenticating = false

    init(
        unlocker: any ShelfUnlocking = LocalAuthenticationUnlocker(),
        settings: ShelfLockSettingsStore = ShelfLockSettingsStore(),
        onLock: @escaping () -> Void = {}
    ) {
        self.unlocker = unlocker
        self.settings = settings
        self.onLock = onLock
        var policy = ShelfLockPolicy.forCurrentPlatform(
            isEnabled: Self.isEnabled(settings: settings, unlocker: unlocker)
        )
        if ShelfLockSession.shared.hasUnlockedThisLaunch {
            policy.didUnlock()
        }
        _policy = State(initialValue: policy)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isCovered {
                    cover
                }
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                switch phase {
                case .background:
                    policy.didLeave(at: .now)
                case .active:
                    policy.didReturn(at: .now)
                    if policy.isLocked {
                        onLock()
                        authenticate()
                    }
                default:
                    // Quiet, not gone. The cover is already up; nothing else is decided here.
                    break
                }
            }
            // The setting lives in another screen, and on the Mac in another window entirely.
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                let isEnabled = Self.isEnabled(settings: settings, unlocker: unlocker)
                if isEnabled != policy.isEnabled {
                    policy.setEnabled(isEnabled)
                }
            }
    }

    /// A device that has nothing to authenticate against cannot be asked, and a shelf that asks it
    /// anyway is a shelf that never opens again. The setting can survive a passcode being turned
    /// off — the lock cannot.
    private static func isEnabled(settings: ShelfLockSettingsStore, unlocker: any ShelfUnlocking) -> Bool {
        settings.isEnabled && unlocker.availability != .unavailable
    }

    /// The shelf is hidden while it is locked, and — everywhere the system keeps a picture of the
    /// app to show elsewhere — for as long as the app is not in front. The Mac has no such picture,
    /// so there it is only ever the lock.
    ///
    /// Both halves belong to a reader who asked for a lock. A shelf with the lock turned off has
    /// nothing to hide from the app switcher, and covering it there shows a padlock over a shelf
    /// that has none.
    private var isCovered: Bool {
        #if os(macOS)
        policy.isLocked
        #else
        policy.isEnabled && (policy.isLocked || scenePhase != .active)
        #endif
    }

    private var cover: some View {
        ZStack {
            Rectangle()
                .fill(.background)
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                // Only once the sheet has come and gone. A cancelled unlock has to leave a way back
                // in, or the reader is left holding a blank screen with nothing to press.
                if policy.isLocked, !isAuthenticating, scenePhase == .active {
                    Button("Unlock") { authenticate() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Locked"))
    }

    private func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        Task {
            let succeeded = await unlocker.unlock(reason: String(localized: "Open your shelf"))
            isAuthenticating = false
            guard succeeded else { return }
            policy.didUnlock()
            ShelfLockSession.shared.hasUnlockedThisLaunch = true
        }
    }
}

extension View {
    func shelfLock(
        unlocker: any ShelfUnlocking = LocalAuthenticationUnlocker(),
        settings: ShelfLockSettingsStore = ShelfLockSettingsStore(),
        onLock: @escaping () -> Void = {}
    ) -> some View {
        modifier(ShelfLockGate(unlocker: unlocker, settings: settings, onLock: onLock))
    }
}
