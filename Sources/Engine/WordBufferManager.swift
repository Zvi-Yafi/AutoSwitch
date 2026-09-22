import Foundation

struct BufferedKeystroke {
    let keyCode: UInt16
    let modifierFlags: UInt32
}

class WordBufferManager {
    static let shared = WordBufferManager()
    
    private var keystrokes: [BufferedKeystroke] = []
    private var resolvedSourceLayoutID: String?
    private var lastInjectedLayoutID: String?
    private let maxBufferLength = 30
    
    private let boundaries: Set<Character> = [
        " ", "\n", "\r", "\t",
        ".", "!", "?",
        "(", ")", "[", "]", "{", "}",
        "\"", "…"
    ]
    
    private init() {}
    
    func setLastInjectedLayout(_ layoutID: String) {
        lastInjectedLayoutID = layoutID
    }
    
    func clearLastInjectedLayout() {
        lastInjectedLayoutID = nil
    }
    
    var effectiveSourceLayoutID: String {
        if let injected = lastInjectedLayoutID {
            return injected
        }
        return resolvedSourceLayoutID ?? InputSourceController.shared.getCurrentLayoutID()
    }
    
    func appendKeystroke(keyCode: UInt16, modifierFlags: UInt32) {
        if keystrokes.isEmpty {
            if let injected = lastInjectedLayoutID {
                resolvedSourceLayoutID = injected
                lastInjectedLayoutID = nil
            } else {
                resolvedSourceLayoutID = InputSourceController.shared.getCurrentLayoutID()
            }
        }
        if keystrokes.count >= maxBufferLength {
            keystrokes.removeFirst()
        }
        keystrokes.append(BufferedKeystroke(keyCode: keyCode, modifierFlags: modifierFlags))
    }
    
    func removeLast() {
        if !keystrokes.isEmpty {
            keystrokes.removeLast()
        }
    }
    
    func isBoundary(_ character: Character) -> Bool {
        return boundaries.contains(character)
    }
    
    func resolveCharacter(keyCode: UInt16, modifierFlags: UInt32) -> Character? {
        let layoutID = effectiveSourceLayoutID
        return LayoutMapper.shared.translateKeyCode(keyCode, modifiers: modifierFlags, layoutID: layoutID)
    }
    
    func getSnapshot(boundary: Character, appBundleId: String?, generation: Int) -> CorrectionSnapshot {
        let layoutID = resolvedSourceLayoutID ?? InputSourceController.shared.getCurrentLayoutID()
        let word = buildWord(layoutID: layoutID)
        return CorrectionSnapshot(
            originalWord: word,
            boundaryCharacter: String(boundary),
            activeAppBundleId: appBundleId,
            generationAtCapture: generation,
            sourceInputSourceID: layoutID,
            keystrokes: keystrokes
        )
    }
    
    private func buildWord(layoutID: String) -> String {
        if let rendered = LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: layoutID),
           rendered.consumedAllKeystrokes {
            return rendered.text
        }
        var result = ""
        for keystroke in keystrokes {
            if let char = LayoutMapper.shared.translateKeyCode(keystroke.keyCode, modifiers: keystroke.modifierFlags, layoutID: layoutID) {
                result.append(char)
            }
        }
        return result
    }
    
    func clear() {
        keystrokes = []
        resolvedSourceLayoutID = nil
    }
    
    var currentWord: String {
        let layoutID = resolvedSourceLayoutID ?? InputSourceController.shared.getCurrentLayoutID()
        return buildWord(layoutID: layoutID)
    }
    
    var isEmpty: Bool {
        keystrokes.isEmpty
    }

    var hasPendingDeadKey: Bool {
        let layoutID = resolvedSourceLayoutID ?? InputSourceController.shared.getCurrentLayoutID()
        return LayoutMapper.shared.render(keystrokes: keystrokes, layoutID: layoutID)?.hasPendingDeadKey == true
    }
}
