import SwiftUI
import AppKit

@main
struct AutoSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The settings NSWindow below is the sole owner of SettingsView.
        // A Settings scene would create a second, independently managed window.
        MenuBarExtra(AppStrings.appName, systemImage: "keyboard") {
            Text(AppStrings.statusActive)
            Divider()
            Button(AppStrings.menuSettings) {
                appDelegate.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            Divider()
            Button(AppStrings.menuQuit) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .menuBarExtraStyle(.menu)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(AppStrings.menuSettings) {
                    appDelegate.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var permissionTimer: Timer?
    private var heartbeatTimer: Timer?
    private var lastAccessibilityGranted: Bool?
    
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

        // Monitoring follows permission state even if the guide is left open
        // or closed without pressing Continue on a first installation.
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange(_:)), name: .appSettingsDidChange, object: nil)
        refreshMonitoring()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshMonitoring()
        }
        permissionTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        startHeartbeat()

        if shouldShowOnboarding() {
            showOnboarding()
        } else {
            openSettings()
        }

    }

    private func shouldShowOnboarding() -> Bool {
        let settings = SettingsStore.shared.getSettings()
        let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        let accessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)

        if !accessibilityGranted {
            return true
        }

        return !settings.hasCompletedOnboarding
    }
    
    private func showOnboarding() {
        if let window = onboardingWindow {
            bringToFront(window)
            return
        }
        appLog("ONBOARDING: Showing permissions onboarding screen")
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 420),
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
        
        bringToFront(window)
    }
    
    private func completeOnboarding() {
        appLog("ONBOARDING: Completed successfully")
        
        SettingsStore.shared.update { settings in
            settings.hasCompletedOnboarding = true
        }
        
        onboardingWindow?.close()
        onboardingWindow = nil
        
        refreshMonitoring()
        openSettings()
    }

    private func refreshMonitoring() {
        let accessEnabled = AXIsProcessTrusted()
        let permissionChanged = lastAccessibilityGranted != accessEnabled
        if permissionChanged {
            lastAccessibilityGranted = accessEnabled
            appLog("PERMISSIONS: Accessibility=\(accessEnabled ? "GRANTED ✓" : "DENIED ✗")")
            // Restore the current app's state after a permission grant without
            // requiring the user to switch apps or restart AutoSwitch.
            AutoSwitchStateMachine.shared.appActivated(
                isAuthorized: accessEnabled && SettingsStore.shared.getSettings().enabled
                    && AppControlManager.shared.currentAppSnapshot().isAuthorized
            )
        }
        if accessEnabled && SettingsStore.shared.getSettings().enabled {
            // Idempotent while starting as well as while running. Retry a failed
            // creation on the next tick, including during onboarding.
            GlobalKeyboardMonitor.shared.startMonitoring()
        } else {
            GlobalKeyboardMonitor.shared.stopMonitoring()
        }
    }

    @objc private func settingsDidChange(_ notification: Notification) {
        if Thread.isMainThread {
            refreshMonitoring()
        } else {
            DispatchQueue.main.async { [weak self] in self?.refreshMonitoring() }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        refreshMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        heartbeatTimer?.invalidate()
        GlobalKeyboardMonitor.shared.stopMonitoring()
    }

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
            let accessibility = AXIsProcessTrustedWithOptions(axOptions)
            let tapActive = GlobalKeyboardMonitor.shared.isMonitoringActive()
            let tapEnabled = GlobalKeyboardMonitor.shared.isTapCurrentlyEnabled()
            let eventsReceived = GlobalKeyboardMonitor.shared.tapEventsReceivedCount()
            let state = AutoSwitchStateMachine.shared.currentState
            let activeApp = AppControlManager.shared.activeAppBundleId ?? "None"

            appLog("HEARTBEAT: Accessibility=\(accessibility) | TapActive=\(tapActive) | TapEnabled=\(tapEnabled) | EventsReceived=\(eventsReceived) | App=\(activeApp) | State=\(state)")

        }
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
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
        if let window = settingsWindow {
            bringToFront(window)
        }
    }

    private func bringToFront(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if shouldShowOnboarding() {
            showOnboarding()
        } else {
            openSettings()
        }
        // Window selection is handled above instead of the default scene behavior.
        return false
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
