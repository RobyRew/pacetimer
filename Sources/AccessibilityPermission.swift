//
//  AccessibilityPermission.swift
//  Observable wrapper around the Accessibility (AXIsProcessTrusted) permission.
//
//  Why this exists: calling `AXIsProcessTrustedWithOptions([prompt: true])` on every
//  launch re-nags the user forever. The correct pattern is:
//    • check status *without* prompting (`AXIsProcessTrusted()`),
//    • prompt only when the user asks for it,
//    • re-check when the app becomes active, so the UI updates the moment the user
//      flips the switch in System Settings (the grant needs no relaunch to be read).
//

import Foundation
import AppKit
import ApplicationServices
import Combine

@MainActor
final class AccessibilityPermission: ObservableObject {
    static let shared = AccessibilityPermission()

    /// True when this app is trusted for Accessibility (i.e. may synthesize keystrokes).
    @Published private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: Timer?
    private var activationObserver: Any?

    private init() {
        // Re-check whenever the app comes forward — typically right after the user
        // returns from System Settings.
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit {
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
    }

    /// Non-prompting status read. Safe to call as often as you like.
    func refresh() {
        let current = AXIsProcessTrusted()
        if current != isTrusted { isTrusted = current }
        if current { stopPolling() }
    }

    /// Prompts at most once for the lifetime of the install, for first-run discovery.
    /// Every later launch stays silent — Settings carries the status row and an
    /// on-demand "Grant…" button, so an unsigned rebuild can't nag on every launch.
    func requestOnceOnFirstLaunch() {
        refresh()
        guard !isTrusted else { return }

        let key = "hasRequestedAccessibilityOnce"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        request()
    }

    /// Shows the system "grant Accessibility" prompt. Call this only from an explicit
    /// user action — never automatically at launch.
    func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        startPolling()
    }

    /// Deep-links straight to Privacy & Security → Accessibility.
    func openSystemSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
        startPolling()
    }

    // While the user is over in System Settings this app may never "become active",
    // so poll briefly to catch the grant live.
    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
