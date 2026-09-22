import XCTest
@testable import AutoSwitch

final class BulkWordCorrectionEvaluationTests: XCTestCase {
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
            settings.enableAmbiguousCorrection = true
        }
    }

    override func tearDown() {
        SettingsStore.shared.setSettings(originalSettings)
        super.tearDown()
    }

    func testBulkTop1000HebrewAndEnglishEvaluation() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishWords = try loadWords(named: "frequent_words_en.txt")
        let hebrewWords = try loadWords(named: "frequent_words_he.txt")

        XCTAssertEqual(englishWords.count, 1000)
        XCTAssertEqual(hebrewWords.count, 1000)

        let englishTypedOnHebrewLayout = evaluate(
            sourceWords: englishWords,
            sourceInputSourceID: hebrewLayoutID,
            expectedTargetInputSourceID: englishLayoutID,
            typoTransform: { LayoutMapper.shared.map(text: $0, from: englishLayoutID, to: hebrewLayoutID) ?? $0 }
        )

        let hebrewTypedOnEnglishLayout = evaluate(
            sourceWords: hebrewWords,
            sourceInputSourceID: englishLayoutID,
            expectedTargetInputSourceID: hebrewLayoutID,
            typoTransform: { LayoutMapper.shared.map(text: $0, from: hebrewLayoutID, to: englishLayoutID) ?? $0 }
        )

        print(englishTypedOnHebrewLayout.report(label: "EN intended, typed on HE layout"))
        print(hebrewTypedOnEnglishLayout.report(label: "HE intended, typed on EN layout"))

        XCTAssertGreaterThan(englishTypedOnHebrewLayout.recoverableCount, 0)
        XCTAssertGreaterThan(hebrewTypedOnEnglishLayout.recoverableCount, 0)
    }

    private func evaluate(
        sourceWords: [String],
        sourceInputSourceID: String,
        expectedTargetInputSourceID: String,
        typoTransform: (String) -> String
    ) -> EvaluationStats {
        var acceptedCount = 0
        var ambiguousCount = 0
        var rejectedCount = 0
        var wrongSuggestionCount = 0

        for sourceWord in sourceWords {
            let typoWord = typoTransform(sourceWord)
            let snapshot = CorrectionSnapshot(
                originalWord: typoWord,
                boundaryCharacter: " ",
                activeAppBundleId: nil,
                generationAtCapture: 1,
                sourceInputSourceID: sourceInputSourceID
            )

            let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
            switch decision {
            case .accepted(let candidate):
                if candidate.target.inputSourceID == expectedTargetInputSourceID && normalize(candidate.word, for: expectedTargetInputSourceID) == normalize(sourceWord, for: expectedTargetInputSourceID) {
                    acceptedCount += 1
                } else {
                    wrongSuggestionCount += 1
                }
            case .ambiguous(let candidate):
                if candidate.target.inputSourceID == expectedTargetInputSourceID && normalize(candidate.word, for: expectedTargetInputSourceID) == normalize(sourceWord, for: expectedTargetInputSourceID) {
                    ambiguousCount += 1
                } else {
                    wrongSuggestionCount += 1
                }
            case .rejected:
                rejectedCount += 1
            case .switchOnly:
                rejectedCount += 1
            }
        }

        return EvaluationStats(
            total: sourceWords.count,
            acceptedCount: acceptedCount,
            ambiguousCount: ambiguousCount,
            rejectedCount: rejectedCount,
            wrongSuggestionCount: wrongSuggestionCount
        )
    }

    private func normalize(_ word: String, for targetInputSourceID: String) -> String {
        if targetInputSourceID == InputSourceController.shared.getEnglishLayoutID() {
            return word.lowercased()
        }
        return word
    }

    private func loadWords(named fileName: String) throws -> [String] {
        let fixturesDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let fileURL = fixturesDir.appendingPathComponent(fileName)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        return content
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

private struct EvaluationStats {
    let total: Int
    let acceptedCount: Int
    let ambiguousCount: Int
    let rejectedCount: Int
    let wrongSuggestionCount: Int

    var recoverableCount: Int {
        acceptedCount + ambiguousCount
    }

    func report(label: String) -> String {
        let totalValue = Double(max(total, 1))
        let acceptedPct = (Double(acceptedCount) / totalValue) * 100
        let ambiguousPct = (Double(ambiguousCount) / totalValue) * 100
        let recoverablePct = (Double(recoverableCount) / totalValue) * 100
        let rejectedPct = (Double(rejectedCount) / totalValue) * 100
        let wrongPct = (Double(wrongSuggestionCount) / totalValue) * 100
        return "[BULK-EVAL] \(label) | total=\(total) | accepted=\(acceptedCount) (\(String(format: "%.2f", acceptedPct))%) | ambiguous=\(ambiguousCount) (\(String(format: "%.2f", ambiguousPct))%) | recoverable=\(recoverableCount) (\(String(format: "%.2f", recoverablePct))%) | rejected=\(rejectedCount) (\(String(format: "%.2f", rejectedPct))%) | wrong=\(wrongSuggestionCount) (\(String(format: "%.2f", wrongPct))%)"
    }
}
