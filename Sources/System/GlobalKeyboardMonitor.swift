import Foundation
import Carbon
import Cocoa

class GlobalKeyboardMonitor {
    static let shared = GlobalKeyboardMonitor()
    
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let stateQueue = DispatchQueue(label: "com.autoswitch.monitor.state", qos: .userInitiated)
    private var isMonitoring = false
    fileprivate var eventsReceivedCount: Int = 0

    private init() {}
    
    func startMonitoring() {
        guard !isMonitoringActive() else { return }

        Thread.detachNewThread { [weak self] in
            guard let self = self else { return }
            
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
                appLog("CRITICAL: Failed to create CGEventTap (Session).")
                self.setMonitoring(false)
                return
            }
            
            self.setMonitoring(true)
            self.eventTap = tap
            self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            
            CFRunLoopAddSource(CFRunLoopGetCurrent(), self.runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            
            appLog("PERMISSIONS: Tap created successfully. Waiting for first keystroke to confirm Input Monitoring is active...")
            self.setupResilienceTimer()
            
            CFRunLoopRun()
        }
    }
    
    func stopMonitoring() {
        guard isMonitoringActive() else { return }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        eventTap = nil
        runLoopSource = nil
        setMonitoring(false)
    }
    
    func isMonitoringActive() -> Bool {
        stateQueue.sync { isMonitoring }
    }

    func tapEventsReceivedCount() -> Int {
        stateQueue.sync { eventsReceivedCount }
    }

    func isTapCurrentlyEnabled() -> Bool {
        guard let tap = eventTap else { return false }
        return CGEvent.tapIsEnabled(tap: tap)
    }
    
    private func setupResilienceTimer() {
        // Run on main queue just to monitor the tap's alive state
        DispatchQueue.main.async {
            Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self = self, self.isMonitoringActive(), let tap = self.eventTap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) {
                    appLog("Tap was disabled. Attempting re-enable...")
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        }
    }
    
    private func setMonitoring(_ value: Bool) {
        stateQueue.sync {
            isMonitoring = value
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
            if let tap = monitor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                appLog("Attempted to re-enable tap")
            }
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
            appLog("PERMISSIONS: ✓ First keystroke received — Input Monitoring is ACTIVE and working.")
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
