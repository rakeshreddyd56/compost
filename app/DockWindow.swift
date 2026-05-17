//
//  DockWindow.swift
//  Compost — floating bottom dock that switches the focused notch scene.
//
//  Mirrors the prototype's .dock chrome: a translucent pill-shaped panel
//  with 5 buttons (☀ Cue, 🌙 Drafts, ⚫ Voice, 📷 Photos, ▼ Collapse/Expand).
//  Click → calls into NotchManager.openScene / collapseToHidden.
//

import SwiftUI
import AppKit

/// NSPanel subclass that accepts key events so SwiftUI Buttons hosted
/// inside actually fire. Without this, clicks on the dock pills get
/// swallowed because the panel is `nonactivatingPanel` (which is correct —
/// we don't want clicking the dock to steal focus from the user's app —
/// but we still need clicks to deliver to the buttons themselves).
final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DockWindow {
    private let manager: NotchManager
    private var window: DockPanel?

    init(manager: NotchManager) {
        self.manager = manager
    }

    func install() {
        let host = NSHostingView(rootView: NotchDock(manager: manager))
        host.translatesAutoresizingMaskIntoConstraints = false

        // Measure SwiftUI's intrinsic size so the panel fits the pill exactly.
        let fitting = host.fittingSize
        let size = NSSize(
            width: max(fitting.width, 480),
            height: max(fitting.height, 56)
        )
        host.setFrameSize(size)

        let panel = DockPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hasShadow = false   // SwiftUI draws its own shadow on the pill
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        // Centre horizontally, 28pt off the bottom of the active screen.
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - size.width / 2
            let y = frame.minY + 28
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
        self.window = panel
    }
}

// MARK: - SwiftUI view

struct NotchDock: View {
    @ObservedObject var manager: NotchManager

    var body: some View {
        HStack(spacing: 4) {
            dockButton(.cue,    label: "Cue",    sf: "sun.max.fill")
            dockButton(.drafts, label: "Drafts", sf: "moon.fill")
            dockButton(.voice,  label: "Voice",  sf: "waveform")
            dockButton(.photos, label: "Photos", sf: "photo.on.rectangle.angled")
            divider
            collapseButton
        }
        .padding(6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(red: 0.031, green: 0.035, blue: 0.047).opacity(0.85))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        .padding(12)
        .fixedSize()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 22)
            .padding(.horizontal, 4)
    }

    private func dockButton(_ scene: NotchSurface, label: String, sf: String) -> some View {
        let on = manager.surface == scene && manager.isVisible
        return Button {
            Task { await manager.openScene(scene) }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(on ? GardenStyle.accentGreen : Color.white.opacity(0.06))
                        .frame(width: 22, height: 22)
                    Image(systemName: sf)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(label)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(on ? GardenStyle.sage300 : GardenStyle.ink2)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(on ? GardenStyle.sage400.opacity(0.20) : Color.clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var collapseButton: some View {
        // Dock button reads "Collapse" when the expanded card is up, and
        // "Expand" when the notch is in peek or hidden. Clicking shrinks to
        // peek (or back to full) — never disappears the dock.
        let expanded = manager.isExpanded
        Button {
            Task {
                if expanded {
                    await manager.collapseToHidden()
                } else {
                    await manager.openScene(.summary)
                }
            }
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(GardenStyle.sage400.opacity(0.30))
                        .frame(width: 22, height: 22)
                    Image(systemName: expanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(expanded ? "Collapse" : "Expand")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundColor(GardenStyle.sage300)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .background(Capsule().fill(GardenStyle.sage400.opacity(0.18)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(expanded ? "Collapse notch" : "Expand notch")
    }
}
