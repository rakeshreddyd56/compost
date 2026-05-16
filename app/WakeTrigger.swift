//
//  WakeTrigger.swift
//  Compost — fires on system wake from sleep (lid open or wake event)
//

import AppKit

final class WakeTrigger {
    var onWake: (() -> Void)?

    init() {
        let center = NSWorkspace.shared.notificationCenter
        // didWakeNotification — full system wake (preferred per workflows/notch-app.md)
        center.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        // screensDidWakeNotification — display wake (also relevant; some Macs only fire this)
        center.addObserver(
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
