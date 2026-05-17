# SwiftUI Mapping — Compost Notch v0.5

> Per-file diff plan for `compost/app/`. Use this together with the
> per-scenario specs in `../scenarios/`.

## High-level order

1. **Tokens first** — extend `GardenStyle.swift`
2. **Models next** — extend `NotchSummary.swift`, add `Photo`
3. **Manager** — extend `NotchManager.swift` with new actions
4. **Views** — refine Cue + Drafts, add Voice + Photos
5. **Wake** — extend `WakeTrigger.swift` for voice hotkey

## `GardenStyle.swift` — extend

Add new color tokens and motion presets. Keep existing names untouched.

```swift
enum GardenStyle {
    // ── existing ──────────────────────────────────────────
    static let accentGreen = Color(red: 0x4F / 255, green: 0x79 / 255, blue: 0x42 / 255)
    static let peekBackground = Color.black.opacity(0.75)
    static let sageBackground = Color(red: 0.92, green: 0.95, blue: 0.92)
    static let materialGray = Color(red: 0.95, green: 0.95, blue: 0.96)
    // ... existing geometry, motion tokens ...

    // ── v0.5 additions ────────────────────────────────────

    // Sage scale
    static let sage900 = Color(hex: "#1f2e18")
    static let sage700 = Color(hex: "#3a5d2f")
    static let sage500 = Color(hex: "#6a9258")
    static let sage400 = Color(hex: "#87a877")
    static let sage300 = Color(hex: "#b9d0ac")

    // Secondary accents
    static let accentGold  = Color(hex: "#c9a85a")  // Photos sighting dots, tags
    static let accentRose  = Color(hex: "#d77a6b")  // Voice live indicator, shouty diff
    static let accentAmber = Color(hex: "#f0a444")  // Drafts review chip

    // Inks (on dark notch surface)
    static let ink  = Color(hex: "#f4f4ee")
    static let ink2 = ink.opacity(0.74)
    static let ink3 = ink.opacity(0.50)
    static let ink4 = ink.opacity(0.30)

    static let card    = Color.white.opacity(0.05)
    static let cardHi  = Color.white.opacity(0.08)
    static let hair    = Color.white.opacity(0.10)

    static let notchBg = Color(hex: "#050608")

    // Geometry additions
    static let peekR = 16.0
    static let expandedR = 22.0
    static let wideR = 22.0
    static let peekPadV = 6.0
    static let peekPadH = 14.0
    static let expandedInnerGap = 10.0
    static let actionRowGap = 6.0

    // Motion presets
    static var springExpand: Animation {
        reduceMotion ? .linear(duration: 0)
                     : .interactiveSpring(response: 0.55, dampingFraction: 0.78)
    }
    static var springCollapse: Animation {
        reduceMotion ? .linear(duration: 0)
                     : .interactiveSpring(response: 0.40, dampingFraction: 0.85)
    }
    static var pulse: Animation {
        reduceMotion ? .default
                     : .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
    }
    static var glow: Animation {
        reduceMotion ? .default
                     : .easeInOut(duration: 2.5).repeatForever(autoreverses: true)
    }
}

// Color(hex:) helper — add to a Color+Hex extension file if not already present
```

## `Models/NotchSummary.swift` — extend

Add `Photo` and extend `NotchSummary` + `FrozenDraft`.

```swift
struct NotchSummary {
    // existing
    let proposalCount: Int
    let proposals: [Proposal]
    let draftCount: Int
    let drafts: [FrozenDraft]
    let digestReady: Bool
    let digestUrl: URL?
    let currentCue: CueCard?
    let lastError: String?

    // v0.5 additions
    let memoryPileCount: Int
    let memoryPile: [Photo]

    var hasAnything: Bool {
        proposalCount + draftCount + memoryPileCount + (digestReady ? 1 : 0) > 0
    }
}

// CueCard already exists. v0.5 reads two more derived fields:
//   - attendees: [Attendee]  (parsed from Calendar block, or nil)
//   - meetUrl:   URL?        (Google Meet link, if present in source page)
extension CueCard {
    struct Attendee {
        let name: String
        let email: String
        let accepted: Bool
    }
    // Parse from the page's Calendar block. Optional — fallback to no row.
}

struct FrozenDraft: Identifiable {
    // existing fields...
    let original: String

    // v0.5: switch from a single string to per-tone variants.
    // Keep `rewrite: String` for back-compat but make it computed.
    let rewrites: [String: String]   // ["Calmer": "...", "Crisp": "...", ...]
    var activeTone: String           // "Calmer" | "Crisp" | "Diplomatic"
    var rewrite: String { rewrites[activeTone] ?? "" }

    init?(_ page: NotionPage) {
        // ... existing parsing
        // Parse Rewrite Variants (a JSON rich_text field — propose in INTERFACE.md)
        // Fall back to a single-key dictionary keyed by "Calmer" if absent
    }
}

struct Photo: Identifiable {
    let id: String              // Notion page id
    let photoId: String         // sha1(assetUri + ISO timestamp)
    let caption: String
    let place: String
    let time: Date
    let lat: Double?
    let lng: Double?
    let assetUrl: URL           // signed file_url from Notion
    let tags: [String]
    let mascotReaction: MascotReaction?

    enum MascotReaction: String {
        case selfSighting = "self-sighting"
        case delighted
        case nostalgic
    }

    init?(_ page: NotionPage) {
        // mirror Proposal.init pattern — read rich_text, number, date, files, multi_select
    }

    // Convenience: human-readable time label
    func timeLabel(now: Date = Date()) -> String {
        // "yesterday · 2:58 PM" / "today · 9:14 AM" / "May 12 · 5:02 PM"
    }
}
```

## `NotchManager.swift` — extend

Add actions and `inflight` cases for the new tools. Follow the
existing per-row error pattern (`proposalErrors`, `draftErrors`).

```swift
extension NotchManager {
    enum InflightAction: Hashable {
        case tidyNow
        case applyApproved
        case applyProposal(String)
        case reviewDraft(String)
        // v0.5 additions
        case rephraseDraft(String, String)    // (draftId, tone)
        case tagPhoto(String, String)         // (photoId, tag)
        case voiceQuery                       // single-shot LLM call
    }

    // Per-row errors (new)
    @Published var photoErrors: [String: String] = [:]

    // Voice mode UI state
    @Published var voiceController: VoiceController?

    func rephraseDraft(draftId: String, tone: String) async {
        inflight.insert(.rephraseDraft(draftId, tone))
        defer { inflight.remove(.rephraseDraft(draftId, tone)) }
        do {
            let result = try await notion.callTool(
                "rephraseDraft",
                payload: ["draftId": draftId, "tone": tone]
            )
            if let idx = summary.drafts.firstIndex(where: { $0.id == draftId }) {
                var d = summary.drafts[idx]
                d.activeTone = tone
                summary.drafts[idx] = d
            }
            draftErrors[draftId] = nil
            lastSuccess = .reviewed
        } catch {
            draftErrors[draftId] = error.localizedDescription
        }
    }

    func tagPhoto(_ photo: Photo, tag: String) async {
        inflight.insert(.tagPhoto(photo.photoId, tag))
        defer { inflight.remove(.tagPhoto(photo.photoId, tag)) }
        do {
            let result = try await notion.callTool(
                "tagPhoto",
                payload: ["photoId": photo.photoId, "tag": tag]
            )
            photoErrors[photo.photoId] = nil
            lastSuccess = .photoTagged(photo.place, tag)
        } catch {
            photoErrors[photo.photoId] = error.localizedDescription
        }
    }

    /// Switch the notch into voice mode. Stores the previous surface so
    /// we can restore it when voice ends.
    func enterVoice(prefilledScript: VoiceScript? = nil) {
        savedSurface = currentSurface
        currentSurface = .voice
        voiceController = VoiceController(prefilledScript: prefilledScript)
        voiceController?.start()
    }
    func exitVoice() {
        voiceController?.stop()
        voiceController = nil
        currentSurface = savedSurface ?? .summary
    }
}

extension SuccessPing {
    case photoTagged(_ place: String, _ tag: String)
}

enum VoiceScript: Equatable {
    case freeform
    case photos  // pre-primes the LLM context with the memory pile
    case drafts  // pre-primes with frozen drafts
}
```

## `Views/CueRow.swift` — refine

Refactor to the new expanded card layout in `scenarios/01-cue.md`:
- Hero time strip with 30pt rounded bold time + countdown pill
- **Gmail / Calendar invite row** — a single-row card with the Gmail
  glyph, "From Calendar via Gmail" label, attendee list, and a
  "Join Meet" button on the right
  - Render only if `cue.attendees` or `cue.meetUrl` is non-nil
  - Tapping Join Meet opens `cue.meetUrl` in default browser, or
  - Falls back to a `meet.google.com/lookup/{calendar event id}` URL
- Body line from `calmCue` (italic on `*foo*` segments)
- Prep checklist parsed from `currentBullets`
- Action row: `↗ Open in Notion` + `Snooze 5m` + `Ask Compost ↗`
  (last one calls `manager.enterVoice(prefilledScript: nil)`)
- Right-aligned meta: `[!cue] · {sourceTitle}`

The Gmail glyph: don't inline an SVG — load a tiny `gmail-logo.pdf`
or `gmail-logo@2x.png` into `Assets.xcassets` (the prototype's SVG is
illustrative, not for shipping). 16pt rendered size.

The Google Meet glyph: same — `meet-logo` asset. 12pt rendered.

### Calendar parsing helper

```swift
extension CueCard {
    /// Parse attendees + meet URL from the source Notion page's calendar block.
    /// Notion calendar blocks expose attendees and conferencing in the page
    /// properties; check the embed type before reading.
    static func enrichFromCalendarBlock(_ page: NotionPage) -> (attendees: [Attendee], meetUrl: URL?) {
        // ...
    }
}
```

## `Views/DraftRow.swift` — refine

Major refactor:
- Move the diff pane from the optional "Compare" toggle to always-on
  side-by-side
- Add tone picker row
- Wire `Use {tone}` button to call `manager.rephraseDraft` then
  `manager.reviewDraft(draftId:approve:true)`

The `ToneDiff` rendering logic in the existing file is great — keep it.
Add "↻ rephrase" pill that calls `rephraseDraft` with the *current*
tone (re-rolls within the same tone).

## `Views/VoiceView.swift` — new

```swift
struct VoiceView: View {
    @ObservedObject var manager: NotchManager
    @ObservedObject var voice: VoiceController

    var body: some View {
        HStack(spacing: 14) {
            mascotSlot
            VStack(alignment: .leading, spacing: 8) {
                stageLabel
                transcript
                Waveform(active: voice.stage != .idle, color: stageColor)
                quickActions
            }
        }
        .padding(GardenStyle.cardPadding)
    }

    private var quickActions: some View {
        HStack(spacing: 6) {
            QuickPill("What did I miss?") {
                manager.exitVoice(); manager.openSummary()
            }
            QuickPill("Read drafts") {
                manager.exitVoice(); manager.openDrafts()
            }
            QuickPill("Show photos") {
                manager.exitVoice(); manager.openPhotos()
            }
            Spacer()
            Button("Tap to end") { manager.exitVoice() }
                .buttonStyle(.plain)
                .foregroundColor(GardenStyle.ink3)
        }
    }
}

final class VoiceController: ObservableObject {
    enum Stage { case listening, thinking, speaking, idle }
    @Published var stage: Stage = .listening
    @Published var transcript: String = ""
    @Published var amplitude: Float = 0          // 0-1, drives Waveform envelope

    private let recognizer = SFSpeechRecognizer(locale: .current)
    private let synthesizer = AVSpeechSynthesizer()
    private var audioEngine: AVAudioEngine?
    private let script: VoiceScript

    init(prefilledScript: VoiceScript? = nil) {
        self.script = prefilledScript ?? .freeform
    }

    func start() { /* setup mic + recognizer */ }
    func stop()  { /* teardown */ }

    func handleFinalTranscript(_ text: String) async {
        stage = .thinking
        let response = await claude.complete(
            system: voiceSystemPrompt(for: script, summary: manager.summary),
            user: text
        )
        stage = .speaking
        await typeOutAndSpeak(response)
        stage = .idle
        // Auto-collapse after 4s
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        manager.exitVoice()
    }
}

struct Waveform: View {
    let active: Bool
    let color: Color
    let amplitude: Float
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0/30.0)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            Canvas { gc, size in
                let barCount = 42
                let gap: CGFloat = 3
                let barW: CGFloat = max(2, (size.width - CGFloat(barCount - 1) * gap) / CGFloat(barCount))
                for i in 0..<barCount {
                    let envelope = sin(Double(i) / Double(barCount - 1) * .pi)
                    let v = active
                        ? envelope * (0.4 + 0.6 * abs(sin(t * 8 + Double(i) * 0.4)))
                        : 0.1
                    let h = max(2, v * Double(size.height) * (active ? Double(amplitude * 0.5 + 0.5) : 1))
                    let x = CGFloat(i) * (barW + gap)
                    let y = (size.height - h) / 2
                    let rect = CGRect(x: x, y: y, width: barW, height: h)
                    gc.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                }
            }
            .frame(height: 26)
        }
    }
}
```

## `Views/PhotosView.swift` — new

Slideshow with navigation arrows, dot indicator, mascot speech bubble
overlay, and tag input.

```swift
struct PhotosView: View {
    @ObservedObject var manager: NotchManager
    @State private var idx: Int = 0
    @State private var playing: Bool = true
    @State private var tagOpen: Bool = false
    @State private var tagInput: String = ""

    private var photos: [Photo] { manager.summary.memoryPile }
    private var photo: Photo? { photos[safe: idx] }

    var body: some View {
        VStack(alignment: .leading, spacing: GardenStyle.expandedInnerGap) {
            header
            viewer
            dots
            actions
        }
        .frame(width: 540)
        .padding(GardenStyle.cardPadding)
        .onReceive(autoAdvanceTimer) { _ in if playing { next() } }
    }

    private var viewer: some View {
        ZStack(alignment: .topLeading) {
            // Photo with crossfade
            AsyncImage(url: photo?.assetUrl) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.black
            }
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: GardenStyle.cardCornerRadius))
            .overlay(prevNextArrows, alignment: .center)
            .overlay(captionStrip, alignment: .bottom)
            .overlay(playPauseButton, alignment: .topTrailing)
            .id(photo?.id)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.22), value: idx)

            // Mascot speech bubble — only when photo.mascotReaction != nil
            if let reaction = photo?.mascotReaction {
                MascotBubble(reaction: reaction)
                    .padding(.top, 10).padding(.leading, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(photos.indices, id: \.self) { i in
                Button {
                    idx = i
                } label: {
                    Capsule()
                        .fill(dotColor(at: i))
                        .frame(width: i == idx ? 18 : 6, height: 6)
                        .animation(GardenStyle.springExpand, value: idx)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo \(i + 1) of \(photos.count)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func dotColor(at i: Int) -> Color {
        if i == idx { return GardenStyle.sage400 }
        if photos[i].mascotReaction != nil { return GardenStyle.accentGold.opacity(0.55) }
        return Color.white.opacity(0.20)
    }
}

struct MascotBubble: View {
    let reaction: Photo.MascotReaction
    private var text: String {
        switch reaction {
        case .selfSighting: return "yes — that's me! the bin at Pier 9. logged it."
        case .delighted:    return "this one's good. tag it for the moodboard?"
        case .nostalgic:    return "oh — this was the day Maya joined."
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("🌱")
            Text(text)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundColor(GardenStyle.sage300)
                .lineLimit(3)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Color(hex: "#142013").opacity(0.92))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GardenStyle.sage400.opacity(0.4), lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}
```

## `Views/ExpandedView.swift` — refine

Add a "Memory pile" section between "Drafts on ice" and "Sunday digest"
**when the summary surface is showing** (i.e. NOT during voice mode):

```swift
if manager.summary.memoryPileCount > 0 {
    sectionLabel("📷 Memory pile · this week")
    Button {
        manager.openPhotos()
    } label: {
        MemoryPileTeaser(photos: manager.summary.memoryPile.prefix(3))
    }
}
```

Order in expanded list:
1. ☀ Up next (cue)
2. 🪴 Tidy (proposals)
3. 🌙 Drafts on ice
4. 📷 Memory pile    ← new
5. 📰 Sunday digest

The voice surface **replaces** the entire expanded body during voice
mode — not a section.

## `Views/PeekView.swift` — refine

Make the peek content **scenario-aware**. Add an enum that decides
what to show, based on what's pending in `NotchSummary`:

```swift
enum PeekVariant {
    case cue(CueCard)
    case voice                  // voice mode is overriding
    case photos(Photo)          // most-recent self-sighting photo wins priority
    case drafts(count: Int)
    case proposals(count: Int)
    case combined(badge: Int)   // fallback: original "leaf + count"
}
```

Priority order (most urgent first):
1. `.voice` — voice mode is live
2. `.cue` — within 30 min
3. `.photos` — at least one **self-sighting** photo logged today
4. `.drafts` — count > 0
5. `.cue` — within 24 hours (lower priority)
6. `.proposals` — count > 0
7. `.photos` — generic memory pile bump
8. `.combined` — default

Each variant renders its own peek layout per the scenario specs.

## `WakeTrigger.swift` — extend

Add a registered hotkey for voice mode.

```swift
extension WakeTrigger {
    static let voiceHotkey: KeyCombo = .init(.v, modifiers: [.option, .command])

    func registerVoiceHotkey(_ onTrigger: @escaping () -> Void) {
        // Carbon RegisterEventHotKey, or a SwiftUI-friendly wrapper
    }
}
```

The handler should:
1. Save current notch state (peek / expanded)
2. Call `NotchManager.enterVoice()`
3. When voice ends, restore previous state via `exitVoice()`

## `Info.plist` — add

Microphone + speech recognition entitlements:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Compost listens for short voice commands when you press ⌥⌘V. Audio is not stored.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Compost transcribes your spoken question to find what's on the pile. Transcripts are not stored.</string>
```

## Testing fixtures

Add a `Previews/MockData.swift` (if not already present) with sample
photos and tone-rich drafts so each new view has a real preview.
Reuse the same sample data the HTML prototype uses (see
`prototype/scenes.jsx` near the `PHOTOS` and `DRAFTS` constants):

```swift
extension Photo {
    static let dustbin = Photo(
        id: "preview-dustbin",
        photoId: "ph_dustbin",
        caption: "saw your logo on a bin at Pier 9 ☺",
        place: "Pier 9 cafeteria",
        time: ISO8601DateFormatter().date(from: "2026-05-15T14:58:00Z")!,
        lat: 37.799, lng: -122.398,
        assetUrl: Bundle.main.url(forResource: "photo-dustbin", withExtension: "jpeg")!,
        tags: ["compost-sighting", "lol"],
        mascotReaction: .selfSighting
    )!
    static let samples: [Photo] = [ /* mirror prototype's 5-photo set */ ]
}
```

Include the 5 sample photos from `prototype/assets/` in
`Assets.xcassets/Photos/` as `.imageset`s with the same filenames
prefixed `photo-` so previews work without a network round-trip.
