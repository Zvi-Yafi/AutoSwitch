import Foundation
import CoreGraphics

class TextInjector {
    static let shared = TextInjector()
    
    private let injectionQueue = DispatchQueue(label: "com.autoswitch.injection", qos: .userInteractive)
    
    private init() {}
    
    func inject(originalLength: Int, correctedWord: String, delimiter: String, layoutToSwitch: String? = nil, completion: @escaping () -> Void) {
        injectionQueue.async {
            for _ in 0..<originalLength {
                self.postEvent(virtualKey: 51, keyDown: true)
                self.postEvent(virtualKey: 51, keyDown: false)
                usleep(2000)
            }
            
            self.postUnicodeString(correctedWord)
            
            self.postUnicodeString(delimiter)
            
            if let layout = layoutToSwitch {
                DispatchQueue.main.async {
                    _ = InputSourceController.shared.switchLayout(to: layout)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        completion()
                    }
                }
            } else {
                completion()
            }
        }
    }
    
    private func postEvent(virtualKey: CGKeyCode, keyDown: Bool) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
            return
        }
        
        event.setIntegerValueField(.eventSourceUserData, value: AppConfig.magicNumber)
        event.post(tap: .cghidEventTap)
    }
    
    private func postUnicodeString(_ text: String) {
        guard let utf16Chars = unicodePayload(for: text) else {
            return
        }
        
        guard let source = CGEventSource(stateID: .hidSystemState),
              let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }
        
        eventDown.setIntegerValueField(.eventSourceUserData, value: AppConfig.magicNumber)
        eventDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        eventDown.post(tap: .cghidEventTap)
        
        eventUp.setIntegerValueField(.eventSourceUserData, value: AppConfig.magicNumber)
        eventUp.post(tap: .cghidEventTap)
        
        usleep(5000)
    }

    func unicodePayload(for text: String) -> [UniChar]? {
        let utf16Chars = Array(text.utf16)
        return utf16Chars.isEmpty ? nil : utf16Chars
    }
}
