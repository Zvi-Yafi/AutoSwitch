import XCTest
@testable import AutoSwitch

final class LoggerPrivacyTests: XCTestCase {
    func testWordDiagnosticsRequireDebugBuildAndExplicitOptIn() {
        let original = SettingsStore.shared.getSettings()
        defer { SettingsStore.shared.setSettings(original) }
        SettingsStore.shared.update { $0.logLevel = .basic }
        XCTAssertFalse(isAppLogEnabled(.debug))
        SettingsStore.shared.update { $0.logLevel = .debug }
        #if DEBUG
        XCTAssertTrue(isAppLogEnabled(.debug))
        #else
        XCTAssertFalse(isAppLogEnabled(.debug), "Release builds must suppress word diagnostics even with saved debug settings")
        #endif
    }

    func testOffDisablesOperationalLogging() {
        let original = SettingsStore.shared.getSettings()
        defer { SettingsStore.shared.setSettings(original) }
        SettingsStore.shared.update { $0.logLevel = .off }
        XCTAssertFalse(isAppLogEnabled(.basic))
        XCTAssertFalse(isAppLogEnabled(.debug))
    }
}
