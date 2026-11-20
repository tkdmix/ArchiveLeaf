import Foundation

/// When the shelf is closed and when it opens again.
///
/// Only two things ever reach this type: the reader left the app, and the reader came back. Notice
/// what is missing — the moment a scene merely goes quiet. Pulling down Control Center, glancing at
/// a notification, answering a call, and raising the unlock sheet itself all make a scene inactive
/// without the reader having gone anywhere, and asking for a face at every one of those makes the
/// lock unusable. Worse, the unlock sheet is itself one of them, so a lock driven by that moment
/// asks again for every answer it gets. Covering the screen is a different job with a different
/// trigger, and it lives in the view.
///
/// This leaves the type with no clock, no framework, and no screen, which is the point: the rule
/// about when a shelf closes is worth testing, and none of those are worth carrying into a test.
struct ShelfLockPolicy: Equatable {
    /// How long the reader can be away before coming back costs an unlock. Short trips — following
    /// a link out and returning, checking the notification that just arrived — are the common case,
    /// and charging them an unlock each time trains the reader to turn the lock off.
    static let defaultGrace: TimeInterval = 180

    /// Whether the reader has asked for the shelf to be locked at all.
    private(set) var isEnabled: Bool
    /// Whether leaving the app closes the shelf again. False on the Mac, which locks once at launch
    /// and then stays open: the Mac already locks its own screen when its owner walks away, and a
    /// second lock on top of that only buys the cost of typing a login password all day.
    let relocksOnReturn: Bool
    let grace: TimeInterval

    private(set) var isLocked: Bool
    private var leftAt: Date?

    init(isEnabled: Bool, relocksOnReturn: Bool, grace: TimeInterval = ShelfLockPolicy.defaultGrace) {
        self.isEnabled = isEnabled
        self.relocksOnReturn = relocksOnReturn
        self.grace = grace
        self.isLocked = isEnabled
    }

    /// The policy this platform runs under.
    static func forCurrentPlatform(isEnabled: Bool) -> ShelfLockPolicy {
        #if os(macOS)
        ShelfLockPolicy(isEnabled: isEnabled, relocksOnReturn: false)
        #else
        ShelfLockPolicy(isEnabled: isEnabled, relocksOnReturn: true)
        #endif
    }

    /// The reader went somewhere else — the Home screen, another app.
    mutating func didLeave(at date: Date) {
        guard leftAt == nil else { return }
        leftAt = date
    }

    /// The reader came back. Long enough away, and the shelf is closed again.
    mutating func didReturn(at date: Date) {
        defer { leftAt = nil }
        guard isEnabled, relocksOnReturn, !isLocked, let leftAt else { return }
        if date.timeIntervalSince(leftAt) >= grace {
            isLocked = true
        }
    }

    /// The device recognized its owner.
    mutating func didUnlock() {
        isLocked = false
        leftAt = nil
    }

    /// The reader changed their mind in Settings.
    ///
    /// Turning the lock on does not close the shelf the reader is holding open. They asked for a
    /// lock, not to be shut out of the screen they are standing on; it takes effect the next time
    /// they leave, or the next time they launch.
    mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            isLocked = false
            leftAt = nil
        }
    }
}
