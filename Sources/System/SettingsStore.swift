import Foundation

enum CorrectionPreferenceMode: String, Codable, CaseIterable {
    case automatic
    case preferSpecificTarget
}

enum LogLevel: String, Codable {
    case off
    case basic
    case debug
}

struct AppSettings: Codable {
    var enabled: Bool
    var correctionPreferenceMode: CorrectionPreferenceMode
    var preferredTargetInputSourceID: String?
    var enabledTargetInputSourceIDs: [String]
    var enableBestEffortTargets: Bool
    var enableAmbiguousCorrection: Bool
    var ambiguousConfidenceThreshold: Double
    var undoWindowSeconds: Double
    var skipNextHotkey: String
    var undoHotkey: String
    var abbreviationPriorityEnabled: Bool
    var abbreviationExceptions: [String]
    var ignoredWords: [String]
    var whitelistedBundleIds: [String]
    var blacklistedBundleIds: [String]
    var logLevel: LogLevel
    var enableLogExport: Bool
    var hasCompletedOnboarding: Bool
    
    static let `default` = AppSettings(
        enabled: true,
        correctionPreferenceMode: .automatic,
        preferredTargetInputSourceID: nil,
        enabledTargetInputSourceIDs: [],
        enableBestEffortTargets: false,
        enableAmbiguousCorrection: true,
        ambiguousConfidenceThreshold: 0.65,
        undoWindowSeconds: 2.5,
        skipNextHotkey: "cmd+shift+;",
        undoHotkey: "cmd+z",
        abbreviationPriorityEnabled: true,
        abbreviationExceptions: [],
        ignoredWords: [],
        whitelistedBundleIds: [],
        blacklistedBundleIds: [],
        logLevel: .basic,
        enableLogExport: true,
        hasCompletedOnboarding: false
    )

    private enum CodingKeys: String, CodingKey {
        case enabled
        case correctionPreferenceMode
        case preferredTargetInputSourceID
        case enabledTargetInputSourceIDs
        case enableBestEffortTargets
        case enableAmbiguousCorrection
        case ambiguousConfidenceThreshold
        case undoWindowSeconds
        case skipNextHotkey
        case undoHotkey
        case abbreviationPriorityEnabled
        case abbreviationExceptions
        case ignoredWords
        case whitelistedBundleIds
        case blacklistedBundleIds
        case logLevel
        case enableLogExport
        case hasCompletedOnboarding
        case preferredOutputLanguage
    }

    private enum LegacyPreferredOutputLanguage: String, Codable {
        case auto
        case hebrew
        case english
    }

    init(
        enabled: Bool,
        correctionPreferenceMode: CorrectionPreferenceMode,
        preferredTargetInputSourceID: String?,
        enabledTargetInputSourceIDs: [String],
        enableBestEffortTargets: Bool,
        enableAmbiguousCorrection: Bool,
        ambiguousConfidenceThreshold: Double,
        undoWindowSeconds: Double,
        skipNextHotkey: String,
        undoHotkey: String,
        abbreviationPriorityEnabled: Bool,
        abbreviationExceptions: [String],
        ignoredWords: [String],
        whitelistedBundleIds: [String],
        blacklistedBundleIds: [String],
        logLevel: LogLevel,
        enableLogExport: Bool,
        hasCompletedOnboarding: Bool
    ) {
        self.enabled = enabled
        self.correctionPreferenceMode = correctionPreferenceMode
        self.preferredTargetInputSourceID = preferredTargetInputSourceID
        self.enabledTargetInputSourceIDs = enabledTargetInputSourceIDs
        self.enableBestEffortTargets = enableBestEffortTargets
        self.enableAmbiguousCorrection = enableAmbiguousCorrection
        self.ambiguousConfidenceThreshold = ambiguousConfidenceThreshold
        self.undoWindowSeconds = undoWindowSeconds
        self.skipNextHotkey = skipNextHotkey
        self.undoHotkey = undoHotkey
        self.abbreviationPriorityEnabled = abbreviationPriorityEnabled
        self.abbreviationExceptions = abbreviationExceptions
        self.ignoredWords = ignoredWords
        self.whitelistedBundleIds = whitelistedBundleIds
        self.blacklistedBundleIds = blacklistedBundleIds
        self.logLevel = logLevel
        self.enableLogExport = enableLogExport
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? AppSettings.default.enabled
        correctionPreferenceMode = try container.decodeIfPresent(CorrectionPreferenceMode.self, forKey: .correctionPreferenceMode) ?? AppSettings.default.correctionPreferenceMode
        preferredTargetInputSourceID = try container.decodeIfPresent(String.self, forKey: .preferredTargetInputSourceID)
        enabledTargetInputSourceIDs = try container.decodeIfPresent([String].self, forKey: .enabledTargetInputSourceIDs) ?? AppSettings.default.enabledTargetInputSourceIDs
        enableBestEffortTargets = try container.decodeIfPresent(Bool.self, forKey: .enableBestEffortTargets) ?? AppSettings.default.enableBestEffortTargets
        enableAmbiguousCorrection = try container.decodeIfPresent(Bool.self, forKey: .enableAmbiguousCorrection) ?? AppSettings.default.enableAmbiguousCorrection
        ambiguousConfidenceThreshold = try container.decodeIfPresent(Double.self, forKey: .ambiguousConfidenceThreshold) ?? AppSettings.default.ambiguousConfidenceThreshold
        undoWindowSeconds = try container.decodeIfPresent(Double.self, forKey: .undoWindowSeconds) ?? AppSettings.default.undoWindowSeconds
        skipNextHotkey = try container.decodeIfPresent(String.self, forKey: .skipNextHotkey) ?? AppSettings.default.skipNextHotkey
        undoHotkey = try container.decodeIfPresent(String.self, forKey: .undoHotkey) ?? AppSettings.default.undoHotkey
        abbreviationPriorityEnabled = try container.decodeIfPresent(Bool.self, forKey: .abbreviationPriorityEnabled) ?? AppSettings.default.abbreviationPriorityEnabled
        abbreviationExceptions = try container.decodeIfPresent([String].self, forKey: .abbreviationExceptions) ?? AppSettings.default.abbreviationExceptions
        ignoredWords = try container.decodeIfPresent([String].self, forKey: .ignoredWords) ?? AppSettings.default.ignoredWords
        whitelistedBundleIds = try container.decodeIfPresent([String].self, forKey: .whitelistedBundleIds) ?? AppSettings.default.whitelistedBundleIds
        blacklistedBundleIds = try container.decodeIfPresent([String].self, forKey: .blacklistedBundleIds) ?? AppSettings.default.blacklistedBundleIds
        logLevel = try container.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? AppSettings.default.logLevel
        enableLogExport = try container.decodeIfPresent(Bool.self, forKey: .enableLogExport) ?? AppSettings.default.enableLogExport
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? AppSettings.default.hasCompletedOnboarding

        if !container.contains(.correctionPreferenceMode),
           let legacyPreference = try container.decodeIfPresent(LegacyPreferredOutputLanguage.self, forKey: .preferredOutputLanguage) {
            switch legacyPreference {
            case .auto:
                correctionPreferenceMode = .automatic
                preferredTargetInputSourceID = nil
            case .hebrew:
                correctionPreferenceMode = .preferSpecificTarget
                preferredTargetInputSourceID = InputSourceController.shared.getHebrewLayoutID()
            case .english:
                correctionPreferenceMode = .preferSpecificTarget
                preferredTargetInputSourceID = InputSourceController.shared.getEnglishLayoutID()
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(correctionPreferenceMode, forKey: .correctionPreferenceMode)
        try container.encodeIfPresent(preferredTargetInputSourceID, forKey: .preferredTargetInputSourceID)
        try container.encode(enabledTargetInputSourceIDs, forKey: .enabledTargetInputSourceIDs)
        try container.encode(enableBestEffortTargets, forKey: .enableBestEffortTargets)
        try container.encode(enableAmbiguousCorrection, forKey: .enableAmbiguousCorrection)
        try container.encode(ambiguousConfidenceThreshold, forKey: .ambiguousConfidenceThreshold)
        try container.encode(undoWindowSeconds, forKey: .undoWindowSeconds)
        try container.encode(skipNextHotkey, forKey: .skipNextHotkey)
        try container.encode(undoHotkey, forKey: .undoHotkey)
        try container.encode(abbreviationPriorityEnabled, forKey: .abbreviationPriorityEnabled)
        try container.encode(abbreviationExceptions, forKey: .abbreviationExceptions)
        try container.encode(ignoredWords, forKey: .ignoredWords)
        try container.encode(whitelistedBundleIds, forKey: .whitelistedBundleIds)
        try container.encode(blacklistedBundleIds, forKey: .blacklistedBundleIds)
        try container.encode(logLevel, forKey: .logLevel)
        try container.encode(enableLogExport, forKey: .enableLogExport)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
    }
}

extension Notification.Name {
    static let appSettingsDidChange = Notification.Name("AppSettingsDidChange")
}

class SettingsStore {
    static let shared = SettingsStore()
    
    private let settingsKey = "autoswitch.settings.v1"
    private let queue = DispatchQueue(label: "com.autoswitch.settings", qos: .userInitiated)
    private var settings: AppSettings
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .default
            persist(settings)
        }
    }
    
    func getSettings() -> AppSettings {
        queue.sync { settings }
    }
    
    func update(_ mutate: (inout AppSettings) -> Void) {
        let updated = queue.sync { () -> AppSettings in
            var copy = settings
            mutate(&copy)
            settings = copy
            persist(copy)
            return copy
        }
        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil, userInfo: ["settings": updated])
    }
    
    func setSettings(_ newSettings: AppSettings) {
        queue.sync {
            settings = newSettings
            persist(newSettings)
        }
        NotificationCenter.default.post(name: .appSettingsDidChange, object: nil, userInfo: ["settings": newSettings])
    }
    
    func exportSettingsJSON() -> String? {
        let current = getSettings()
        guard let data = try? JSONEncoder().encode(current) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
    
    func importSettingsJSON(_ json: String) -> Bool {
        guard let data = json.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return false
        }
        setSettings(decoded)
        return true
    }
    
    private func persist(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }
}
