//
//  GardenStyle.swift
//  Compost — calm design tokens (sage palette, 8pt grid)
//

import SwiftUI
import AppKit

enum GardenStyle {
    // ── existing ────────────────────────────────────────────
    static let accentGreen = Color(red: 0x4F / 255, green: 0x79 / 255, blue: 0x42 / 255)
    static let peekBackground = Color.black.opacity(0.75)
    static let sageBackground = Color(red: 0.92, green: 0.95, blue: 0.92)
    static let materialGray = Color(red: 0.95, green: 0.95, blue: 0.96)

    static let cardCornerRadius: CGFloat = 14
    static let cornerRadius: CGFloat = 8
    static let peekCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 16
    static let spacing: CGFloat = 6
    static let rowGap: CGFloat = 8
    static let sectionGap: CGFloat = 12
    static let expandedWidth: CGFloat = 380

    static var spring: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .linear(duration: 0)
            : .spring(response: 0.4, dampingFraction: 0.85)
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // ── v0.5 sage scale ──────────────────────────────────────
    static let sage900 = Color(hex: "#1f2e18")
    static let sage700 = Color(hex: "#3a5d2f")
    static let sage500 = Color(hex: "#6a9258")
    static let sage400 = Color(hex: "#87a877")
    static let sage300 = Color(hex: "#b9d0ac")
    static let sage100 = Color(hex: "#e3edd8")

    // ── v0.5 secondary accents ───────────────────────────────
    static let accentGold  = Color(hex: "#c9a85a")
    static let accentRose  = Color(hex: "#d77a6b")
    static let accentAmber = Color(hex: "#f0a444")

    // ── v0.5 inks (on dark notch surface) ────────────────────
    static let ink  = Color(hex: "#f4f4ee")
    static var ink2: Color { ink.opacity(0.74) }
    static var ink3: Color { ink.opacity(0.50) }
    static var ink4: Color { ink.opacity(0.30) }

    static let card   = Color.white.opacity(0.05)
    static let cardHi = Color.white.opacity(0.08)
    static let hair   = Color.white.opacity(0.10)

    static let notchBg = Color(hex: "#050608")

    // ── v0.5 geometry ────────────────────────────────────────
    static let peekR: CGFloat = 16
    static let expandedR: CGFloat = 22
    static let wideR: CGFloat = 22
    static let peekPadV: CGFloat = 6
    static let peekPadH: CGFloat = 14
    static let expandedInnerGap: CGFloat = 10
    static let actionRowGap: CGFloat = 6
    static let wideWidth: CGFloat = 540

    // ── v0.5 motion presets ──────────────────────────────────
    static var springExpand: Animation {
        reduceMotion ? .linear(duration: 0)
                     : .interactiveSpring(response: 0.55, dampingFraction: 0.78)
    }
    static var springCollapse: Animation {
        reduceMotion ? .linear(duration: 0)
                     : .interactiveSpring(response: 0.40, dampingFraction: 0.85)
    }
    static var pulse: Animation {
        reduceMotion ? .default
                     : .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    }
    static var glow: Animation {
        reduceMotion ? .default
                     : .easeInOut(duration: 2.5).repeatForever(autoreverses: true)
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&v)
        let r, g, b, a: Double
        switch trimmed.count {
        case 6:
            r = Double((v & 0xFF0000) >> 16) / 255
            g = Double((v & 0x00FF00) >> 8) / 255
            b = Double(v & 0x0000FF) / 255
            a = 1
        case 8:
            r = Double((v & 0xFF000000) >> 24) / 255
            g = Double((v & 0x00FF0000) >> 16) / 255
            b = Double((v & 0x0000FF00) >> 8) / 255
            a = Double(v & 0x000000FF) / 255
        default:
            r = 1; g = 0; b = 1; a = 1   // magenta = "you typed it wrong"
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
