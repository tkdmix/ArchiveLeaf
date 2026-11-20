import Foundation
import LocalAuthentication

/// Which of the device's own ways of recognizing its owner is available.
///
/// The shelf never asks what the reader knows — it asks the device, and the device decides. So the
/// only thing worth reporting here is what the unlock sheet will look like, which is what the
/// settings screen has to describe before the reader has ever seen it.
enum ShelfLockAvailability: Equatable {
    /// Touch ID or Face ID is enrolled. The device passcode remains behind it as the fallback, so
    /// a failed face or finger is never the end of the road.
    case biometry(ShelfBiometry)
    /// No biometry, but there is a passcode or login password to fall back to. A Mac mini without
    /// a Touch ID keyboard lands here, and so does an iPhone whose owner has not enrolled a face.
    case passcodeOnly
    /// Nothing to authenticate against, because the device has no passcode set at all.
    case unavailable
}

enum ShelfBiometry: Equatable {
    case touchID
    case faceID
}

/// Asking the device to recognize its owner.
///
/// A protocol rather than a bare `LAContext` call, because everything above this line can then be
/// tested without a face, a finger, or a device.
protocol ShelfUnlocking: Sendable {
    var availability: ShelfLockAvailability { get }
    /// Returns whether the device recognized its owner. A refusal, a cancellation, and a failure
    /// are the same answer to the shelf: it stays closed.
    func unlock(reason: String) async -> Bool
}

/// The real one, which is the system's own authentication sheet and nothing else.
struct LocalAuthenticationUnlocker: ShelfUnlocking {
    /// The policy is deliberately `deviceOwnerAuthentication` rather than the biometrics-only one.
    /// Biometrics alone locks the reader out of their own shelf after a few failed attempts, with
    /// no way back; this one falls through to the passcode, which they can always type.
    private let policy: LAPolicy = .deviceOwnerAuthentication

    var availability: ShelfLockAvailability {
        let context = LAContext()
        // `biometryType` is only meaningful after the context has been asked whether it can
        // evaluate, so the order of these lines matters.
        guard context.canEvaluatePolicy(policy, error: nil) else { return .unavailable }
        // And it answers what the device has, not what its owner has enrolled. A phone with a
        // sensor nobody has taught a finger to still opens with a passcode, and saying otherwise
        // promises the reader a sheet they will never see.
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return .passcodeOnly
        }
        switch context.biometryType {
        case .touchID: return .biometry(.touchID)
        case .faceID: return .biometry(.faceID)
        // ArchiveLeaf ships to Mac, iPhone, and iPad, so nothing else occurs. If it ever does,
        // the passcode wording is the one that stays true.
        default: return .passcodeOnly
        }
    }

    func unlock(reason: String) async -> Bool {
        let context = LAContext()
        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }
}
