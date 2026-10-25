import Foundation
import Carbon
import Cocoa

class GlobalKeyboardMonitor {
    static let shared = GlobalKeyboardMonitor()
    
    // Reserve a session before starting its thread. An active-only guard leaves
    // a window in which multiple permission/settings notifications create taps.
    private final class Session {
        var tap: CFMachPort?
        var source: CFRunLoopSource?
        var runLoop: CFRunLoop?
        var timer: Timer?
    }

    private let stateQueue = DispatchQueue(label: "com.autoswitch.monitor.state", qos: .userInitiated)
    private var session: Session?
    private var eventsReceivedCount = 0

    private init() {}

    func startMonitoring() {
        let candidate = Session()
        let reserved = stateQueue.sync { () -> Bool in
            guard session == nil else { return false }
            session = candidate
            return true
        }
        guard reserved else { return }

        Thread.detachNewThread { [self] in
            let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: customEventTapCallback,
                userInfo: userInfo
            ) else {
                stateQueue.sync {
                    if session === candidate { session = nil }
                }
                appLog("MONITOR: Tap creation failed; permission supervisor will retry.")
                return
            }

            // A newly created tap must not process keys until its session is
            // published. stopMonitoring may have cancelled it during creation.
            CGEvent.tapEnable(tap: tap, enable: false)
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                CFMachPortInvalidate(tap)
                stateQueue.sync {
                    if session === candidate { session = nil }
                }
                appLog("MONITOR: Run loop source creation failed; will retry.")
                return
            }
            let runLoop = CFRunLoopGetCurrent()!
            let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.reenableTapIfNeeded()
            }
            let installed = stateQueue.sync { () -> Bool in
                guard session === candidate else { return false }
                candidate.tap = tap
                candidate.source = source
                candidate.runLoop = runLoop
                candidate.timer = timer
                eventsReceivedCount = 0
                CFRunLoopAddSource(runLoop, source, .commonModes)
                RunLoop.current.add(timer, forMode: .common)
                CGEvent.tapEnable(tap: tap, enable: true)
                return true
            }
            guard installed else {
                timer.invalidate()
                CFRunLoopSourceInvalidate(source)
                CFMachPortInvalidate(tap)
                return
            }
            appLog("PERMISSIONS: Tap created successfully. Waiting for first keystroke to confirm keyboard monitoring is active...")
            CFRunLoopRun()

            // Cleanup belongs to this session, never to a newer start request.
            stateQueue.sync {
                timer.invalidate()
                CFRunLoopSourceInvalidate(source)
                CFMachPortInvalidate(tap)
                if session === candidate { session = nil }
            }
        }
    }

    func stopMonitoring() {
        stateQueue.sync {
            guard let current = session else { return }
            session = nil
            if let tap = current.tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            if let runLoop = current.runLoop {
                // Queue the stop on the owning loop: it also works if stop is
                // requested just before the worker enters CFRunLoopRun().
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                    current.timer?.invalidate()
                    if let source = current.source { CFRunLoopSourceInvalidate(source) }
                    CFRunLoopStop(runLoop)
                }
                CFRunLoopWakeUp(runLoop)
            }
        }
    }

    func isMonitoringActive() -> Bool {
        stateQueue.sync { session?.tap != nil }
    }

    func tapEventsReceivedCount() -> Int {
        stateQueue.sync { eventsReceivedCount }
    }

    func isTapCurrentlyEnabled() -> Bool {
        stateQueue.sync {
            guard let tap = session?.tap else { return false }
            return CGEvent.tapIsEnabled(tap: tap)
        }
    }

    fileprivate func reenableTapIfNeeded() {
        stateQueue.sync {
            guard let tap = session?.tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
            appLog("MONITOR: Tap was disabled; attempting re-enable.")
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    fileprivate func incrementEventCount() {
        stateQueue.sync { eventsReceivedCount += 1 }
    }
}

private func customEventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    // 1. Check for tap failure timeouts
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        appLog("Tap disabled by OS (\(type.rawValue))")
        // Just let the resilience timer fix it or fix it explicitly here
        if let tapRef = refcon {
            let monitor = Unmanaged<GlobalKeyboardMonitor>.fromOpaque(tapRef).takeUnretainedValue()
            monitor.reenableTapIfNeeded()
        }
        return Unmanaged.passUnretained(event)
    }
    
    // 2. Ignore our own synthetic injections via MAGIC_NUMBER
    let userData = event.getIntegerValueField(.eventSourceUserData)
    if userData == AppConfig.magicNumber {
        return Unmanaged.passUnretained(event)
    }
    
    let stateMachine = AutoSwitchStateMachine.shared
    guard SettingsStore.shared.getSettings().enabled else {
        if type == .keyDown {
            appLog("CALLBACK: Dropping event because AutoSwitch is disabled")
        }
        return Unmanaged.passUnretained(event)
    }

    let appSnapshot = AppControlManager.shared.currentAppSnapshot()
    
    // 3. System must be authorized and not in a secure field
    if stateMachine.currentState == .disabled {
        if type == .keyDown {
            appLog("CALLBACK: Dropping event because state is DISABLED")
        }
        return Unmanaged.passUnretained(event)
    }
    
    // 4. If LOCKED (Injecting), DROP the real event
    if stateMachine.currentState == .injecting {
        return nil // Swallow real keystrokes during injection
    }
    
    if let tapRef = refcon {
        let monitor = Unmanaged<GlobalKeyboardMonitor>.fromOpaque(tapRef).takeUnretainedValue()
        let count = monitor.tapEventsReceivedCount()
        monitor.incrementEventCount()
        if count == 0 {
            appLog("PERMISSIONS: ✓ First keystroke received — keyboard monitoring is ACTIVE and working.")
        }
    }

    if type == .keyDown {
        if SecureFieldDetector.shared.isSecureFieldFocused() {
            stateMachine.secureFieldDetected()
            return Unmanaged.passUnretained(event)
        } else {
            stateMachine.secureFieldCleared(isAuthorized: appSnapshot.isAuthorized)
        }
        
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        if isAppLogEnabled(.debug) {
            appLog("Scanned keycode: \(keycode)", level: .debug)
        }
        let flags = event.flags
        
        if OverrideController.shared.matchesSkipShortcut(keyCode: keycode, flags: flags) {
            OverrideController.shared.armSkipNextCorrection()
            appLog("Override: skip-next armed")
            return nil
        }
        
        if OverrideController.shared.matchesUndoShortcut(keyCode: keycode, flags: flags) {
            if stateMachine.requestUndoRecentCorrection() {
                appLog("Override: undo triggered")
                return nil
            }
        }
        
        // Navigation Checks (Drop state)
        if keycode == 123 || keycode == 124 || keycode == 125 || keycode == 126 || keycode == 115 || keycode == 119 /* Home/End etc */ {
            stateMachine.handleNavigationEvent()
            return Unmanaged.passUnretained(event)
        }
        
        // Backspace
        if keycode == 51 {
            stateMachine.handleBackspace()
            return Unmanaged.passUnretained(event)
        }
        
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            stateMachine.handleNavigationEvent()
            return Unmanaged.passUnretained(event)
        }
        
        let kc = UInt16(keycode)
        var modifiers = UInt32(0)
        if flags.contains(.maskShift) {
            modifiers |= UInt32(shiftKey >> 8)
        }
        if flags.contains(.maskAlternate) {
            modifiers |= UInt32(optionKey >> 8)
        }

        guard let classification = LayoutMapper.shared.classifyKeyStroke(kc, modifiers: modifiers, layoutID: WordBufferManager.shared.effectiveSourceLayoutID) else {
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
            if length > 0, let scalar = UnicodeScalar(chars[0]) {
                let fallbackChar = Character(scalar)
                appLog("DIAG: resolveCharacter nil for kc=\(kc) → fallback='\(fallbackChar)' isBoundary=\(WordBufferManager.shared.isBoundary(fallbackChar))", level: .debug)
                if WordBufferManager.shared.isBoundary(fallbackChar) {
                    stateMachine.handleBoundary(fallbackChar, activeAppId: appSnapshot.activeAppBundleId)
                } else {
                    stateMachine.handleNavigationEvent()
                }
            } else {
                appLog("DIAG: resolveCharacter nil for kc=\(kc) AND fallback empty — ignoring keystroke", level: .debug)
            }
            return Unmanaged.passUnretained(event)
        }

        switch classification {
        case .text(let output):
            if output.count == 1,
               let character = output.first,
               WordBufferManager.shared.isBoundary(character),
               !WordBufferManager.shared.hasPendingDeadKey {
                appLog("DIAG: kc=\(kc) → char='\(character)' isBoundary=true layout=\(WordBufferManager.shared.effectiveSourceLayoutID)", level: .debug)
                stateMachine.handleBoundary(character, activeAppId: appSnapshot.activeAppBundleId)
            } else {
                stateMachine.handleKeystroke(keyCode: kc, modifierFlags: modifiers)
            }
        case .deadKey:
            stateMachine.handleKeystroke(keyCode: kc, modifierFlags: modifiers)
        case .nonText:
            stateMachine.handleNavigationEvent()
        }
    }
    
    return Unmanaged.passUnretained(event)
}
