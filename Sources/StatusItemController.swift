//
//  StatusItemController.swift
//  Owns the menu-bar item, its popover, and the "drag to set the timer" gesture.
//
//  Why not `MenuBarExtra`? SwiftUI's MenuBarExtra gives no access to mouse events on
//  the status item, so a click-and-drag gesture is impossible. Managing NSStatusItem
//  directly lets us distinguish a plain click (open the popover) from a drag
//  (stretch out a duration and start the countdown).
//

import SwiftUI
import AppKit

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let overlay = DragTimeOverlay()
    private let engine: TimerEngine

    /// Pixels of drag travel per minute. ~2.2 pt/min puts the 5-hour ceiling about
    /// 660 pt away — a long but comfortable pull on any display.
    private let pointsPerMinute: CGFloat = 2.2

    private var lastHapticMilestone = -1

    init(engine: TimerEngine, updater: UpdateController) {
        self.engine = engine
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = AppIconView.menuBarImage(active: false)
            button.target = self
            button.action = #selector(handleClick)
            // We need the raw mouse-down so we can start tracking a drag ourselves.
            button.sendAction(on: [.leftMouseDown])
            button.toolTip = "\(AppConfig.appName) — click to open, or drag down to set a timer"
        }

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MainPopOverView(engine: engine)
                .environmentObject(updater)
                .frame(width: 340)
        )

        // Keep the menu-bar glyph in sync with the running state.
        engine.onRunningChanged = { [weak self] running in
            self?.statusItem.button?.image = AppIconView.menuBarImage(active: running)
        }
    }

    // MARK: Click vs. drag

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent, event.type == .leftMouseDown else { return }
        trackDrag()
    }

    /// Runs a short modal event loop: if the pointer travels far enough we treat it as
    /// a duration drag; otherwise it was just a click and we open the popover.
    private func trackDrag() {
        guard let anchor = statusItemCenterOnScreen() else { togglePopover(); return }

        var isDragging = false
        var minutes = 0
        lastHapticMilestone = -1

        trackingLoop: while true {
            guard let event = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                             until: .distantFuture,
                                             inMode: .eventTracking,
                                             dequeue: true) else { break }
            switch event.type {
            case .leftMouseDragged:
                let p = NSEvent.mouseLocation
                let travel = hypot(p.x - anchor.x, anchor.y - p.y)   // down OR sideways

                if !isDragging, travel > 6 {
                    isDragging = true
                    closePopover()
                    overlay.show(anchor: anchor)
                }
                if isDragging {
                    minutes = min(AppConfig.maxMinutes,
                                  max(1, Int((travel / pointsPerMinute).rounded())))
                    overlay.update(to: p, minutes: minutes)
                    fireHapticIfMilestoneCrossed(minutes)
                }

            case .leftMouseUp:
                break trackingLoop

            default:
                break
            }
        }

        overlay.hide()

        if isDragging {
            // Commit the dragged duration and start counting immediately.
            engine.configuredMinutes = minutes
            engine.start()
        } else {
            togglePopover()
        }
    }

    private func fireHapticIfMilestoneCrossed(_ minutes: Int) {
        let milestone = minutes / AppConfig.hapticIntervalMinutes
        guard milestone != lastHapticMilestone else { return }
        lastHapticMilestone = milestone
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// Centre of the status-item button in screen coordinates.
    private func statusItemCenterOnScreen() -> CGPoint? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        let inWindow = button.convert(button.bounds, to: nil)
        let onScreen = window.convertToScreen(inWindow)
        return CGPoint(x: onScreen.midX, y: onScreen.minY)
    }

    // MARK: Popover

    private func togglePopover() {
        popover.isShown ? closePopover() : openPopover()
    }

    private func openPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // Make the popover key so text fields inside it accept typing.
        popover.contentViewController?.view.window?.makeKey()
    }

    private func closePopover() {
        popover.performClose(nil)
    }
}
