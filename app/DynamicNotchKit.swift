//
//  DynamicNotchKit.swift
//  Compost — stub for DynamicNotchKit (fallback UI for non-notch Macs)
//

import SwiftUI
import AppKit

// For v1, we provide a minimal stub that uses a floating window as fallback
public class DynamicNotch<Content: View> {
    private let content: () -> Content
    private var window: NSWindow?

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public func expand() async {
        // Floating window expand
        await MainActor.run {
            showFloatingWindow()
        }
    }

    public func hide() async {
        // Hide floating window
        await MainActor.run {
            hideFloatingWindow()
        }
    }

    private func showFloatingWindow() {
        let hostVC = NSHostingController(rootView: content())
        let w = NSWindow(contentViewController: hostVC)
        w.styleMask = [.titled, .closable]
        w.level = .floating
        w.isOpaque = false
        w.backgroundColor = .clear
        w.setFrame(NSRect(x: NSScreen.main?.frame.midX ?? 400, y: NSScreen.main?.frame.maxY ?? 800, width: 400, height: 400), display: true)
        w.makeKeyAndOrderFront(nil)
        self.window = w
    }

    private func hideFloatingWindow() {
        window?.close()
        window = nil
    }
}
