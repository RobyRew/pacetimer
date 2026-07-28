//
//  DragTimeOverlay.swift
//  The floating visual for "drag down from the menu-bar icon to set the timer":
//  a glowing line that stretches from the status item to the cursor, with a live
//  countdown bubble at the end of it.
//
//  It lives in a borderless, transparent, click-through NSWindow pinned above the
//  menu bar, so it can draw outside any app window while the drag is in flight.
//

import SwiftUI
import AppKit

@MainActor
final class DragTimeOverlay {
    private var window: NSWindow?
    private let model = DragOverlayModel()

    /// Show the overlay anchored at the status-item's centre (screen coordinates).
    func show(anchor: CGPoint) {
        model.anchor = anchor
        model.current = anchor
        model.minutes = 0

        guard window == nil else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let frame = screen?.frame ?? .zero

        let w = NSWindow(contentRect: frame, styleMask: .borderless,
                         backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .popUpMenu                 // above the menu bar
        w.ignoresMouseEvents = true          // never steal the drag
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.contentView = NSHostingView(
            rootView: DragOverlayView(model: model, origin: frame.origin)
        )
        w.orderFrontRegardless()
        window = w
    }

    /// Update while dragging.
    func update(to point: CGPoint, minutes: Int) {
        model.current = point
        model.minutes = minutes
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

/// Observable state driving the overlay drawing.
@MainActor
final class DragOverlayModel: ObservableObject {
    @Published var anchor: CGPoint = .zero
    @Published var current: CGPoint = .zero
    @Published var minutes: Int = 0
}

/// The stretching line + countdown bubble.
private struct DragOverlayView: View {
    @ObservedObject var model: DragOverlayModel
    /// Screen origin, so global (screen) points can be mapped into view space.
    let origin: CGPoint

    var body: some View {
        GeometryReader { geo in
            let a = toLocal(model.anchor, in: geo.size)
            let c = toLocal(model.current, in: geo.size)

            ZStack(alignment: .topLeading) {
                // The stretching beam, with a soft glow underneath.
                Path { p in
                    p.move(to: a)
                    p.addLine(to: c)
                }
                .stroke(
                    LinearGradient(colors: [AppConfig.accent.opacity(0.35), AppConfig.accent],
                                   startPoint: .top, endPoint: .bottom),
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .shadow(color: AppConfig.accent.opacity(0.7), radius: 8)

                // Arrow head at the dragging end.
                Circle()
                    .fill(.white)
                    .frame(width: 13, height: 13)
                    .shadow(color: AppConfig.accent.opacity(0.9), radius: 6)
                    .position(c)

                // Live read-out bubble.
                readout
                    .position(x: c.x, y: c.y + 34)
            }
        }
        .ignoresSafeArea()
    }

    private var readout: some View {
        let h = model.minutes / 60, m = model.minutes % 60
        return Text(String(format: "%02dh %02dm", h, m))
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                ZStack {
                    VisualEffectBlur(material: .hudWindow)
                    LinearGradient(colors: [AppConfig.accent.opacity(0.30), AppConfig.accentDeep.opacity(0.30)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            )
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    /// Screen coords (y-up, origin bottom-left) → SwiftUI view coords (y-down).
    private func toLocal(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x - origin.x, y: size.height - (p.y - origin.y))
    }
}
