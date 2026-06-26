//
//  MainPopOverView.swift
//  The glassmorphic popover: the drag-to-stretch timer (with coordinate math and
//  haptic milestones), live read-out, a prompt field, transport controls, the
//  self-tracked usage gauge, and an inline settings panel.
//
//  Settings are shown *inline* (not via `.sheet`) — a sheet presented from a
//  MenuBarExtra window steals key focus from the popover, which makes it flicker
//  open/closed. Swapping content within the same window fixes that.
//

import SwiftUI
import AppKit

struct MainPopOverView: View {
    @ObservedObject var engine: TimerEngine
    @Binding var displayModeRaw: String

    @State private var showSettings = false
    @State private var lastHapticMilestone = -1

    private let trackHeight: CGFloat = 30

    var body: some View {
        ZStack {
            background
            if showSettings {
                SettingsPanel(engine: engine, displayModeRaw: $displayModeRaw, showSettings: $showSettings)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                mainContent
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.28), value: showSettings)
    }

    private var background: some View {
        ZStack {
            VisualEffectBlur(material: .underWindowBackground)
            LinearGradient(
                colors: [AppConfig.accent.opacity(0.08), .clear, AppConfig.accentDeep.opacity(0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var mainContent: some View {
        VStack(spacing: 16) {
            header
            stretchTrack
            readout
            promptField
            controls
            usageGauge
            footer
        }
        .padding(18)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.system(size: 16))
                .foregroundStyle(
                    LinearGradient(colors: [AppConfig.accent, AppConfig.accentDeep],
                                   startPoint: .top, endPoint: .bottom)
                )
            Text(AppConfig.appName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.white.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Drag-to-stretch track

    /// A horizontal capsule mapping its full width to 0…`maxMinutes`. The user drags
    /// anywhere along it to "stretch" the glowing accent fill minute-by-minute.
    private var stretchTrack: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = currentFraction(width: w)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)

                Capsule()
                    .fill(LinearGradient(colors: [AppConfig.accent, AppConfig.accentDeep],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(trackHeight, w * frac))
                    .shadow(color: AppConfig.accent.opacity(0.6), radius: 10)

                handle
                    .position(x: min(max(trackHeight / 2, w * frac), w - trackHeight / 2),
                              y: trackHeight / 2)
            }
            .frame(height: trackHeight)
            .contentShape(Rectangle())
            .gesture(dragGesture(width: w))
        }
        .frame(height: trackHeight)
    }

    private var handle: some View {
        ZStack {
            Circle().fill(.white)
            Circle().strokeBorder(AppConfig.accent.opacity(0.6), lineWidth: 2)
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(AppConfig.accentDeep)
        }
        .frame(width: trackHeight + 6, height: trackHeight + 6)
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private func currentFraction(width: CGFloat) -> CGFloat {
        if engine.isRunning {
            let total = Double(engine.configuredMinutes * 60)
            return total > 0 ? CGFloat(engine.remaining / total) : 0
        }
        return CGFloat(Double(engine.configuredMinutes) / Double(AppConfig.maxMinutes))
    }

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !engine.isRunning, width > 0 else { return }
                let frac = min(1, max(0, value.location.x / width))
                engine.configuredMinutes = max(1, Int((frac * Double(AppConfig.maxMinutes)).rounded()))

                let milestone = engine.configuredMinutes / AppConfig.hapticIntervalMinutes
                if milestone != lastHapticMilestone {
                    lastHapticMilestone = milestone
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }
            }
    }

    // MARK: Read-out

    private var readout: some View {
        let total = engine.isRunning ? Int(engine.remaining.rounded(.up)) : engine.configuredMinutes * 60
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(String(format: "%02dh %02dm", h, m))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            if engine.isRunning {
                Text(String(format: "%02ds", s))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    // MARK: Prompt field (on the main screen)

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "text.cursor")
                Text("Note to paste on finish")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if !engine.notes.isEmpty {
                    Button { engine.notes = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.4))
                }
            }
            .foregroundStyle(.white.opacity(0.7))

            ZStack(alignment: .topLeading) {
                if engine.notes.isEmpty {
                    Text("Type a prompt…")
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }
                TextEditor(text: $engine.notes)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12))
                    .frame(height: 52)
                    .padding(3)
            }
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12)))
        }
    }

    // MARK: Transport controls

    private var controls: some View {
        HStack(spacing: 10) {
            if engine.isRunning {
                glassButton("Pause", system: "pause.fill") { engine.pause() }
            } else if engine.remaining > 0 {
                glassButton("Resume", system: "play.fill") { engine.resume() }
            } else {
                glassButton("Start", system: "play.fill", prominent: true) { engine.start() }
            }
            glassButton("Reset", system: "arrow.counterclockwise") { engine.reset() }
        }
    }

    private func glassButton(_ title: String, system: String,
                             prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: system)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Group {
                        if prominent {
                            LinearGradient(colors: [AppConfig.accent, AppConfig.accentDeep],
                                           startPoint: .leading, endPoint: .trailing)
                        } else {
                            Color.white.opacity(0.08)
                        }
                    }
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    // MARK: Self-tracked usage gauge

    private var usageGauge: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
                    Circle().trim(from: 0, to: engine.usageFraction)
                        .stroke(
                            LinearGradient(colors: [AppConfig.accent, AppConfig.accentDeep],
                                           startPoint: .top, endPoint: .bottom),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(engine.usageFraction * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Usage window")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(engine.usageRemainingText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button(engine.windowStart == nil ? "Start" : "Reset") {
                    if engine.windowStart == nil { engine.startUsageWindow() }
                    else { engine.clearUsageWindow() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppConfig.accent)
            }
            .padding(10)
            .glassCard(cornerRadius: 14)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button { showSettings = true } label: {
                Label("Settings", systemImage: "gearshape").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))

            Spacer()

            Button { NSApp.terminate(nil) } label: {
                Label("Quit", systemImage: "power").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))
        }
    }
}

// MARK: - Inline settings panel

struct SettingsPanel: View {
    @ObservedObject var engine: TimerEngine
    @Binding var displayModeRaw: String
    @Binding var showSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.snappy(duration: 0.28)) { showSettings = false }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Settings").font(.system(size: 15, weight: .bold))
                }
            }
            .buttonStyle(.plain)

            field("Appearance") {
                Picker("", selection: Binding(
                    get: { DisplayMode(rawValue: displayModeRaw) ?? .menuBarOnly },
                    set: { newValue in
                        displayModeRaw = newValue.rawValue
                        NSApp.setActivationPolicy(newValue.activationPolicy)
                    }
                )) {
                    ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Toggle("Launch at login", isOn: Binding(
                get: { LaunchAtLogin.isEnabled },
                set: { LaunchAtLogin.isEnabled = $0 }
            ))

            field("AI target on finish") {
                Picker("", selection: $engine.target) {
                    ForEach(AITarget.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Toggle("Prevent sleep during countdown", isOn: $engine.preventSleep)
            Toggle("Auto-paste note on finish (asks first)", isOn: $engine.attendedAutomation)

            Spacer(minLength: 0)
        }
        .padding(18)
        .toggleStyle(.switch)
        .tint(AppConfig.accent)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func field<Content: View>(_ title: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            content()
        }
    }
}
