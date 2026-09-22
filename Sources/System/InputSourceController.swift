import Foundation
import Carbon

class InputSourceController {
    static let shared = InputSourceController()
    
    private init() {}
    
    func getCurrentLayoutID() -> String {
        performOnMainThread {
            let currentSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            return getInputSourceID(from: currentSource) ?? "Unknown"
        }
    }

    func getCurrentInputSource() -> InstalledInputSource? {
        performOnMainThread {
            let currentSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            return installedInputSource(from: currentSource)
        }
    }

    func listInstalledInputSources() -> [InstalledInputSource] {
        performOnMainThread {
            let sourceList = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
            let sources = sourceList.map { $0 as! TISInputSource }
            var seenIDs = Set<String>()
            var ordered: [InstalledInputSource] = []
            for source in sources {
                guard let installed = installedInputSource(from: source),
                      !seenIDs.contains(installed.id) else {
                    continue
                }
                seenIDs.insert(installed.id)
                ordered.append(installed)
            }
            return ordered
        }
    }

    func getHebrewLayoutID() -> String {
        if let source = listInstalledInputSources().first(where: {
            $0.languageCode?.hasPrefix("he") == true || $0.id.localizedCaseInsensitiveContains("hebrew")
        }) {
            return source.id
        }
        return "com.apple.keylayout.Hebrew"
    }
    
    func getEnglishLayoutID() -> String {
        let sources = listInstalledInputSources()
        if let abc = sources.first(where: { $0.id == "com.apple.keylayout.ABC" }) {
            return abc.id
        }
        if let english = sources.first(where: {
            $0.languageCode?.hasPrefix("en") == true || ($0.isASCIICapable && $0.supportTier != .unsupported)
        }) {
            return english.id
        }
        return "com.apple.keylayout.ABC"
    }
    
    @discardableResult
    func switchLayout(to identifier: String) -> Bool {
        performOnMainThread {
            let conditions = [kTISPropertyInputSourceID as String: identifier]
            let sourceList = TISCreateInputSourceList(conditions as CFDictionary, false).takeRetainedValue() as NSArray
            
            if let targetSource = sourceList.firstObject as! TISInputSource? {
                TISSelectInputSource(targetSource)
                for _ in 0..<6 {
                    if getCurrentLayoutID() == identifier {
                        appLog("Switched layout to: \(identifier)")
                        return true
                    }
                    RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                }
                let currentLayoutID = getCurrentLayoutID()
                appLog("Layout switch verification failed. Expected: \(identifier) | Actual: \(currentLayoutID)")
                return currentLayoutID == identifier
            } else {
                appLog("Failed to find layout with ID: \(identifier)")
                return false
            }
        }
    }

    private func installedInputSource(from source: TISInputSource) -> InstalledInputSource? {
        guard let id = getStringProperty(from: source, key: kTISPropertyInputSourceID) else {
            return nil
        }
        let localizedName = getStringProperty(from: source, key: kTISPropertyLocalizedName) ?? id
        let inputModeID = getStringProperty(from: source, key: kTISPropertyInputModeID)
        let languages = getStringArrayProperty(from: source, key: kTISPropertyInputSourceLanguages)
        let primaryLanguage = languages.first
        let languageCode = normalizedLanguageCode(primaryLanguage ?? inputModeID)
        let scriptCode = normalizedScriptCode(for: languageCode)
        let isSelectable = getBoolProperty(from: source, key: kTISPropertyInputSourceIsSelectCapable)
        let isASCIICapable = getBoolProperty(from: source, key: kTISPropertyInputSourceIsASCIICapable)
        let hasKeyboardLayoutMapping = hasKeyboardLayoutData(source)
        let spellcheckLocale = DictionaryManager.shared.bestSupportedLocale(forLanguageCode: languageCode)
        let supportTier: InputSourceSupportTier
        if !hasKeyboardLayoutMapping || !isSelectable {
            supportTier = .unsupported
        } else if spellcheckLocale != nil {
            supportTier = .fullSupport
        } else if scriptCode != nil || isASCIICapable {
            supportTier = .bestEffort
        } else {
            supportTier = .unsupported
        }
        return InstalledInputSource(
            id: id,
            localizedName: localizedName,
            inputModeID: inputModeID,
            primaryLanguage: primaryLanguage,
            languageCode: languageCode,
            scriptCode: scriptCode,
            isSelectable: isSelectable,
            isASCIICapable: isASCIICapable,
            hasKeyboardLayoutMapping: hasKeyboardLayoutMapping,
            supportTier: supportTier,
            spellcheckLocale: spellcheckLocale
        )
    }
    
    private func getInputSourceID(from source: TISInputSource) -> String? {
        if let propertyPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            return Unmanaged<CFString>.fromOpaque(propertyPtr).takeUnretainedValue() as String
        }
        return nil
    }

    private func getStringProperty(from source: TISInputSource, key: CFString) -> String? {
        guard let propertyPtr = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        let cfType = Unmanaged<CFTypeRef>.fromOpaque(propertyPtr).takeUnretainedValue()
        return cfType as? String
    }

    private func getStringArrayProperty(from source: TISInputSource, key: CFString) -> [String] {
        guard let propertyPtr = TISGetInputSourceProperty(source, key) else {
            return []
        }
        let cfType = Unmanaged<CFTypeRef>.fromOpaque(propertyPtr).takeUnretainedValue()
        return cfType as? [String] ?? []
    }

    private func getBoolProperty(from source: TISInputSource, key: CFString) -> Bool {
        guard let propertyPtr = TISGetInputSourceProperty(source, key) else {
            return false
        }
        let cfType = Unmanaged<CFTypeRef>.fromOpaque(propertyPtr).takeUnretainedValue()
        if let number = cfType as? NSNumber {
            return number.boolValue
        }
        if let boolean = cfType as? Bool {
            return boolean
        }
        return false
    }

    private func hasKeyboardLayoutData(_ source: TISInputSource) -> Bool {
        TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) != nil
    }

    private func normalizedLanguageCode(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        let normalized = value.replacingOccurrences(of: "_", with: "-").lowercased()
        if normalized.contains(".") {
            let components = normalized.split(separator: ".")
            return components.first.map(String.init)
        }
        return normalized
    }

    private func normalizedScriptCode(for languageCode: String?) -> String? {
        guard let prefix = languageCode?.split(separator: "-").first.map(String.init) else {
            return nil
        }
        switch prefix {
        case "he":
            return "Hebr"
        case "ru", "uk", "bg", "sr", "mk", "be":
            return "Cyrl"
        case "el":
            return "Grek"
        case "ar", "fa", "ur":
            return "Arab"
        case "hi", "mr", "ne":
            return "Deva"
        default:
            return "Latn"
        }
    }
    
    private func performOnMainThread<T>(_ block: () -> T) -> T {
        if Thread.isMainThread {
            return block()
        }
        return DispatchQueue.main.sync(execute: block)
    }
}
