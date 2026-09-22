import Foundation
import AppKit

class DictionaryManager {
    static let shared = DictionaryManager()
    
    private let spellChecker = NSSpellChecker.shared
    private let availableLanguagesByNormalizedKey: [String: String]
    
    private let spellCheckerQueue = DispatchQueue(label: "com.autoswitch.spellchecker")
    private let maxLookupCacheEntries = 20_000
    private var lookupCache: [String: Bool] = [:]
    private var resolvedLanguageCache: [String: String?] = [:]
    
    private init() {
        let availableLanguages = spellChecker.availableLanguages
        var mapping: [String: String] = [:]
        for language in availableLanguages {
            mapping[DictionaryManager.normalizedLocale(language)] = language
        }
        self.availableLanguagesByNormalizedKey = mapping
    }
    
    func loadDictionaries(english: [String], hebrew: [String]) {
        spellCheckerQueue.sync {
            lookupCache.removeAll(keepingCapacity: true)
            resolvedLanguageCache.removeAll(keepingCapacity: true)
        }
    }
    
    func availableSpellcheckLanguages() -> [String] {
        availableLanguagesByNormalizedKey.values.sorted()
    }

    func bestSupportedLocale(for inputSource: InstalledInputSource) -> String? {
        if let spellcheckLocale = inputSource.spellcheckLocale {
            return spellcheckLocale
        }
        return bestSupportedLocale(forLanguageCode: inputSource.languageCode)
    }

    func bestSupportedLocale(forLanguageCode languageCode: String?) -> String? {
        guard let languageCode else {
            return nil
        }
        let normalized = DictionaryManager.normalizedLocale(languageCode)
        return spellCheckerQueue.sync {
            if let cached = resolvedLanguageCache[normalized] {
                return cached
            }
            let resolved = resolveLanguageCandidates(for: normalized)
            resolvedLanguageCache[normalized] = resolved
            return resolved
        }
    }

    func isWord(_ word: String, in locale: String) -> Bool {
        let normalizedWord = normalizeWord(word, locale: locale)
        guard !normalizedWord.isEmpty else {
            return false
        }
        let cacheKey = "\(DictionaryManager.normalizedLocale(locale))|\(normalizedWord)"
        return spellCheckerQueue.sync {
            if let cached = lookupCache[cacheKey] {
                return cached
            }
            let range = self.spellChecker.checkSpelling(
                of: normalizedWord,
                startingAt: 0,
                language: locale,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
            let isMatch = range.location == NSNotFound
            cacheLookup(value: isMatch, for: cacheKey)
            return isMatch
        }
    }

    func isEnglishWord(_ word: String) -> Bool {
        guard let locale = bestSupportedLocale(forLanguageCode: "en") else {
            return false
        }
        return isWord(word, in: locale)
    }
    
    func isHebrewWord(_ word: String) -> Bool {
        guard let locale = bestSupportedLocale(forLanguageCode: "he") else {
            return false
        }
        return isWord(word, in: locale)
    }

    private func cacheLookup(value: Bool, for cacheKey: String) {
        if lookupCache[cacheKey] == nil && lookupCache.count >= maxLookupCacheEntries {
            lookupCache.removeAll(keepingCapacity: true)
        }
        lookupCache[cacheKey] = value
    }

    private func resolveLanguageCandidates(for normalizedLanguageCode: String) -> String? {
        if let exact = availableLanguagesByNormalizedKey[normalizedLanguageCode] {
            return exact
        }

        let languagePrefix = normalizedLanguageCode.split(separator: "_").first.map(String.init) ?? normalizedLanguageCode
        if let prefixMatch = availableLanguagesByNormalizedKey.first(where: { $0.key.hasPrefix(languagePrefix) }) {
            return prefixMatch.value
        }

        return nil
    }

    private static func normalizedLocale(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "_").lowercased()
    }

    private func normalizeWord(_ word: String, locale: String) -> String {
        let hasNonLatinLetter = word.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.value > 0x024F }
        if hasNonLatinLetter {
            return word
        }
        return word.lowercased()
    }
}
