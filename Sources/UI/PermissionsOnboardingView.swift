import SwiftUI
import AppKit
import IOKit.hid

struct PermissionsOnboardingView: View {
    @State private var accessibilityGranted: Bool = false
    @State private var inputMonitoringGranted: Bool = false
    @State private var showingAccessibilityPrompt: Bool = false
    @State private var inputMonitoringRequestInFlight: Bool = false
    @State private var openInputMonitoringSettingsAfterRequest: Bool = false
    @State private var checkTimer: Timer?
    
    var onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Text(AppStrings.onboardingTitle)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 32)
            
            Text(AppStrings.onboardingDescription)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            VStack(spacing: 20) {
                PermissionRow(
                    title: AppStrings.onboardingAccessibilityTitle,
                    description: AppStrings.onboardingAccessibilityDesc,
                    isGranted: accessibilityGranted,
                    stepNumber: 1,
                    onRequest: requestAccessibilityPermission
                )
                
                PermissionRow(
                    title: AppStrings.onboardingInputMonitoringTitle,
                    description: AppStrings.onboardingInputMonitoringDesc,
                    isGranted: inputMonitoringGranted,
                    stepNumber: 2,
                    onRequest: requestInputMonitoringPermission
                )
            }
            .padding(.horizontal, 32)
            
            if accessibilityGranted && inputMonitoringGranted {
                Button(action: onComplete) {
                    Text(AppStrings.onboardingContinue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            } else {
                Text(AppStrings.onboardingWaiting)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 32)
            }
        }
        .frame(width: 600, height: 500)
        .onAppear {
            checkPermissions()
            requestInputMonitoringRegistrationIfNeeded()
            startCheckingPermissions()
        }
        .onDisappear {
            openInputMonitoringSettingsAfterRequest = false
            stopCheckingPermissions()
        }
    }
    
    private func checkPermissions() {
        let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityGranted = AXIsProcessTrustedWithOptions(axOptions)
        
        let imAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        inputMonitoringGranted = (imAccess == kIOHIDAccessTypeGranted)
    }
    
    private func startCheckingPermissions() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            checkPermissions()
        }
    }
    
    private func stopCheckingPermissions() {
        checkTimer?.invalidate()
        checkTimer = nil
    }
    
    private func requestAccessibilityPermission() {
        let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(axOptions)
        showingAccessibilityPrompt = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingAccessibilityPrompt = false
            checkPermissions()
        }
    }
    
    private func requestInputMonitoringRegistrationIfNeeded(openSettingsAfterRequest: Bool = false) {
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted else {
            checkPermissions()
            return
        }

        if openSettingsAfterRequest {
            openInputMonitoringSettingsAfterRequest = true
        }
        guard !inputMonitoringRequestInFlight else { return }
        inputMonitoringRequestInFlight = true

        // Denied access does not tell us whether the app is listed in Settings.
        // Submit the request before directing the user there, even when denied.
        DispatchQueue.global(qos: .userInitiated).async {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            DispatchQueue.main.async {
                inputMonitoringRequestInFlight = false
                checkPermissions()

                let shouldOpenSettings = openInputMonitoringSettingsAfterRequest
                openInputMonitoringSettingsAfterRequest = false
                if shouldOpenSettings && !inputMonitoringGranted {
                    openInputMonitoringSettings()
                }
            }
        }
    }

    private func openInputMonitoringSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func requestInputMonitoringPermission() {
        requestInputMonitoringRegistrationIfNeeded(openSettingsAfterRequest: true)
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let stepNumber: Int
    let onRequest: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                
                if isGranted {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .bold))
                } else {
                    Text("\(stepNumber)")
                        .foregroundColor(.primary)
                        .font(.system(size: 16, weight: .bold))
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if !isGranted {
                    Button(action: onRequest) {
                        Text(AppStrings.onboardingRequestPermission)
                            .font(.system(size: 13))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundColor(.accentColor)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}
