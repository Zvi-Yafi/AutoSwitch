import XCTest
@testable import AutoSwitch

final class OverrideControllerTests: XCTestCase {
    private var originalSettings: AppSettings!
    
    override func setUp() {
        super.setUp()
        originalSettings = SettingsStore.shared.getSettings()
        SettingsStore.shared.update { settings in
            settings.ignoredWords = []
        }
    }
    
    override func tearDown() {
        SettingsStore.shared.setSettings(originalSettings)
        super.tearDown()
    }
    
    func testSkipNextCorrectionConsumesOnce() {
        XCTAssertFalse(OverrideController.shared.consumeSkipNextCorrection())
        OverrideController.shared.armSkipNextCorrection()
        XCTAssertTrue(OverrideController.shared.consumeSkipNextCorrection())
        XCTAssertFalse(OverrideController.shared.consumeSkipNextCorrection())
    }
    
    func testIgnoredWordLifecycle() {
        XCTAssertFalse(OverrideController.shared.isIgnoredWord("customword"))
        OverrideController.shared.addIgnoredWord("customword")
        XCTAssertTrue(OverrideController.shared.isIgnoredWord("customword"))
        OverrideController.shared.removeIgnoredWord("customword")
        XCTAssertFalse(OverrideController.shared.isIgnoredWord("customword"))
    }
}
