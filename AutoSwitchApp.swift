import SwiftUI
import AppKit
import IOKit.hid

@main
struct AutoSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        appLog("--- STARTING AUTOSWITCH ---")

        _ = SettingsStore.shared
        _ = AppControlManager.shared
        _ = SecureFieldDetector.shared
        _ = WordBufferManager.shared
        _ = LanguageDecisionEngine.shared

        let installedLayouts = InputSourceController.shared.listInstalledInputSources()
        for layout in installedLayouts {
            LayoutMapper.shared.warmCache(for: layout.id)
        }

        if shouldShowOnboarding() {
            showOnboarding()
        } else {
            logPermissionsStatus(prompt: true)
            startHeartbeat()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange(_:)), name: .appSettingsDidChange, object: nil)
        setupMenu()
    }

    private func inputMonitoringStatus() -> String {
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        switch access {
        case kIOHIDAccessTypeGranted: return "GRANTED ✓"
        case kIOHIDAccessTypeDenied:  return "DENIED ✗ — go to System Settings → Privacy & Security → Input Monitoring → enable AutoSwitch"
        default:                      return "NOT_DETERMINED — requesting prompt now"
        }
    }

    private func shouldShowOnboarding() -> Bool {
        let settings = SettingsStore.shared.getSettings()
        let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
        let imAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        let inputMonitoringGranted = (imAccess == kIOHIDAccessTypeGranted)

        if !accessibilityGranted || !inputMonitoringGranted {
            return true
        }

        return !settings.hasCompletedOnboarding
    }
    
    private func showOnboarding() {
        appLog("ONBOARDING: Showing permissions onboarding screen")
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = AppStrings.appName
        window.contentView = NSHostingView(rootView: PermissionsOnboardingView(onComplete: { [weak self] in
            self?.completeOnboarding()
        }))
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        onboardingWindow = window
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func completeOnboarding() {
        appLog("ONBOARDING: Completed successfully")
        
        SettingsStore.shared.update { settings in
            settings.hasCompletedOnboarding = true
        }
        
        onboardingWindow?.close()
        onboardingWindow = nil
        
        logPermissionsStatus(prompt: false)
        startHeartbeat()
    }

    private func logPermissionsStatus(prompt: Bool) {
        let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        let accessEnabled = AXIsProcessTrustedWithOptions(axOptions)

        let imStatus = inputMonitoringStatus()
        let imAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)

        appLog("PERMISSIONS: Accessibility=\(accessEnabled ? "GRANTED ✓" : "DENIED ✗") | InputMonitoring=\(imStatus)")

        if imAccess != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }

        if accessEnabled && SettingsStore.shared.getSettings().enabled {
            if !GlobalKeyboardMonitor.shared.isMonitoringActive() {
                GlobalKeyboardMonitor.shared.startMonitoring()
            }
        } else if !accessEnabled {
            appLog("CRITICAL: Accessibility not granted — corrections will not work until granted.")
        }
    }

    @objc private func settingsDidChange(_ notification: Notification) {
        guard let settings = notification.userInfo?["settings"] as? AppSettings else {
            return
        }

        if settings.enabled {
            logPermissionsStatus(prompt: false)
        } else {
            appLog("SETTINGS: AutoSwitch disabled — stopping monitor.")
            GlobalKeyboardMonitor.shared.stopMonitoring()
            AutoSwitchStateMachine.shared.appActivated(isAuthorized: false)
        }
    }
    
    private func startHeartbeat() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            let accessibility = AXIsProcessTrustedWithOptions(axOptions)
            let imAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
            let inputMonitoring: String
            switch imAccess {
            case kIOHIDAccessTypeGranted: inputMonitoring = "GRANTED"
            case kIOHIDAccessTypeDenied:  inputMonitoring = "DENIED"
            default:                      inputMonitoring = "NOT_DETERMINED"
            }
            let tapActive = GlobalKeyboardMonitor.shared.isMonitoringActive()
            let tapEnabled = GlobalKeyboardMonitor.shared.isTapCurrentlyEnabled()
            let eventsReceived = GlobalKeyboardMonitor.shared.tapEventsReceivedCount()
            let state = AutoSwitchStateMachine.shared.currentState
            let activeApp = AppControlManager.shared.activeAppBundleId ?? "None"

            appLog("HEARTBEAT: Accessibility=\(accessibility) | InputMonitoring=\(inputMonitoring) | TapActive=\(tapActive) | TapEnabled=\(tapEnabled) | EventsReceived=\(eventsReceived) | App=\(activeApp) | State=\(state)")

            if accessibility && SettingsStore.shared.getSettings().enabled && !tapActive {
                appLog("HEARTBEAT: Monitor not active — restarting now.")
                GlobalKeyboardMonitor.shared.startMonitoring()
            }

            if tapActive && imAccess == kIOHIDAccessTypeDenied {
                appLog("HEARTBEAT: WARNING — Tap is running but Input Monitoring is DENIED. Go to System Settings → Privacy & Security → Input Monitoring → enable AutoSwitch, then restart.")
            }
        }
    }
    
    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: AppStrings.appName)
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: AppStrings.statusActive, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: AppStrings.menuSettings, action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: AppStrings.menuQuit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 520),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = AppStrings.settingsWindowTitle
            window.contentView = NSHostingView(rootView: SettingsView())
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow {
            settingsWindow = nil
        } else if (notification.object as? NSWindow) === onboardingWindow {
            onboardingWindow = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
