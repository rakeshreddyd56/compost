//
//  CompostApp.swift
//  Compost — macOS notch client
//
//  Entry point. The app is LSUIElement (no Dock icon).
//

import SwiftUI
import AppKit

@main
struct CompostApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No primary window. The app lives in the notch.
        Settings {
            SetupView()
                .frame(width: 420, height: 300)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchManager: NotchManager?
    private var setupWindow: NSWindow?  // retained so the manual setup window survives the launch cycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        // NSLog so the path the launch took shows up in `log stream`.
        let token       = Keychain.get(.notionToken)
        let parentId    = Keychain.get(.parentPageId)
        let compostDbId = Keychain.get(.compostPileDbId)
        let frozenDbId  = Keychain.get(.frozenDraftsDbId)
        let weeklyDbId  = Keychain.get(.weeklyDigestsDbId)
        let cueDbId     = Keychain.get(.cueCardsDbId)
        NSLog("[Compost] keychain state — token:%@ parent:%@ compost:%@ frozen:%@ weekly:%@ cue:%@",
              token        == nil ? "MISSING" : "ok",
              parentId     == nil ? "MISSING" : "ok",
              compostDbId  == nil ? "MISSING" : "ok",
              frozenDbId   == nil ? "MISSING" : "ok",
              weeklyDbId   == nil ? "MISSING" : "ok",
              cueDbId      == nil ? "MISSING" : "ok")

        guard let token, let parentId, let compostDbId, let frozenDbId else {
            NSLog("[Compost] required keychain fields missing — opening SetupView")
            openSetupWindow()
            return
        }
        NSLog("[Compost] credentials ok — starting NotchManager and polling Notion")

        let client = NotionClient(
            token: token,
            ids: NotionDbIds(
                compostPile: compostDbId,
                frozenDrafts: frozenDbId,
                weeklyDigests: Keychain.get(.weeklyDigestsDbId) ?? "",
                cueCards: Keychain.get(.cueCardsDbId) ?? "",
                notionMemory: Keychain.get(.notionMemoryDbId) ?? "",
                parentPage: parentId,
                memoryParentPage: Keychain.get(.memoryParentPageId) ?? ""
            )
        )
        let manager = NotchManager(notion: client)
        self.notchManager = manager
        Task { await manager.start() }
    }

    private func openSetupWindow() {
        // LSUIElement apps have no Dock icon and no menu bar; sendAction(
        // showSettingsWindow:) was getting filtered out, so build the window
        // ourselves and retain it. Dispatch async so AppKit has finished
        // app-launch bookkeeping before we flip the activation policy.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            let host = NSHostingController(rootView: SetupView())
            let window = NSWindow(contentViewController: host)
            window.title = "Compost — first run setup"
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 480, height: 420))
            window.center()
            window.isReleasedWhenClosed = false  // we keep the strong reference
            window.makeKeyAndOrderFront(nil)
            self.setupWindow = window
            NSLog("[Compost] setup window made key+ordered front")
        }
    }
}

struct SetupView: View {
    @State private var token: String = Keychain.get(.notionToken) ?? ""
    @State private var parentId: String = Keychain.get(.parentPageId) ?? ""
    @State private var compostDbId: String = Keychain.get(.compostPileDbId) ?? ""
    @State private var frozenDbId: String = Keychain.get(.frozenDraftsDbId) ?? ""
    @State private var weeklyDigestsDbId: String = Keychain.get(.weeklyDigestsDbId) ?? ""
    @State private var cueCardsDbId: String = Keychain.get(.cueCardsDbId) ?? ""
    @State private var notionMemoryDbId: String = Keychain.get(.notionMemoryDbId) ?? ""
    @State private var memoryParentPageId: String = Keychain.get(.memoryParentPageId) ?? ""
    @State private var trusted: Bool = HotkeyManager.isTrusted

    var body: some View {
        Form {
            Section("Notion integration") {
                SecureField("Integration token (secret_…)", text: $token)
                    .accessibilityLabel("Notion integration token")
                TextField("Parent page ID", text: $parentId)
                    .accessibilityLabel("Notion parent page ID")
            }
            Section("Database IDs (from INTERFACE.md)") {
                TextField("compostPile DB ID", text: $compostDbId)
                TextField("frozenDrafts DB ID", text: $frozenDbId)
                TextField("weeklyDigests DB ID (optional)", text: $weeklyDigestsDbId)
                TextField("cueCards DB ID (optional)", text: $cueCardsDbId)
                TextField("notionMemory DB ID (optional)", text: $notionMemoryDbId)
                TextField("Memory parent page ID (optional, for voice capture)",
                          text: $memoryParentPageId)
            }
            Section("Global hotkey ⌘⇧C") {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundColor(trusted ? .green : .orange)
                    Text(trusted
                        ? "Accessibility granted — hotkey active."
                        : "Compost needs Accessibility to register ⌘⇧C globally.")
                        .font(.callout)
                }
                if !trusted {
                    Button("Open System Settings") {
                        HotkeyManager.requestAccessibility()
                    }
                }
            }
            Button("Save and start") {
                Keychain.set(.notionToken, token)
                Keychain.set(.parentPageId, parentId)
                Keychain.set(.compostPileDbId, compostDbId)
                Keychain.set(.frozenDraftsDbId, frozenDbId)
                Keychain.set(.weeklyDigestsDbId, weeklyDigestsDbId)
                Keychain.set(.cueCardsDbId, cueCardsDbId)
                Keychain.set(.notionMemoryDbId, notionMemoryDbId)
                Keychain.set(.memoryParentPageId, memoryParentPageId)
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.isEmpty || compostDbId.isEmpty || frozenDbId.isEmpty)
        }
        .padding()
        .onAppear { trusted = HotkeyManager.isTrusted }
    }
}
