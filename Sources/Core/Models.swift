import Foundation

enum SystemState {
    case idle
    case buffering
    case evaluating
    case injecting
    case disabled
}

struct CorrectionSnapshot {
    let originalWord: String
    let boundaryCharacter: String
    let activeAppBundleId: String?
    let generationAtCapture: Int
    let sourceInputSourceID: String?
    let keystrokes: [BufferedKeystroke]

    init(
        originalWord: String,
        boundaryCharacter: String,
        activeAppBundleId: String?,
        generationAtCapture: Int,
        sourceInputSourceID: String?,
        keystrokes: [BufferedKeystroke] = []
    ) {
        self.originalWord = originalWord
        self.boundaryCharacter = boundaryCharacter
        self.activeAppBundleId = activeAppBundleId
        self.generationAtCapture = generationAtCapture
        self.sourceInputSourceID = sourceInputSourceID
        self.keystrokes = keystrokes
    }
}

struct CorrectionHistoryItem {
    let originalWord: String
    let correctedWord: String
    let delimiter: String
    let previousLayout: String 
    let targetInputSourceID: String
    let appBundleId: String?
    let timestamp: Date
    let generation: Int
}

enum InputSourceSupportTier: String, Codable, CaseIterable {
    case fullSupport
    case bestEffort
    case unsupported
}

struct InstalledInputSource: Equatable, Codable, Identifiable {
    let id: String
    let localizedName: String
    let inputModeID: String?
    let primaryLanguage: String?
    let languageCode: String?
    let scriptCode: String?
    let isSelectable: Bool
    let isASCIICapable: Bool
    let hasKeyboardLayoutMapping: Bool
    let supportTier: InputSourceSupportTier
    let spellcheckLocale: String?
}

struct CorrectionTarget: Equatable {
    let inputSourceID: String
    let languageCode: String?
    let supportTier: InputSourceSupportTier
}

struct CorrectionCandidate: Equatable {
    let word: String
    let target: CorrectionTarget
    let score: Double
}

enum LanguageDecision {
    case rejected
    case accepted(candidate: CorrectionCandidate)
    case ambiguous(candidate: CorrectionCandidate)
    case switchOnly(targetInputSourceID: String, targetLanguageCode: String?)
}

struct PendingAmbiguousCorrection {
    let originalWord: String
    let correctedWord: String
    let delimiter: String
    let target: CorrectionTarget
    let appBundleId: String?
    let generation: Int
}

struct AppConfig {
    static let magicNumber: Int64 = 0x05A17C // Safe hex value for user data
}
