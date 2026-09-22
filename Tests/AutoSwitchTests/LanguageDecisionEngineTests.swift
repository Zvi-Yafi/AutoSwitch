import XCTest
@testable import AutoSwitch

final class LanguageDecisionEngineTests: XCTestCase {
    private var originalSettings: AppSettings!
    
    override func setUp() {
        super.setUp()
        originalSettings = SettingsStore.shared.getSettings()
        SettingsStore.shared.update { settings in
            settings.ignoredWords = []
            settings.abbreviationExceptions = []
            settings.abbreviationPriorityEnabled = true
            settings.correctionPreferenceMode = .automatic
            settings.preferredTargetInputSourceID = nil
            settings.enabledTargetInputSourceIDs = []
            settings.enableBestEffortTargets = false
        }
    }
    
    override func tearDown() {
        SettingsStore.shared.setSettings(originalSettings)
        super.tearDown()
    }
    
    func testIgnoredWordAlwaysRejected() {
        OverrideController.shared.addIgnoredWord("tbh")
        let snapshot = CorrectionSnapshot(
            originalWord: "tbh",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: nil
        )
        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .rejected:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected rejected for ignored word")
        }
    }
    
    func testEnglishTypoConvertsToHebrew() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        guard DictionaryManager.shared.isHebrewWord("שלום") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "akuo", from: InputSourceController.shared.getEnglishLayoutID(), to: hebrewLayoutID) == "שלום" else {
            throw XCTSkip("Hebrew layout mapping is not available on this machine")
        }
        
        let snapshot = CorrectionSnapshot(
            originalWord: "akuo",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: InputSourceController.shared.getEnglishLayoutID()
        )
        
        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "שלום")
            XCTAssertEqual(candidate.target.inputSourceID, hebrewLayoutID)
        default:
            XCTFail("Expected accepted Hebrew correction for akuo")
        }
    }

    func testEnglishTypoWithLeadingPunctuationThatMapsToHebrewLetterConvertsToHebrew() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isHebrewWord("תמיד") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: ",nhs", from: englishLayoutID, to: hebrewLayoutID) == "תמיד" else {
            throw XCTSkip("Hebrew layout mapping is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: ",nhs",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: englishLayoutID
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "תמיד")
            XCTAssertEqual(candidate.target.inputSourceID, hebrewLayoutID)
        case .ambiguous(let candidate):
            XCTFail("Expected accepted Hebrew correction for ,nhs but got ambiguous: \(candidate.word)")
        case .rejected:
            XCTFail("Expected accepted Hebrew correction for ,nhs but got rejected")
        case .switchOnly:
            XCTFail("Expected accepted Hebrew correction for ,nhs but got switchOnly")
        }
    }

    func testEnglishTypoWithTrailingCommaPreservesComma() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isHebrewWord("שלום") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "akuo", from: englishLayoutID, to: hebrewLayoutID) == "שלום" else {
            throw XCTSkip("Hebrew layout mapping is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "akuo,",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: englishLayoutID
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "שלום,")
            XCTAssertEqual(candidate.target.inputSourceID, hebrewLayoutID)
        default:
            XCTFail("Expected accepted Hebrew correction for akuo,")
        }
    }

    func testEnglishTypoWithWrappedPunctuationPreservesAffixes() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isHebrewWord("שלום") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "akuo", from: englishLayoutID, to: hebrewLayoutID) == "שלום" else {
            throw XCTSkip("Hebrew layout mapping is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "\"akuo",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: englishLayoutID
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "\"שלום")
            XCTAssertEqual(candidate.target.inputSourceID, hebrewLayoutID)
        default:
            XCTFail("Expected accepted Hebrew correction for wrapped punctuation")
        }
    }

    func testMergedPeriodTokenPreservesPeriod() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isHebrewWord("שלום") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "akuo", from: englishLayoutID, to: hebrewLayoutID) == "שלום" else {
            throw XCTSkip("Hebrew layout mapping is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "akuo.",
            boundaryCharacter: "",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: englishLayoutID
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "שלום.")
            XCTAssertEqual(candidate.target.inputSourceID, hebrewLayoutID)
        default:
            XCTFail("Expected accepted Hebrew correction for merged period token")
        }
    }
    
    func testHebrewTypoConvertsToEnglish() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isEnglishWord("hello") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "יקךךם", from: InputSourceController.shared.getHebrewLayoutID(), to: englishLayoutID) == "hello" else {
            throw XCTSkip("English layout mapping is not available on this machine")
        }
        
        let snapshot = CorrectionSnapshot(
            originalWord: "יקךךם",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: InputSourceController.shared.getHebrewLayoutID()
        )
        
        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "hello")
            XCTAssertEqual(candidate.target.inputSourceID, englishLayoutID)
        default:
            XCTFail("Expected accepted English correction for יקךךם")
        }
    }

    func testHebrewTypoConvertsToEnglishWhenPreferredTargetIsEnglish() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        guard DictionaryManager.shared.isEnglishWord("hello") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "יקךךם", from: hebrewLayoutID, to: englishLayoutID) == "hello" else {
            throw XCTSkip("English layout mapping is not available on this machine")
        }

        SettingsStore.shared.update { settings in
            settings.correctionPreferenceMode = .preferSpecificTarget
            settings.preferredTargetInputSourceID = englishLayoutID
            settings.enableAmbiguousCorrection = true
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "יקךךם",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: hebrewLayoutID
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "hello")
            XCTAssertEqual(candidate.target.inputSourceID, englishLayoutID)
        case .ambiguous(let candidate):
            XCTFail("Expected accepted English correction for יקךךם but got ambiguous: \(candidate.word)")
        case .rejected:
            XCTFail("Expected accepted English correction for יקךךם but got rejected")
        case .switchOnly:
            XCTFail("Expected accepted English correction for יקךךם but got switchOnly")
        }
    }

    func testHebrewWordWithGereshDefersAsAmbiguous() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isEnglishWord("how") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }
        guard DictionaryManager.shared.isHebrewWord("ים") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }

        XCTAssertEqual(LayoutMapper.shared.mapToEnglish("ים׳"), "how")

        let snapshot = CorrectionSnapshot(
            originalWord: "ים׳",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: InputSourceController.shared.getHebrewLayoutID()
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .ambiguous(let candidate):
            XCTAssertEqual(candidate.word, "how")
            XCTAssertEqual(candidate.target.inputSourceID, englishLayoutID)
        case .accepted(let candidate):
            XCTFail("Word with valid Hebrew core must not switch immediately, got accepted: \(candidate.word)")
        case .rejected:
            XCTFail("Expected ambiguous deferral for ים׳ but got rejected")
        case .switchOnly:
            XCTFail("Expected ambiguous deferral for ים׳ but got switchOnly")
        }
    }

    func testValidHebrewWordDoesNotConvertToEnglish() throws {
        guard DictionaryManager.shared.isHebrewWord("שלום") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "שלום",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: InputSourceController.shared.getHebrewLayoutID()
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .rejected:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected valid Hebrew word to remain unchanged")
        }
    }

    func testValidHebrewWordThatAlsoMapsToEnglishCandidateBecomesAmbiguous() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isHebrewWord("מקבל") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        guard DictionaryManager.shared.isEnglishWord("neck") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "מקבל", from: hebrewLayoutID, to: englishLayoutID) == "neck" else {
            throw XCTSkip("English layout mapping is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "מקבל",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: hebrewLayoutID
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .ambiguous(let candidate):
            XCTAssertEqual(candidate.word, "neck")
            XCTAssertEqual(candidate.target.inputSourceID, englishLayoutID)
        case .accepted(let candidate):
            XCTFail("Expected ambiguous decision for valid Hebrew word, got accepted: \(candidate.word)")
        case .rejected:
            XCTFail("Expected ambiguous decision for bilingual valid word")
        case .switchOnly:
            XCTFail("Expected ambiguous decision for bilingual valid word, got switchOnly")
        }
    }

    func testValidEnglishWordDoesNotConvertToHebrew() throws {
        guard DictionaryManager.shared.isEnglishWord("hello") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "hello",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: InputSourceController.shared.getEnglishLayoutID()
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .rejected:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected valid English word to remain unchanged")
        }
    }

    func testTechnicalEmailLikeTokenIsRejected() {
        let snapshot = CorrectionSnapshot(
            originalWord: "user@host",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: InputSourceController.shared.getEnglishLayoutID()
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .rejected:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected technical token to be rejected")
        }
    }

    func testTechnicalPathLikeTokenIsRejected() {
        let snapshot = CorrectionSnapshot(
            originalWord: "path/to/file",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: InputSourceController.shared.getEnglishLayoutID()
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .rejected:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected path-like token to be rejected")
        }
    }

    func testLetterDigitTokenIsRejected() {
        let snapshot = CorrectionSnapshot(
            originalWord: "abc123",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: InputSourceController.shared.getEnglishLayoutID()
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .rejected:
            XCTAssertTrue(true)
        default:
            XCTFail("Expected mixed letter-digit token to be rejected")
        }
    }

    func testValidHebrewWordCanBecomeAmbiguousWhenEnglishCandidateIsStrong() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isHebrewWord("יש") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        guard DictionaryManager.shared.isEnglishWord("ha") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "יש", from: InputSourceController.shared.getHebrewLayoutID(), to: englishLayoutID) == "ha" else {
            throw XCTSkip("English layout mapping is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "יש",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: InputSourceController.shared.getHebrewLayoutID()
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .ambiguous(let candidate):
            XCTAssertEqual(candidate.word, "ha")
            XCTAssertEqual(candidate.target.inputSourceID, englishLayoutID)
        default:
            XCTFail("Expected ambiguous candidate for valid bilingual word")
        }
    }

    func testStructurallyInvalidHebrewWordIsAcceptedAsEnglish() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        guard DictionaryManager.shared.isEnglishWord("hello") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "יקךךם", from: hebrewLayoutID, to: englishLayoutID) == "hello" else {
            throw XCTSkip("English layout mapping is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "יקךךם",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: hebrewLayoutID
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "hello")
            XCTAssertEqual(candidate.target.inputSourceID, englishLayoutID)
        case .ambiguous(let candidate):
            XCTFail("Structurally invalid Hebrew should not defer; got ambiguous: \(candidate.word)")
        case .rejected:
            XCTFail("Structurally invalid Hebrew should not be rejected when target is a real English word")
        case .switchOnly:
            XCTFail("Structurally invalid Hebrew should not be switchOnly")
        }
    }

    func testValidHebrewWithFinalLetterAtEndStaysAmbiguousWithStrongEnglishCandidate() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        guard DictionaryManager.shared.isHebrewWord("יש") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        guard DictionaryManager.shared.isEnglishWord("ha") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "יש", from: hebrewLayoutID, to: InputSourceController.shared.getEnglishLayoutID()) == "ha" else {
            throw XCTSkip("English layout mapping is not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "יש",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: hebrewLayoutID
        )

        if case .ambiguous = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot) {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected ambiguous deferral for valid bilingual short word `יש`")
        }
    }

    func testCommonHebrewWordAniIsNotReplacedWithTbh() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard LayoutMapper.shared.map(text: "אני", from: hebrewLayoutID, to: englishLayoutID) == "tbh" else {
            throw XCTSkip("Layout mapping not available on this machine")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "אני",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: hebrewLayoutID
        )

        let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
        switch decision {
        case .rejected:
            XCTAssertTrue(true)
        case .ambiguous:
            XCTAssertTrue(true)
        case .accepted(let candidate):
            XCTFail("Common Hebrew word 'אני' should not be replaced with '\(candidate.word)'")
        case .switchOnly:
            XCTFail("Common Hebrew word 'אני' should not trigger switchOnly")
        }
    }

    func testEnglishTypoUsesKeystrokeReplayForHebrewCandidate() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        guard DictionaryManager.shared.isHebrewWord("שלום") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        let keystrokes = [
            BufferedKeystroke(keyCode: 0, modifierFlags: 0),
            BufferedKeystroke(keyCode: 40, modifierFlags: 0),
            BufferedKeystroke(keyCode: 32, modifierFlags: 0),
            BufferedKeystroke(keyCode: 31, modifierFlags: 0)
        ]
        guard LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: englishLayoutID)?.text == "akuo",
              LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: hebrewLayoutID)?.text == "שלום" else {
            throw XCTSkip("Required keyboard layout replay is unavailable")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "akuo",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: englishLayoutID,
            keystrokes: keystrokes
        )

        switch LanguageDecisionEngine.shared.evaluate(snapshot: snapshot) {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "שלום")
            XCTAssertEqual(candidate.target.inputSourceID, hebrewLayoutID)
        default:
            XCTFail("Expected keystroke replay to produce the Hebrew correction")
        }
    }

    func testKeystrokeReplayPreservesTrailingCommaAffix() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        guard DictionaryManager.shared.isHebrewWord("שלום") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        let keystrokes = [
            BufferedKeystroke(keyCode: 0, modifierFlags: 0),
            BufferedKeystroke(keyCode: 40, modifierFlags: 0),
            BufferedKeystroke(keyCode: 32, modifierFlags: 0),
            BufferedKeystroke(keyCode: 31, modifierFlags: 0),
            BufferedKeystroke(keyCode: 43, modifierFlags: 0)
        ]
        guard LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: englishLayoutID)?.text == "akuo," else {
            throw XCTSkip("Required keyboard layout replay is unavailable")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "akuo,",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: englishLayoutID,
            keystrokes: keystrokes
        )

        switch LanguageDecisionEngine.shared.evaluate(snapshot: snapshot) {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "שלום,")
            XCTAssertEqual(candidate.target.inputSourceID, hebrewLayoutID)
        default:
            XCTFail("Expected replay correction to preserve the trailing comma")
        }
    }

    func testKeystrokeReplayMapsLeadingSourcePunctuationAsTargetLetter() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        guard DictionaryManager.shared.isHebrewWord("תמיד") else {
            throw XCTSkip("Hebrew dictionary is not available on this machine")
        }
        let keystrokes = [
            BufferedKeystroke(keyCode: 43, modifierFlags: 0),
            BufferedKeystroke(keyCode: 45, modifierFlags: 0),
            BufferedKeystroke(keyCode: 4, modifierFlags: 0),
            BufferedKeystroke(keyCode: 1, modifierFlags: 0)
        ]
        guard LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: englishLayoutID)?.text == ",nhs" else {
            throw XCTSkip("Required keyboard layout replay is unavailable")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: ",nhs",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: englishLayoutID,
            keystrokes: keystrokes
        )

        switch LanguageDecisionEngine.shared.evaluate(snapshot: snapshot) {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "תמיד")
            XCTAssertEqual(candidate.target.inputSourceID, hebrewLayoutID)
        default:
            XCTFail("Expected leading source punctuation to map as a target letter")
        }
    }

    func testIdenticalReplacementWordAcrossLatinTargetsIsAcceptedImmediately() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isEnglishWord("hello") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "יקךךם", from: hebrewLayoutID, to: englishLayoutID) == "hello" else {
            throw XCTSkip("English layout mapping is not available on this machine")
        }

        let installedSources = InputSourceController.shared.listInstalledInputSources()
        let helloLatinTargets = installedSources.filter { source in
            guard source.id != hebrewLayoutID,
                  source.scriptCode == "Latn",
                  source.supportTier == .fullSupport,
                  let mapped = LayoutMapper.shared.map(text: "יקךךם", from: hebrewLayoutID, to: source.id),
                  mapped == "hello",
                  let locale = DictionaryManager.shared.bestSupportedLocale(for: source) else {
                return false
            }
            return DictionaryManager.shared.isWord("hello", in: locale)
        }
        guard helloLatinTargets.count >= 2 else {
            throw XCTSkip("Need at least two Latin targets that validate hello for this regression")
        }

        let snapshot = CorrectionSnapshot(
            originalWord: "יקךךם",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: hebrewLayoutID
        )

        switch LanguageDecisionEngine.shared.evaluate(snapshot: snapshot) {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "hello")
        case .ambiguous(let candidate):
            XCTFail("Expected immediate acceptance for identical replacement word, got ambiguous: \(candidate.word)")
        case .rejected:
            XCTFail("Expected immediate acceptance for identical replacement word, got rejected")
        case .switchOnly:
            XCTFail("Expected immediate acceptance for identical replacement word, got switchOnly")
        }
    }

    func testIdenticalReplacementWordPrefersEarliestMacOSOrderTarget() throws {
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        guard DictionaryManager.shared.isEnglishWord("hello") else {
            throw XCTSkip("English dictionary is not available on this machine")
        }
        guard LayoutMapper.shared.map(text: "יקךךם", from: hebrewLayoutID, to: englishLayoutID) == "hello" else {
            throw XCTSkip("English layout mapping is not available on this machine")
        }

        let installedSources = InputSourceController.shared.listInstalledInputSources()
        let helloLatinTargets = installedSources.filter { source in
            guard source.id != hebrewLayoutID,
                  source.scriptCode == "Latn",
                  source.supportTier == .fullSupport,
                  let mapped = LayoutMapper.shared.map(text: "יקךךם", from: hebrewLayoutID, to: source.id),
                  mapped == "hello",
                  let locale = DictionaryManager.shared.bestSupportedLocale(for: source) else {
                return false
            }
            return DictionaryManager.shared.isWord("hello", in: locale)
        }
        guard helloLatinTargets.count >= 2 else {
            throw XCTSkip("Need at least two Latin targets that validate hello for this regression")
        }

        let expectedTargetID = helloLatinTargets
            .min(by: { lhs, rhs in
                let lhsRank = installedSources.firstIndex(where: { $0.id == lhs.id }) ?? Int.max
                let rhsRank = installedSources.firstIndex(where: { $0.id == rhs.id }) ?? Int.max
                return lhsRank < rhsRank
            })?
            .id

        let snapshot = CorrectionSnapshot(
            originalWord: "יקךךם",
            boundaryCharacter: " ",
            activeAppBundleId: nil,
            generationAtCapture: 1,
            sourceInputSourceID: hebrewLayoutID
        )

        switch LanguageDecisionEngine.shared.evaluate(snapshot: snapshot) {
        case .accepted(let candidate):
            XCTAssertEqual(candidate.word, "hello")
            XCTAssertEqual(candidate.target.inputSourceID, expectedTargetID)
        default:
            XCTFail("Expected accepted hello using earliest macOS-order Latin target")
        }
    }
}
