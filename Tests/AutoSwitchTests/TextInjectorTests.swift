import XCTest
@testable import AutoSwitch

final class TextInjectorTests: XCTestCase {
    func testUnicodePayloadIsNilForEmptyString() {
        XCTAssertNil(TextInjector.shared.unicodePayload(for: ""))
    }

    func testUnicodePayloadExistsForNonEmptyString() {
        let payload = TextInjector.shared.unicodePayload(for: "תציץ")
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.count, "תציץ".utf16.count)
    }
}
