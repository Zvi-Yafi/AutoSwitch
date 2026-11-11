import Foundation
import ApplicationServices

// These local types shadow system services. AXValue and Core Foundation remain
// real so equality, type checking and UTF-16 range bridging are exercised.
typealias AXUIElement = NSDictionary
let systemElement: NSDictionary = ["id": "system"]
let searchElement: NSDictionary = ["id": "search"]
let otherElement: NSDictionary = ["id": "other"]

final class Scenario {
    var focused = searchElement
    var bundleID = "com.apple.Spotlight"
    var value = "אבגד "
    var selection = CFRange(location: 5, length: 0)
    var subrole = "AXSearchField"
    var identifier = "SpotlightSearchField"
    var missingFocus = false
    var focusAfterEvent: Int?
    var focusOnMainDispatch = false
    var settable = true
    var missingRange = false
    var writeError: AXError = .success
    var focusOnRead: Int?
    var changeValueOnRead: Int?
    var changeSelectionOnRead: Int?
    var focusOnWrite = false
    var ignoreWrite = false
    var reads = 0
    var writes = 0
    var events: [String] = []
    var recipients: [NSDictionary] = []
    var layouts: [String] = []
}
var scenario = Scenario()

func AXUIElementCreateSystemWide() -> AXUIElement { systemElement }
func AXUIElementGetTypeID() -> CFTypeID { CFDictionaryGetTypeID() }
func AXUIElementGetPid(_ element: AXUIElement, _ pid: UnsafeMutablePointer<pid_t>) -> AXError {
    pid.pointee = 123
    return .success
}
func AXUIElementSetMessagingTimeout(_ element: AXUIElement, _ timeout: Float) -> AXError { .success }
func AXUIElementCopyAttributeValue(_ element: AXUIElement, _ attribute: CFString, _ output: UnsafeMutablePointer<CFTypeRef?>) -> AXError {
    scenario.reads += 1
    if scenario.focusOnRead == scenario.reads { scenario.focused = otherElement }
    if scenario.changeValueOnRead == scenario.reads { scenario.value = "changed" }
    if scenario.changeSelectionOnRead == scenario.reads { scenario.selection.location = 0 }
    switch attribute as String {
    case kAXFocusedUIElementAttribute:
        if scenario.missingFocus { return .noValue }
        output.pointee = scenario.focused
    case kAXRoleAttribute: output.pointee = kAXTextFieldRole as CFString
    case kAXSubroleAttribute: output.pointee = scenario.subrole as CFString
    case kAXIdentifierAttribute: output.pointee = scenario.identifier as CFString
    case kAXValueAttribute: output.pointee = scenario.value as CFString
    case kAXSelectedTextRangeAttribute:
        if scenario.missingRange { return .attributeUnsupported }
        output.pointee = AXValueCreate(.cfRange, &scenario.selection)
    default: return .attributeUnsupported
    }
    return .success
}
func AXUIElementIsAttributeSettable(_ element: AXUIElement, _ attribute: CFString, _ result: UnsafeMutablePointer<DarwinBoolean>) -> AXError {
    result.pointee = DarwinBoolean(scenario.settable)
    return .success
}
func AXUIElementSetAttributeValue(_ element: AXUIElement, _ attribute: CFString, _ value: CFTypeRef) -> AXError {
    scenario.writes += 1
    if scenario.focusOnWrite { scenario.focused = otherElement }
    if scenario.writeError != .success { return scenario.writeError }
    if !scenario.ignoreWrite { _ = AXValueGetValue(value as! AXValue, .cfRange, &scenario.selection) }
    return .success
}
final class NSRunningApplication {
    init?(processIdentifier: pid_t) {}
    var bundleIdentifier: String? { scenario.bundleID }
}
final class DispatchQueue {
    enum QoS { case userInteractive }
    static let main = DispatchQueue(label: "main", qos: .userInteractive)
    let label: String
    init(label: String, qos: QoS) { self.label = label }
    func async(execute: () -> Void) {
        if label == "main" && scenario.focusOnMainDispatch { scenario.focused = otherElement }
        execute()
    }
    func asyncAfter(deadline: Double, execute: () -> Void) { execute() }
}
extension Double { static func now() -> Double { 0 } }
func usleep(_ microseconds: UInt32) {}
enum AppConfig { static let magicNumber: Int64 = 12345 }
final class InputSourceController {
    static let shared = InputSourceController()
    func switchLayout(to layout: String) -> Bool { scenario.layouts.append(layout); return true }
}
final class CGEventSource {
    enum State { case hidSystemState }
    init?(stateID: State) {}
}
final class CGEvent {
    enum Field { case eventSourceUserData }
    enum Tap { case cghidEventTap }
    let key: CGKeyCode
    let down: Bool
    var payload: String?
    init?(keyboardEventSource: CGEventSource, virtualKey: CGKeyCode, keyDown: Bool) {
        key = virtualKey; down = keyDown
    }
    func setIntegerValueField(_ field: Field, value: Int64) {}
    func keyboardSetUnicodeString(stringLength: Int, unicodeString: [UniChar]) {
        payload = String(decoding: unicodeString.prefix(stringLength), as: UTF16.self)
    }
    func post(tap: Tap) {
        guard down else { return }
        scenario.recipients.append(scenario.focused)
        scenario.events.append(payload ?? "DELETE")
        guard scenario.focused == searchElement else { return }
        var range = NSRange(location: scenario.selection.location, length: scenario.selection.length)
        let text = scenario.value as NSString
        if payload == nil && range.length == 0 && range.location > 0 {
            range = text.rangeOfComposedCharacterSequence(at: range.location - 1)
        }
        guard range.location >= 0, range.location + range.length <= text.length else { return }
        scenario.value = text.replacingCharacters(in: range, with: payload ?? "")
        scenario.selection = CFRange(location: range.location + (payload ?? "").utf16.count, length: 0)
        if scenario.focusAfterEvent == scenario.events.count { scenario.focused = otherElement }
    }
}
