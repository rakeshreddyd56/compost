//
//  DynamicNotchKit.swift
//  Compost — stub for DynamicNotchKit (fallback UI for non-notch Macs)
//

import SwiftUI
import AppKit

private final class CompostNotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// Fallback notch surface used until the full DynamicNotchKit package is wired in.
// It intentionally models the same compact/expanded lifecycle: a persistent
// compact peek panel, plus a larger expanded panel for actions.
@MainActor
public class DynamicNotch<Content: View> {
    private let content: () -> Content
    private var peekPanel: NSPanel?
    private var expandedPanel: NSPanel?

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public func compact() async {
        showPeekPanel()
    }

    public func expand() async {
        hidePeekPanel()
        showExpandedPanel()
    }

    public func hide() async {
        hidePeekPanel()
        hideExpandedPanel()
    }

    private func showPeekPanel() {
        hideExpandedPanel()

        let hostVC = hostedContent()
        let size = fittingSize(
            for: hostVC,
            fallback: NSSize(width: 62, height: 28),
            minimum: NSSize(width: 48, height: 24),
            maximum: NSSize(width: 220, height: 44)
        )
        let panel = peekPanel ?? makePanel()
        panel.contentViewController = hostVC
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.setFrame(topCenteredFrame(size: size, topInset: 8), display: true)
        panel.orderFrontRegardless()
        peekPanel = panel
    }

    private func showExpandedPanel() {
        let hostVC = NSHostingController(rootView: content())
        hostVC.view.wantsLayer = true
        hostVC.view.layer?.backgroundColor = NSColor.clear.cgColor

        let screenFrame = activeScreenFrame()
        let size = fittingSize(
            for: hostVC,
            fallback: NSSize(width: 420, height: 520),
            minimum: NSSize(width: 380, height: 260),
            maximum: NSSize(width: 520, height: min(680, screenFrame.height - 96))
        )
        let panel = expandedPanel ?? makePanel()
        panel.contentViewController = hostVC
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.setFrame(topCenteredFrame(size: size, topInset: 36), display: true)
        panel.makeKeyAndOrderFront(nil)
        expandedPanel = panel
    }

    private func hidePeekPanel() {
        peekPanel?.orderOut(nil)
    }

    private func hideExpandedPanel() {
        expandedPanel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = CompostNotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow
        panel.acceptsMouseMovedEvents = true
        return panel
    }

    private func hostedContent() -> NSHostingController<Content> {
        let hostVC = NSHostingController(rootView: content())
        hostVC.view.wantsLayer = true
        hostVC.view.layer?.backgroundColor = NSColor.clear.cgColor
        return hostVC
    }

    private func fittingSize(
        for hostVC: NSHostingController<Content>,
        fallback: NSSize,
        minimum: NSSize,
        maximum: NSSize
    ) -> NSSize {
        hostVC.view.layoutSubtreeIfNeeded()
        var size = hostVC.view.fittingSize
        if !size.width.isFinite || size.width <= 1 { size.width = fallback.width }
        if !size.height.isFinite || size.height <= 1 { size.height = fallback.height }
        size.width = min(max(size.width, minimum.width), maximum.width)
        size.height = min(max(size.height, minimum.height), maximum.height)
        return size
    }

    private func topCenteredFrame(size: NSSize, topInset: CGFloat) -> NSRect {
        let frame = activeScreenFrame()
        let x = frame.midX - size.width / 2
        let y = frame.maxY - size.height - topInset
        return NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    private func activeScreenFrame() -> NSRect {
        NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }
}
