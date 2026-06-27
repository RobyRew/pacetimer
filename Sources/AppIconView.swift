//
//  AppIconView.swift
//  The app's visual identity rendered in SwiftUI: a glass countdown dial with a
//  terminal ">_" prompt at its center (a mirror of the native `.icon`). Also vends
//  the minimalist monochrome ">_" template image used in the menu bar.
//

import SwiftUI
import AppKit

/// Full-resolution app icon / logo. A SwiftUI mirror of `AppIcon.icon`: a glass
/// timer dial with a bright countdown arc and a ">_" command prompt.
struct AppIconView: View {
    /// Fraction of the dial drawn as the bright "elapsed" arc (0…1).
    var progress: CGFloat = 0.7

    var body: some View {
        ZStack {
            // Blue glass squircle.
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.50, green: 0.78, blue: 1.00),
                                 Color(red: 0.42, green: 0.36, blue: 1.00)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.30), .clear],
                        center: UnitPoint(x: 0.5, y: 0.26), startRadius: 4, endRadius: 210
                    )
                )

            // Timer dial ring.
            Circle()
                .stroke(
                    LinearGradient(colors: [AppConfig.accent, AppConfig.accentDeep],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 22
                )
                .opacity(0.6)
                .padding(58)

            // Countdown progress arc.
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(58)

            // Terminal ">_" prompt.
            ZStack {
                Image(systemName: "chevron.right")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: -16)
                Capsule()
                    .fill(.white)
                    .frame(width: 40, height: 16)
                    .offset(x: 30, y: 26)
            }
        }
        .frame(width: 256, height: 256)
    }
}

extension AppIconView {
    /// A crisp monochrome ">_" template glyph for the menu bar — the chevron thickens
    /// slightly while a countdown is active. `isTemplate` lets macOS tint it for
    /// light/dark menu bars.
    @MainActor
    static func menuBarImage(active: Bool) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarGlyph(active: active))
        renderer.scale = 2.0
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }
}

/// The vector glyph that becomes the menu-bar template image: a small ">_" prompt.
private struct MenuBarGlyph: View {
    var active: Bool

    var body: some View {
        ZStack {
            ChevronShape()
                .stroke(Color.black,
                        style: StrokeStyle(lineWidth: active ? 2.3 : 1.9, lineCap: .round, lineJoin: .round))
                .frame(width: 7, height: 11)
                .offset(x: -2.5)
            Capsule()
                .fill(Color.black)
                .frame(width: 6, height: 1.9)
                .offset(x: 5, y: 5)
        }
        .frame(width: 18, height: 18)
    }
}

/// A simple ">" chevron path that fills its rect.
struct ChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return p
    }
}

#if DEBUG
#Preview("App Icon") { AppIconView().padding(40) }
#endif
