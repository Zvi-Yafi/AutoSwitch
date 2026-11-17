var failures = 0
var scenarios = 0
let machine = AutoSwitchStateMachine.shared
let target = CorrectionTarget(inputSourceID: "target", languageCode: "en", supportTier: .fullSupport)
let candidate = CorrectionCandidate(word: "next", target: target, score: 1)
let priorCandidate = CorrectionCandidate(word: "prior", target: target, score: 0.8)
let engine = LanguageDecisionEngine.shared
let injector = TextInjector.shared
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures += 1; print("  FAIL: \(message)") }
}
func run(_ name: String, _ body: () -> Void) {
    scenarios += 1
    for queue in DispatchQueue.all { queue.blocks.removeAll() }
    SettingsStore.shared.settings = TestSettings()
    InputSourceController.shared.current = "source"
    InputSourceController.shared.switches = []
    WordBufferManager.shared.clear()
    WordBufferManager.shared.clearLastInjectedLayout()
    CorrectionHistory.shared.clear()
    engine.decision = .rejected
    engine.snapshots = []
    engine.duringEvaluation = nil
    injector.injections = []
    injector.succeeds = true
    injector.holdCompletion = false
    injector.completion = nil
    OverrideController.shared.skipNext = false
    SecureFieldDetector.shared.secure = false
    machine.appActivated(isAuthorized: true)
    DispatchQueue.settle()
    let before = failures
    body()
    print("\(before == failures ? "PASS" : "FAIL") \(name)")
}
@discardableResult func key(_ code: UInt16, flags: CGEventFlags = [], synthetic: Bool = false) -> Bool {
    let event = CGEvent(key: code, flags: flags, synthetic: synthetic)
    let result = customEventTapCallback(proxy: 0, type: .keyDown, event: event, refcon: nil)
    _ = machine.currentState // drain submitted state work, as a later callback does
    return result != nil
}
func typeWord(_ keys: [UInt16]) { for code in keys { key(code) } }
func complete(_ decision: LanguageDecision) {
    engine.decision = decision
    key(49)
    DispatchQueue.settle()
}
func seedPending() {
    typeWord([0, 1, 2])
    complete(.ambiguous(candidate: priorCandidate))
    expect(machine._pendingAmbiguousForTesting != nil, "Setup must defer the first word")
}
func expectOnlyNext() {
    expect(injector.injections.count == 1, "Exactly one replacement must be issued")
    expect(injector.injections.first?.original == "דה", "Do not delete text belonging to the erased word")
    expect(injector.injections.first?.corrected == "next", "Do not resurrect the erased word's translation")
}

run("Full deletion after boundary discards the deferred word before the next correction") {
    seedPending()
    for _ in 0..<4 { key(51) }
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expectOnlyNext()
}
run("Deleting only the delimiter also invalidates a deferred prefix") {
    seedPending()
    key(51)
    expect(machine._pendingAmbiguousForTesting == nil, "Deletion must invalidate pending source text even with an empty buffer")
}
run("Deleting all of the next buffered word cannot leave a deferred prefix") {
    seedPending()
    typeWord([3, 4])
    key(51); key(51)
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expectOnlyNext()
}
run("A partial Backspace preserves the remaining current-word keystrokes") {
    seedPending()
    typeWord([3, 4])
    key(51)
    expect(WordBufferManager.shared.currentWord == "ד", "Single Backspace removes one tracked keystroke")
    typeWord([4])
    complete(.accepted(candidate: candidate))
    expectOnlyNext()
}
for (name, flags) in [("Option", CGEventFlags.maskAlternate), ("Command", .maskCommand), ("Control", .maskControl)] {
    run("\(name)-Delete drops the whole buffered word and deferred prefix") {
        seedPending()
        typeWord([0, 1, 2])
        key(51, flags: flags)
        expect(WordBufferManager.shared.isEmpty, "Bulk deletion must not retain all but one keystroke")
        typeWord([3, 4])
        complete(.accepted(candidate: candidate))
        expectOnlyNext()
    }
}
run("Forward Delete invalidates buffered and deferred text") {
    seedPending()
    typeWord([0, 1, 2])
    key(117)
    expect(WordBufferManager.shared.isEmpty && machine._pendingAmbiguousForTesting == nil, "Forward deletion invalidates known caret context")
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expectOnlyNext()
}
run("Select-all followed by Delete starts a fresh word") {
    seedPending()
    typeWord([0, 1, 2])
    key(0, flags: .maskCommand)
    key(51)
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expectOnlyNext()
}
run("No deletion retains legitimate deferred two-word correction") {
    seedPending()
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expect(injector.injections.first?.original == "אבג דה", "Keep an untouched adjacent source word")
    expect(injector.injections.first?.corrected == "prior next", "Keep contextual ambiguity resolution")
}
run("Trailing punctuation still preserves a deferred word") {
    seedPending()
    key(44); key(47)
    expect(machine._pendingAmbiguousForTesting?.correctedWord == "prior", "Punctuation alone is not deletion")
}
run("Tagged synthetic Backspace is ignored by the real callback") {
    seedPending()
    key(51, synthetic: true)
    expect(machine._pendingAmbiguousForTesting != nil, "AutoSwitch's own events must not invalidate state")
}
run("Repeated Backspace on an empty buffer remains usable") {
    for _ in 0..<10 { key(51) }
    expect(machine.currentState == .idle && WordBufferManager.shared.isEmpty, "No stuck state or underflow")
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expectOnlyNext()
}

let delayedDecisions: [(String, LanguageDecision)] = [
    ("ambiguous", .ambiguous(candidate: priorCandidate)),
    ("accepted", .accepted(candidate: priorCandidate)),
    ("switch-only", .switchOnly(targetInputSourceID: "target", targetLanguageCode: "en")),
    ("rejected", .rejected),
]
for (name, decision) in delayedDecisions {
    run("Late \(name) evaluation after deletion cannot alter the new word") {
        typeWord([0, 1, 2])
        engine.decision = decision
        key(49)
        engine.duringEvaluation = {
            for _ in 0..<4 { key(51) }
            typeWord([3, 4])
        }
        DispatchQueue.settle()
        expect(machine._pendingAmbiguousForTesting == nil, "A cancelled evaluation must not restore the erased prefix")
        expect(machine.currentState == .buffering && WordBufferManager.shared.currentWord == "דה", "A stale result must not clear the new word")
        expect(injector.injections.isEmpty && InputSourceController.shared.switches.isEmpty, "No stale injection or layout switch")
        complete(.accepted(candidate: candidate))
        expectOnlyNext()
    }
}
for (name, decision) in delayedDecisions.prefix(3) where name != "ambiguous" {
    run("\(name) waiting on the main queue is cancelled by a later deletion") {
        typeWord([0, 1, 2])
        engine.decision = decision
        key(49)
        DispatchQueue.named("com.autoswitch.evaluation").drain()
        DispatchQueue.named("com.autoswitch.state").drain()
        for _ in 0..<4 { key(51) }
        typeWord([3, 4])
        DispatchQueue.main.drain()
        _ = machine.currentState
        expect(injector.injections.isEmpty && InputSourceController.shared.switches.isEmpty, "Cancelled main-queue work must not touch the editor")
        expect(machine.currentState == .buffering && WordBufferManager.shared.currentWord == "דה", "Cancelled main-queue work must leave new buffering intact")
        complete(.accepted(candidate: candidate))
        expectOnlyNext()
    }
}
run("Late ambiguous result cannot rearm correction after navigation") {
    typeWord([0, 1, 2])
    engine.decision = .ambiguous(candidate: priorCandidate)
    key(49)
    engine.duringEvaluation = { key(123) }
    DispatchQueue.settle()
    expect(machine._pendingAmbiguousForTesting == nil, "Navigation cancels in-flight ambiguity")
}
run("Late ambiguous result cannot leave a secure context re-enabled") {
    typeWord([0, 1, 2])
    engine.decision = .ambiguous(candidate: priorCandidate)
    key(49)
    engine.duringEvaluation = { machine.secureFieldDetected(); _ = machine.currentState }
    DispatchQueue.settle()
    expect(machine.currentState == .disabled && machine._pendingAmbiguousForTesting == nil, "Stale ambiguity must not transition a disabled state to idle")
}
run("Ambiguity disabled never leaves a deferred prefix") {
    SettingsStore.shared.settings.enableAmbiguousCorrection = false
    typeWord([0, 1, 2])
    complete(.ambiguous(candidate: priorCandidate))
    expect(machine._pendingAmbiguousForTesting == nil, "Respect ambiguity setting")
}
run("Skip-next discards pending context and does not inject") {
    seedPending()
    OverrideController.shared.armSkipNextCorrection()
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expect(injector.injections.isEmpty && machine._pendingAmbiguousForTesting == nil, "Skip-next applies before evaluation")
}
run("A failed injection does not create undo history and leaves correction usable") {
    injector.succeeds = false
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expect(CorrectionHistory.shared.peekLast() == nil && machine.currentState == .idle, "Failed replacement must not be undoable or stuck")
}
run("Successful correction is still undoable") {
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expect(CorrectionHistory.shared.peekLast() != nil, "Successful injection records history")
    expect(!key(6, flags: .maskCommand), "The handled undo shortcut is consumed")
    DispatchQueue.settle()
    expect(injector.injections.last?.original == "next" && injector.injections.last?.corrected == "דה", "Undo restores the corrected current word")
    expect(machine.currentState == .idle, "Undo completes")
}
run("A real Delete is swallowed while injection is locked") {
    injector.holdCompletion = true
    typeWord([3, 4])
    complete(.accepted(candidate: candidate))
    expect(machine.currentState == .injecting, "Test holds the actual injection state")
    expect(!key(51), "A swallowed edit must not invalidate an ongoing injection")
    injector.completion?(true)
    DispatchQueue.settle()
    expect(machine.currentState == .idle, "Completion releases injection lock")
}
print("Scenarios: \(scenarios); assertion failures: \(failures)")
exit(failures == 0 ? 0 : 1)
