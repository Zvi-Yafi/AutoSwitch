import Foundation

enum AppStrings {
    static var appName: String { localized("app.name") }
    static var settingsWindowTitle: String { localized("settings.window.title") }
    static var settingsTitle: String { localized("settings.title") }
    static var enableAutoSwitch: String { localized("settings.enableAutoSwitch") }
    static var correctionMode: String { localized("settings.correctionMode") }
    static var correctionModeAutomatic: String { localized("settings.correctionMode.automatic") }
    static var correctionModePreferSpecificTarget: String { localized("settings.correctionMode.preferSpecificTarget") }
    static var preferredTargetInputSource: String { localized("settings.preferredTargetInputSource") }
    static var noEnabledTargets: String { localized("settings.noEnabledTargets") }
    static var enableBestEffortTargets: String { localized("settings.enableBestEffortTargets") }
    static var installedInputSources: String { localized("settings.installedInputSources") }
    static var enableAmbiguousCorrection: String { localized("settings.enableAmbiguousCorrection") }
    static var enableAbbreviationPriority: String { localized("settings.enableAbbreviationPriority") }
    static var undoWindowSeconds: String { localized("settings.undoWindowSeconds") }
    static var undoHotkey: String { localized("settings.undoHotkey") }
    static var skipNextHotkey: String { localized("settings.skipNextHotkey") }
    static var whitelistedApps: String { localized("settings.whitelistedApps") }
    static var blacklistedApps: String { localized("settings.blacklistedApps") }
    static var ignoredWords: String { localized("settings.ignoredWords") }
    static var abbreviationExceptions: String { localized("settings.abbreviationExceptions") }
    static var logLevel: String { localized("settings.logLevel") }
    static var logLevelOff: String { localized("settings.logLevel.off") }
    static var logLevelBasic: String { localized("settings.logLevel.basic") }
    static var logLevelDebug: String { localized("settings.logLevel.debug") }
    static var enableLogExport: String { localized("settings.enableLogExport") }
    static var exportSettingsJSON: String { localized("settings.exportSettingsJSON") }
    static var refreshExport: String { localized("settings.refreshExport") }
    static var importSettingsJSON: String { localized("settings.importSettingsJSON") }
    static var importSettings: String { localized("settings.importSettings") }
    static var requiredEntitlements: String { localized("settings.requiredEntitlements") }
    static var addBundleID: String { localized("settings.addBundleId") }
    static var addIgnoredWord: String { localized("settings.addIgnoredWord") }
    static var addAbbreviationException: String { localized("settings.addAbbreviationException") }
    static var addAction: String { localized("common.add") }
    static var statusActive: String { localized("status.active") }
    static var menuSettings: String { localized("menu.settings") }
    static var menuQuit: String { localized("menu.quit") }
    static var permissionAccessibility: String { localized("permissions.accessibility") }
    static var permissionInputMonitoring: String { localized("permissions.inputMonitoring") }
    static var tabGeneral: String { localized("tab.general") }
    static var tabLanguages: String { localized("tab.languages") }
    static var tabBehavior: String { localized("tab.behavior") }
    static var tabApps: String { localized("tab.apps") }
    static var tabWords: String { localized("tab.words") }
    static var tabAdvanced: String { localized("tab.advanced") }
    static var tabAppsAndWords: String { localized("tab.appsAndWords") }
    static var statusEnabled: String { localized("settings.status.enabled") }
    static var statusDisabled: String { localized("settings.status.disabled") }
    static var statusMissingAccessibilityPermission: String { localized("settings.status.missingAccessibilityPermission") }
    static var statusMissingInputMonitoringPermission: String { localized("settings.status.missingInputMonitoringPermission") }
    static var statusMissingRequiredPermissions: String { localized("settings.status.missingRequiredPermissions") }
    static var settingsCorrectionSection: String { localized("settings.section.correction") }
    static var settingsShortcutsSection: String { localized("settings.section.shortcuts") }
    static var sectionLanguages: String { localized("settings.section.languages") }
    static var sectionLogging: String { localized("settings.section.logging") }
    static var alwaysActiveApps: String { localized("settings.alwaysActiveApps") }
    static var alwaysActiveAppsSubtitle: String { localized("settings.alwaysActiveApps.subtitle") }
    static var neverActiveApps: String { localized("settings.neverActiveApps") }
    static var neverActiveAppsSubtitle: String { localized("settings.neverActiveApps.subtitle") }
    static var ignoredWordsSubtitle: String { localized("settings.ignoredWords.subtitle") }
    static var abbreviationExceptionsSubtitle: String { localized("settings.abbreviationExceptions.subtitle") }
    static var enableAmbiguousCorrectionSubtitle: String { localized("settings.enableAmbiguousCorrection.subtitle") }
    static var enableAbbreviationPrioritySubtitle: String { localized("settings.enableAbbreviationPriority.subtitle") }
    static var enableBestEffortTargetsSubtitle: String { localized("settings.enableBestEffortTargets.subtitle") }
    static var undoWindowSubtitle: String { localized("settings.undoWindowSeconds.subtitle") }
    static var bundleIdHint: String { localized("settings.addBundleId.hint") }
    static var exportImportDisclosure: String { localized("settings.exportImport.disclosure") }
    static var onboardingTitle: String { localized("onboarding.title") }
    static var onboardingDescription: String { localized("onboarding.description") }
    static var onboardingAccessibilityTitle: String { localized("onboarding.accessibility.title") }
    static var onboardingAccessibilityDesc: String { localized("onboarding.accessibility.description") }
    static var onboardingInputMonitoringTitle: String { localized("onboarding.inputMonitoring.title") }
    static var onboardingInputMonitoringDesc: String { localized("onboarding.inputMonitoring.description") }
    static var onboardingRequestPermission: String { localized("onboarding.requestPermission") }
    static var onboardingContinue: String { localized("onboarding.continue") }
    static var onboardingWaiting: String { localized("onboarding.waiting") }

    static func supportTier(_ supportTier: InputSourceSupportTier) -> String {
        switch supportTier {
        case .fullSupport:
            return localized("supportTier.fullSupport")
        case .bestEffort:
            return localized("supportTier.bestEffort")
        case .unsupported:
            return localized("supportTier.unsupported")
        }
    }

    private static func localized(_ key: String) -> String {
        resourceBundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static let resourceBundle: Bundle = {
        if let url = Bundle.main.url(forResource: "AutoSwitch_AutoSwitch", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.main
    }()
}
