//
//  HotkeyManager.swift
//  Compost — ⌘⇧C global hotkey monitor
//

import AppKit

final class HotkeyManager {
    var onPressed: (() -> Void)?

    init() {
        // Placeholder: global hotkey setup for Cmd+Shift+C
        // Requires Accessibility permissions; for v1, toggle is optional
        // if hotkey fails to register, user can still use UI buttons
    }

    deinit {
    }
}
