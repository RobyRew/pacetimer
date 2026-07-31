//
//  AppMain.swift
//  PaceTimer — a premium Liquid-Glass menu-bar countdown app.
//
//  Lifecycle, MenuBarExtra hosting, dock/menu-bar activation policy, and the
//  single source of app-wide configuration.
//

import SwiftUI
import AppKit
import ApplicationServices

// MARK: - App configuration

/// Everything brandable in one place. Change `appName` to rebrand the whole app.
enum AppConfig {
    static let appName = "PeaceTimer"

    /// Hard ceiling for the drag-to-stretch timer (5 hours, expressed in minutes).
    static let maxMinutes = 300
    /// Crisp haptic feedback fires whenever the drag crosses one of these milestones.
    static let hapticIntervalMinutes = 30
    /// Default length of the self-tracked usage window (mirrors a 5-hour cadence).

    /// Accent gradient used throughout the glass UI.
    static let accent     = Color(red: 0.39, green: 0.74, blue: 1.00)
    static let accentDeep = Color(red: 0.55, green: 0.45, blue: 1.00)
}

// MARK: - Display mode (menu-bar-only vs. dock)

enum DisplayMode: String, CaseIterable, Identifiable {
    case menuBarOnly
    case dual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .menuBarOnly: return "Menu Bar Only"
        case .dual:        return "Menu Bar + Dock"
        }
    }

    /// `.accessory` keeps the app out of the Dock while still allowing windows and
    /// activation. `.prohibited` is intentionally avoided — it stops the app from
    /// activating at all, which breaks the popover.
    var activationPolicy: NSApplication.ActivationPolicy {
        self == .dual ? .regular : .accessory
    }
}

// MARK: - App entry point

@main
struct PaceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu-bar item is managed by `StatusItemController` (AppKit) rather than
    // `MenuBarExtra`, because MenuBarExtra exposes no mouse events — and the
    // drag-from-the-icon gesture needs them. This scene therefore stays empty.
    var body: some Scene {
        Settings { EmptyView() }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = TimerEngine()
    let updater = UpdateController()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Set the initial activation policy (Dock vs Menu Bar only)
        let raw = UserDefaults.standard.string(forKey: "displayMode")
            ?? DisplayMode.menuBarOnly.rawValue
        let mode = DisplayMode(rawValue: raw) ?? .menuBarOnly
        NSApp.setActivationPolicy(mode.activationPolicy)

        // 2. Menu-bar item + drag-to-set-timer gesture.
        statusItemController = StatusItemController(engine: engine, updater: updater)

        // 3. Accessibility: prompt at most once ever (first-run discovery), then stay
        //    silent. Re-prompting on every launch is what makes unsigned rebuilds nag
        //    forever — instead, Settings shows a live status row with a "Grant…" button.
        AccessibilityPermission.shared.requestOnceOnFirstLaunch()
    }

    // MARK: - Session Lock

    /// Prevents quitting while a timer is running unless the user confirms.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard engine.isRunning else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Timer is running"
        alert.informativeText = "Quitting will stop the countdown. Are you sure?"
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        return response == .alertSecondButtonReturn ? .terminateCancel : .terminateNow
    }

    /// When the user tries to relaunch the app (or clicks the Dock icon), bring the
    /// existing instance to front instead of opening a new window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Reopen the popover if needed – for now, we just activate the app.
        NSApp.activate(ignoringOtherApps: true)
        // Optionally, we could call statusItemController?.openPopover() here,
        // but we'll keep it minimal – the user can click the menu bar icon.
        return false // Prevent default window creation.
    }
}
