import XCTest
@testable import AutoSwitch

final class SettingsStoreTests: XCTestCase {
    private var originalSettings: AppSettings!
    
    override func setUp() {
        super.setUp()
        originalSettings = SettingsStore.shared.getSettings()
    }
    
    override func tearDown() {
        SettingsStore.shared.setSettings(originalSettings)
        super.tearDown()
    }
    
    func testExportImportRoundTrip() throws {
        let baseline = SettingsStore.shared.getSettings()
        SettingsStore.shared.update { settings in
            settings.enabled = false
            settings.correctionPreferenceMode = .preferSpecificTarget
            settings.preferredTargetInputSourceID = "com.apple.keylayout.ABC"
            settings.enabledTargetInputSourceIDs = ["com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew"]
            settings.enableBestEffortTargets = true
            settings.undoWindowSeconds = 4.0
            settings.ignoredWords = ["foo", "bar"]
            settings.skipNextHotkey = "cmd+shift+;"
        }
        let exported = SettingsStore.shared.exportSettingsJSON()
        XCTAssertNotNil(exported)
        SettingsStore.shared.setSettings(baseline)
        XCTAssertTrue(SettingsStore.shared.importSettingsJSON(exported ?? ""))
        let imported = SettingsStore.shared.getSettings()
        XCTAssertEqual(imported.enabled, false)
        XCTAssertEqual(imported.correctionPreferenceMode, .preferSpecificTarget)
        XCTAssertEqual(imported.preferredTargetInputSourceID, "com.apple.keylayout.ABC")
        XCTAssertEqual(imported.enabledTargetInputSourceIDs, ["com.apple.keylayout.ABC", "com.apple.keylayout.Hebrew"])
        XCTAssertEqual(imported.enableBestEffortTargets, true)
        XCTAssertEqual(imported.undoWindowSeconds, 4.0)
        XCTAssertEqual(imported.ignoredWords.sorted(), ["bar", "foo"])
        XCTAssertEqual(imported.skipNextHotkey, "cmd+shift+;")
    }

    func testLegacyPreferenceDecodesIntoV2Model() throws {
        let legacyJSON = """
        {
          "enabled": true,
          "preferredOutputLanguage": "english",
          "enableAmbiguousCorrection": true,
          "ambiguousConfidenceThreshold": 0.65,
          "undoWindowSeconds": 2.5,
          "skipNextHotkey": "cmd+shift+;",
          "undoHotkey": "cmd+z",
          "abbreviationPriorityEnabled": true,
          "abbreviationExceptions": [],
          "ignoredWords": [],
          "whitelistedBundleIds": [],
          "blacklistedBundleIds": [],
          "logLevel": "basic",
          "enableLogExport": true
        }
        """
        let data = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.correctionPreferenceMode, .preferSpecificTarget)
        XCTAssertEqual(decoded.preferredTargetInputSourceID, InputSourceController.shared.getEnglishLayoutID())
    }
}
