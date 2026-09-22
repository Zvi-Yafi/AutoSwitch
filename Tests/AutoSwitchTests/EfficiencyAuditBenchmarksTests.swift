import XCTest
@testable import AutoSwitch

final class EfficiencyAuditBenchmarksTests: XCTestCase {
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
            settings.logLevel = .off
        }
    }

    override func tearDown() {
        SettingsStore.shared.setSettings(originalSettings)
        super.tearDown()
    }

    func testEfficiencyBenchmarks() throws {
        let englishLayoutID = InputSourceController.shared.getEnglishLayoutID()
        let hebrewLayoutID = InputSourceController.shared.getHebrewLayoutID()
        let englishWords = try loadWords(named: "frequent_words_en.txt")
        let hebrewWords = try loadWords(named: "frequent_words_he.txt")
        let enTypos = englishWords.map { LayoutMapper.shared.map(text: $0, from: englishLayoutID, to: hebrewLayoutID) ?? $0 }
        let heTypos = hebrewWords.map { LayoutMapper.shared.map(text: $0, from: hebrewLayoutID, to: englishLayoutID) ?? $0 }
        let allTypos = enTypos + heTypos
        let evaluations = enTypos.map { (word: $0, sourceID: hebrewLayoutID) } + heTypos.map { (word: $0, sourceID: englishLayoutID) }

        let mapDuration = measureNanoseconds {
            _ = allTypos.map { LayoutMapper.shared.map(text: $0, from: hebrewLayoutID, to: englishLayoutID) ?? $0 }
            _ = allTypos.map { LayoutMapper.shared.map(text: $0, from: englishLayoutID, to: hebrewLayoutID) ?? $0 }
        }

        let dictionaryDuration = measureNanoseconds {
            for word in allTypos {
                _ = DictionaryManager.shared.isEnglishWord(word)
                _ = DictionaryManager.shared.isHebrewWord(word)
            }
        }

        let evaluateDuration = measureNanoseconds {
            for evaluation in evaluations {
                _ = LanguageDecisionEngine.shared.evaluate(
                    snapshot: CorrectionSnapshot(
                        originalWord: evaluation.word,
                        boundaryCharacter: " ",
                        activeAppBundleId: nil,
                        generationAtCapture: 1,
                        sourceInputSourceID: evaluation.sourceID
                    )
                )
            }
        }

        let burstWords = Array(evaluations.prefix(120))
        let burstDuration = measureNanoseconds {
            for evaluation in burstWords {
                _ = LanguageDecisionEngine.shared.evaluate(
                    snapshot: CorrectionSnapshot(
                        originalWord: evaluation.word,
                        boundaryCharacter: " ",
                        activeAppBundleId: nil,
                        generationAtCapture: 1,
                        sourceInputSourceID: evaluation.sourceID
                    )
                )
            }
        }

        Thread.sleep(forTimeInterval: 1.0)

        print("[EFF-AUDIT] dataset_words=\(allTypos.count)")
        print("[EFF-AUDIT] mapping_total_ms=\(formatMs(mapDuration)) mapping_avg_us=\(formatUs(mapDuration, count: allTypos.count * 2))")
        print("[EFF-AUDIT] dictionary_total_ms=\(formatMs(dictionaryDuration)) dictionary_avg_us=\(formatUs(dictionaryDuration, count: allTypos.count * 2))")
        print("[EFF-AUDIT] evaluate_total_ms=\(formatMs(evaluateDuration)) evaluate_avg_us=\(formatUs(evaluateDuration, count: allTypos.count))")
        print("[EFF-AUDIT] burst_120_total_ms=\(formatMs(burstDuration)) burst_120_avg_us=\(formatUs(burstDuration, count: max(burstWords.count, 1)))")

        XCTAssertEqual(allTypos.count, 2000)
    }

    private func measureNanoseconds(_ block: () -> Void) -> UInt64 {
        let start = DispatchTime.now().uptimeNanoseconds
        block()
        let end = DispatchTime.now().uptimeNanoseconds
        return end - start
    }

    private func formatMs(_ nanos: UInt64) -> String {
        String(format: "%.3f", Double(nanos) / 1_000_000.0)
    }

    private func formatUs(_ nanos: UInt64, count: Int) -> String {
        let divisor = Double(max(count, 1))
        return String(format: "%.3f", Double(nanos) / 1_000.0 / divisor)
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
