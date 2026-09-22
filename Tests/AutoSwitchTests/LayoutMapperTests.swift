import Carbon
import XCTest
@testable import AutoSwitch

final class LayoutMapperTests: XCTestCase {
    func testKeystrokeReplayMapsEnglishSequenceToHebrew() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let keystrokes = [
            BufferedKeystroke(keyCode: 0, modifierFlags: 0),
            BufferedKeystroke(keyCode: 40, modifierFlags: 0),
            BufferedKeystroke(keyCode: 32, modifierFlags: 0),
            BufferedKeystroke(keyCode: 31, modifierFlags: 0)
        ]

        guard let english = LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: englishLayoutID),
              let hebrew = LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: hebrewLayoutID) else {
            throw XCTSkip("Required keyboard layouts are unavailable")
        }

        XCTAssertEqual(english.text, "akuo")
        XCTAssertEqual(hebrew.text, "שלום")
        XCTAssertEqual(english.characterKeyRanges.count, english.text.count)
        XCTAssertTrue(english.consumedAllKeystrokes)
        XCTAssertFalse(english.hasPendingDeadKey)
    }

    func testOptionDeadKeySequenceComposesAccentedCharacter() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let optionModifier = UInt32(optionKey >> 8)

        guard case .deadKey? = LayoutMapper.shared.classifyKeyStroke(
            14,
            modifiers: optionModifier,
            layoutID: englishLayoutID
        ) else {
            throw XCTSkip("The active English layout does not use Option-E as a dead key")
        }

        let keystrokes = [
            BufferedKeystroke(keyCode: 14, modifierFlags: optionModifier),
            BufferedKeystroke(keyCode: 14, modifierFlags: 0)
        ]
        guard let rendered = LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: englishLayoutID) else {
            throw XCTSkip("The English keyboard layout is unavailable")
        }

        XCTAssertEqual(rendered.text.precomposedStringWithCanonicalMapping, "é")
        XCTAssertEqual(rendered.characterKeyRanges, [0..<2])
        XCTAssertTrue(rendered.consumedAllKeystrokes)
        XCTAssertFalse(rendered.hasPendingDeadKey)
    }

    func testIncompleteDeadKeyRemainsPending() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let keystrokes = [
            BufferedKeystroke(keyCode: 14, modifierFlags: UInt32(optionKey >> 8))
        ]
        guard let rendered = LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: englishLayoutID) else {
            throw XCTSkip("The English keyboard layout is unavailable")
        }

        XCTAssertTrue(rendered.text.isEmpty)
        XCTAssertTrue(rendered.hasPendingDeadKey)
        XCTAssertTrue(rendered.consumedAllKeystrokes)
    }
}
