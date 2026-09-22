import Foundation
import Carbon

struct KeystrokeRenderResult {
    let text: String
    let characterKeyRanges: [Range<Int>]
    let hasPendingDeadKey: Bool
    let consumedAllKeystrokes: Bool
}

enum KeystrokeClassification {
    case text(String)
    case deadKey
    case nonText
}

class LayoutMapper {
    static let shared = LayoutMapper()

    private let mappingQueue = DispatchQueue(label: "com.autoswitch.layoutmapper", qos: .userInitiated)
    private var pairMappingCache: [String: [Character: Character]?] = [:]
    private var layoutDataCache: [String: Data] = [:]
    private let keyCodes: [UInt16] = [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9,
        11, 12, 13, 14, 15, 16, 17, 31, 32, 34, 35, 37, 38, 40, 41, 45, 46,
        18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24, 33, 30, 42, 43, 47, 44, 39, 50
    ]

    private init() {}

    func warmCache(for layoutID: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.warmCache(for: layoutID) }
            return
        }
        guard let newData = keyboardLayoutData(for: layoutID) else { return }

        let existingCache: [String: Data] = mappingQueue.sync { layoutDataCache }

        var builtPairs: [String: [Character: Character]?] = [:]
        for (otherID, otherData) in existingCache where otherID != layoutID {
            builtPairs["\(layoutID)->\(otherID)"] = buildMappingFromData(source: newData, target: otherData)
            builtPairs["\(otherID)->\(layoutID)"] = buildMappingFromData(source: otherData, target: newData)
        }

        mappingQueue.async(flags: .barrier) {
            self.layoutDataCache[layoutID] = newData
            for (key, mapping) in builtPairs {
                self.pairMappingCache[key] = mapping
            }
        }
    }

    func map(text: String, from sourceInputSourceID: String, to targetInputSourceID: String) -> String? {
        guard sourceInputSourceID != targetInputSourceID else {
            return text
        }
        guard let pairMapping = mapping(for: sourceInputSourceID, targetInputSourceID: targetInputSourceID) else {
            return nil
        }
        return String(text.map { char in
            let normalized = normalizeCharacter(char)
            return pairMapping[normalized] ?? normalized
        })
    }

    func canMap(from sourceInputSourceID: String, to targetInputSourceID: String) -> Bool {
        mapping(for: sourceInputSourceID, targetInputSourceID: targetInputSourceID) != nil
    }

    func translateKeyCode(_ keyCode: UInt16, modifiers: UInt32, layoutID: String) -> Character? {
        let data: Data? = mappingQueue.sync {
            if let cached = layoutDataCache[layoutID] {
                return cached
            }
            return nil
        }
        let layoutData: Data
        if let d = data {
            layoutData = d
        } else if Thread.isMainThread, let fetched = keyboardLayoutData(for: layoutID) {
            mappingQueue.async(flags: .barrier) { self.layoutDataCache[layoutID] = fetched }
            layoutData = fetched
        } else {
            return nil
        }
        guard let str = translate(keyCode: keyCode, modifiers: modifiers, keyboardLayout: layoutData),
              str.count == 1,
              let char = str.first else {
            return nil
        }
        return char
    }

    func classifyKeyStroke(_ keyCode: UInt16, modifiers: UInt32, layoutID: String) -> KeystrokeClassification? {
        guard let layoutData = layoutData(for: layoutID) else {
            return nil
        }
        var deadKeyState: UInt32 = 0
        guard let output = translateStatefully(
            keyCode: keyCode,
            modifiers: modifiers,
            keyboardLayout: layoutData,
            deadKeyState: &deadKeyState
        ) else {
            return nil
        }
        if !output.isEmpty {
            return .text(output)
        }
        return deadKeyState == 0 ? .nonText : .deadKey
    }

    func render(keystrokes: [BufferedKeystroke], layoutID: String) -> KeystrokeRenderResult? {
        guard let layoutData = layoutData(for: layoutID) else {
            return nil
        }
        var text = ""
        var characterKeyRanges: [Range<Int>] = []
        var deadKeyState: UInt32 = 0
        var pendingDeadKeyStart: Int?
        var consumedAll = true

        for (index, keystroke) in keystrokes.enumerated() {
            let previousDeadKeyState = deadKeyState
            guard let output = translateStatefully(
                keyCode: keystroke.keyCode,
                modifiers: keystroke.modifierFlags,
                keyboardLayout: layoutData,
                deadKeyState: &deadKeyState
            ) else {
                consumedAll = false
                continue
            }

            if output.isEmpty {
                if deadKeyState != 0 {
                    if pendingDeadKeyStart == nil {
                        pendingDeadKeyStart = index
                    }
                } else if previousDeadKeyState == 0 {
                    consumedAll = false
                } else {
                    pendingDeadKeyStart = nil
                }
                continue
            }

            if previousDeadKeyState != 0, deadKeyState != 0 {
                var standaloneState: UInt32 = 0
                _ = translateStatefully(
                    keyCode: keystroke.keyCode,
                    modifiers: keystroke.modifierFlags,
                    keyboardLayout: layoutData,
                    deadKeyState: &standaloneState
                )
                if standaloneState == 0 {
                    deadKeyState = 0
                }
            }

            let keyRange = (pendingDeadKeyStart ?? index)..<(index + 1)
            text.append(output)
            characterKeyRanges.append(contentsOf: output.map { _ in keyRange })
            pendingDeadKeyStart = deadKeyState == 0 ? nil : index
        }

        return KeystrokeRenderResult(
            text: text,
            characterKeyRanges: characterKeyRanges,
            hasPendingDeadKey: deadKeyState != 0,
            consumedAllKeystrokes: consumedAll
        )
    }

    func mapToHebrew(_ text: String) -> String {
        let sourceID = InputSourceController.shared.getEnglishLayoutID()
        let targetID = InputSourceController.shared.getHebrewLayoutID()
        return map(text: text, from: sourceID, to: targetID) ?? text
    }

    func mapToEnglish(_ text: String) -> String {
        let sourceID = InputSourceController.shared.getHebrewLayoutID()
        let targetID = InputSourceController.shared.getEnglishLayoutID()
        return map(text: text, from: sourceID, to: targetID) ?? text
    }

    private func mapping(for sourceInputSourceID: String, targetInputSourceID: String) -> [Character: Character]? {
        let cacheKey = "\(sourceInputSourceID)->\(targetInputSourceID)"
        return mappingQueue.sync {
            if let cached = pairMappingCache[cacheKey] {
                return cached
            }
            let built = buildMapping(from: sourceInputSourceID, to: targetInputSourceID)
            pairMappingCache[cacheKey] = built
            return built
        }
    }

    private func buildMapping(from sourceInputSourceID: String, to targetInputSourceID: String) -> [Character: Character]? {
        let sourceData = layoutDataCacheEntry(for: sourceInputSourceID)
        let targetData = layoutDataCacheEntry(for: targetInputSourceID)
        guard let sd = sourceData, let td = targetData else { return nil }
        return buildMappingFromData(source: sd, target: td)
    }

    private func layoutDataCacheEntry(for layoutID: String) -> Data? {
        if let cached = layoutDataCache[layoutID] { return cached }
        let fetched: Data?
        if Thread.isMainThread {
            fetched = keyboardLayoutData(for: layoutID)
        } else {
            fetched = DispatchQueue.main.sync { self.keyboardLayoutData(for: layoutID) }
        }
        if let data = fetched {
            layoutDataCache[layoutID] = data
        }
        return fetched
    }

    private func layoutData(for layoutID: String) -> Data? {
        if let cached = mappingQueue.sync(execute: { layoutDataCache[layoutID] }) {
            return cached
        }
        let fetched: Data?
        if Thread.isMainThread {
            fetched = keyboardLayoutData(for: layoutID)
        } else {
            fetched = DispatchQueue.main.sync { self.keyboardLayoutData(for: layoutID) }
        }
        if let fetched {
            mappingQueue.sync(flags: .barrier) {
                layoutDataCache[layoutID] = fetched
            }
        }
        return fetched
    }

    private func buildMappingFromData(source: Data, target: Data) -> [Character: Character]? {
        var mapping: [Character: Character] = [:]
        for keyCode in keyCodes {
            let sourceVariants = translatedVariants(for: keyCode, keyboardLayout: source)
            let targetVariants = translatedVariants(for: keyCode, keyboardLayout: target)
            for modifier in [UInt32(0), UInt32(shiftKey >> 8)] {
                guard let sourceOutput = sourceVariants[modifier],
                      let targetOutput = targetVariants[modifier] else {
                    continue
                }
                let normalizedSourceOutput = normalizeCharacter(sourceOutput)
                if mapping[normalizedSourceOutput] == nil {
                    mapping[normalizedSourceOutput] = targetOutput
                }
            }
        }
        return mapping.isEmpty ? nil : mapping
    }

    private func keyboardLayoutData(for inputSourceID: String) -> Data? {
        let conditions = [kTISPropertyInputSourceID as String: inputSourceID] as CFDictionary
        let sourceList = TISCreateInputSourceList(conditions, false).takeRetainedValue() as NSArray
        guard let source = sourceList.firstObject as! TISInputSource? else {
            return nil
        }
        guard let propertyPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(propertyPtr).takeUnretainedValue() as Data
        return data
    }

    private func translatedVariants(for keyCode: UInt16, keyboardLayout: Data) -> [UInt32: Character] {
        var variants: [UInt32: Character] = [:]
        for modifier in [UInt32(0), UInt32(shiftKey >> 8)] {
            if let output = translate(keyCode: keyCode, modifiers: modifier, keyboardLayout: keyboardLayout),
               output.count == 1,
               let character = output.first {
                variants[modifier] = character
            }
        }
        return variants
    }

    private func translate(keyCode: UInt16, modifiers: UInt32, keyboardLayout: Data) -> String? {
        keyboardLayout.withUnsafeBytes { buffer in
            guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var deadKeyState: UInt32 = 0
            var length: Int = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let result = UCKeyTranslate(
                pointer,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                modifiers,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard result == noErr, length > 0 else {
                return nil
            }
            return String(utf16CodeUnits: chars, count: Int(length))
        }
    }

    private func translateStatefully(
        keyCode: UInt16,
        modifiers: UInt32,
        keyboardLayout: Data,
        deadKeyState: inout UInt32
    ) -> String? {
        keyboardLayout.withUnsafeBytes { buffer in
            guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return nil
            }
            var length: Int = 0
            var chars = [UniChar](repeating: 0, count: 8)
            let result = UCKeyTranslate(
                pointer,
                keyCode,
                UInt16(kUCKeyActionDown),
                modifiers,
                UInt32(LMGetKbdType()),
                OptionBits(0),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard result == noErr else {
                return nil
            }
            return String(utf16CodeUnits: chars, count: Int(length))
        }
    }

    private func normalizeCharacter(_ char: Character) -> Character {
        switch char {
        case "׳", "’", "‘", "`", "´":
            return "'"
        default:
            return char
        }
    }
}
