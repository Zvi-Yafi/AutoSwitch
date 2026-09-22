import Foundation
import CoreGraphics

class OverrideController {
    static let shared = OverrideController()
    
    private let queue = DispatchQueue(label: "com.autoswitch.override", qos: .userInitiated)
    private var skipNextCorrection = false
    private var ignoredWordsCache: Set<String> = []
    private var abbreviationExceptionsCache: Set<String> = []
    private var abbreviationPriorityEnabled = true
    private var settingsObserver: NSObjectProtocol?
    
    private init() {
        applySettingsCache(SettingsStore.shared.getSettings())
        settingsObserver = NotificationCenter.default.addObserver(
            forName: .appSettingsDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self else { return }
            if let settings = notification.userInfo?["settings"] as? AppSettings {
                self.applySettingsCache(settings)
            } else {
                self.applySettingsCache(SettingsStore.shared.getSettings())
            }
        }
    }
    
    func consumeSkipNextCorrection() -> Bool {
        queue.sync {
            let value = skipNextCorrection
            skipNextCorrection = false
            return value
        }
    }
    
    func armSkipNextCorrection() {
        queue.sync {
            skipNextCorrection = true
        }
    }
    
    func isIgnoredWord(_ word: String) -> Bool {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return false
        }
        return queue.sync { ignoredWordsCache.contains(normalized) }
    }
    
    func addIgnoredWord(_ word: String) {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty {
            return
        }
        if queue.sync(execute: { ignoredWordsCache.contains(normalized) }) {
            return
        }
        SettingsStore.shared.update { settings in
            var merged = Set(settings.ignoredWords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })
            merged.insert(normalized)
            settings.ignoredWords = merged.sorted()
        }
        _ = queue.sync {
            ignoredWordsCache.insert(normalized)
        }
    }
    
    func removeIgnoredWord(_ word: String) {
        let normalized = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        SettingsStore.shared.update { settings in
            settings.ignoredWords.removeAll { $0.lowercased() == normalized }
        }
        _ = queue.sync {
            ignoredWordsCache.remove(normalized)
        }
    }
    
    func isAbbreviationPriorityEnabled(for word: String) -> Bool {
        let normalized = word.lowercased()
        return queue.sync {
            abbreviationPriorityEnabled && !abbreviationExceptionsCache.contains(normalized)
        }
    }
    
    func matchesSkipShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool {
        matchesHotkey(keyCode: keyCode, flags: flags, hotkey: SettingsStore.shared.getSettings().skipNextHotkey)
    }
    
    func matchesUndoShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool {
        matchesHotkey(keyCode: keyCode, flags: flags, hotkey: SettingsStore.shared.getSettings().undoHotkey)
    }
    
    private func matchesHotkey(keyCode: Int64, flags: CGEventFlags, hotkey: String) -> Bool {
        let tokens = hotkey.lowercased().split(separator: "+").map { String($0) }
        guard let keyToken = tokens.last, let expectedKeyCode = keyCodeForToken(keyToken) else {
            return false
        }
        if expectedKeyCode != keyCode {
            return false
        }
        let needsCommand = tokens.contains("cmd") || tokens.contains("command")
        let needsShift = tokens.contains("shift")
        let needsOption = tokens.contains("alt") || tokens.contains("option")
        let needsControl = tokens.contains("ctrl") || tokens.contains("control")
        if needsCommand != flags.contains(.maskCommand) {
            return false
        }
        if needsShift != flags.contains(.maskShift) {
            return false
        }
        if needsOption != flags.contains(.maskAlternate) {
            return false
        }
        if needsControl != flags.contains(.maskControl) {
            return false
        }
        return true
    }
    
    private func keyCodeForToken(_ token: String) -> Int64? {
        let mapping: [String: Int64] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4, "i": 34, "j": 38,
            "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35, "q": 12, "r": 15, "s": 1, "t": 17,
            "u": 32, "v": 9, "w": 13, "x": 7, "y": 16, "z": 6, ";": 41
        ]
        return mapping[token]
    }

    private func applySettingsCache(_ settings: AppSettings) {
        let normalizedIgnoredWords = Set(settings.ignoredWords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        let normalizedAbbreviationExceptions = Set(settings.abbreviationExceptions.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })
        queue.sync {
            ignoredWordsCache = normalizedIgnoredWords
            abbreviationExceptionsCache = normalizedAbbreviationExceptions
            abbreviationPriorityEnabled = settings.abbreviationPriorityEnabled
        }
    }
}
