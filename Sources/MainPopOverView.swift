//
//  MainPopOverView.swift
//  The glassmorphic popover: the drag-to-stretch timer (with coordinate math and
//  haptic milestones), live read-out, transport controls, the self-tracked usage
//  gauge, and a settings sheet.
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
        VStack(spacing: 16) {
            header
            stretchTrack
            readout
            controls
            usageGauge
            footer
        }
        .padding(18)
        .background(
            ZStack {
                VisualEffectBlur(material: .underWindowBackground)
                LinearGradient(
                    colors: [AppConfig.accent.opacity(0.08), .clear, AppConfig.accentDeep.opacity(0.10)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea()
        )
        .sheet(isPresented: $showSettings) {
            SettingsSheet(engine: engine, displayModeRaw: $displayModeRaw, isPresented: $showSettings)
        }
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

                // Glowing, stretchable accent fill.
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

    /// While idle the fill reflects the *configured* length; while running it drains
    /// to reflect the *remaining* time.
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
                // Coordinate → fraction → minutes (snapped to whole minutes, clamped to ceiling).
                let frac = min(1, max(0, value.location.x / width))
                engine.configuredMinutes = max(1, Int((frac * Double(AppConfig.maxMinutes)).rounded()))

                // Crisp haptic at every 30-minute milestone crossing.
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

// MARK: - Settings sheet

struct SettingsSheet: View {
    @ObservedObject var engine: TimerEngine
    @Binding var displayModeRaw: String
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 16, weight: .bold))

            // Appearance: menu-bar-only vs. dock.
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

            // AI target brought forward when the timer ends.
            field("AI target on finish") {
                Picker("", selection: $engine.target) {
                    ForEach(AITarget.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Toggle("Prevent sleep during countdown", isOn: $engine.preventSleep)
            Toggle("Attended auto-submit (asks before pasting)", isOn: $engine.attendedAutomation)

            // Saved note with a custom placeholder overlay.
            field("Saved note") {
                ZStack(alignment: .topLeading) {
                    if engine.notes.isEmpty {
                        Text("Type a prompt or instruction to paste when the timer ends…")
                            .foregroundStyle(.white.opacity(0.3))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $engine.notes)
                        .scrollContentBackground(.hidden)
                        .frame(height: 90)
                        .padding(4)
                }
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.15)))
            }

            HStack {
                Spacer()
                Button("Done") { isPresented = false }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 340)
        .toggleStyle(.switch)
        .tint(AppConfig.accent)
        .foregroundStyle(.white)
        .background(VisualEffectBlur(material: .underWindowBackground).ignoresSafeArea())
    }

    /// A labelled settings row.
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
