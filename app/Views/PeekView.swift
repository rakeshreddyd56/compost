//
//  PeekView.swift
//  Compost — collapsed notch badge capsule
//

import SwiftUI

struct PeekView: View {
    let badge: Int
    let imminentCue: Bool  // true when Cue's "minutesUntilNext" < 10 — pulses the leaf

    @State private var pulse: Bool = false

    var body: some View {
        HStack(spacing: 6) {
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
            Text("\(badge)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(GardenStyle.peekBackground))
        .accessibilityLabel("Compost: \(badge) item\(badge == 1 ? "" : "s") pending\(imminentCue ? ", next moment soon" : "")")
        .onAppear { if imminentCue { pulse.toggle() } }
        .onChange(of: imminentCue) { on in pulse = on }
    }
}

#Preview {
    HStack(spacing: 20) {
        PeekView(badge: 3, imminentCue: false)
        PeekView(badge: 7, imminentCue: true)
    }
    .padding()
    .background(Color.gray)
}
