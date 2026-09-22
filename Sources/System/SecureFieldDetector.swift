import Foundation
import ApplicationServices

class SecureFieldDetector {
    static let shared = SecureFieldDetector()
    
    private let mandatoryBlacklist: Set<String> = [
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.apple.keychainaccess",
        "com.bitwarden.desktop"
    ]
    
    private init() {}
    
    func isAppBlacklisted(_ bundleId: String) -> Bool {
        return mandatoryBlacklist.contains(bundleId)
    }
    
    // Checks if the currently focused accessibility element is a secure text field
    func isSecureFieldFocused() -> Bool {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElementRaw: CFTypeRef?
        
        let error = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElementRaw)
        
        guard error == .success, let focusedElement = focusedElementRaw else {
            return false
        }
        
        guard CFGetTypeID(focusedElement) == AXUIElementGetTypeID() else {
            return false
        }
        let axElement = focusedElement as! AXUIElement
        var roleRaw: CFTypeRef?
        var subroleRaw: CFTypeRef?
        
        let roleError = AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRaw)
        let subroleError = AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleRaw)
        
        guard roleError == .success else {
            return false
        }
        
        let role = roleRaw as? String
        let subrole = subroleError == .success ? (subroleRaw as? String) : nil
        
        return role == "AXSecureTextField" || subrole == "AXSecureTextField"
    }
    
    // Optional: Start an observer to actively watch for focus changes rather than polling
}
