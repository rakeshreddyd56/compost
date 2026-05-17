//
//  VoiceView.swift
//  Compost — expanded notch voice surface (push-to-talk ⌥⌘V).
//
//  This surface replaces the entire expanded body while active. The user
//  holds ⌥⌘V to record, releases to transcribe. The recognized text is
//  the receipt — voice does NOT mutate Notion in v0.5. Quick-action pills
//  route to the matching expanded surface and exit voice mode.
//

import SwiftUI

enum VoiceStage: Equatable {
    case idle
    case listening
    case transcribing
    case finished(String)
    case failed(String)

    var label: String {
        switch self {
        case .idle:             return "Idle"
        case .listening:        return "Listening"
        case .transcribing:     return "Transcribing"
        case .finished:         return "Compost · finished"
        case .failed:           return "Compost · failed"
        }
    }

    var dotColor: Color {
        switch self {
        case .idle, .finished:  return GardenStyle.sage400
        case .listening:        return GardenStyle.accentRose
        case .transcribing:     return GardenStyle.accentAmber
        case .failed:           return GardenStyle.accentRose
        }
    }
}

struct VoiceView: View {
    @ObservedObject var manager: NotchManager

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            mascotSlot
            VStack(alignment: .leading, spacing: 10) {
                stagePill
                transcript
                waveform
                quickActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, GardenStyle.cardPadding)
        .padding(.vertical, 14)
        .frame(width: 440)
        .background(GardenStyle.notchBg)
        .clipShape(RoundedRectangle(cornerRadius: GardenStyle.expandedR, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Voice mode, \(manager.voiceStage.label)")
    }

    // MARK: - Mascot with sage halo

    private var mascotSlot: some View {
        ZStack {
            RadialGradient(
                colors: [GardenStyle.sage400.opacity(0.20), .clear],
                center: .center, startRadius: 4, endRadius: 56
            )
            .frame(width: 110, height: 110)
            .blur(radius: 8)
            .opacity(manager.voiceStage == .idle ? 0.5 : 1)
            .scaleEffect(manager.voiceStage == .idle ? 0.95 : 1.05)
            .animation(GardenStyle.glow, value: manager.voiceStage)
            Mascot(size: 84, mood: mascotMood)
        }
        .frame(width: 110, height: 110)
        .accessibilityHidden(true)
    }

    private var mascotMood: Mascot.Mood {
        switch manager.voiceStage {
        case .listening:    return .calm
        case .transcribing: return .calm
        case .finished:     return .nudging
        case .failed:       return .alert
        case .idle:         return .calm
        }
    }

    // MARK: - State pill

    private var stagePill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(manager.voiceStage.dotColor)
                .frame(width: 7, height: 7)
                .modifier(PulseModifier(active: manager.voiceStage == .listening || manager.voiceStage == .transcribing))
            Text(manager.voiceStage.label.uppercased())
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundColor(GardenStyle.ink2)
            Spacer()
            Text("hold ⌥⌘V")
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcript: some View {
        switch manager.voiceStage {
        case .idle:
            Text("Hold ⌥⌘V anywhere to talk.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(GardenStyle.ink2)
        case .listening:
            Text(manager.voiceTranscript.isEmpty
                 ? "listening…"
                 : manager.voiceTranscript)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(GardenStyle.ink)
                .italic(manager.voiceTranscript.isEmpty)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .transcribing:
            Text("transcribing…")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(GardenStyle.ink3)
                .italic()
        case .finished(let text):
            Text(text.isEmpty ? "(no speech detected)" : text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(GardenStyle.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let err):
            Text(err)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(GardenStyle.accentRose)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Waveform

    private var waveform: some View {
        Waveform(
            active: manager.voiceStage == .listening || manager.voiceStage == .transcribing,
            color: manager.voiceStage == .listening
                ? GardenStyle.accentRose
                : GardenStyle.sage400,
            amplitudeProvider: { manager.voiceAmplitude }
        )
        .frame(height: 26)
    }

    // MARK: - Quick actions (router into other surfaces)

    private var quickActions: some View {
        HStack(spacing: GardenStyle.actionRowGap) {
            QuickPill("Tidy now") {
                manager.exitVoice()
                Task { await manager.tidyNow() }
            }
            QuickPill("What did I miss?") {
                manager.exitVoice()
                Task { await manager.toggle() }
            }
            QuickPill("Read drafts") {
                manager.exitVoice()
                Task { await manager.toggle() }
            }
            Spacer()
            Button("Tap to end") { manager.exitVoice() }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
        }
    }
}

// MARK: - Quick action pill

private struct QuickPill: View {
    let label: String
    let action: () -> Void

    init(_ label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(GardenStyle.ink2)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(GardenStyle.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(GardenStyle.hair, lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Pulse modifier

private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(active && on ? 0.4 : 1.0)
            .scaleEffect(active && on ? 0.85 : 1.0)
            .animation(active ? GardenStyle.pulse : .default, value: on)
            .onAppear { if active { on.toggle() } }
            .onChange(of: active) { newValue in on = newValue }
    }
}

// MARK: - Waveform canvas

struct Waveform: View {
    let active: Bool
    let color: Color
    let amplitudeProvider: () -> Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let amp = max(0.05, min(1.0, Double(amplitudeProvider())))
            Canvas { gc, size in
                let barCount = 42
                let gap: CGFloat = 3
                let barW: CGFloat = max(2, (size.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount))
                for i in 0..<barCount {
                    let envelope = sin(Double(i) / Double(barCount - 1) * .pi)
                    let phase = sin(t * 8 + Double(i) * 0.4)
                    let v = active
                        ? envelope * (0.4 + 0.6 * abs(phase)) * (0.4 + 0.6 * amp)
                        : 0.08
                    let h = max(2, v * Double(size.height))
                    let x = CGFloat(i) * (barW + gap)
                    let y = (size.height - h) / 2
                    let rect = CGRect(x: x, y: y, width: barW, height: h)
                    gc.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
