//
//  Mascot.swift
//  Compost — first-pass mascot loader.
//
//  Loads "Mascot" from Assets.xcassets. The shipped art is a low-effort sage
//  sprout placeholder; drop a real PNG over Assets.xcassets/Mascot.imageset/
//  mascot{,@2x,@3x}.png to upgrade without touching code. If the asset is
//  missing entirely the view falls back to an SF Symbol so the UI never
//  ships with a broken-image placeholder.
//

import SwiftUI
import AppKit

struct Mascot: View {
    enum Mood {
        case calm     // default — empty workspace, ambient peek
        case nudging  // proposals or drafts pending
        case alert    // imminent cue / something time-sensitive
    }

    var size: CGFloat = 56
    var mood: Mood = .calm

    var body: some View {
        Group {
            if let nsImage = NSImage(named: "Mascot") {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundColor(tint)
            }
        }
        .frame(width: size, height: size)
        .opacity(mood == .calm ? 0.9 : 1.0)
        .accessibilityHidden(true)  // mascot is decorative; label lives on its container
    }

    private var fallbackSymbol: String {
        switch mood {
        case .calm:    return "leaf.fill"
        case .nudging: return "sparkles"
        case .alert:   return "sun.max.fill"
        }
    }

    private var tint: Color {
        switch mood {
        case .calm:    return GardenStyle.accentGreen
        case .nudging: return GardenStyle.accentGreen
        case .alert:   return .orange
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        Mascot(size: 64, mood: .calm)
        Mascot(size: 64, mood: .nudging)
        Mascot(size: 64, mood: .alert)
    }
    .padding()
    .background(.regularMaterial)
}
