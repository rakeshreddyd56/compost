//
//  VoiceView.swift
//  Compost — expanded notch voice surface, matched to handoff scene 03.
//
//  Press ⌥⌘V → recorder starts → mascot listens.
//  Release         → SFSpeechRecognizer transcribes.
//  Then            → Worker `voiceReply` returns a real Claude answer.
//  Then            → AVSpeechSynthesizer speaks it while we type it out.
//
//  Stages map 1:1 to the prototype labels in `scenes.jsx`:
//    listening   → "Listening"          rose dot
//    transcribing→ "Transcribing"       amber dot   (audio→text)
//    replying    → "Thinking"           amber dot   + italic "checking the pile…"
//    speaking    → "Compost"            sage  dot   + progressive type-out
//    finished    → "Compost · finished" sage  dot
//

import SwiftUI

enum VoiceStage: Equatable {
    case idle
    case listening
    case transcribing
    case replying          // voiceReply Worker tool in-flight
    case speaking(String)  // TTS playing the worker reply
    case finished(String)  // reply done OR transcript-only empty case
    case replyFailed(String)
    case failed(String)

    var label: String {
        switch self {
        case .idle:         return "Idle"
        case .listening:    return "Listening"
        case .transcribing: return "Transcribing"
        case .replying:     return "Thinking"
        case .speaking:     return "Compost"
        case .finished:     return "Compost · finished"
        case .replyFailed:  return "Reply failed"
        case .failed:       return "Capture failed"
        }
    }

    var dotColor: Color {
        switch self {
        case .listening:                  return GardenStyle.accentRose
        case .transcribing, .replying:    return GardenStyle.accentAmber
        case .speaking, .finished, .idle: return GardenStyle.sage400
        case .failed, .replyFailed:       return GardenStyle.accentRose
        }
    }
}

struct VoiceView: View {
    @ObservedObject var manager: NotchManager
    @State private var typed: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            mascotSlot
            VStack(alignment: .leading, spacing: 8) {
                stagePill
                transcript
                waveform
                quickActions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, GardenStyle.cardPadding)
        .padding(.vertical, 14)
        .frame(width: GardenStyle.expandedWidth)
        .background(GardenStyle.notchBg)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: GardenStyle.expandedR,
                bottomTrailingRadius: GardenStyle.expandedR,
                topTrailingRadius: 0,
                style: .continuous
            )
        )
        .shadow(color: .black.opacity(0.55), radius: 18, y: 8)
        .onChange(of: manager.voiceStage) { handleStageChange($0) }
        .onAppear { handleStageChange(manager.voiceStage) }
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
            Mascot(size: 84, mood: mascotMood, bobble: isSpeaking)
        }
        .frame(width: 110, height: 110)
        .accessibilityHidden(true)
    }

    private var isSpeaking: Bool {
        if case .speaking = manager.voiceStage { return true }
        return false
    }

    private var mascotMood: Mascot.Mood {
        switch manager.voiceStage {
        case .listening, .transcribing, .replying, .idle: return .calm
        case .speaking, .finished:                         return .nudging
        case .failed, .replyFailed:                        return .alert
        }
    }

    // MARK: - State pill

    private var stagePill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(manager.voiceStage.dotColor)
                .frame(width: 7, height: 7)
                .modifier(PulseDot(active: isBusy))
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

    private var isBusy: Bool {
        switch manager.voiceStage {
        case .listening, .transcribing, .replying, .speaking: return true
        default: return false
        }
    }

    // MARK: - Transcript (single live region — matches prototype)

    @ViewBuilder
    private var transcript: some View {
        switch manager.voiceStage {
        case .idle:
            Text("Hold ⌥⌘V anywhere to talk.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(GardenStyle.ink2)

        case .listening:
            HStack(spacing: 2) {
                Text(manager.voiceTranscript.isEmpty ? "listening…" : manager.voiceTranscript)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .italic(manager.voiceTranscript.isEmpty)
                    .foregroundColor(GardenStyle.ink)
                Caret()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .transcribing:
            HStack(spacing: 2) {
                Text(manager.voiceTranscript.isEmpty ? "transcribing…" : manager.voiceTranscript)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .italic(manager.voiceTranscript.isEmpty)
                    .foregroundColor(GardenStyle.ink2)
                Caret()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .replying:
            // Prototype's "thinking" stage — italic gray placeholder.
            Text("checking the pile…")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .italic()
                .foregroundColor(GardenStyle.ink3)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .speaking:
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(typed)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(GardenStyle.ink)
                Caret()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        case .finished(let reply):
            Text(reply.isEmpty ? "(no speech detected)" : reply)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(GardenStyle.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .replyFailed(let err):
            Text(err)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(GardenStyle.accentRose)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .failed(let err):
            Text(err)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(GardenStyle.accentRose)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Type-out driver

    /// On stage transitions, drive a progressive type-out of the reply at
    /// ~24ms/char (matches prototype). Listening/transcribing don't type-out
    /// (the recognizer's partial results would, but we're file-based right now,
    /// so transcript appears all at once on release).
    private func handleStageChange(_ stage: VoiceStage) {
        switch stage {
        case .speaking(let full), .finished(let full):
            startTypeOut(full)
        case .replying, .listening, .transcribing, .idle:
            typed = ""
        case .failed, .replyFailed:
            typed = ""
        }
    }

    @State private var typeTask: Task<Void, Never>?

    private func startTypeOut(_ text: String) {
        typeTask?.cancel()
        guard !text.isEmpty else { typed = ""; return }
        if GardenStyle.reduceMotion {
            typed = text
            return
        }
        typed = ""
        typeTask = Task { @MainActor in
            for (i, _) in text.enumerated() {
                if Task.isCancelled { return }
                typed = String(text.prefix(i + 1))
                try? await Task.sleep(nanoseconds: 24_000_000) // 24ms/char
            }
        }
    }

    // MARK: - Waveform

    private var waveform: some View {
        Waveform(
            active: isBusy,
            color: waveformColor,
            amplitudeProvider: { manager.voiceAmplitude }
        )
        .frame(height: 26)
    }

    private var waveformColor: Color {
        switch manager.voiceStage {
        case .listening:                  return GardenStyle.accentRose
        case .transcribing, .replying:    return GardenStyle.accentAmber
        default:                          return GardenStyle.sage400
        }
    }

    // MARK: - Quick actions (route to surfaces)

    private var quickActions: some View {
        HStack(spacing: GardenStyle.actionRowGap) {
            QuickPill("What did I miss?") {
                Task { await manager.openScene(.cue) }
            }
            QuickPill("Read drafts") {
                Task { await manager.openScene(.drafts) }
            }
            QuickPill("Show photos") {
                Task { await manager.openScene(.photos) }
            }
            Spacer()
            Button("Tap to end") { manager.exitVoice() }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(GardenStyle.ink3)
        }
    }
}

// MARK: - Caret blinker

private struct Caret: View {
    @State private var on = true
    var body: some View {
        Rectangle()
            .fill(GardenStyle.sage400)
            .frame(width: 2, height: 16)
            .opacity(on ? 1 : 0)
            .onAppear {
                guard !GardenStyle.reduceMotion else { return }
                withAnimation(.linear(duration: 0.5).repeatForever(autoreverses: true)) {
                    on.toggle()
                }
            }
            .accessibilityHidden(true)
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
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(GardenStyle.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Pulse dot

private struct PulseDot: ViewModifier {
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
