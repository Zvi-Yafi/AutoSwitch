#!/usr/bin/env python3
"""Exercise production onboarding methods with deterministic, in-memory services.

Does not launch AutoSwitch or invoke real permission, preferences or keyboard APIs.
Extracts source verbatim into a Swift control-flow harness; this is not a SwiftUI
hosting test or a test of whether macOS registers an app in its privacy database.
"""
from pathlib import Path
import hashlib
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / "Sources/UI/PermissionsOnboardingView.swift").read_text()


def block_after(marker):
    """Extract a balanced block; the current source has no braces in literals."""
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth and end < len(source):
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    if depth:
        raise RuntimeError(f"Unbalanced source block: {marker}")
    return source[start:end], source[opening + 1:end - 1]


methods = []
for match in re.finditer(r"    private func (\w+)\(", source):
    methods.append(block_after(match.group())[0])
properties = "\n".join(re.findall(r"^    @State private var .+$", source, re.M))
appear = block_after(".onAppear {")[1]
disappear = block_after(".onDisappear {")[1]
prelude = r'''
import Foundation

// A reference-backed State wrapper preserves the source struct's nonmutating
// state updates. It does not reproduce SwiftUI mounting or identity semantics.
@propertyWrapper struct State<Value> {
    final class Storage { var value: Value; init(_ value: Value) { self.value = value } }
    let storage: Storage
    init(wrappedValue: Value) { storage = Storage(wrappedValue) }
    var wrappedValue: Value {
        get { storage.value }
        nonmutating set { storage.value = newValue }
    }
}
struct PromptOption { func takeUnretainedValue() -> String { "prompt" } }
let kAXTrustedCheckOptionPrompt = PromptOption()
var accessibilityGranted = false
var prompts = 0
var createdTimers = 0
var invalidatedTimers = 0
func AXIsProcessTrustedWithOptions(_ options: NSDictionary) -> Bool {
    if options["prompt"] as? Bool == true { prompts += 1 }
    return accessibilityGranted
}
final class DispatchQueue {
    enum QoS { case userInitiated }
    static let main = DispatchQueue()
    static let worker = DispatchQueue()
    var work: [() -> Void] = []
    static func global(qos: QoS) -> DispatchQueue { worker }
    func async(execute: @escaping () -> Void) { work.append(execute) }
    func asyncAfter(deadline: Double, execute: @escaping () -> Void) { work.append(execute) }
    func drain() { while !work.isEmpty { work.removeFirst()() } }
}
extension Double { static func now() -> Double { 0 } }
final class Timer {
    static func scheduledTimer(withTimeInterval: Double, repeats: Bool, block: @escaping (Timer) -> Void) -> Timer { createdTimers += 1; return Timer() }
    func invalidate() { invalidatedTimers += 1 }
}
'''
production = "\nstruct PermissionsOnboardingView {\n" + properties + "\n"
production += "\n".join(methods)
production += "\nfunc appear() {" + appear + "}\n"
production += "func disappear() {" + disappear + "}\n"
production += "func clickPermission() { requestAccessibilityPermission() }\n"
production += "func poll() { checkPermissions() }\nfunc canContinue() -> Bool { accessibilityGranted }\n}\n"
tests = r'''
var failures = 0
var count = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures += 1; print("  FAIL: \(message)") }
}
func run(_ name: String, _ body: () -> Void) {
    count += 1
    accessibilityGranted = false
    prompts = 0
    createdTimers = 0
    invalidatedTimers = 0
    DispatchQueue.main.work = []
    DispatchQueue.worker.work = []
    let before = failures
    body()
    print("\(before == failures ? "PASS" : "FAIL") \(name)")
}
run("Missing Accessibility blocks completion without prompting at appearance") {
    let view = PermissionsOnboardingView()
    view.appear()
    expect(!view.canContinue(), "Missing access must block completion")
    expect(prompts == 0 && createdTimers == 1, "Observe permission without an automatic prompt")
}
run("Accessibility alone allows completion") {
    accessibilityGranted = true
    let view = PermissionsOnboardingView()
    view.appear()
    expect(view.canContinue() && prompts == 0, "No second permission may block completion")
}
run("User click explicitly requests Accessibility") {
    let view = PermissionsOnboardingView()
    view.clickPermission()
    expect(prompts == 1, "Exactly one explicit Accessibility prompt")
    DispatchQueue.main.drain()
    expect(!view.canContinue(), "An unanswered prompt is not a grant")
}
run("External grant is recognized after requesting") {
    let view = PermissionsOnboardingView()
    view.clickPermission()
    accessibilityGranted = true
    DispatchQueue.main.drain()
    expect(view.canContinue(), "Refresh must recognize the actual grant")
}
run("Polling observes revocation without requesting again") {
    accessibilityGranted = true
    let view = PermissionsOnboardingView()
    view.appear()
    accessibilityGranted = false
    view.poll()
    expect(!view.canContinue() && prompts == 0, "Revocation must remove readiness without prompting")
}
run("Dismissal cancels permission polling") {
    let view = PermissionsOnboardingView()
    view.appear()
    view.disappear()
    expect(invalidatedTimers == 1, "No polling timer after dismissal")
}
print("Scenarios: \(count); assertion failures: \(failures)")
exit(failures == 0 ? 0 : 1)
'''
output = Path(tempfile.mkdtemp(prefix="autoswitch-permissions-policy.", dir="/private/tmp"))
(output / "main.swift").write_text(prelude + production + tests)
print(f"Source SHA-256: {hashlib.sha256(source.encode()).hexdigest()}", flush=True)
print(f"Artifacts: {output}", flush=True)
subprocess.run([
    "xcrun", "swiftc", "-module-cache-path", str(output / "module-cache"),
    str(output / "main.swift"), "-o", str(output / "permissions-policy"),
], check=True)
raise SystemExit(subprocess.run([str(output / "permissions-policy")]).returncode)
