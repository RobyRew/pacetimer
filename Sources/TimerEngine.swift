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

    /// Best-known bundle identifiers, tried in order. These can change between
    /// releases — verify on your machine with, e.g.:
    ///     osascript -e 'id of app "Claude"'
    /// and edit here if a launch fails.
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

    // User content / settings (persisted via didSet — note: init assignments don't fire didSet)
    @Published var notes: String            { didSet { persist("notes", notes) } }
    @Published var target: AITarget         { didSet { persist("target", target.rawValue) } }
    @Published var attendedAutomation: Bool { didSet { persist("attended", attendedAutomation) } }
    @Published var preventSleep: Bool       { didSet { persist("preventSleep", preventSleep) } }

    // Self-tracked usage window (honest substitute for scraping quota internals)
    @Published var windowStart: Date?       { didSet { persistDate("windowStart", windowStart) } }
    @Published var windowMinutes: Int       { didSet { persist("windowMinutes", windowMinutes) } }

    private var ticker: Timer?
    private var endDate: Date?
    private var assertionID = IOPMAssertionID(0)
    private var assertionActive = false

    init() {
        let d = UserDefaults.standard
        notes              = d.string(forKey: "notes") ?? ""
        target             = AITarget(rawValue: d.string(forKey: "target") ?? "") ?? .claude
        attendedAutomation = d.object(forKey: "attended") as? Bool ?? false
        preventSleep       = d.object(forKey: "preventSleep") as? Bool ?? true
        windowStart        = d.object(forKey: "windowStart") as? Date
        windowMinutes      = d.object(forKey: "windowMinutes") as? Int ?? AppConfig.defaultWindowMinutes
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

    // MARK: Sleep assertion (prevent idle sleep mid-countdown)

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

    // MARK: On-finish execution (attended)

    private func executeOnFinish() async {
        // 1. Bring the chosen AI app forward — a one-shot activation, never a relaunch loop.
        await activateTarget()

        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if attendedAutomation, !trimmed.isEmpty {
            // 2. Attended auto-submit: requires Accessibility + an explicit confirmation.
            guard ensureAccessibilityPermission() else {
                notify("Grant Accessibility permission to enable auto-paste.")
                return
            }
            if confirmPaste(into: target.displayName) {
                pasteAndSubmit(trimmed)
            }
        } else {
            // 3. No automation → passive reminder. Never a lock, never a force-reopen.
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
        // Fallback: locate by display name in /Applications.
        let byName = URL(fileURLWithPath: "/Applications/\(target.displayName).app")
        if FileManager.default.fileExists(atPath: byName.path) {
            _ = try? await workspace.openApplication(at: byName, configuration: config)
        }
    }

    // MARK: Accessibility + keystroke synthesis

    /// Returns whether the process is trusted for Accessibility, prompting the user
    /// to grant it the first time.
    private func ensureAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func confirmPaste(into app: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Paste your note into \(app)?"
        alert.informativeText = "\(AppConfig.appName) will paste the saved note and press Return."
        alert.addButton(withTitle: "Paste & Submit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func pasteAndSubmit(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Task { @MainActor in
            // Re-focus the target (the confirmation alert stole focus), then paste + submit.
            await activateTarget()
            try? await Task.sleep(nanoseconds: 150_000_000)
            postKey(0x09, command: true)            // ⌘V  ('v' = key code 9)
            try? await Task.sleep(nanoseconds: 200_000_000)   // exactly 200ms
            postKey(0x24, command: false)           // Return (key code 36)
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
        // `message` is a Sendable String; rebuild the (non-Sendable) notification objects
        // back on the main actor to keep the concurrency checker happy.
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

    /// 0…1 fraction of the user-defined window consumed. Pure local timekeeping.
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
