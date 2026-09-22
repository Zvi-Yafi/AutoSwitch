import SwiftUI
import Carbon
import ApplicationServices
import IOKit.hid

private struct SectionLabel: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(title)
                .fontWeight(.semibold)
        }
    }
}

private struct SettingToggleRow: View {
    let label: String
    let subtitle: String
    let isOn: Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(label, isOn: isOn)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @State private var whitelistInput: String = ""
    @State private var blacklistInput: String = ""
    @State private var ignoredWordInput: String = ""
    @State private var abbreviationExceptionInput: String = ""
    @State private var currentWhitelist: [String] = []
    @State private var currentBlacklist: [String] = []
    @State private var ignoredWords: [String] = []
    @State private var abbreviationExceptions: [String] = []
    @State private var installedInputSources: [InstalledInputSource] = []
    @State private var isEnabled: Bool = true
    @State private var correctionPreferenceMode: CorrectionPreferenceMode = .automatic
    @State private var preferredTargetInputSourceID: String = ""
    @State private var enabledTargetInputSourceIDs: Set<String> = []
    @State private var enableBestEffortTargets: Bool = false
    @State private var enableAmbiguousCorrection: Bool = true
    @State private var abbreviationPriorityEnabled: Bool = true
    @State private var undoWindowSeconds: Double = 2.5
    @State private var skipNextHotkey: String = "cmd+shift+;"
    @State private var undoHotkey: String = "cmd+z"
    @State private var logLevel: LogLevel = .basic
    @State private var enableLogExport: Bool = true
    @State private var importedJSON: String = ""
    @State private var exportJSON: String = ""
    @State private var accessibilityPermissionGranted: Bool = true
    @State private var inputMonitoringPermissionGranted: Bool = true

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(AppStrings.tabGeneral, systemImage: "keyboard.fill") }
            appsAndWordsTab
                .tabItem { Label(AppStrings.tabAppsAndWords, systemImage: "square.grid.2x2.fill") }
            advancedTab
                .tabItem { Label(AppStrings.tabAdvanced, systemImage: "wrench.and.screwdriver.fill") }
        }
        .frame(width: 560, height: 540)
        .onAppear { loadSettings() }
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String)
            )
        ) { _ in
            loadSettings()
        }
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String)
            )
        ) { _ in
            loadSettings()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            checkSystemPermissions()
        }
    }

    // MARK: - General Tab

    private var generalTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                statusCard

                GroupBox {
                    VStack(spacing: 0) {
                        ForEach(installedInputSources, id: \.id) { inputSource in
                            HStack(spacing: 10) {
                                Toggle("", isOn: enabledBinding(for: inputSource))
                                    .toggleStyle(.checkbox)
                                    .disabled(inputSource.supportTier == .unsupported)
                                Text(inputSource.localizedName)
                                    .foregroundStyle(inputSource.supportTier == .unsupported ? Color.secondary : Color.primary)
                                Spacer()
                                tierBadge(for: inputSource.supportTier)
                            }
                            .padding(.vertical, 6)
                            if inputSource.id != installedInputSources.last?.id {
                                Divider()
                            }
                        }
                        if !installedInputSources.isEmpty {
                            Divider()
                                .padding(.top, 4)
                        }
                        SettingToggleRow(
                            label: AppStrings.enableBestEffortTargets,
                            subtitle: AppStrings.enableBestEffortTargetsSubtitle,
                            isOn: $enableBestEffortTargets
                        )
                        .padding(.top, 8)
                        .onChange(of: enableBestEffortTargets) { value in
                            SettingsStore.shared.update { $0.enableBestEffortTargets = value }
                            loadSettings()
                        }
                    }
                } label: {
                    SectionLabel(title: AppStrings.sectionLanguages, icon: "globe", color: .green)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: $correctionPreferenceMode) {
                            Text(AppStrings.correctionModeAutomatic).tag(CorrectionPreferenceMode.automatic)
                            Text(AppStrings.correctionModePreferSpecificTarget).tag(CorrectionPreferenceMode.preferSpecificTarget)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: correctionPreferenceMode) { value in
                            SettingsStore.shared.update { settings in
                                settings.correctionPreferenceMode = value
                                if value == .automatic {
                                    settings.preferredTargetInputSourceID = nil
                                } else if settings.preferredTargetInputSourceID == nil {
                                    settings.preferredTargetInputSourceID = preferredTargetInputSourceID.isEmpty ? enabledInputSourcesForSelection().first?.id : preferredTargetInputSourceID
                                }
                            }
                            loadSettings()
                        }

                        if correctionPreferenceMode == .preferSpecificTarget {
                            Picker(AppStrings.preferredTargetInputSource, selection: $preferredTargetInputSourceID) {
                                ForEach(enabledInputSourcesForSelection(), id: \.id) { inputSource in
                                    Text(inputSource.localizedName).tag(inputSource.id)
                                }
                            }
                            .disabled(enabledInputSourcesForSelection().isEmpty)
                            .onChange(of: preferredTargetInputSourceID) { value in
                                SettingsStore.shared.update { settings in
                                    settings.preferredTargetInputSourceID = value.isEmpty ? nil : value
                                }
                            }
                            if enabledInputSourcesForSelection().isEmpty {
                                Text(AppStrings.noEnabledTargets)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        SettingToggleRow(
                            label: AppStrings.enableAmbiguousCorrection,
                            subtitle: AppStrings.enableAmbiguousCorrectionSubtitle,
                            isOn: $enableAmbiguousCorrection
                        )
                        .onChange(of: enableAmbiguousCorrection) { value in
                            SettingsStore.shared.update { $0.enableAmbiguousCorrection = value }
                        }

                        Divider()

                        SettingToggleRow(
                            label: AppStrings.enableAbbreviationPriority,
                            subtitle: AppStrings.enableAbbreviationPrioritySubtitle,
                            isOn: $abbreviationPriorityEnabled
                        )
                        .onChange(of: abbreviationPriorityEnabled) { value in
                            SettingsStore.shared.update { $0.abbreviationPriorityEnabled = value }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    SectionLabel(title: AppStrings.settingsCorrectionSection, icon: "wand.and.stars", color: .purple)
                }

                GroupBox {
                    VStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(AppStrings.undoWindowSeconds)
                                    .frame(minWidth: 140, alignment: .leading)
                                Slider(value: $undoWindowSeconds, in: 1...5, step: 0.5)
                                Text(String(format: "%.1f s", undoWindowSeconds))
                                    .frame(width: 44, alignment: .trailing)
                                    .monospacedDigit()
                            }
                            .onChange(of: undoWindowSeconds) { value in
                                SettingsStore.shared.update { $0.undoWindowSeconds = value }
                            }
                            Text(AppStrings.undoWindowSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack {
                            Text(AppStrings.undoHotkey)
                                .frame(minWidth: 140, alignment: .leading)
                            TextField("", text: $undoHotkey)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    SettingsStore.shared.update { $0.undoHotkey = undoHotkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                                }
                        }

                        HStack {
                            Text(AppStrings.skipNextHotkey)
                                .frame(minWidth: 140, alignment: .leading)
                            TextField("", text: $skipNextHotkey)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    SettingsStore.shared.update { $0.skipNextHotkey = skipNextHotkey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                                }
                        }
                    }
                } label: {
                    SectionLabel(title: AppStrings.settingsShortcutsSection, icon: "command", color: .blue)
                }
            }
            .padding()
        }
    }

    private var statusCard: some View {
        let hasRequiredPermissions = accessibilityPermissionGranted && inputMonitoringPermissionGranted
        let statusText = statusCardText
        let statusColor: Color = hasRequiredPermissions ? (isEnabled ? Color.green : Color.orange) : Color.red

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 48, height: 48)
                Image(systemName: isEnabled ? "keyboard" : "keyboard.slash")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(AppStrings.appName)
                    .font(.title3)
                    .fontWeight(.semibold)
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .onChange(of: isEnabled) { value in
                    SettingsStore.shared.update { $0.enabled = value }
                }
        }
        .padding(14)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }

    private var statusCardText: String {
        switch (accessibilityPermissionGranted, inputMonitoringPermissionGranted) {
        case (true, true):
            return isEnabled ? AppStrings.statusEnabled : AppStrings.statusDisabled
        case (false, true):
            return AppStrings.statusMissingAccessibilityPermission
        case (true, false):
            return AppStrings.statusMissingInputMonitoringPermission
        case (false, false):
            return AppStrings.statusMissingRequiredPermissions
        }
    }

    @ViewBuilder
    private func tierBadge(for tier: InputSourceSupportTier) -> some View {
        let color: Color = switch tier {
        case .fullSupport: .green
        case .bestEffort: .orange
        case .unsupported: Color(.disabledControlTextColor)
        }
        Text(AppStrings.supportTier(tier))
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Apps & Words Tab

    private var appsAndWordsTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.alwaysActiveAppsSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        inlineListEditor(
                            input: $whitelistInput,
                            placeholder: AppStrings.bundleIdHint,
                            items: currentWhitelist,
                            addAction: addBundleId,
                            removeAction: removeBundleId
                        )
                    }
                } label: {
                    SectionLabel(title: AppStrings.alwaysActiveApps, icon: "checkmark.circle.fill", color: .green)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.neverActiveAppsSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        inlineListEditor(
                            input: $blacklistInput,
                            placeholder: AppStrings.bundleIdHint,
                            items: currentBlacklist,
                            addAction: addBlacklistedBundleId,
                            removeAction: removeBlacklistedBundleId
                        )
                    }
                } label: {
                    SectionLabel(title: AppStrings.neverActiveApps, icon: "xmark.circle.fill", color: .red)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.ignoredWordsSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        inlineListEditor(
                            input: $ignoredWordInput,
                            placeholder: AppStrings.addIgnoredWord,
                            items: ignoredWords,
                            addAction: addIgnoredWord,
                            removeAction: removeIgnoredWord
                        )
                    }
                } label: {
                    SectionLabel(title: AppStrings.ignoredWords, icon: "eye.slash.fill", color: .teal)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.abbreviationExceptionsSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        inlineListEditor(
                            input: $abbreviationExceptionInput,
                            placeholder: AppStrings.addAbbreviationException,
                            items: abbreviationExceptions,
                            addAction: addAbbreviationException,
                            removeAction: removeAbbreviationException
                        )
                    }
                } label: {
                    SectionLabel(title: AppStrings.abbreviationExceptions, icon: "text.badge.checkmark", color: .indigo)
                }
            }
            .padding()
        }
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(AppStrings.logLevel, selection: $logLevel) {
                            Text(AppStrings.logLevelOff).tag(LogLevel.off)
                            Text(AppStrings.logLevelBasic).tag(LogLevel.basic)
                            #if DEBUG
                            Text(AppStrings.logLevelDebug).tag(LogLevel.debug)
                            #endif
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: logLevel) { value in
                            SettingsStore.shared.update { $0.logLevel = value }
                        }
                        Divider()
                        Toggle(AppStrings.enableLogExport, isOn: $enableLogExport)
                            .onChange(of: enableLogExport) { value in
                                SettingsStore.shared.update { $0.enableLogExport = value }
                            }
                    }
                } label: {
                    SectionLabel(title: AppStrings.sectionLogging, icon: "doc.text.fill", color: Color(.systemGray))
                }

                DisclosureGroup(AppStrings.exportImportDisclosure) {
                    VStack(spacing: 12) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                TextEditor(text: $exportJSON)
                                    .frame(height: 80)
                                    .font(.system(.caption, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .background(Color(.textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Button(AppStrings.refreshExport) {
                                    exportJSON = SettingsStore.shared.exportSettingsJSON() ?? ""
                                }
                                .buttonStyle(.bordered)
                            }
                        } label: {
                            SectionLabel(title: AppStrings.exportSettingsJSON, icon: "arrow.up.doc.fill", color: .cyan)
                        }

                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                TextEditor(text: $importedJSON)
                                    .frame(height: 80)
                                    .font(.system(.caption, design: .monospaced))
                                    .scrollContentBackground(.hidden)
                                    .background(Color(.textBackgroundColor))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Button(AppStrings.importSettings) {
                                    if SettingsStore.shared.importSettingsJSON(importedJSON) {
                                        loadSettings()
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        } label: {
                            SectionLabel(title: AppStrings.importSettingsJSON, icon: "arrow.down.doc.fill", color: .blue)
                        }
                    }
                    .padding(.top, 8)
                }

                Text(AppStrings.requiredEntitlements)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func inlineListEditor(
        input: Binding<String>,
        placeholder: String,
        items: [String],
        addAction: @escaping () -> Void,
        removeAction: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(placeholder, text: input)
                    .textFieldStyle(.roundedBorder)
                Button(AppStrings.addAction) {
                    addAction()
                }
                .disabled(input.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            if items.isEmpty {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(items, id: \.self) { value in
                    HStack {
                        Text(value)
                            .font(.callout)
                        Spacer()
                        Button {
                            removeAction(value)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 3)
                    if value != items.last {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Data Helpers

    private func enabledBinding(for inputSource: InstalledInputSource) -> Binding<Bool> {
        Binding(
            get: { enabledTargetInputSourceIDs.contains(inputSource.id) },
            set: { newValue in
                if newValue {
                    enabledTargetInputSourceIDs.insert(inputSource.id)
                } else {
                    enabledTargetInputSourceIDs.remove(inputSource.id)
                }
                SettingsStore.shared.update { settings in
                    settings.enabledTargetInputSourceIDs = Array(enabledTargetInputSourceIDs).sorted()
                    if !enabledTargetInputSourceIDs.contains(settings.preferredTargetInputSourceID ?? "") {
                        settings.preferredTargetInputSourceID = enabledTargetInputSourceIDs.sorted().first
                    }
                }
                loadSettings()
            }
        )
    }

    private func enabledInputSourcesForSelection() -> [InstalledInputSource] {
        installedInputSources.filter { enabledTargetInputSourceIDs.contains($0.id) }
    }

    private func loadSettings() {
        let settings = SettingsStore.shared.getSettings()
        let inputSources = InputSourceController.shared.listInstalledInputSources()
        checkSystemPermissions()
        installedInputSources = inputSources.filter { $0.isSelectable }
        currentWhitelist = settings.whitelistedBundleIds.sorted()
        currentBlacklist = settings.blacklistedBundleIds.sorted()
        ignoredWords = settings.ignoredWords.sorted()
        abbreviationExceptions = settings.abbreviationExceptions.sorted()
        isEnabled = settings.enabled
        correctionPreferenceMode = settings.correctionPreferenceMode
        enableBestEffortTargets = settings.enableBestEffortTargets
        enabledTargetInputSourceIDs = effectiveEnabledTargetInputSourceIDs(settings: settings, inputSources: installedInputSources)
        preferredTargetInputSourceID = settings.preferredTargetInputSourceID ?? enabledInputSourcesForSelection().first?.id ?? ""
        enableAmbiguousCorrection = settings.enableAmbiguousCorrection
        abbreviationPriorityEnabled = settings.abbreviationPriorityEnabled
        undoWindowSeconds = settings.undoWindowSeconds
        skipNextHotkey = settings.skipNextHotkey
        undoHotkey = settings.undoHotkey
        #if DEBUG
        logLevel = settings.logLevel
        #else
        logLevel = settings.logLevel == .debug ? .basic : settings.logLevel
        #endif
        enableLogExport = settings.enableLogExport
        exportJSON = SettingsStore.shared.exportSettingsJSON() ?? ""
        AppControlManager.shared.whitelistedBundleIds = Set(settings.whitelistedBundleIds)
        AppControlManager.shared.blacklistedBundleIds = Set(settings.blacklistedBundleIds)
    }

    private func checkSystemPermissions() {
        let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityPermissionGranted = AXIsProcessTrustedWithOptions(axOptions)
        inputMonitoringPermissionGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    private func effectiveEnabledTargetInputSourceIDs(settings: AppSettings, inputSources: [InstalledInputSource]) -> Set<String> {
        if !settings.enabledTargetInputSourceIDs.isEmpty {
            return Set(settings.enabledTargetInputSourceIDs)
        }
        let defaultTargets = inputSources.filter {
            $0.supportTier == .fullSupport || (settings.enableBestEffortTargets && $0.supportTier == .bestEffort)
        }
        return Set(defaultTargets.map(\.id))
    }

    private func addBundleId() {
        let trimmed = whitelistInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            AppControlManager.shared.whitelistedBundleIds.insert(trimmed)
            currentWhitelist = Array(AppControlManager.shared.whitelistedBundleIds).sorted()
            whitelistInput = ""
        }
    }

    private func removeBundleId(_ bundleId: String) {
        AppControlManager.shared.whitelistedBundleIds.remove(bundleId)
        currentWhitelist = Array(AppControlManager.shared.whitelistedBundleIds).sorted()
    }

    private func addBlacklistedBundleId() {
        let trimmed = blacklistInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            AppControlManager.shared.blacklistedBundleIds.insert(trimmed)
            currentBlacklist = Array(AppControlManager.shared.blacklistedBundleIds).sorted()
            blacklistInput = ""
        }
    }

    private func removeBlacklistedBundleId(_ bundleId: String) {
        AppControlManager.shared.blacklistedBundleIds.remove(bundleId)
        currentBlacklist = Array(AppControlManager.shared.blacklistedBundleIds).sorted()
    }

    private func addIgnoredWord() {
        let trimmed = ignoredWordInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            OverrideController.shared.addIgnoredWord(trimmed)
            ignoredWords = SettingsStore.shared.getSettings().ignoredWords.sorted()
            ignoredWordInput = ""
        }
    }

    private func removeIgnoredWord(_ word: String) {
        OverrideController.shared.removeIgnoredWord(word)
        ignoredWords = SettingsStore.shared.getSettings().ignoredWords.sorted()
    }

    private func addAbbreviationException() {
        let trimmed = abbreviationExceptionInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            SettingsStore.shared.update { settings in
                if !settings.abbreviationExceptions.map({ $0.lowercased() }).contains(trimmed) {
                    settings.abbreviationExceptions.append(trimmed)
                    settings.abbreviationExceptions.sort()
                }
            }
            abbreviationExceptions = SettingsStore.shared.getSettings().abbreviationExceptions.sorted()
            abbreviationExceptionInput = ""
        }
    }

    private func removeAbbreviationException(_ value: String) {
        let normalized = value.lowercased()
        SettingsStore.shared.update { settings in
            settings.abbreviationExceptions.removeAll { $0.lowercased() == normalized }
        }
        abbreviationExceptions = SettingsStore.shared.getSettings().abbreviationExceptions.sorted()
    }
}
