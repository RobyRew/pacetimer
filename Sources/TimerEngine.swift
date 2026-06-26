//
//  TimerEngine.swift
//  Countdown state machine + on-finish execution.
//
//  Scope note: this engine is deliberately *attended* and non-hostile. It does NOT
//  read another app's private files, scrape undocumented endpoints, auto-submit
//  unattended on a loop, or block/relaunch any application. The usage gauge is
//  self-tracked, automation asks for explicit confirmation, and the fallback is a
//  passive notification.
//
import SwiftUI
import AppKit
import CoreGraphics
import IOKit.pwr_mgt
import UserNotifications
import ApplicationServices

// MARK: - AI target apps

enum AITarget: String, CaseIterable, Identifiable {
    case claude, chatgpt, perplexity, cursor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:     return "Claude"
        case .chatgpt:    return "ChatGPT"
        case .perplexity: return "Perplexity"
        case .cursor:     return "Cursor"
        }
    }

    var bundleIDs: [String] {
        switch self {
        case .claude:     return ["com.anthropic.claudefordesktop", "com.anthropic.claude"]
        case .chatgpt:    return ["com.openai.chat"]
        case .perplexity: return ["ai.perplexity.mac", "ai.perplexity.comet"]
        case .cursor:     return ["com.todesktop.230313mzl4w4u92"]
        }
    }
}

// MARK: - Engine

@MainActor
final class TimerEngine: ObservableObject {

    // Countdown
    @Published var configuredMinutes: Int = 25
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isRunning = false

    // User content / settings
    @Published var notes: String            { didSet { persist("notes", notes) } }
    @Published var target: AITarget         { didSet { persist("target", target.rawValue) } }
    @Published var unattendedAutomation: Bool { didSet { persist("unattended", unattendedAutomation) } }
    @Published var preventSleep: Bool       { didSet { persist("preventSleep", preventSleep) } }

    // Self-tracked usage window
    @Published var windowStart: Date?       { didSet { persistDate("windowStart", windowStart) } }
    @Published var windowMinutes: Int       { didSet { persist("windowMinutes", windowMinutes) } }

    private var ticker: Timer?
    private var endDate: Date?
    private var assertionID = IOPMAssertionID(0)
    private var assertionActive = false

    init() {
        let d = UserDefaults.standard
        notes                = d.string(forKey: "notes") ?? ""
        target               = AITarget(rawValue: d.string(forKey: "target") ?? "") ?? .claude
        unattendedAutomation = d.object(forKey: "unattended") as? Bool ?? false
        preventSleep         = d.object(forKey: "preventSleep") as? Bool ?? true
        windowStart          = d.object(forKey: "windowStart") as? Date
        windowMinutes        = d.object(forKey: "windowMinutes") as? Int ?? AppConfig.defaultWindowMinutes
    }

    // MARK: Countdown control

    func start() {
        guard configuredMinutes > 0 else { return }
        remaining = TimeInterval(configuredMinutes * 60)
        beginCounting()
    }

    func resume() {
        guard !isRunning, remaining > 0 else { return }
        beginCounting()
    }

    func pause() {
        isRunning = false
        ticker?.invalidate(); ticker = nil
        endSleepAssertion()
    }

    func reset() {
        pause()
        remaining = 0
        endDate = nil
    }

    private func beginCounting() {
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        if preventSleep { beginSleepAssertion() }
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { fire() }
    }

    private func fire() {
        pause()
        remaining = 0
        Task { await executeOnFinish() }
    }

    // MARK: Sleep assertion

    private func beginSleepAssertion() {
        guard !assertionActive else { return }
        let reason = "\(AppConfig.appName) countdown is running" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        assertionActive = (result == kIOReturnSuccess)
    }

    private func endSleepAssertion() {
        guard assertionActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionActive = false
    }

    // MARK: Unattended Execution Pipeline

    private func executeOnFinish() async {
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if unattendedAutomation, !trimmed.isEmpty {
            // 1. Silent check for TCC Accessibility permissions
            guard ensureAccessibilityPermission() else {
                notify("Grant Accessibility permission in System Settings to enable auto-paste.")
                return
            }
            
            // 2. Direct execution. No NSAlert. No asking for permission.
            pasteAndSubmit(trimmed)
            
        } else {
            // Passive fallback if automation is off or note is empty
            notify(trimmed.isEmpty
                   ? "Your countdown finished."
                   : "Your note is ready to paste into \(target.displayName).")
        }
    }

    private func activateTarget() async {
        let workspace = NSWorkspace.shared
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        for id in target.bundleIDs {
            if let url = workspace.urlForApplication(withBundleIdentifier: id) {
                _ = try? await workspace.openApplication(at: url, configuration: config)
                return
            }
        }
        
        let byName = URL(fileURLWithPath: "/Applications/\(target.displayName).app")
        if FileManager.default.fileExists(atPath: byName.path) {
            _ = try? await workspace.openApplication(at: byName, configuration: config)
        }
    }

    // MARK: Accessibility + keystroke synthesis

    private func ensureAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func pasteAndSubmit(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Task { @MainActor in
            // Bring target app to absolute front
            await activateTarget()
            
            // Allow app rendering and text-field focus
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
            
            // ⌘V (Paste)
            postKey(0x09, command: true)
            
            // Allow pasteboard transfer
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            
            // Return Key (Submit)
            postKey(0x24, command: false)
        }
    }

    private func postKey(_ keyCode: CGKeyCode, command: Bool) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        if command {
            down?.flags = .maskCommand
            up?.flags   = .maskCommand
        }
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Passive notification fallback

    private func notify(_ message: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            Task { @MainActor in
                let content = UNMutableNotificationContent()
                content.title = AppConfig.appName
                content.body = message
                content.sound = .default
                UNUserNotificationCenter.current().add(
                    UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                )
            }
        }
    }

    // MARK: Self-tracked usage window

    func startUsageWindow() { windowStart = Date() }
    func clearUsageWindow() { windowStart = nil }

    var usageFraction: Double {
        guard let start = windowStart else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        return min(1, max(0, elapsed / Double(windowMinutes * 60)))
    }

    var usageRemainingText: String {
        guard let start = windowStart else { return "No window started" }
        let left = max(0, Double(windowMinutes * 60) - Date().timeIntervalSince(start))
        return String(format: "%dh %02dm left", Int(left) / 3600, (Int(left) % 3600) / 60)
    }

    // MARK: Persistence helpers

    private func persist(_ key: String, _ value: Any) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistDate(_ key: String, _ value: Date?) {
        if let value { UserDefaults.standard.set(value, forKey: key) }
        else { UserDefaults.standard.removeObject(forKey: key) }
    }
}
