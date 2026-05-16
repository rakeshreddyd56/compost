//
//  CueRow.swift
//  Compost — ☀️ Up next card driven by cueCards
//

import SwiftUI

struct CueRow: View {
    let cue: CueCard
    @ObservedObject var manager: NotchManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(cue.currentHeading.isEmpty ? cue.sourceTitle : cue.currentHeading)
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                if cue.minutesUntilNext > 0 {
                    Text("next in \(cue.minutesUntilNext)m")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(cue.minutesUntilNext < 10 ? GardenStyle.accentGreen : .secondary)
                }
            }

            if !cue.calmCue.isEmpty {
                Text(cue.calmCue)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(3)
            }

            if !cue.nextHeading.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(cue.nextHeading)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GardenStyle.accentGreen.opacity(0.10))
        .cornerRadius(GardenStyle.cornerRadius)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Up next: \(cue.calmCue.isEmpty ? cue.currentHeading : cue.calmCue)")
        .onTapGesture { openSource() }
    }

    private func openSource() {
        let id = cue.sourcePageId.replacingOccurrences(of: "-", with: "")
        guard !id.isEmpty, let url = URL(string: "notion://www.notion.so/\(id)") else { return }
        NSWorkspace.shared.open(url)
    }
}
