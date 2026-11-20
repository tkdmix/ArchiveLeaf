import Foundation
import XCTest
@testable import ArchiveLeaf

final class ShelfLockPolicyTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func iOSPolicy(isEnabled: Bool = true, grace: TimeInterval = 180) -> ShelfLockPolicy {
        ShelfLockPolicy(isEnabled: isEnabled, relocksOnReturn: true, grace: grace)
    }

    private func macPolicy(isEnabled: Bool = true) -> ShelfLockPolicy {
        ShelfLockPolicy(isEnabled: isEnabled, relocksOnReturn: false)
    }

    func testDisabledShelfIsNeverLocked() {
        var policy = iOSPolicy(isEnabled: false)

        XCTAssertFalse(policy.isLocked)

        policy.didLeave(at: start)
        policy.didReturn(at: start.addingTimeInterval(3_600))

        XCTAssertFalse(policy.isLocked)
    }

    func testEnabledShelfStartsLocked() {
        XCTAssertTrue(iOSPolicy().isLocked)
        XCTAssertTrue(macPolicy().isLocked)
    }

    func testShortDepartureCostsNothing() {
        var policy = iOSPolicy()
        policy.didUnlock()

        policy.didLeave(at: start)
        policy.didReturn(at: start.addingTimeInterval(179))

        XCTAssertFalse(policy.isLocked)
    }

    func testDepartureBeyondGraceLocksTheShelf() {
        var policy = iOSPolicy()
        policy.didUnlock()

        policy.didLeave(at: start)
        policy.didReturn(at: start.addingTimeInterval(180))

        XCTAssertTrue(policy.isLocked)
    }

    /// The departure is timed from when the reader left, not from the last of several reports of
    /// having left.
    func testDepartureIsTimedFromTheFirstReport() {
        var policy = iOSPolicy()
        policy.didUnlock()

        policy.didLeave(at: start)
        policy.didLeave(at: start.addingTimeInterval(170))
        policy.didReturn(at: start.addingTimeInterval(200))

        XCTAssertTrue(policy.isLocked)
    }

    func testReturningWithoutHavingLeftChangesNothing() {
        var policy = iOSPolicy()
        policy.didUnlock()

        policy.didReturn(at: start.addingTimeInterval(3_600))

        XCTAssertFalse(policy.isLocked)
    }

    /// Each departure is measured on its own. Two short trips are not one long one.
    func testSuccessiveShortDeparturesDoNotAccumulate() {
        var policy = iOSPolicy()
        policy.didUnlock()

        policy.didLeave(at: start)
        policy.didReturn(at: start.addingTimeInterval(100))
        policy.didLeave(at: start.addingTimeInterval(200))
        policy.didReturn(at: start.addingTimeInterval(300))

        XCTAssertFalse(policy.isLocked)
    }

    func testMacLocksAtLaunchAndThenStaysOpen() {
        var policy = macPolicy()
        XCTAssertTrue(policy.isLocked)

        policy.didUnlock()
        policy.didLeave(at: start)
        policy.didReturn(at: start.addingTimeInterval(86_400))

        XCTAssertFalse(policy.isLocked)
    }

    func testTurningTheLockOnDoesNotShutTheReaderOutOfTheScreenTheyAreOn() {
        var policy = iOSPolicy(isEnabled: false)

        policy.setEnabled(true)

        XCTAssertFalse(policy.isLocked)
    }

    func testTurningTheLockOnTakesEffectAtTheNextDeparture() {
        var policy = iOSPolicy(isEnabled: false)
        policy.setEnabled(true)

        policy.didLeave(at: start)
        policy.didReturn(at: start.addingTimeInterval(600))

        XCTAssertTrue(policy.isLocked)
    }

    func testTurningTheLockOffOpensAClosedShelf() {
        var policy = iOSPolicy()
        XCTAssertTrue(policy.isLocked)

        policy.setEnabled(false)

        XCTAssertFalse(policy.isLocked)
    }
}
