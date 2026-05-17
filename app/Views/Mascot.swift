//
//  Mascot.swift
//  Compost — mascot loader with per-mood assets + graceful fallbacks.
//
//  Lookup chain for each mood:
//    1. Mood-specific asset (MascotCalm / MascotNudging / MascotAlert /
//       MascotSweep) — newest art for that emotional beat.
//    2. Canonical "Mascot" asset — safe default if the mood art is missing.
//    3. SF Symbol — ultimate fallback so the bundle never ships a broken
//       image placeholder.
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
        .accessibilityHidden(true)  // decorative; the container reads its own label
    }

    private var tint: Color {
        switch mood {
        case .calm, .nudging, .sweep: return GardenStyle.accentGreen
        case .alert:                   return .orange
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
