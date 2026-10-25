#!/usr/bin/env python3
"""Exercise production monitor lifecycle with real threads/run loops and fake taps.

No macOS permissions, keyboard capture, or application launch. The monitor class
and permission-refresh method are extracted verbatim. --baseline reproduces the
old duplicate-start bug using the supplied pre-fix monitor file.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', type=Path)
args = parser.parse_args()
source_path = args.baseline or root / 'Sources/System/GlobalKeyboardMonitor.swift'
source = source_path.read_text()
monitor = source[source.index('class GlobalKeyboardMonitor {'):source.index('\nprivate func customEventTapCallback')]
prelude = r'''
import Foundation
import CoreFoundation

final class FakePort { var enabled = false; var valid = true }
typealias CFMachPort = FakePort
typealias CGEventMask = UInt64
enum CGEventType: UInt32 { case keyDown = 10, flagsChanged = 12 }
enum TapLocation { case cgSessionEventTap }
enum TapPlacement { case headInsertEventTap }
enum TapOptions { case defaultTap }
let lock = NSLock()
var attempts = 0
var ports: [FakePort] = []
var creationGate: DispatchSemaphore?
var failCreation = false
var failSource = false
func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
enum CGEvent {
    static func tapCreate(tap: TapLocation, place: TapPlacement, options: TapOptions,
                          eventsOfInterest: CGEventMask, callback: () -> Void,
                          userInfo: UnsafeMutableRawPointer) -> FakePort? {
        let request = locked { () -> (DispatchSemaphore?, Bool) in
            attempts += 1
            return (creationGate, failCreation)
        }
        if let gate = request.0 { _ = gate.wait(timeout: .now() + 5) }
        if request.1 { return nil }
        return locked { let port = FakePort(); ports.append(port); return port }
    }
    static func tapEnable(tap: FakePort, enable: Bool) { locked { tap.enabled = enable && tap.valid } }
    static func tapIsEnabled(tap: FakePort) -> Bool { locked { tap.enabled && tap.valid } }
}
func CFMachPortInvalidate(_ tap: FakePort) { locked { tap.valid = false; tap.enabled = false } }
func CFMachPortCreateRunLoopSource(_ allocator: CFAllocator?, _ tap: FakePort, _ order: CFIndex) -> CFRunLoopSource? {
    if locked({ failSource }) { return nil }
    var context = CFRunLoopSourceContext(version: 0, info: nil, retain: nil, release: nil,
        copyDescription: nil, equal: nil, hash: nil, schedule: nil, cancel: nil, perform: { _ in })
    return CFRunLoopSourceCreate(allocator, order, &context)
}
func customEventTapCallback() {}
func appLog(_ message: String) {}
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); exit(1) }
}
func eventually(_ message: String, _ condition: () -> Bool) {
    let end = Date().addingTimeInterval(3)
    while !condition() && Date() < end { Thread.sleep(forTimeInterval: 0.005) }
    expect(condition(), message)
}
let monitor = GlobalKeyboardMonitor.shared
'''
# A blocked tap factory deterministically exposes the gap in the old guard;
# this does not rely on a lucky scheduling race or on timing of log writes.
baseline = r'''
let gate = DispatchSemaphore(value: 0)
locked { creationGate = gate }
monitor.startMonitoring()
eventually("First creation entered") { locked { attempts == 1 } }
monitor.startMonitoring()
eventually("Baseline reproduced two simultaneous tap creations") { locked { attempts == 2 } }
print("REPRODUCED: two start calls create two taps before either start finishes")
exit(0)
'''
tests = r'''
let gate = DispatchSemaphore(value: 0)
locked { creationGate = gate }
monitor.startMonitoring()
eventually("First creation entered") { locked { attempts == 1 } }
DispatchQueue.concurrentPerform(iterations: 100) { _ in monitor.startMonitoring() }
expect(locked { attempts == 1 }, "Concurrent starts must share one pending session")
locked { creationGate = nil }
gate.signal()
eventually("One active monitor") { monitor.isMonitoringActive() && monitor.isTapCurrentlyEnabled() }
expect(locked { ports.filter { $0.valid && $0.enabled }.count == 1 }, "Only one enabled tap")
print("PASS: 101 concurrent/repeated starts create one tap")
monitor.stopMonitoring()
eventually("All taps invalidated") { locked { ports.allSatisfy { !$0.valid } } }

let cancellationGate = DispatchSemaphore(value: 0)
locked { creationGate = cancellationGate }
monitor.startMonitoring()
eventually("Pending start") { locked { attempts == 2 } }
monitor.stopMonitoring()
locked { creationGate = nil }
monitor.startMonitoring()
eventually("New session after cancellation") { locked { attempts == 3 } && monitor.isMonitoringActive() }
cancellationGate.signal()
eventually("Cancelled tap cleaned up") { locked { ports.count == 3 && ports.filter { $0.valid }.count == 1 } }
expect(monitor.isTapCurrentlyEnabled(), "Old worker must not disable new session")
print("PASS: stop during creation cancels stale tap and preserves restart")
monitor.stopMonitoring()

locked { failCreation = true }
monitor.startMonitoring()
eventually("Failed creation attempted") { locked { attempts == 4 } }
locked { failCreation = false }
eventually("Creation failure permits retry") {
    monitor.startMonitoring()
    return monitor.isMonitoringActive()
}
expect(monitor.isTapCurrentlyEnabled(), "Retry enables tap")
print("PASS: creation failure can recover on a later request")
monitor.stopMonitoring()

locked { failSource = true }
let beforeSourceFailure = locked { attempts }
monitor.startMonitoring()
eventually("Failed source tap invalidated") {
    locked { attempts > beforeSourceFailure && ports.allSatisfy { !$0.valid } }
}
locked { failSource = false }
eventually("Source failure permits retry") {
    monitor.startMonitoring()
    return monitor.isMonitoringActive()
}
print("PASS: run-loop source failure releases reservation")
monitor.stopMonitoring()

for _ in 0..<20 {
    monitor.startMonitoring()
    eventually("Restart active") { monitor.isMonitoringActive() }
    monitor.stopMonitoring()
}
eventually("No tap leaked after repeated restarts") { locked { ports.allSatisfy { !$0.valid } } }
print("PASS: repeated start/stop leaves no live taps")
'''
# Exercise the permission policy independently of macOS's TCC database.
app = (root / 'AutoSwitchApp.swift').read_text()
start = app.index('    private func refreshMonitoring()')
end = app.index('\n    @objc private func settingsDidChange', start)
policy = r'''
var accessGranted = false
func AXIsProcessTrusted() -> Bool { accessGranted }
struct TestSettings { var enabled = true }
final class SettingsStore {
    static let shared = SettingsStore()
    var settings = TestSettings()
    func getSettings() -> TestSettings { settings }
}
final class AutoSwitchStateMachine {
    static let shared = AutoSwitchStateMachine()
    var updates: [Bool] = []
    func appActivated(isAuthorized: Bool) { updates.append(isAuthorized) }
}
struct AppSnapshot { var isAuthorized = true }
final class AppControlManager {
    static let shared = AppControlManager()
    var snapshot = AppSnapshot()
    func currentAppSnapshot() -> AppSnapshot { snapshot }
}
final class PermissionSupervisor {
    private var lastAccessibilityGranted: Bool?
    func tick() { refreshMonitoring() }
'''+app[start:end]+r'''
}
let supervisor = PermissionSupervisor()
supervisor.tick()
expect(!monitor.isMonitoringActive(), "No monitor without permission")
accessGranted = true
supervisor.tick()
eventually("Grant starts monitoring without onboarding completion") { monitor.isMonitoringActive() }
let stateUpdates = AutoSwitchStateMachine.shared.updates.count
supervisor.tick()
expect(AutoSwitchStateMachine.shared.updates.count == stateUpdates, "Polling must not reset a word in progress")
accessGranted = false
supervisor.tick()
expect(!monitor.isMonitoringActive(), "Revocation stops capture")
expect(AutoSwitchStateMachine.shared.updates.last == false, "Revocation disables correction state")
accessGranted = true
supervisor.tick()
eventually("Regrant restores capture") { monitor.isMonitoringActive() }
expect(AutoSwitchStateMachine.shared.updates.last == true, "Regrant restores current application")
SettingsStore.shared.settings.enabled = false
supervisor.tick()
expect(!monitor.isMonitoringActive(), "User disable stops capture")
supervisor.tick()
expect(!monitor.isMonitoringActive(), "Polling respects user disable")
print("PASS: grant/revoke/regrant/disable policy without onboarding completion")
'''
out = Path(tempfile.mkdtemp(prefix='autoswitch-startup-regression.', dir='/private/tmp'))
(out/'main.swift').write_text(prelude+monitor+(baseline if args.baseline else tests+policy))
print(f'Artifacts: {out}', flush=True)
subprocess.run(['xcrun','swiftc','-module-cache-path',str(out/'module-cache'),str(out/'main.swift'),'-o',str(out/'regression')],check=True)
raise SystemExit(subprocess.run([str(out/'regression')]).returncode)
