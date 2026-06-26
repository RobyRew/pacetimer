//
//  AppIconView.swift
//  The app's visual identity rendered entirely in SwiftUI: a "mercury drop" core
//  floating inside a glassy lens ring. Also vends the minimalist monochrome
//  template image used in the menu bar.
//

import SwiftUI
import AppKit

/// Full-resolution app icon / logo. Drop this into a preview or an `ImageRenderer`
/// to export a 1024×1024 `.icns` source. Depth comes from overlapping shapes with
/// vibrant radial gradients, additive blending, and selective blur.
struct AppIconView: View {
    var glow: Bool = true

    var body: some View {
        ZStack {
            // Refractive squircle base.
            RoundedRectangle(cornerRadius: 56, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.12, blue: 0.20),
                                 Color(red: 0.04, green: 0.05, blue: 0.10)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            // Glassy lens ring.
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [AppConfig.accent, AppConfig.accentDeep, AppConfig.accent],
                        center: .center
                    ),
                    lineWidth: 14
                )
                .blur(radius: 0.5)
                .padding(40)

            // Mercury-drop core — additive blend gives it that liquid, lit-from-within feel.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, AppConfig.accent, AppConfig.accentDeep],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 2, endRadius: 120
                    )
                )
                .blendMode(.plusLighter)
                .padding(70)
                .blur(radius: glow ? 0.5 : 0)

            // Specular highlight (the "wet" reflection).
            Ellipse()
                .fill(Color.white.opacity(0.6))
                .frame(width: 60, height: 34)
                .blur(radius: 8)
                .offset(x: -28, y: -40)
                .blendMode(.plusLighter)
        }
        .frame(width: 256, height: 256)
    }
}

extension AppIconView {
    /// A crisp monochrome template glyph for the menu bar: a lens ring with a center
    /// drop. The core grows when a countdown is active. Marked `isTemplate` so macOS
    /// tints it automatically for light/dark menu bars.
    @MainActor
    static func menuBarImage(active: Bool) -> NSImage {
        let renderer = ImageRenderer(content: MenuBarGlyph(active: active))
        renderer.scale = 2.0
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 18))
        image.isTemplate = true
        return image
    }
}

/// The vector glyph that becomes the menu-bar template image.
private struct MenuBarGlyph: View {
    var active: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black, lineWidth: 1.6)
                .padding(1.6)
            Circle()
                .fill(Color.black)
                .frame(width: active ? 7 : 4, height: active ? 7 : 4)
        }
        .frame(width: 18, height: 18)
    }
}

#if DEBUG
#Preview("App Icon") { AppIconView().padding(40) }
#endif
