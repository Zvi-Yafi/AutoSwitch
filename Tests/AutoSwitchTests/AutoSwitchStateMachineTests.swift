import XCTest
@testable import AutoSwitch

// These tests use hooks deliberately excluded from production builds.
#if DEBUG
final class AutoSwitchStateMachineTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AutoSwitchStateMachine.shared._setPendingAmbiguousForTesting(nil)
    }

    override func tearDown() {
        AutoSwitchStateMachine.shared._setPendingAmbiguousForTesting(nil)
        super.tearDown()
    }

    func testPendingAmbiguousSurvivesQuestionMarkBoundary() {
        let pending = makePending()
        AutoSwitchStateMachine.shared._setPendingAmbiguousForTesting(pending)

        AutoSwitchStateMachine.shared.handleBoundary("?", activeAppId: nil)
        waitForStateMachine()

        let remaining = AutoSwitchStateMachine.shared._pendingAmbiguousForTesting
        XCTAssertNotNil(remaining, "Pending ambiguous correction must not be consumed by a trailing '?'")
        XCTAssertEqual(remaining?.originalWord, pending.originalWord)
        XCTAssertEqual(remaining?.correctedWord, pending.correctedWord)
    }

    func testPendingAmbiguousSurvivesPeriodBoundary() {
        let pending = makePending()
        AutoSwitchStateMachine.shared._setPendingAmbiguousForTesting(pending)

        AutoSwitchStateMachine.shared.handleBoundary(".", activeAppId: nil)
        waitForStateMachine()

        XCTAssertNotNil(AutoSwitchStateMachine.shared._pendingAmbiguousForTesting,
                        "Pending ambiguous correction must not be consumed by a trailing '.'")
    }

    func testPendingAmbiguousSurvivesExclamationBoundary() {
        let pending = makePending()
        AutoSwitchStateMachine.shared._setPendingAmbiguousForTesting(pending)

        AutoSwitchStateMachine.shared.handleBoundary("!", activeAppId: nil)
        waitForStateMachine()

        XCTAssertNotNil(AutoSwitchStateMachine.shared._pendingAmbiguousForTesting,
                        "Pending ambiguous correction must not be consumed by a trailing '!'")
    }

    func testPendingAmbiguousSurvivesEllipsisBoundary() {
        let pending = makePending()
        AutoSwitchStateMachine.shared._setPendingAmbiguousForTesting(pending)

        AutoSwitchStateMachine.shared.handleBoundary("\u{2026}", activeAppId: nil)
        waitForStateMachine()

        XCTAssertNotNil(AutoSwitchStateMachine.shared._pendingAmbiguousForTesting,
                        "Pending ambiguous correction must not be consumed by a trailing '…'")
    }

    func testPendingAmbiguousClearedByNavigationEvent() {
        AutoSwitchStateMachine.shared._setPendingAmbiguousForTesting(makePending())

        AutoSwitchStateMachine.shared.handleNavigationEvent()
        waitForStateMachine()

        XCTAssertNil(AutoSwitchStateMachine.shared._pendingAmbiguousForTesting,
                     "Navigation events must still clear pending ambiguous corrections")
    }

    private func makePending() -> PendingAmbiguousCorrection {
        let target = CorrectionTarget(
            inputSourceID: "com.apple.keylayout.Hebrew",
            languageCode: "he",
            supportTier: .fullSupport
        )
        return PendingAmbiguousCorrection(
            originalWord: "url",
            correctedWord: "ורך",
            delimiter: " ",
            target: target,
            appBundleId: nil,
            generation: AutoSwitchStateMachine.shared.currentGeneration
        )
    }

    private func waitForStateMachine() {
        let expectation = expectation(description: "state machine queue drained")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { expectation.fulfill() }
        wait(for: [expectation], timeout: 1.0)
    }
}

#endif
