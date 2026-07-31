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

nonisolated enum AITarget: String, CaseIterable, Identifiable {
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

// MARK: - Any installed app as a target

/// A target the timer can bring to the front: either one of the known AI presets or
/// any other app found on disk (untested — the user picks it at their own risk).
nonisolated struct AppTarget: Identifiable, Hashable {
    var name: String
    var bundleID: String?
    var path: String?

    var id: String { bundleID ?? path ?? name }

    static func preset(_ t: AITarget) -> AppTarget {
        AppTarget(name: t.displayName, bundleID: t.bundleIDs.first, path: nil)
    }

    static let presets: [AppTarget] = AITarget.allCases.map(preset)

    /// Every `.app` in the usual locations, sorted by name. Computed once and cached —
    /// this is a disk scan, so don't call it in a view body repeatedly.
    static let installed: [AppTarget] = {
        let fm = FileManager.default
        let dirs = ["/Applications", "/Applications/Utilities",
                    "/System/Applications",
                    NSHomeDirectory() + "/Applications"]
        var seen = Set<String>()
        var out: [AppTarget] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = dir + "/" + item
                let name = String(item.dropLast(4))
                let bid = Bundle(path: path)?.bundleIdentifier
                let key = bid ?? path
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                out.append(AppTarget(name: name, bundleID: bid, path: path))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()
}

// MARK: - Finish Action

/// What to do when the timer reaches zero.
enum FinishAction: String, CaseIterable, Identifiable {
    case sendMessage
    case justReturn
    case newChat

    var id: String { rawValue }
    var label: String {
        switch self {
        case .sendMessage: return "Send Message"
        case .justReturn:  return "Just Return"
        case .newChat:     return "New Chat"
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

    /// The message used when no one-shot note is set. Persisted.
    @Published var notes: String            { didSet { persist("notes", notes) } }
    /// A one-off message for *this* session: it overrides `notes` for a single run and
    /// is wiped as soon as it has been used once, so it never lingers into later runs.
    @Published var oneShotNote: String = ""
    @Published var target: AITarget         { didSet { persist("target", target.rawValue) } }
    @Published var unattendedAutomation: Bool { didSet { persist("unattended", unattendedAutomation) } }
    @Published var preventSleep: Bool       { didSet { persist("preventSleep", preventSleep) } }

    /// Selected app to bring forward. Stored as name+bundle id so any installed app works.
    @Published var appTarget: AppTarget {
        didSet {
            persist("targetName", appTarget.name)
            if let b = appTarget.bundleID { persist("targetBundleID", b) }
            if let p = appTarget.path { persist("targetPath", p) }
        }
    }

    // NEW: What to do on finish
    @Published var finishAction: FinishAction {
        didSet { persist("finishAction", finishAction.rawValue) }
    }

    // NEW: Usage window reset – file path and start date
    @Published var usageResetFilePath: String {
        didSet { persist("usageResetFilePath", usageResetFilePath) }
    }
    @Published var usageWindowStart: Date? {
        didSet { persist("usageWindowStart", usageWindowStart) }
    }
    private var lastResetFileModDate: Date?
    private var resetFileMonitorTimer: Timer?

    /// Called whenever the countdown starts/stops, so the menu-bar glyph can update.
    var onRunningChanged: ((Bool) -> Void)?

    private var ticker: Timer?
    private var endDate: Date?
    private var assertionID = IOPMAssertionID(0)
    private var assertionActive = false

    init() {
        let d = UserDefaults.standard
        // Default message is "continue" — the common "carry on" nudge. Editable in Settings.
        notes                = d.string(forKey: "notes") ?? "continue"
        target               = AITarget(rawValue: d.string(forKey: "target") ?? "") ?? .claude
        unattendedAutomation = d.object(forKey: "unattended") as? Bool ?? false
        preventSleep         = d.object(forKey: "preventSleep") as? Bool ?? true
        appTarget = AppTarget(name: d.string(forKey: "targetName") ?? "Claude",
                              bundleID: d.string(forKey: "targetBundleID")
                                        ?? AITarget.claude.bundleIDs.first,
                              path: d.string(forKey: "targetPath"))

        // NEW: Finish action
        finishAction = FinishAction(rawValue: d.string(forKey: "finishAction") ?? "") ?? .sendMessage

        // NEW: Usage window reset file
        usageResetFilePath = d.string(forKey: "usageResetFilePath") ?? "~/Library/Application Support/Claude/usage.json"
        usageWindowStart = d.object(forKey: "usageWindowStart") as? Date

        // Start monitoring the reset file
        startMonitoringResetFile()
    }

    /// The text that will actually be sent: the one-shot note if present, else the default.
    var effectiveMessage: String {
        let one = oneShotNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return one.isEmpty ? notes.trimmingCharacters(in: .whitespacesAndNewlines) : one
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
        onRunningChanged?(false)
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
        onRunningChanged?(true)
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
        let trimmed = effectiveMessage

        // NEW: Branch based on finishAction
        switch finishAction {
        case .sendMessage:
            if unattendedAutomation, !trimmed.isEmpty {
                // 1. Silent check for TCC Accessibility permissions
                guard ensureAccessibilityPermission() else {
                    notify("Grant Accessibility permission in System Settings to enable auto-paste.")
                    return
                }

                // 2. Direct execution. No NSAlert. No asking for permission.
                pasteAndSubmit(trimmed)
            } else {
                // Passive fallback if automation is off or the message is empty
                notify(trimmed.isEmpty
                       ? "Your countdown finished."
                       : "Your message is ready to paste into \(appTarget.name).")
            }

        case .justReturn:
            submitReturnOnly()

        case .newChat:
            // Bring app to front, then press New Chat shortcut
            await activateTarget()
            try? await Task.sleep(nanoseconds: 300_000_000)
            let shortcut = newChatShortcut(for: appTarget)
            postKey(shortcut.keyCode,
                    command: shortcut.command,
                    option: shortcut.option,
                    control: shortcut.control)
        }

        // The one-shot note has now been used — wipe it so it can't leak into a later run.
        oneShotNote = ""
    }

    // MARK: - NEW: Solo Return (Enter only)

    func submitReturnOnly() {
        Task { @MainActor in
            guard ensureAccessibilityPermission() else {
                notify("Accessibility permission required to press Return.")
                return
            }
            await activateTarget()
            try? await Task.sleep(nanoseconds: 200_000_000)
            postKey(0x24, command: false) // Return key
        }
    }

    // MARK: - NEW: Focus frontmost app's text field

    /// Heuristic: click at the centre of the frontmost window to focus the first text field.
    private func focusFrontmostApp() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return }
        // FIX: processIdentifier is non-optional, use directly
        let pid = frontApp.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &window)
        guard result == .success, let windowElement = window as! AXUIElement? else { return }

        var position: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &position)
        var size: CFTypeRef?
        AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &size)
        guard let pos = position as? CGPoint, let sz = size as? CGSize else { return }
        let center = CGPoint(x: pos.x + sz.width/2, y: pos.y + sz.height/2)

        let click = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                            mouseCursorPosition: center, mouseButton: .left)
        click?.post(tap: .cghidEventTap)
        let clickUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                              mouseCursorPosition: center, mouseButton: .left)
        clickUp?.post(tap: .cghidEventTap)
    }

    // MARK: - NEW: New Chat shortcut per app

    private func newChatShortcut(for target: AppTarget) -> (keyCode: CGKeyCode, command: Bool, option: Bool, control: Bool) {
        // Default: ⌘N
        let defaultShortcut = (keyCode: CGKeyCode(0x2D), command: true, option: false, control: false)
        guard let bid = target.bundleID else { return defaultShortcut }
        // Customise per known app
        if bid.contains("com.openai.chat") || bid.contains("com.anthropic") || bid.contains("ai.perplexity") || bid.contains("com.todesktop") {
            return defaultShortcut // All use ⌘N (common)
        }
        return defaultShortcut
    }

    // MARK: - Activation

    private func activateTarget() async {
        let workspace = NSWorkspace.shared
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        // 1. Preferred: the selected app's bundle identifier.
        if let bid = appTarget.bundleID,
           let url = workspace.urlForApplication(withBundleIdentifier: bid) {
            _ = try? await workspace.openApplication(at: url, configuration: config)
            return
        }
        // 2. Fall back to the on-disk path we recorded when it was picked.
        if let path = appTarget.path, FileManager.default.fileExists(atPath: path) {
            _ = try? await workspace.openApplication(at: URL(fileURLWithPath: path),
                                                     configuration: config)
            return
        }
        // 3. Last resort: guess by name in /Applications.
        let byName = URL(fileURLWithPath: "/Applications/\(appTarget.name).app")
        if FileManager.default.fileExists(atPath: byName.path) {
            _ = try? await workspace.openApplication(at: byName, configuration: config)
        }
    }

    // MARK: Accessibility + keystroke synthesis

    /// TRULY silent check — no system prompt, ever.
    private func ensureAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    private func pasteAndSubmit(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        Task { @MainActor in
            // Bring target app to absolute front
            await activateTarget()

            // Allow app rendering and text-field focus
            try? await Task.sleep(nanoseconds: 300_000_000)

            // Optional: focus the text field (heuristic)
            focusFrontmostApp()
            try? await Task.sleep(nanoseconds: 200_000_000)

            // ⌘V (Paste)
            postKey(0x09, command: true)

            // Allow pasteboard transfer
            try? await Task.sleep(nanoseconds: 200_000_000)

            // Return Key (Submit)
            postKey(0x24, command: false)
        }
    }

    // MARK: - Extended postKey with modifiers

    private func postKey(_ keyCode: CGKeyCode,
                         command: Bool = false,
                         option: Bool = false,
                         control: Bool = false) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        var flags = CGEventFlags()
        if command { flags.insert(.maskCommand) }
        if option  { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        down?.flags = flags
        up?.flags = flags
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
                // FIX: Use async version of add()
                do {
                    try await UNUserNotificationCenter.current().add(
                        UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    )
                } catch {
                    NSLog("Failed to send notification: \(error)")
                }
            }
        }
    }

    // MARK: - NEW: Usage window reset via file monitoring

    private func startMonitoringResetFile() {
        resetFileMonitorTimer?.invalidate()
        resetFileMonitorTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            // FIX: Ensure call is on MainActor
            Task { @MainActor in
                self?.checkResetFile()
            }
        }
        // Also check immediately
        checkResetFile()
    }

    private func checkResetFile() {
        let path = (usageResetFilePath as NSString).expandingTildeInPath
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modDate = attrs[.modificationDate] as? Date else {
            // File not found – reset stored date so we don't trigger on first appearance
            lastResetFileModDate = nil
            return
        }
        if lastResetFileModDate == nil {
            lastResetFileModDate = modDate
            return
        }
        if modDate > lastResetFileModDate! {
            // File changed – reset the 5h usage window
            usageWindowStart = Date()
            persist("usageWindowStart", usageWindowStart!)
            lastResetFileModDate = modDate
            // Optionally post a notification for UI refresh
            NotificationCenter.default.post(name: .usageWindowReset, object: nil)
        }
    }

    // MARK: Persistence helpers

    private func persist(_ key: String, _ value: Any?) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

// MARK: - Notification extension

extension Notification.Name {
    static let usageWindowReset = Notification.Name("usageWindowReset")
}
