//
//  PeekView.swift
//  Compost — collapsed notch badge capsule
//

import SwiftUI

struct PeekView: View {
    let badge: Int
    let imminentCue: Bool   // true when Cue's "minutesUntilNext" < 10 — pulses the leaf
    let offline: Bool       // true when the last poll failed

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.green)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(
                        imminentCue && !GardenStyle.reduceMotion
                            ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                            : .default,
                        value: pulse
                    )
                if offline {
                    Circle()
                        .fill(Color.yellow)
                        .frame(width: 5, height: 5)
                        .offset(x: 3, y: -2)
                        .accessibilityHidden(true)
                }
            }
            Text("\(badge)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(GardenStyle.peekBackground))
        .accessibilityLabel(label)
        .onAppear { if imminentCue { pulse.toggle() } }
        .onChange(of: imminentCue) { on in pulse = on }
    }

    private var label: String {
        var parts = ["Compost: \(badge) item\(badge == 1 ? "" : "s") pending"]
        if imminentCue { parts.append("next moment soon") }
        if offline { parts.append("offline — last sync failed") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    HStack(spacing: 20) {
        PeekView(badge: 3, imminentCue: false, offline: false)
        PeekView(badge: 7, imminentCue: true, offline: false)
        PeekView(badge: 0, imminentCue: false, offline: true)
    }
    .padding()
    .background(Color.gray)
}
