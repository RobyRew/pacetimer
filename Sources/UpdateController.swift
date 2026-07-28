//
//  UpdateController.swift
//  Thin wrapper around Sparkle so the rest of the app (menu command + the Updates
//  section in Settings) can drive updates with plain Swift. Sparkle handles the
//  scheduled checks, the quiet "update available" UI, EdDSA signature verification,
//  download → install → relaunch, and the optional silent auto-download.
//
//  Guarded with `#if canImport(Sparkle)` so the project still compiles if the
//  package isn't linked yet (e.g. a plain `swiftc` type-check). See UPDATES.md for
//  the one-time signing-key setup.
//

import Foundation
import Combine

#if canImport(Sparkle)
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    /// Mirrors Sparkle so the "Check for Updates…" control can enable/disable.
    @Published var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    var updater: SPUUpdater { controller.updater }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        // Only start Sparkle once a real EdDSA key is configured — a placeholder
        // SUPublicEDKey makes startUpdater abort — and never inside a test host.
        guard Self.updatesConfigured, !Self.isRunningTests else { return }
        controller.startUpdater()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// True once `SUPublicEDKey` holds a real key (see UPDATES.md), not the placeholder.
    static var updatesConfigured: Bool {
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && !key.hasPrefix("REPLACE_WITH")
    }

    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func checkForUpdates() { controller.updater.checkForUpdates() }

    // Settings-bound conveniences.
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }
    var updateCheckInterval: TimeInterval {
        get { updater.updateCheckInterval }
        set { updater.updateCheckInterval = newValue }
    }
    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }
}

#else

// Sparkle not linked (e.g. bare type-check). A no-op stub with the same surface so
// the UI compiles unchanged.
@MainActor
final class UpdateController: ObservableObject {
    @Published var canCheckForUpdates = false
    static var updatesConfigured: Bool { false }
    func checkForUpdates() {}
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = false
    var updateCheckInterval: TimeInterval = 86_400
    var lastUpdateCheckDate: Date? { nil }
}

#endif
