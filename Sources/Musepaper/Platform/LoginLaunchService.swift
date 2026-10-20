import AppKit
import Foundation
import ServiceManagement

/// Login-item registration via the modern SMAppService API (macOS 13+).
enum LoginLaunchService {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    static var needsApproval: Bool {
        status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if status == .enabled { return }
            try SMAppService.mainApp.register()
        } else {
            if status == .notRegistered { return }
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
