//
//  VoiceCaptureHotkey.swift
//  Compost — global hotkey ⌘⇧V for push-to-talk voice capture.
//
//  Mirrors HotkeyManager pattern: NSEvent.addGlobalMonitorForEvents +
//  NSEvent.addLocalMonitorForEvents, gated on Accessibility permission.
//
//  Behavior: keyDown fires `onPress`, keyUp fires `onRelease`. The recorder
//  starts on press and stops on release; transcription kicks off in the
//  release handler.
//

import AppKit

final class VoiceCaptureHotkey {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    // ⌘⇧V — keyCode 9 = "v" on US layout
    private static let vKeyCode: UInt16 = 9
    private var pressed = false
    private var globalDown: Any?
    private var globalUp: Any?
    private var localDown: Any?
    private var localUp: Any?

    init() {
        install()
    }

    private func install() {
        globalDown = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e, down: true)
        }
        globalUp = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] e in
            self?.handle(e, down: false)
        }
        localDown = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            self?.handle(e, down: true)
            return e
        }
        localUp = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] e in
            self?.handle(e, down: false)
            return e
        }
    }

    private func handle(_ event: NSEvent, down: Bool) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] else {
            // Modifier released → if we were recording, end it.
            if !down && pressed {
                pressed = false
                onRelease?()
            }
            return
        }
        guard event.keyCode == Self.vKeyCode else { return }
        if down {
            if !pressed {
                pressed = true
                onPress?()
            }
        } else {
            if pressed {
                pressed = false
                onRelease?()
            }
        }
    }

    deinit {
        [globalDown, globalUp, localDown, localUp].compactMap { $0 }.forEach(NSEvent.removeMonitor)
    }
}
