import Foundation
import CoreGraphics
import AppKit
import ApplicationServices

class TextInjector {
    static let shared = TextInjector()
    
    private let injectionQueue = DispatchQueue(label: "com.autoswitch.injection", qos: .userInteractive)

    private enum ReplacementPreparation {
        case keyboard
        case selected
        case cancelled
    }

    private struct InjectionFocus {
        let systemWide: AXUIElement
        let element: AXUIElement
    }
    
    private init() {}
    
    // Completion distinguishes cancellation from a completed injection sequence;
    // CGEvent posting does not acknowledge that the target app applied the text.
    func inject(originalWord: String, correctedWord: String, delimiter: String, layoutToSwitch: String? = nil, completion: @escaping (Bool) -> Void) {
        injectionQueue.async {
            guard let focus = self.captureFocus() else {
                completion(false)
                return
            }
            switch self.selectSpotlightReplacement(originalWord: originalWord, delimiter: delimiter, focus: focus) {
            case .selected:
                // Replace the verified selection in one event so Spotlight cannot
                // refresh its inline completion between the word and the space.
                guard self.postUnicodeString(correctedWord + delimiter, focus: focus) else {
                    completion(false)
                    return
                }
            case .keyboard:
                for _ in 0..<(originalWord.count + delimiter.count) {
                    guard self.postKeyStroke(virtualKey: 51, focus: focus) else {
                        completion(false)
                        return
                    }
                    usleep(2000)
                }

                guard self.postUnicodeString(correctedWord, focus: focus),
                      self.postUnicodeString(delimiter, focus: focus) else {
                    completion(false)
                    return
                }
            case .cancelled:
                completion(false)
                return
            }
            
            if let layout = layoutToSwitch {
                DispatchQueue.main.async {
                    // Focus can change again while this main-queue work waits.
                    guard self.isStillFocused(focus) else {
                        completion(false)
                        return
                    }
                    _ = InputSourceController.shared.switchLayout(to: layout)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        completion(true)
                    }
                }
            } else {
                completion(true)
            }
        }
    }

    private func captureFocus() -> InjectionFocus? {
        let systemWide = AXUIElementCreateSystemWide()
        guard let focused = attribute(kAXFocusedUIElementAttribute, of: systemWide),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        return InjectionFocus(systemWide: systemWide, element: focused as! AXUIElement)
    }

    private func isStillFocused(_ focus: InjectionFocus) -> Bool {
        guard let current = attribute(kAXFocusedUIElementAttribute, of: focus.systemWide),
              CFGetTypeID(current) == AXUIElementGetTypeID() else { return false }
        return CFEqual(focus.element, current)
    }

    private func selectSpotlightReplacement(originalWord: String, delimiter: String, focus: InjectionFocus) -> ReplacementPreparation {
        guard !originalWord.isEmpty, delimiter == " " else { return .keyboard }

        let element = focus.element
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else {
            return .keyboard
        }

        // Bound calls on this element only; do not change the global AX timeout.
        AXUIElementSetMessagingTimeout(element, 0.1)
        if bundleID != "com.apple.Spotlight" {
            // Newer macOS versions host Spotlight in Siri. Limit this path to
            // its search field, not other text controls in the same process.
            guard bundleID == "com.apple.campo",
                  attribute(kAXIdentifierAttribute, of: element) as? String == "SpotlightSearchField" else {
                return .keyboard
            }
        }
        guard let role = attribute(kAXRoleAttribute, of: element) as? String,
              role == kAXTextFieldRole || role == kAXComboBoxRole,
              attribute(kAXSubroleAttribute, of: element) as? String != kAXSecureTextFieldSubrole,
              let value = attribute(kAXValueAttribute, of: element) as? String,
              let selected = attribute(kAXSelectedTextRangeAttribute, of: element),
              CFGetTypeID(selected) == AXValueGetTypeID() else { return .keyboard }

        let selectedValue = selected as! AXValue
        var selection = CFRange(location: 0, length: 0)
        let text = value as NSString
        guard AXValueGetType(selectedValue) == .cfRange,
              AXValueGetValue(selectedValue, .cfRange, &selection),
              selection.location >= 0, selection.location <= text.length,
              selection.length >= 0, selection.length <= text.length - selection.location,
              selection.length == 0 || selection.location + selection.length == text.length else {
            return .cancelled
        }

        var isSettable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &isSettable) == .success,
              isSettable.boolValue else { return .keyboard }

        // AX text offsets use UTF-16, independently of the visual RTL/LTR order.
        // The selected suffix may be an inline completion. A space consumed by
        // the search UI may also be absent from the actual field value.
        for expected in [originalWord + delimiter, originalWord] {
            let length = (expected as NSString).length
            guard selection.location >= length else { continue }
            let sourceRange = NSRange(location: selection.location - length, length: length)
            guard text.substring(with: sourceRange) == expected else { continue }

            // Do not select text in a field that lost focus during the AX reads.
            guard isStillFocused(focus),
                  attribute(kAXValueAttribute, of: element) as? String == value,
                  let currentSelection = attribute(kAXSelectedTextRangeAttribute, of: element),
                  CFEqual(selected, currentSelection) else { return .cancelled }

            var replacementRange = CFRange(location: sourceRange.location, length: length + selection.length)
            guard let rangeValue = AXValueCreate(.cfRange, &replacementRange),
                  isStillFocused(focus) else { return .cancelled }
            // A failed write may have timed out after changing the selection;
            // never fall back to a blind series of deletes after attempting it.
            guard AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success,
                  let appliedSelection = attribute(kAXSelectedTextRangeAttribute, of: element),
                  CFEqual(rangeValue, appliedSelection) else { return .cancelled }
            return .selected
        }
        return .cancelled
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
    
    private func postKeyStroke(virtualKey: CGKeyCode, focus: InjectionFocus) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let eventDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false) else {
            return false
        }

        eventDown.setIntegerValueField(.eventSourceUserData, value: AppConfig.magicNumber)
        eventUp.setIntegerValueField(.eventSourceUserData, value: AppConfig.magicNumber)
        // Every fallback keystroke must still belong to the captured field.
        // Once keyDown is posted, always pair it with keyUp.
        guard isStillFocused(focus) else { return false }
        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)
        return true
    }
    
    private func postUnicodeString(_ text: String, focus: InjectionFocus) -> Bool {
        guard let utf16Chars = unicodePayload(for: text) else {
            return isStillFocused(focus)
        }
        
        guard let source = CGEventSource(stateID: .hidSystemState),
              let eventDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let eventUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return false
        }
        
        eventDown.setIntegerValueField(.eventSourceUserData, value: AppConfig.magicNumber)
        eventDown.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
        eventUp.setIntegerValueField(.eventSourceUserData, value: AppConfig.magicNumber)
        // This check is after all selection reads/writes, including failed AX
        // reads that chose the keyboard fallback. AX failure is not permission
        // to send events to whichever field happens to be focused now.
        guard isStillFocused(focus) else { return false }
        eventDown.post(tap: .cghidEventTap)
        eventUp.post(tap: .cghidEventTap)
        
        usleep(5000)
        return true
    }

    func unicodePayload(for text: String) -> [UniChar]? {
        let utf16Chars = Array(text.utf16)
        return utf16Chars.isEmpty ? nil : utf16Chars
    }
}
