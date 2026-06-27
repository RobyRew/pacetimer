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
    static let defaultWindowMinutes = 300

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
    @StateObject private var engine = TimerEngine()
    @AppStorage("displayMode") private var displayModeRaw = DisplayMode.menuBarOnly.rawValue

    var body: some Scene {
        MenuBarExtra {
            MainPopOverView(engine: engine, displayModeRaw: $displayModeRaw)
                .frame(width: 340)
        } label: {
            Image(nsImage: AppIconView.menuBarImage(active: engine.isRunning))
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - App delegate
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Set the initial activation policy (Dock vs Menu Bar only)
        let raw = UserDefaults.standard.string(forKey: "displayMode")
            ?? DisplayMode.menuBarOnly.rawValue
        let mode = DisplayMode(rawValue: raw) ?? .menuBarOnly
        NSApp.setActivationPolicy(mode.activationPolicy)
        
        // 2. Trigger the Accessibility (Privacy) prompt on first launch
        let promptOption = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptOption: true] as CFDictionary
        
        // This will silently return true if they already gave permission,
        // or forcefully pop the System Settings alert right now if they haven't.
        _ = AXIsProcessTrustedWithOptions(options)
    }
}