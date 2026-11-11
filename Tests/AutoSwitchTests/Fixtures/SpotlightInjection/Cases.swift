var cases = 0
var failures = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures += 1; print("  FAIL: \(message)") }
}
func run(_ name: String, _ body: () -> Void) {
    cases += 1
    scenario = Scenario()
    let previousFailures = failures
    body()
    print("\(previousFailures == failures ? "PASS" : "FAIL") \(name)")
}
@discardableResult
func inject(_ original: String = "אבגד", replacement: String = "demo", delimiter: String = " ") -> Bool {
    var completed: Bool?
    TextInjector.shared.inject(originalWord: original, correctedWord: replacement,
        delimiter: delimiter, layoutToSwitch: "fixture.English") { completed = $0 }
    expect(completed != nil, "Completion must be delivered")
    return completed ?? false
}
func expectCancelled() {
    expect(!inject(), "Stale or unsafe context must cancel")
    expect(scenario.events.isEmpty, "Cancellation must not post keyboard events")
    expect(scenario.layouts.isEmpty, "Cancellation must not switch layout")
}

run("Plain word and trailing space are replaced together") {
    expect(inject(), "Injection should complete")
    expect(scenario.value == "demo ", "No source character may remain")
    expect(scenario.events == ["demo "], "One replacement, no Backspace")
}
run("Selected inline completion is removed with the source") {
    scenario.value = "אבגד suggestion"
    scenario.selection = CFRange(location: 5, length: 10)
    inject()
    expect(scenario.value == "demo ", "Completion and source must both be replaced")
}
run("Space consumed by search is restored exactly once") {
    scenario.value = "אבגד"
    scenario.selection = CFRange(location: 4, length: 0)
    inject()
    expect(scenario.value == "demo ", "Space must be restored")
}
run("Completion after source with consumed space") {
    scenario.value = "אבגדsuffix"
    scenario.selection = CFRange(location: 4, length: 6)
    inject()
    expect(scenario.value == "demo ", "Selected completion must not remain")
}
run("Emoji and earlier query stay intact using UTF-16 offsets") {
    scenario.value = "🔎 קודם אבגד "
    scenario.selection = CFRange(location: scenario.value.utf16.count, length: 0)
    inject()
    expect(scenario.value == "🔎 קודם demo ", "Earlier query must be preserved")
}
run("A following unselected suffix stays intact") {
    scenario.value = "אבגד next"
    scenario.selection = CFRange(location: 5, length: 0)
    inject()
    expect(scenario.value == "demo next", "Unselected following text must be preserved")
}
run("Combined pending words are replaced as a full span") {
    scenario.value = "אבגד אבגד "
    scenario.selection = CFRange(location: 10, length: 0)
    inject("אבגד אבגד", replacement: "demo demo")
    expect(scenario.value == "demo demo ", "Both source words must be replaced")
}
run("Undo uses the same exact-range path") {
    scenario.value = "demo "
    inject("demo", replacement: "אבגד")
    expect(scenario.value == "אבגד ", "Undo must restore the original source")
}
run("Non-Spotlight keeps the existing keyboard path") {
    scenario.bundleID = "fixture.editor"
    inject()
    expect(scenario.writes == 0, "Do not set AX ranges outside Spotlight")
    expect(scenario.events.filter { $0 == "DELETE" }.count == 5, "Delete original and delimiter")
    expect(scenario.value == "demo ", "Fallback should replace the source")
}
run("Missing Accessibility range keeps the documented fallback") {
    scenario.missingRange = true
    inject()
    expect(scenario.value == "demo ", "Fallback should replace the source")
    expect(scenario.writes == 0, "No AX range write")
}
run("Nonwritable range keeps the documented fallback") {
    scenario.settable = false
    inject()
    expect(scenario.value == "demo ", "Fallback should replace the source")
}
run("Nonmatching original cancels without deleting other text") {
    scenario.value = "other"
    expectCancelled()
}
run("Invalid negative range cancels") {
    scenario.selection.location = -1
    expectCancelled()
}
run("Out-of-bounds range cancels") {
    scenario.selection.length = 100
    expectCancelled()
}
run("Nontrailing selection cancels") {
    scenario.value = "אבגד other"
    scenario.selection = CFRange(location: 5, length: 2)
    expectCancelled()
}
run("Focus change before selecting cancels") {
    scenario.focusOnRead = 6
    expectCancelled()
}
run("Value change before selecting cancels") {
    scenario.changeValueOnRead = 7
    expectCancelled()
}
run("Selection change before selecting cancels") {
    scenario.changeSelectionOnRead = 8
    expectCancelled()
}
run("AX write timeout does not fall back to destructive deletes") {
    scenario.writeError = .cannotComplete
    expectCancelled()
}
run("Successful AX response without applying selection cancels") {
    scenario.ignoreWrite = true
    expectCancelled()
}
run("Focus change during AX selection write must not type into another app") {
    scenario.focusOnWrite = true
    expectCancelled()
    expect(!scenario.recipients.contains(otherElement), "No events may reach another field")
}
run("Focus change while an AX range read fails must not trigger blind fallback") {
    scenario.missingRange = true
    scenario.focusOnRead = 5
    expectCancelled()
    expect(!scenario.recipients.contains(otherElement), "No events may reach another field")
}
run("Spotlight hosted by Siri uses exact selection on macOS 27") {
    scenario.bundleID = "com.apple.campo"
    scenario.value = "אבגד suggestion"
    scenario.selection = CFRange(location: 5, length: 10)
    inject()
    expect(scenario.writes == 1, "The observed SpotlightSearchField must use exact selection")
    expect(scenario.events == ["demo "], "No blind Backspace in the verified search field")
    expect(scenario.value == "demo ", "Source and completion must both be replaced")
}
run("Unrelated Siri field does not use Spotlight-specific replacement") {
    scenario.bundleID = "com.apple.campo"
    scenario.identifier = "ConversationInput"
    inject()
    expect(scenario.writes == 0, "Do not extend Spotlight behavior to Siri conversation fields")
    expect(scenario.value == "demo ", "Normal keyboard fallback remains available")
}
run("Focus loss between fallback deletes stops the remaining sequence") {
    scenario.bundleID = "fixture.editor"
    scenario.focusAfterEvent = 1
    expect(!inject(), "Sequence must cancel after focus loss")
    expect(scenario.events == ["DELETE"], "Stop before the second deletion")
    expect(!scenario.recipients.contains(otherElement), "No events in the new field")
    expect(scenario.layouts.isEmpty, "Do not switch layout after cancellation")
}
run("Focus loss while waiting for main queue prevents layout switch") {
    scenario.focusOnMainDispatch = true
    expect(!inject(), "Sequence must report cancellation")
    expect(scenario.events == ["demo "], "Text may already have reached the original field")
    expect(scenario.layouts.isEmpty, "Do not switch layout for a different field")
}
run("Unidentifiable focus cancels before any keyboard event") {
    scenario.missingFocus = true
    expectCancelled()
}
print("RESULT: \(cases) cases, \(failures) failed assertions")
exit(failures == 0 ? 0 : 1)
