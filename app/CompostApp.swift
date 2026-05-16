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

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let token = Keychain.get(.notionToken),
              let parentId = Keychain.get(.parentPageId),
              let compostDbId = Keychain.get(.compostPileDbId),
              let frozenDbId = Keychain.get(.frozenDraftsDbId)
        else {
            openSetupWindow()
            return
        }

        let client = NotionClient(
            token: token,
            ids: NotionDbIds(
                compostPile: compostDbId,
                frozenDrafts: frozenDbId,
                weeklyDigests: Keychain.get(.weeklyDigestsDbId) ?? "",
                cueCards: Keychain.get(.cueCardsDbId) ?? "",
                parentPage: parentId
            )
        )
        let manager = NotchManager(notion: client)
        self.notchManager = manager
        Task { await manager.start() }
    }

    private func openSetupWindow() {
        // For S1 the user can paste creds via SettingsView (cmd+,).
        // For later: open setup explicitly here.
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SetupView: View {
    @State private var token: String = Keychain.get(.notionToken) ?? ""
    @State private var parentId: String = Keychain.get(.parentPageId) ?? ""
    @State private var compostDbId: String = Keychain.get(.compostPileDbId) ?? ""
    @State private var frozenDbId: String = Keychain.get(.frozenDraftsDbId) ?? ""
    @State private var weeklyDigestsDbId: String = Keychain.get(.weeklyDigestsDbId) ?? ""
    @State private var cueCardsDbId: String = Keychain.get(.cueCardsDbId) ?? ""
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
                NSApp.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .disabled(token.isEmpty || compostDbId.isEmpty || frozenDbId.isEmpty)
        }
        .padding()
        .onAppear { trusted = HotkeyManager.isTrusted }
    }
}
