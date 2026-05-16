//
//  WakeTrigger.swift
//  Compost — detect system wake from sleep
//

import AppKit

final class WakeTrigger {
    var onWake: (() -> Void)?

    init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func systemDidWake() {
        onWake?()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
