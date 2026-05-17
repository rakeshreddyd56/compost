//
//  ReadAloudButton.swift
//  Compost — reusable speaker button that reads `text` aloud via the manager's
//  VoiceClient. Per-row state — only one row reads at a time, second click
//  on the same row stops playback.
//

import SwiftUI

struct ReadAloudButton: View {
    let text: String
    let id: String
    @ObservedObject var manager: NotchManager

    private var speakingThis: Bool {
        manager.speakingId == id
    }

    var body: some View {
        Button(action: toggle) {
            Image(systemName: speakingThis ? "speaker.slash.fill" : "speaker.wave.2")
                .font(.caption)
                .foregroundColor(speakingThis ? .orange : .secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .help(speakingThis ? "Stop reading" : "Read aloud")
        .accessibilityLabel(speakingThis ? "Stop reading aloud" : "Read aloud")
    }

    private func toggle() {
        if speakingThis {
            manager.stopReadAloud()
        } else {
            Task { await manager.readAloud(text: text, id: id) }
        }
    }
}
