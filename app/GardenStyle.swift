//
//  GardenStyle.swift
//  Compost — calm design tokens (sage palette, 8pt grid)
//

import SwiftUI
import AppKit

// Numbers reference workflows/notch-app.md "Design language (concrete tokens)"
enum GardenStyle {
    // Color tokens
    static let accentGreen = Color(red: 0x4F / 255, green: 0x79 / 255, blue: 0x42 / 255)  // sage #4F7942
    static let peekBackground = Color.black.opacity(0.75)                                  // capsule peek
    static let sageBackground = Color(red: 0.92, green: 0.95, blue: 0.92)
    static let materialGray = Color(red: 0.95, green: 0.95, blue: 0.96)

    // Geometry
    static let cardCornerRadius: CGFloat = 14
    static let cornerRadius: CGFloat = 8
    static let peekCornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 16
    static let spacing: CGFloat = 6
    static let rowGap: CGFloat = 8
    static let sectionGap: CGFloat = 12
    static let expandedWidth: CGFloat = 380

    // Motion — workflows/notch-app.md spring tokens
    static var spring: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .linear(duration: 0)
            : .spring(response: 0.4, dampingFraction: 0.85)
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}
