//
//  HotkeyManager.swift
//  Compost — ⌘⇧C global hotkey (requires Accessibility permission)
//

import AppKit

final class HotkeyManager {
    var onPressed: (() -> Void)?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    // ⌘⇧C — keyCode 8 = "c" on US layout
    private static let cKeyCode: UInt16 = 8

    init() {
        installMonitors()
    }

    /// True if the process is trusted for input monitoring (Accessibility approval).
    /// When false, the global hotkey will be silent — only the local monitor fires
    /// (when Compost is itself focused, which isn't useful for LSUIElement apps).
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user with the system "Accessibility" dialog and bring them to
    /// System Settings → Privacy & Security → Accessibility.
    static func requestAccessibility() {
        let opts: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSString: true
        ]
        _ = AXIsProcessTrustedWithOptions(opts)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func installMonitors() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] else { return }
        guard event.keyCode == Self.cKeyCode else { return }
        onPressed?()
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}
