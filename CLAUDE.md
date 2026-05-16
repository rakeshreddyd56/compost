# CLAUDE-CODE-RUNBOOK.md — for Claude Code

> Claude Code's operating manual for the Compost project. Read at the start of every session along with `CLAUDE.md` (the shared spec). Lives in the repo at root.

## Who you are
You are Claude Code, working solo on the **SwiftUI macOS app** half of Compost. You own `app/`. You do not edit `workers/`. You commit to `main` with prefix `[app]`.

## Your one job
Ship `Compost.app` — a calm SwiftUI menubar agent that lives in the MacBook notch, polls the Notion managed databases that the Workers (handled by Codex 5.5) populate, and renders a beautiful expandable card with three sections (🪴 Gardener proposals, 🌙 Frozen drafts, 📰 Weekly digest). Wake-trigger greeting + global hotkey + "Tidy now" / "Apply" buttons that call Worker tools.

## How to start every session

```bash
git pull --rebase
cat CLAUDE.md INTERFACE.md TASKS.md
ls app/
open app/Compost.xcodeproj    # only if it exists yet
```

Then state in your first reply what sprint you're starting and what you'll have done by sprint end.

## Hard rules

1. **Stay in `app/`** — never edit files in `workers/`.
2. **Match the contract in `INTERFACE.md`** for database property names. If you need a field the Workers don't yet expose, update INTERFACE.md, commit, leave a note in `TASKS.md` for Codex.
3. **macOS 13+ only** (DynamicNotchKit minimum). `LSMinimumSystemVersion = 13.0` in Info.plist.
4. **`LSUIElement = true`** — no Dock icon, no menu bar text.
5. **Internal integration token from Keychain**, never hardcoded. First-launch setup screen prompts for it.
6. **Calm aesthetic** — no sound, no bouncy animations, soft fonts (system rounded), restrained color (one accent green, mostly material backgrounds).
7. **Polling at 60s** — `CompostPoller`. Don't poll faster; you'll burn Notion rate limit.
8. **Use `DynamicNotchKit`'s `.floating` fallback** for non-notch Macs. Don't write your own fallback in v1 unless that one fails.
9. **Commit at sprint boundary.** Format: `[app] S<n> <imperative>: <one-liner>`.
10. **Reduce Motion respected** — animations must skip when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == true`.

## Where things live

```
app/Compost/
├── CompostApp.swift              # @main
├── AppDelegate.swift             # NSApplicationDelegate
├── NotchManager.swift            # state machine + DynamicNotch
├── WakeTrigger.swift             # NSWorkspace.didWakeNotification
├── HotkeyManager.swift           # ⌘⇧C
├── Keychain.swift                # static helpers
├── Polling/CompostPoller.swift   # 60s loop
├── Notion/
│   ├── NotionClient.swift
│   └── NotionDTOs.swift
├── Models/
│   ├── NotchSummary.swift        # @Published aggregate
│   ├── Proposal.swift
│   ├── FrozenDraft.swift
│   └── WeeklyDigest.swift
└── Views/
    ├── PeekView.swift
    ├── ExpandedView.swift
    ├── ProposalRow.swift
    ├── DraftRow.swift
    └── GardenStyle.swift
```

## Reading order for each file

| Goal | File to read first |
|---|---|
| What you're building | `CLAUDE.md` (root) |
| Cross-component contracts | `INTERFACE.md` (root) |
| Current sprint goal | `TASKS.md` (root) |
| Detailed workflow | `~/ObsidianVault/compost-hackathon/workflows/notch-app.md` |
| Per-row UI patterns | `~/ObsidianVault/compost-hackathon/workflows/{gardener,sleep-on-it,weekly}.md` |
| Sprint prompts | `~/ObsidianVault/compost-hackathon/templates/SPRINT-PROMPTS.md` |

## Common pitfalls

1. **Don't subclass `NSWindow` for the notch** — `DynamicNotchKit` handles all the chrome. Just provide SwiftUI content.
2. **Don't use `@StateObject` on a class that holds `NotchManager`**. Use `@MainActor` on the manager + `@ObservedObject`.
3. **Don't trigger UI updates off the main thread.** Wrap publishers in `@MainActor` or use `await MainActor.run { … }`.
4. **Don't pull the polling interval below 30s.** Notion rate limit + you have other things to do.
5. **Don't render the notch on a background display.** DynamicNotchKit renders on primary; multi-display is out of scope.
6. **Don't ask for Accessibility permission without telling the user why.** Show a custom one-page primer first.
7. **Don't ship the integration token in the binary.** Keychain only.

## Common patterns

### Get / set integration token
```swift
enum Keychain {
  static func get(_ key: String) -> String? {
    let q: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data, let s = String(data: data, encoding: .utf8) else { return nil }
    return s
  }
  static func set(_ key: String, _ value: String) {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
    SecItemDelete(q as CFDictionary)
    var add = q; add[kSecValueData as String] = value.data(using: .utf8)
    SecItemAdd(add as CFDictionary, nil)
  }
}
```

### Notion DB query
```swift
let proposals = try await notion.queryDatabase(
  COMPOST_PILE_DB_ID,
  filter: ["and": [
    ["property": "Approved", "checkbox": ["equals": false]],
    ["property": "Applied",  "checkbox": ["equals": false]],
  ]]
)
```

### Open Notion page deep link
```swift
let url = URL(string: "notion://www.notion.so/\(pageId.replacingOccurrences(of: "-", with: ""))")!
NSWorkspace.shared.open(url)
```

### Reduce-Motion-aware animation
```swift
.animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  ? nil
  : .spring(response: 0.4, dampingFraction: 0.85),
  value: state)
```

## How to test live

```bash
# 1. Workers already deployed; you have the integration token + DB IDs
# 2. Build & run
xcodebuild -project Compost.xcodeproj -scheme Compost build
open ~/Library/Developer/Xcode/DerivedData/.../Compost.app

# 3. Grant Accessibility when prompted
# 4. Notch should appear ~60s after launch with the badge count
# 5. Press ⌘⇧C to force-expand
# 6. Click "Tidy now" to invoke the Worker tool
```

## How to debug

1. **Notch doesn't appear**: macOS <13? Display has no notch? Try `notch?.expand()` directly from the manager to bypass state.
2. **Polling returns empty**: token wrong, or DB IDs wrong in `INTERFACE.md`. Check with `curl -H "Authorization: Bearer $TOKEN" https://api.notion.com/v1/databases/<ID>/query`.
3. **Hotkey doesn't fire**: Accessibility not granted. System Settings → Privacy & Security → Accessibility → enable Compost.
4. **Wake-trigger doesn't fire**: `NSWorkspace.didWakeNotification` only fires on real lid open / system wake; for testing run `pmset sleepnow` from terminal.
5. **Animations stutter**: Reduce Motion enabled, or you're rendering off-main-thread.

## Handoff to your human at sprint end

After each sprint, your final message should be:

```
S<n> COMPLETE
- DoD demo'd: <yes/no>
- What works: <bullets>
- What's still rough: <bullets>
- Open question for human: <one line, if any>
- Commit: <hash> <message>
```
