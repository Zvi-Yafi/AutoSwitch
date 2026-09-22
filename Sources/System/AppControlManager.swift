import Foundation
import Cocoa

class AppControlManager {
    static let shared = AppControlManager()
    private var isApplyingSettingsUpdate = false
    private let appStateQueue = DispatchQueue(label: "com.autoswitch.appcontrol.state", qos: .userInitiated)
    
    var whitelistedBundleIds: Set<String> = [] {
        didSet {
            if isApplyingSettingsUpdate {
                return
            }
            SettingsStore.shared.update { settings in
                settings.whitelistedBundleIds = Array(self.whitelistedBundleIds).sorted()
            }
            evaluateCurrentApp()
        }
    }
    
    var blacklistedBundleIds: Set<String> = [] {
        didSet {
            if isApplyingSettingsUpdate {
                return
            }
            SettingsStore.shared.update { settings in
                settings.blacklistedBundleIds = Array(self.blacklistedBundleIds).sorted()
            }
            evaluateCurrentApp()
        }
    }
    
    // Fast path cached status
    private var _isCurrentAppAuthorized: Bool = true
    private var _activeAppBundleId: String?

    var isCurrentAppAuthorized: Bool {
        appStateQueue.sync { _isCurrentAppAuthorized }
    }

    var activeAppBundleId: String? {
        appStateQueue.sync { _activeAppBundleId }
    }
    
    private init() {
        loadFromSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(settingsDidChange(_:)), name: .appSettingsDidChange, object: nil)
        startObserving()
    }
    
    private func startObserving() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        
        evaluateCurrentApp()
    }
    
    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        evaluateApp(app)
    }
    
    @objc private func settingsDidChange(_ notification: Notification) {
        guard let settings = notification.userInfo?["settings"] as? AppSettings else {
            return
        }
        isApplyingSettingsUpdate = true
        whitelistedBundleIds = Set(settings.whitelistedBundleIds)
        blacklistedBundleIds = Set(settings.blacklistedBundleIds)
        isApplyingSettingsUpdate = false
        evaluateCurrentApp()
    }

    func currentAppSnapshot() -> (isAuthorized: Bool, activeAppBundleId: String?) {
        appStateQueue.sync {
            (_isCurrentAppAuthorized, _activeAppBundleId)
        }
    }
    
    private func evaluateApp(_ app: NSRunningApplication) {
        guard let bundleId = app.bundleIdentifier else {
            appLog("AppControl: App has no bundle ID, disabling")
            setCurrentAppState(isAuthorized: false, activeBundleId: nil)
            AutoSwitchStateMachine.shared.appActivated(isAuthorized: false)
            return
        }

        guard SettingsStore.shared.getSettings().enabled else {
            appLog("AppControl: AutoSwitch disabled in settings")
            setCurrentAppState(isAuthorized: false, activeBundleId: bundleId)
            AutoSwitchStateMachine.shared.appActivated(isAuthorized: false)
            return
        }
        
        appLog("AppControl: App activated - \(bundleId)")
        // Check mandatory blacklist (e.g. password managers)
        let isBlacklisted = SecureFieldDetector.shared.isAppBlacklisted(bundleId) || blacklistedBundleIds.contains(bundleId)
        let isAuthorized: Bool

        if isBlacklisted {
            appLog("AppControl: App is BLACKLISTED - \(bundleId)")
            isAuthorized = false
        } else {
            // Check whitelist
            isAuthorized = whitelistedBundleIds.isEmpty ? true : whitelistedBundleIds.contains(bundleId)
            appLog("AppControl: App authorized check: \(isAuthorized)")
        }

        setCurrentAppState(isAuthorized: isAuthorized, activeBundleId: bundleId)
        AutoSwitchStateMachine.shared.appActivated(isAuthorized: isAuthorized)
    }
    
    private func evaluateCurrentApp() {
        performOnMainThread {
            if let currentApp = NSWorkspace.shared.frontmostApplication {
                evaluateApp(currentApp)
            }
        }
    }
    
    private func loadFromSettings() {
        let settings = SettingsStore.shared.getSettings()
        isApplyingSettingsUpdate = true
        whitelistedBundleIds = Set(settings.whitelistedBundleIds)
        blacklistedBundleIds = Set(settings.blacklistedBundleIds)
        isApplyingSettingsUpdate = false
    }
    
    private func performOnMainThread(_ block: () -> Void) {
        if Thread.isMainThread {
            block()
            return
        }
        DispatchQueue.main.sync(execute: block)
    }

    private func setCurrentAppState(isAuthorized: Bool, activeBundleId: String?) {
        appStateQueue.sync {
            _isCurrentAppAuthorized = isAuthorized
            _activeAppBundleId = activeBundleId
        }
    }
}
