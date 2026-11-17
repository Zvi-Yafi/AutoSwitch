import Foundation
import CoreGraphics
import Carbon.HIToolbox

// A deterministic scheduler, not a model of GCD thread execution. sync drains
// prior work on that serial queue. Deferred queues can be held independently.
final class DispatchQueue {
    enum QoS { case userInteractive, userInitiated }
    enum Flags { case barrier }
    static var all: [DispatchQueue] = []
    static let main = DispatchQueue(label: "main", qos: .userInteractive)
    let label: String
    var blocks: [() -> Void] = []
    private var running = false
    init(label: String, qos: QoS) { self.label = label; Self.all.append(self) }
    func async(flags: Flags? = nil, execute: @escaping () -> Void) { blocks.append(execute) }
    func asyncAfter(deadline: Double, execute: @escaping () -> Void) { blocks.append(execute) }
    func sync<T>(flags: Flags? = nil, execute: () -> T) -> T {
        precondition(!running, "Synchronous reentry to serial queue")
        drain()
        running = true
        defer { running = false }
        return execute()
    }
    func drain() {
        precondition(!running)
        var count = 0
        while !blocks.isEmpty {
            count += 1
            precondition(count < 1000, "Queue did not settle")
            running = true
            blocks.removeFirst()()
            running = false
        }
    }
    static func named(_ label: String) -> DispatchQueue { all.first { $0.label == label }! }
    static func settle() {
        for _ in 0..<100 {
            let queues = all
            if queues.allSatisfy({ $0.blocks.isEmpty }) { return }
            for queue in queues { queue.drain() }
        }
        fatalError("Scheduled work did not settle")
    }
}
extension Double { static func now() -> Double { 0 } }

enum LogLevel { case basic, debug }
func appLog(_ message: String, level: LogLevel = .basic) {}
func isAppLogEnabled(_ level: LogLevel) -> Bool { false }

struct TestSettings {
    var enabled = true
    var enableAmbiguousCorrection = true
    var undoWindowSeconds = 10.0
}
final class SettingsStore {
    static let shared = SettingsStore()
    var settings = TestSettings()
    func getSettings() -> TestSettings { settings }
}
final class InputSourceController {
    static let shared = InputSourceController()
    var current = "source"
    var switches: [String] = []
    func getCurrentLayoutID() -> String { current }
    func switchLayout(to layout: String) -> Bool { switches.append(layout); current = layout; return true }
}
struct TestRender {
    let text: String
    let consumedAllKeystrokes = true
    let hasPendingDeadKey = false
}
enum KeyStrokeClassification { case text(String), deadKey, nonText }
final class LayoutMapper {
    static let shared = LayoutMapper()
    // Deliberately synthetic layout; tests concern edit lifetimes, not mapping.
    let characters: [UInt16: Character] = [0: "א", 1: "ב", 2: "ג", 3: "ד", 4: "ה", 49: " ", 44: "?", 47: "."]
    func translateKeyCode(_ key: UInt16, modifiers: UInt32, layoutID: String) -> Character? { characters[key] }
    func render(keystrokes: [BufferedKeystroke], layoutID: String) -> TestRender? {
        TestRender(text: String(keystrokes.compactMap { characters[$0.keyCode] }))
    }
    func classifyKeyStroke(_ key: UInt16, modifiers: UInt32, layoutID: String) -> KeyStrokeClassification? {
        characters[key].map { .text(String($0)) } ?? .nonText
    }
    func warmCache(for layout: String) {}
}
final class LanguageDecisionEngine {
    static let shared = LanguageDecisionEngine()
    var decision: LanguageDecision = .rejected
    var snapshots: [CorrectionSnapshot] = []
    var duringEvaluation: (() -> Void)?
    func evaluate(snapshot: CorrectionSnapshot) -> LanguageDecision {
        snapshots.append(snapshot)
        let result = decision
        let action = duringEvaluation
        duringEvaluation = nil
        action?()
        return result
    }
    func effectivePeriodMergeForSnapshot(originalWord: String, boundary: Character, sourceLayoutID: String) -> (originalWord: String, boundaryCharacter: String) {
        (originalWord, String(boundary))
    }
}
struct TestInjection {
    let original: String
    let corrected: String
    let delimiter: String
    let layout: String?
}
final class TextInjector {
    static let shared = TextInjector()
    var injections: [TestInjection] = []
    var succeeds = true
    var holdCompletion = false
    var completion: ((Bool) -> Void)?
    func inject(originalWord: String, correctedWord: String, delimiter: String, layoutToSwitch: String?, completion: @escaping (Bool) -> Void) {
        injections.append(TestInjection(original: originalWord, corrected: correctedWord, delimiter: delimiter, layout: layoutToSwitch))
        if holdCompletion { self.completion = completion; return }
        if succeeds, let layout = layoutToSwitch { _ = InputSourceController.shared.switchLayout(to: layout) }
        completion(succeeds)
    }
}
final class OverrideController {
    static let shared = OverrideController()
    var skipNext = false
    func consumeSkipNextCorrection() -> Bool { let result = skipNext; skipNext = false; return result }
    func armSkipNextCorrection() { skipNext = true }
    func matchesSkipShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool { false }
    func matchesUndoShortcut(keyCode: Int64, flags: CGEventFlags) -> Bool { keyCode == 6 && flags.contains(.maskCommand) }
}
final class AppControlManager {
    static let shared = AppControlManager()
    func currentAppSnapshot() -> (activeAppBundleId: String?, isAuthorized: Bool) { ("test.editor", true) }
}
final class SecureFieldDetector {
    static let shared = SecureFieldDetector()
    var secure = false
    func isSecureFieldFocused() -> Bool { secure }
}
final class GlobalKeyboardMonitor {
    func reenableTapIfNeeded() {}
    func tapEventsReceivedCount() -> Int { 1 }
    func incrementEventCount() {}
}
typealias CGEventTapProxy = Int
final class CGEvent {
    enum Field { case eventSourceUserData, keyboardEventKeycode }
    let key: UInt16
    let flags: CGEventFlags
    let synthetic: Bool
    init(key: UInt16, flags: CGEventFlags = [], synthetic: Bool = false) { self.key = key; self.flags = flags; self.synthetic = synthetic }
    func getIntegerValueField(_ field: Field) -> Int64 {
        switch field {
        case .eventSourceUserData: return synthetic ? AppConfig.magicNumber : 0
        case .keyboardEventKeycode: return Int64(key)
        }
    }
    func keyboardGetUnicodeString(maxStringLength: Int, actualStringLength: UnsafeMutablePointer<Int>, unicodeString: UnsafeMutablePointer<UniChar>) {
        actualStringLength.pointee = 0
    }
}
