// Policy regression harness. Compile with the production Models.swift and
// LanguageDecisionEngine.swift. All external services below are in-memory doubles;
// this executable never changes preferences, switches layouts or injects text.
import Foundation

enum CorrectionPreferenceMode { case automatic, preferSpecificTarget }
struct AppSettings {
    var correctionPreferenceMode = CorrectionPreferenceMode.automatic
    var preferredTargetInputSourceID: String? = nil
    var enabledTargetInputSourceIDs: [String] = []
    var enableBestEffortTargets = false
    var enableAmbiguousCorrection = true
    var ambiguousConfidenceThreshold = 0.65
}
final class SettingsStore {
    static let shared = SettingsStore()
    var settings = AppSettings()
    func getSettings() -> AppSettings { settings }
}
final class OverrideController {
    static let shared = OverrideController()
    var ignoredWords: Set<String> = []
    func isIgnoredWord(_ word: String) -> Bool { ignoredWords.contains(word) }
    func isAbbreviationPriorityEnabled(for word: String) -> Bool { false }
}
enum LogLevel { case debug }
func appLog(_ message: String, level: LogLevel) {}

final class InputSourceController {
    static let shared = InputSourceController()
    var extraSources: [InstalledInputSource] = []
    func getCurrentLayoutID() -> String { "he" }
    func listInstalledInputSources() -> [InstalledInputSource] {
        let sources = [("he", "Hebr"), ("en", "Latn")].map { language, script in
            InstalledInputSource(
                id: language, localizedName: language, inputModeID: nil,
                primaryLanguage: language, languageCode: language, scriptCode: script,
                isSelectable: true, isASCIICapable: language == "en",
                hasKeyboardLayoutMapping: true, supportTier: .fullSupport,
                spellcheckLocale: language
            )
        }
        return sources + extraSources
    }
}
final class DictionaryManager {
    static let shared = DictionaryManager()
    // Explicit fixtures distinguish real dictionary evidence from the engine's
    // weak two-letter rule. These are not claims about NSSpellChecker results.
    var words: [String: Set<String>] = [
        "en": ["why", "how", "hello"], "he": ["ים", "שלום"]
    ]
    func bestSupportedLocale(for source: InstalledInputSource) -> String? {
        source.spellcheckLocale
    }
    func isWord(_ word: String, in locale: String) -> Bool {
        words[locale]?.contains(word) == true
    }
}
struct BufferedKeystroke {}
struct KeystrokeRenderResult {
    let text: String
    let characterKeyRanges: [Range<Int>]
    let hasPendingDeadKey: Bool
    let consumedAllKeystrokes: Bool
}
final class LayoutMapper {
    static let shared = LayoutMapper()
    var extraTargetWords: [String: String] = [:]
    // Hebrew key positions needed by these cases; all mapping is deterministic.
    private let englishKeys: [Character: Character] = [
        "׳": "w", "'": "w", "י": "h", "ט": "y", "ם": "o",
        "ק": "e", "ך": "l", "ש": "a", "ל": "k"
    ]
    func map(text: String, from source: String, to target: String) -> String? {
        if source == "he", text == "׳יט", let mapped = extraTargetWords[target] {
            return mapped
        }
        guard source == "he", target == "en" else { return nil }
        return String(text.map { englishKeys[$0] ?? $0 })
    }
    func render(keystrokes: [BufferedKeystroke], layoutID: String) -> KeystrokeRenderResult? {
        // These cases intentionally exercise the engine's text mapping fallback.
        nil
    }
}

var failures = 0
var checks = 0
func check(_ name: String, word: String, expected: String?, ambiguous: Bool = false) {
    checks += 1
    let snapshot = CorrectionSnapshot(
        originalWord: word, boundaryCharacter: " ", activeAppBundleId: nil,
        generationAtCapture: 1, sourceInputSourceID: "he"
    )
    let decision = LanguageDecisionEngine.shared.evaluate(snapshot: snapshot)
    let passed: Bool
    let actual: String
    switch decision {
    case .accepted(let candidate):
        passed = !ambiguous && candidate.word == expected && candidate.target.inputSourceID == "en"
        actual = "accepted(\(candidate.word))"
    case .rejected:
        passed = expected == nil
        actual = "rejected"
    case .ambiguous(let candidate):
        passed = ambiguous && candidate.word == expected
        actual = "ambiguous(\(candidate.word))"
    case .switchOnly:
        passed = false
        actual = "switchOnly"
    }
    if !passed { failures += 1 }
    let expectedLabel = expected.map { "\(ambiguous ? "ambiguous" : "accepted")(\($0))" } ?? "rejected"
    print("\(passed ? "PASS" : "FAIL") \(name): expected=\(expectedLabel) actual=\(actual)")
}

// Requested policy: a valid full-token translation wins before stripping geresh,
// whether the stripped source has weak structural or dictionary evidence.
check("leading geresh before weak two-letter core", word: "׳יט", expected: "why")
check("ASCII apostrophe before weak two-letter core", word: "'יט", expected: "why")
check("trailing geresh after dictionary core", word: "ים׳", expected: "how")
// Fallback: no valid full translation, so retain the valid Hebrew core.
check("no full match preserves valid Hebrew core", word: "׳ים", expected: nil)
// Fallback: full translation is invalid; translate the core and preserve punctuation.
check("no full match falls back to core translation", word: "׳יקךךם", expected: "׳hello")
check("ordinary typo still translates", word: "יקךךם", expected: "hello")
check("ordinary Hebrew word stays unchanged", word: "שלום", expected: nil)

// Priority must preserve explicit user settings and ambiguity between full matches.
SettingsStore.shared.settings.enableAmbiguousCorrection = false
check("full match needs no deferred-correction setting", word: "׳יט", expected: "why")
SettingsStore.shared.settings = AppSettings()
SettingsStore.shared.settings.ambiguousConfidenceThreshold = 0.99
check("full match respects confidence threshold", word: "׳יט", expected: nil)
SettingsStore.shared.settings = AppSettings()
OverrideController.shared.ignoredWords = ["׳יט"]
check("ignored full token stays unchanged", word: "׳יט", expected: nil)
OverrideController.shared.ignoredWords = ["יט"]
check("ignored core stays unchanged", word: "׳יט", expected: nil)
OverrideController.shared.ignoredWords = []
SettingsStore.shared.settings.enabledTargetInputSourceIDs = ["he"]
check("disabled target is not used", word: "׳יט", expected: nil)
SettingsStore.shared.settings = AppSettings()

InputSourceController.shared.extraSources = [InstalledInputSource(
    id: "en-second", localizedName: "Second English layout", inputModeID: nil,
    primaryLanguage: "en", languageCode: "en", scriptCode: "Latn",
    isSelectable: true, isASCIICapable: true, hasKeyboardLayoutMapping: true,
    supportTier: .fullSupport, spellcheckLocale: "en"
)]
LayoutMapper.shared.extraTargetWords = ["en-second": "who"]
// Introduce this word only for the multi-target case; earlier fallback fixtures
// intentionally have no full-token dictionary match.
DictionaryManager.shared.words["en", default: []].insert("who")
check("different full matches remain ambiguous", word: "׳יט", expected: "who", ambiguous: true)
LayoutMapper.shared.extraTargetWords = ["en-second": "why"]
check("identical full matches do not create false ambiguity", word: "׳יט", expected: "why")
print("Policy checks: \(checks - failures) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
