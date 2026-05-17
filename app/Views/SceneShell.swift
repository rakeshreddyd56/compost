//
//  SceneShell.swift
//  Compost — shared notch shell for focused scenes (Cue / Drafts / Photos).
//
//  Renders the dark notchBg surface with the standard head row:
//    [mascot] [eyebrow] [title]                          [✕]
//  …and then a child slot. Matches the prototype's `.expanded` layout
//  in styles.css.
//

import SwiftUI

struct SceneShell<Content: View>: View {
    @ObservedObject var manager: NotchManager
    let eyebrow: String
    let title: String
    let mood: Mascot.Mood
    let wide: Bool
    let content: () -> Content

    init(
        manager: NotchManager,
        eyebrow: String,
        title: String,
        mood: Mascot.Mood = .calm,
        wide: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.manager = manager
        self.eyebrow = eyebrow
        self.title = title
        self.mood = mood
        self.wide = wide
        self.content = content
    }

    var body: some View {
        VStack(spacing: GardenStyle.expandedInnerGap) {
            head
            content()
        }
        .padding(.horizontal, GardenStyle.cardPadding)
        .padding(.vertical, 14)
        .frame(width: wide ? GardenStyle.wideWidth : GardenStyle.expandedWidth)
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
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 10) {
            Mascot(size: 36, mood: mood, bobble: mood == .alert)
            VStack(alignment: .leading, spacing: 1) {
                Text(eyebrow)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundColor(GardenStyle.sage300)
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(GardenStyle.ink)
                    .lineLimit(1)
            }
            Spacer()
            Button { Task { await manager.collapseToHidden() } } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(GardenStyle.ink2)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse")
        }
    }
}
