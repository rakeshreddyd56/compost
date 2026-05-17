//
//  Mascot.swift
//  Compost — mascot loader with per-mood assets + idle float + bobble.
//
//  Animations (all gated through GardenStyle.reduceMotion):
//   • Idle float: continuous 4.2s sine bob ±2pt vertical — feels alive at rest
//   • Bobble: one-shot 0.42s spring scale+tilt on mood transition into .alert
//             or any view that sets `bobble: true`
//   • Mood crossfade: 0.24s ease-out when the asset switches
//

import SwiftUI
import AppKit

struct Mascot: View {
    enum Mood: String, CaseIterable {
        case calm     // workspace is empty / idle
        case nudging  // proposals or drafts pending — "look at this"
        case alert    // imminent cue / time-sensitive moment
        case sweep    // Gardener actively running / tidy in flight

        var assetName: String {
            switch self {
            case .calm:    return "MascotCalm"
            case .nudging: return "MascotNudging"
            case .alert:   return "MascotAlert"
            case .sweep:   return "MascotSweep"
            }
        }

        var fallbackSymbol: String {
            switch self {
            case .calm:    return "leaf.fill"
            case .nudging: return "sparkles"
            case .alert:   return "sun.max.fill"
            case .sweep:   return "wand.and.stars.inverse"
            }
        }
    }

    var size: CGFloat = 56
    var mood: Mood = .calm
    var bobble: Bool = false
    var idleFloat: Bool = true

    @State private var bobbleOn = false
    @State private var floatPhase: Double = 0

    var body: some View {
        Group {
            if let nsImage = NSImage(named: mood.assetName) ?? NSImage(named: "Mascot") {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: mood.fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(tint)
            }
        }
        .frame(width: size, height: size)
        .opacity(mood == .calm ? 0.95 : 1.0)
        .modifier(IdleFloat(active: idleFloat))
        .scaleEffect(bobble && bobbleOn ? 1.06 : 1.0)
        .rotationEffect(.degrees(bobble && bobbleOn ? -3.0 : 0))
        .animation(GardenStyle.springExpand, value: bobbleOn)
        .animation(.easeOut(duration: 0.24), value: mood)
        .task(id: bobble) {
            guard bobble, !GardenStyle.reduceMotion else { return }
            bobbleOn = true
            try? await Task.sleep(for: .milliseconds(420))
            bobbleOn = false
        }
        .accessibilityHidden(true)
    }

    private var tint: Color {
        switch mood {
        case .calm, .nudging, .sweep: return GardenStyle.accentGreen
        case .alert:                   return .orange
        }
    }
}

/// Continuous gentle vertical bob via a TimelineView clock. Cheap (60Hz of
/// pure transform math) and respects Reduce Motion via the GardenStyle flag.
private struct IdleFloat: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if !active || GardenStyle.reduceMotion {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let dy = CGFloat(sin(t * 2 * .pi / 4.2) * 2.0)   // ±2pt over 4.2s
                content.offset(y: dy)
            }
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        ForEach(Mascot.Mood.allCases, id: \.self) { mood in
            VStack {
                Mascot(size: 80, mood: mood)
                Text(mood.rawValue).font(.caption2)
            }
        }
    }
    .padding()
    .background(.regularMaterial)
}
