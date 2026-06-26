//
//  LaunchAtLogin.swift
//  Thin wrapper over ServiceManagement's modern login-item API (macOS 13+).
//  Registers the main app itself as a login item — no separate helper bundle.
//

import Foundation
import ServiceManagement

enum LaunchAtLogin {
    /// Whether the app is currently registered to start at login.
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                    }
                }
            } catch {
                // Registration can fail for an unsigned/non-/Applications build; log and move on.
                NSLog("[\(AppConfig.appName)] Launch-at-login toggle failed: \(error.localizedDescription)")
            }
        }
    }
}
