//
//  VoiceCaptureHotkey.swift
//  Compost — ⌥⌘V global hotkey (push-to-talk).
//
//  Mirrors HotkeyManager's NSEvent monitor pattern. Holds the key combo →
//  triggers `onPress` once. Releases the key (or modifiers) → `onRelease`.
//  Requires Accessibility permission to fire globally; works locally for
//  preview / testing without it.
//

import AppKit

final class VoiceCaptureHotkey {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private var globalDown: Any?
    private var globalUp: Any?
    private var globalFlags: Any?
    private var localDown: Any?
    private var localUp: Any?
    private var localFlags: Any?
    private var down = false

    // ⌥⌘V — keyCode 9 is "v" on US layout.
    private static let vKeyCode: UInt16 = 9
    private static let requiredFlags: NSEvent.ModifierFlags = [.command, .option]

    init() {
        globalDown = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleDown(e)
        }
        globalUp = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] e in
            self?.handleUp(e)
        }
        globalFlags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e)
        }
        localDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handleDown(e); return e
        }
        localUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] e in
            self?.handleUp(e); return e
        }
        localFlags = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] e in
            self?.handleFlags(e); return e
        }
    }

    private func handleDown(_ e: NSEvent) {
        guard e.keyCode == Self.vKeyCode else { return }
        guard e.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(Self.requiredFlags) else { return }
        guard !down else { return }
        down = true
        onPress?()
    }

    private func handleUp(_ e: NSEvent) {
        guard e.keyCode == Self.vKeyCode, down else { return }
        down = false
        onRelease?()
    }

    private func handleFlags(_ e: NSEvent) {
        // If either modifier drops away mid-hold, treat as release so the
        // recording doesn't keep running silently.
        guard down else { return }
        let masked = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if !masked.contains(Self.requiredFlags) {
            down = false
            onRelease?()
        }
    }

    deinit {
        [globalDown, globalUp, globalFlags, localDown, localUp, localFlags]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
    }
}
