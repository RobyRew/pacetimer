//
//  GlassComponents.swift
//  Reusable Liquid-Glass building blocks: a real NSVisualEffectView blur and a
//  layered "glass card" modifier (blur + micro-gradient sheen + thin inner border
//  + soft shadow) used to simulate refracted light.
//

import SwiftUI
import AppKit

/// Bridge to `NSVisualEffectView` for genuine behind-window blur — the base layer
/// of the Liquid-Glass look that SwiftUI's `.ultraThinMaterial` can't fully match.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// A frosted glass panel. Layers, from back to front:
///   1. behind-window blur
///   2. a top→bottom sheen + an accent radial glow (micro-gradients)
///   3. a 1px semi-transparent inner border (the "refraction" edge)
///   4. a soft drop shadow for depth
struct GlassCard: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    VisualEffectBlur()
                    LinearGradient(
                        colors: [Color.white.opacity(0.10), .clear, Color.black.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    )
                    RadialGradient(
                        colors: [AppConfig.accent.opacity(0.16), .clear],
                        center: .topLeading, startRadius: 4, endRadius: 260
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

extension View {
    /// Wrap any view in the reusable Liquid-Glass panel treatment.
    func glassCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }
}
