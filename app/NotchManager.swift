//
//  NotchManager.swift
//  Compost
//
//  State machine that wraps DynamicNotchKit and orchestrates Wake / Hotkey / Polling.
//

import SwiftUI
import AppKit
import Combine

enum NotchState: Equatable {
    case hidden
    case peek(badge: Int)
    case expanding
    case expanded
    case retracting
}

/// Identifies an in-flight worker action so the row showing the trigger can
/// render a spinner / disabled state without other rows reacting.
enum InflightAction: Hashable {
    case tidyNow
    case applyApproved
    case applyProposal(String)   // per-proposal apply, keyed by proposalId
    case reviewDraft(String)
    case voiceCapture
    case tagMemory(String)       // memory item id
    case rephraseDraft(String, String) // (draftId, lowercase tone)
}

/// One-shot success ping consumed by the view layer to flash a brief "✓ done"
/// affordance after a worker tool call returns.
enum SuccessPing: Equatable {
    case tidied
    case applied
    case proposalApplied(String) // payload = proposal title for the pip text
    case reviewed(String)
    case voiceCaptured(String)   // transcript preview
    case memoryTagged(String, String)  // (memory title, tag)
    case workspaceRefreshed      // tidyNow + refreshBridge both ok
}

/// What's filling the expanded card right now. The dock switches between
/// these focused scenes; `summary` is the default at-a-glance card.
enum NotchSurface: Equatable {
    case summary
    case cue
    case drafts
    case voice
    case photos
}

@MainActor
final class NotchManager: ObservableObject {
    @Published private(set) var state: NotchState = .hidden
    @Published private(set) var summary: NotchSummary = .empty
    @Published private(set) var hasLoadedOnce: Bool = false
    @Published private(set) var inflight: Set<InflightAction> = []
    @Published private(set) var lastSuccess: SuccessPing?
    @Published private(set) var lastActionError: String?
    /// Inline error attached to a single proposal so the failing row can show
    /// what the worker said. Keyed by proposalId. Cleared on the next refresh
    /// that returns the proposal (so the same id keeps the error until either
    /// the user retries successfully or the row vanishes).
    @Published private(set) var proposalErrors: [String: String] = [:]
    /// Same pattern for Sleep-On-It draft review failures, keyed by draft.id
    /// (the Notion page id of the frozenDrafts row).
    @Published private(set) var draftErrors: [String: String] = [:]
    @Published private(set) var memoryErrors: [String: String] = [:]

    // Voice surface state. The voice flow is fire-and-forget per
    // press/release; the view observes these to render.
    @Published private(set) var surface: NotchSurface = .summary
    @Published private(set) var voiceStage: VoiceStage = .idle
    @Published private(set) var voiceTranscript: String = ""
    @Published private(set) var voiceReply: String = ""
    @Published private(set) var voiceMode: String = ""     // "general" | "briefing" | "memory" | "draft"
    @Published private(set) var voiceUsedMemory: Bool = false
    @Published private(set) var voiceAmplitude: Float = 0

    let notion: NotionClient
    private var notch: DynamicNotch<AnyView>?
    private let poller: CompostPoller
    private let wake: WakeTrigger
    private let hotkey: HotkeyManager
    private let voiceHotkey: VoiceCaptureHotkey
    private let voice: VoiceClient
    private var hasAutoGreetedFirstLoad = false
    private var voiceTask: Task<Void, Never>?
    private var ampTimer: Task<Void, Never>?
    private static let resolvedDraftIdsKey = "compost.resolvedDraftIds"
    private var resolvedDraftIds: Set<String>
    // Optimistic-hide for proposals: when applyProposal returns ok, we drop
    // the row from the visible summary immediately so the user gets a clean
    // "removed" beat instead of waiting for the next poller tick. Stored in
    // UserDefaults so a restart mid-demo doesn't resurrect just-applied rows.
    private static let resolvedProposalIdsKey = "compost.resolvedProposalIds"
    private var resolvedProposalIds: Set<String>
    // Notion Worker sync data-source properties can be read-only to tool calls.
    // rephraseDraft still returns the real Worker rewrite, so keep those tone
    // variants locally and overlay them on the next poll instead of pretending
    // the DB persisted a field it rejected.
    private static let localDraftRewriteVariantsKey = "compost.localDraftRewriteVariants"
    private var localDraftRewriteVariants: [String: [String: String]]
    private var userCollapsed = false
    private var previousSurfaceBeforeVoice: NotchSurface?

    init(notion: NotionClient, voice: VoiceClient = AppleVoiceClient()) {
        self.notion = notion
        self.poller = CompostPoller(client: notion)
        self.wake = WakeTrigger()
        self.hotkey = HotkeyManager()
        self.voiceHotkey = VoiceCaptureHotkey()
        self.voice = voice
        self.resolvedDraftIds = Set(UserDefaults.standard.stringArray(forKey: Self.resolvedDraftIdsKey) ?? [])
        self.resolvedProposalIds = Set(UserDefaults.standard.stringArray(forKey: Self.resolvedProposalIdsKey) ?? [])
        self.localDraftRewriteVariants = Self.loadLocalDraftRewriteVariants()
    }

    func start() async {
        // Build the notch with a SwiftUI router view that observes self.
        notch = DynamicNotch { [weak self] in
            AnyView(ContentRouter(manager: self ?? NotchManager.preview))
        }

        await poller.start { [weak self] s in
            Task { await self?.applySummary(s) }
        }
        wake.onWake = { [weak self] in
            Task { await self?.greet() }
        }
        hotkey.onPressed = { [weak self] in
            Task { await self?.toggle() }
        }
        voiceHotkey.onPress = { [weak self] in
            Task { await self?.beginVoiceCapture() }
        }
        voiceHotkey.onRelease = { [weak self] in
            Task { await self?.endVoiceCapture() }
        }
    }

    // MARK: - Voice surface

    /// Push-to-talk start. Switches into voice mode, starts the recorder
    /// immediately, then returns. The actual transcription runs in
    /// `endVoiceCapture` when the user releases ⌥⌘V — that's what was
    /// missing before (the old path slept for a fixed 8s regardless of
    /// release, so most captures were padded with silence and the
    /// recognizer returned empty).
    func beginVoiceCapture() async {
        guard voiceStage != .listening, voiceStage != .transcribing else { return }
        userCollapsed = false
        if surface != .voice { previousSurfaceBeforeVoice = surface }
        surface = .voice
        voiceStage = .listening
        voiceTranscript = ""
        voiceReply = ""
        if state != .expanded {
            transition(to: .expanding)
            await notch?.expand()
            transition(to: .expanded)
        }

        // Kick the recorder. If permissions are missing we surface the error
        // immediately rather than waiting for a release that produces nothing.
        do {
            try await voice.startListening()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            voiceStage = .failed(msg)
            NSLog("[CompostAction] voiceCapture startListening failed: %@", msg)
            return
        }

        // Amplitude polling — drives the waveform envelope while held.
        ampTimer?.cancel()
        ampTimer = Task { [weak self] in
            while let self, !Task.isCancelled {
                let stillListening = await MainActor.run { self.voiceStage == .listening }
                guard stillListening else { break }
                let amp = (self.voice as? AppleVoiceClient)?.currentAmplitude() ?? 0
                await MainActor.run { self.voiceAmplitude = amp }
                try? await Task.sleep(nanoseconds: 50_000_000) // ~20 fps
            }
        }
    }

    /// Call the Worker `voiceReply` tool with the recognised transcript +
    /// a compact summary snapshot, then speak the response via the local
    /// TTS. We pass `mode=nil` so the Worker picks the right mode itself.
    private func requestVoiceReply(for transcript: String) async {
        guard !transcript.trimmingCharacters(in: .whitespaces).isEmpty else {
            await MainActor.run { self.voiceStage = .finished(transcript) }
            return
        }
        if await routeLocalVoiceCommand(transcript) {
            return
        }
        let payload: [String: Any] = [
            "transcript": transcript,
            "mode": NSNull(),
            "context": compactSummaryContext(),
        ]
        do {
            let data = try await notion.invokeTool("voiceReply", input: payload)
            let parsed = try Self.parseVoiceReply(data)
            await MainActor.run {
                self.voiceReply = parsed.reply
                self.voiceMode = parsed.mode
                self.voiceUsedMemory = parsed.usedMemory
                self.voiceStage = .speaking(parsed.reply)
            }
            // Speak the reply via the local Apple TTS. We swallow speak errors
            // since the user has the transcript on screen either way.
            try? await voice.speak(text: parsed.reply)
            await MainActor.run {
                if case .speaking = self.voiceStage {
                    self.voiceStage = .finished(parsed.reply)
                }
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            await MainActor.run { self.voiceStage = .replyFailed(msg) }
            NSLog("[CompostAction] voiceReply failed: %@", msg)
        }
    }

    private struct LocalVoiceRoute {
        let scene: NotchSurface
        let reply: String
        let mode: String
        let usedMemory: Bool
    }

    /// Tiny deterministic router for demo-critical navigation phrases. This
    /// keeps "show me photos" / "read drafts" snappy and reliable even if the
    /// assistant reply takes longer than the scene switch should.
    private func routeLocalVoiceCommand(_ transcript: String) async -> Bool {
        // Action intents first (tidy / refresh / collapse). These fire a real
        // worker call or notch-state change instead of switching scenes.
        if let action = Self.localVoiceAction(for: transcript) {
            let reply = action.reply
            voiceReply = reply
            voiceMode = "general"
            voiceUsedMemory = false
            voiceStage = .speaking(reply)
            NSLog("[CompostAction] voiceAction[%@] -> %@", transcript, action.kind.rawValue)
            try? await voice.speak(text: reply)
            switch action.kind {
            case .tidy:     await refreshAll()
            case .collapse: await collapseToHidden()
            }
            if case .speaking = voiceStage { voiceStage = .finished(reply) }
            return true
        }

        // Scene navigation. Navigate FIRST for instant visual feedback,
        // then ask the Worker `voiceReply` tool for a real grounded
        // description of what's on the scene (e.g. "5 photos from yesterday:
        // a Compost bin at Pier 9, Salesforce Tower, …") and speak that.
        guard let route = Self.localVoiceRoute(for: transcript) else { return false }
        voiceMode = route.mode
        voiceUsedMemory = route.usedMemory
        NSLog("[CompostAction] voiceRoute[%@] -> %@", transcript, String(describing: route.scene))
        await showRoutedScene(route.scene)

        // Render the canned reply immediately as a holding line so the
        // user sees feedback while the Worker round-trip runs.
        voiceReply = route.reply
        voiceStage = .replying

        let payload: [String: Any] = [
            "transcript": transcript,
            "mode": route.mode,
            "context": sceneContextString(for: route.scene),
        ]
        let finalReply: String
        do {
            let data = try await notion.invokeTool("voiceReply", input: payload)
            let parsed = try Self.parseVoiceReply(data)
            finalReply = parsed.reply
            await MainActor.run {
                self.voiceReply = parsed.reply
                self.voiceMode = parsed.mode
                self.voiceUsedMemory = parsed.usedMemory
                self.voiceStage = .speaking(parsed.reply)
            }
        } catch {
            // Worker failed — fall back to the canned reply so the user still
            // gets audio feedback, but record the error in the action log.
            NSLog("[CompostAction] voiceReply(routed) failed: %@", String(describing: error))
            finalReply = route.reply
            await MainActor.run {
                self.voiceStage = .speaking(route.reply)
            }
        }
        try? await voice.speak(text: finalReply)
        await MainActor.run {
            if case .speaking = self.voiceStage {
                self.voiceStage = .finished(finalReply)
            }
        }
        return true
    }

    /// Scene-specific context for `voiceReply`. Each scene gets the data the
    /// Worker needs to describe it accurately — photo captions for memory,
    /// draft titles for drafts, etc. Never leaks row IDs or full bodies.
    private func sceneContextString(for scene: NotchSurface) -> String {
        switch scene {
        case .photos:
            let photos = summary.memoryPhotos.prefix(8)
            if photos.isEmpty { return "memory_photos=0" }
            let items = photos.enumerated().map { (i, p) -> String in
                let cap = p.caption.isEmpty ? p.title : p.caption
                let when = p.timeLabel()
                let place = p.tags.first(where: { !$0.lowercased().hasPrefix("compost-") }) ?? ""
                var parts = ["#\(i+1): \(cap)"]
                if !when.isEmpty { parts.append("when=\(when)") }
                if !place.isEmpty { parts.append("place=\(place)") }
                return parts.joined(separator: ", ")
            }.joined(separator: " | ")
            return "memory_photos=\(photos.count); \(items)"

        case .drafts:
            let drafts = summary.drafts.prefix(3)
            if drafts.isEmpty { return "drafts=0" }
            let items = drafts.map { d -> String in
                "\(d.title) [tone=\(d.activeTone)]"
            }.joined(separator: " | ")
            return "drafts=\(drafts.count); \(items)"

        case .cue:
            guard let cue = summary.currentCue else { return "cue=none" }
            let head = cue.currentHeading.isEmpty ? cue.sourceTitle : cue.currentHeading
            return "cue=\(head); in \(cue.minutesUntilNext)m; calm_cue=\(cue.calmCue.prefix(140))"

        case .summary, .voice:
            return compactSummaryContext()
        }
    }

    private struct LocalVoiceAction {
        enum Kind: String { case tidy, collapse }
        let kind: Kind
        let reply: String
    }

    private static func localVoiceAction(for transcript: String) -> LocalVoiceAction? {
        let s = transcript
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if s.range(of: #"\b(tidy|tidy up|refresh|refresh tidy|clean up|garden)\b"#, options: .regularExpression) != nil {
            return LocalVoiceAction(kind: .tidy, reply: "Refreshing tidy proposals.")
        }
        if s.range(of: #"\b(collapse|hide|close|go away|dismiss)\b"#, options: .regularExpression) != nil {
            return LocalVoiceAction(kind: .collapse, reply: "Collapsing the notch.")
        }
        return nil
    }

    private static func localVoiceRoute(for transcript: String) -> LocalVoiceRoute? {
        // Strip punctuation + lowercase so "show me, photos" matches "photos".
        let s = transcript
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // Photos / memory pile
        if s.range(of: #"\b(photo|photos|picture|pictures|memory|memories|slideshow|pile)\b"#, options: .regularExpression) != nil {
            return LocalVoiceRoute(
                scene: .photos,
                reply: "Opening your photo memories.",
                mode: "memory",
                usedMemory: true
            )
        }
        // Drafts
        if s.range(of: #"\b(draft|drafts|rewrite|rewrites|sleep on it|morning review)\b"#, options: .regularExpression) != nil {
            return LocalVoiceRoute(
                scene: .drafts,
                reply: "Opening drafts on ice.",
                mode: "draft",
                usedMemory: false
            )
        }
        // Cue / next briefing
        if s.contains("what did i miss")
            || s.range(of: #"\b(cue|brief|briefing|calendar|meeting|next|invite|agenda)\b"#, options: .regularExpression) != nil {
            return LocalVoiceRoute(
                scene: .cue,
                reply: "Opening your next briefing.",
                mode: "briefing",
                usedMemory: false
            )
        }
        // Summary / everything
        if s.range(of: #"\b(summary|everything|home|workspace|what is pending|whats pending)\b"#, options: .regularExpression) != nil {
            return LocalVoiceRoute(
                scene: .summary,
                reply: "Here is your workspace summary.",
                mode: "general",
                usedMemory: false
            )
        }
        return nil
    }

    private func showRoutedScene(_ scene: NotchSurface) async {
        ampTimer?.cancel()
        ampTimer = nil
        previousSurfaceBeforeVoice = nil
        surface = scene
        if state != .expanded {
            transition(to: .expanding)
            await notch?.expand()
            transition(to: .expanded)
        }
    }

    /// Demo-safe typed/quick-action voice route. It uses the same Worker
    /// `voiceReply` path as speech recognition, but avoids depending on the
    /// Mac microphone permission during a recorded demo.
    func askCompost(_ prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        userCollapsed = false
        if surface != .voice { previousSurfaceBeforeVoice = surface }
        surface = .voice
        voiceTranscript = trimmed
        voiceReply = ""
        voiceMode = ""
        voiceUsedMemory = false
        voiceStage = .replying
        if state != .expanded {
            transition(to: .expanding)
            await notch?.expand()
            transition(to: .expanded)
        }
        await requestVoiceReply(for: trimmed)
    }

    /// Compact, secret-free summary blob passed as `context` to the Worker.
    /// Single string per the contract; counts + the current cue headline
    /// only, so the Worker can ground the reply without us leaking row IDs
    /// or full draft bodies.
    private func compactSummaryContext() -> String {
        var parts: [String] = []
        if let cue = summary.currentCue {
            let head = cue.currentHeading.isEmpty ? cue.sourceTitle : cue.currentHeading
            parts.append("cue=\(head) in \(cue.minutesUntilNext)m")
        }
        parts.append("tidy=\(summary.proposalCount)")
        parts.append("drafts=\(summary.draftCount)")
        parts.append("memory=\(summary.memoryCount)")
        return parts.joined(separator: "; ")
    }

    private struct VoiceReplyResult {
        let ok: Bool
        let reply: String
        let mode: String
        let usedMemory: Bool
    }

    private static func parseVoiceReply(_ data: Data) throws -> VoiceReplyResult {
        // ntn CLI sometimes prepends diagnostics; pull the last JSON object.
        let raw: Any? = (try? JSONSerialization.jsonObject(with: data))
            ?? jsonObjectFromTail(data)
        guard let dict = raw as? [String: Any] else {
            throw NotionError.toolFailed("voiceReply: malformed response")
        }
        let ok = (dict["ok"] as? Bool) ?? false
        if !ok {
            throw NotionError.toolFailed((dict["error"] as? String) ?? "voiceReply returned ok=false")
        }
        guard let reply = dict["reply"] as? String, !reply.isEmpty else {
            throw NotionError.toolFailed("voiceReply: empty reply")
        }
        return VoiceReplyResult(
            ok: true,
            reply: reply,
            mode: (dict["mode"] as? String) ?? "general",
            usedMemory: (dict["usedMemory"] as? Bool) ?? false
        )
    }

    private static func jsonObjectFromTail(_ data: Data) -> Any? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        var searchEnd = s.endIndex
        while let r = s.range(of: "{", options: .backwards, range: s.startIndex..<searchEnd) {
            let candidate = String(s[r.lowerBound...])
            if let d = candidate.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) {
                return obj
            }
            searchEnd = r.lowerBound
        }
        return nil
    }

    /// Call the Worker `rephraseDraft` tool. Maps the UI's capitalised
    /// tone name to the lowercase contract value, drops the returned rewrite
    /// into the visible summary so the diff pane swaps instantly.
    func rephraseDraft(_ draft: FrozenDraft, displayTone: String) async {
        let lower = displayTone.lowercased()
        let action = InflightAction.rephraseDraft(draft.id, lower)
        draftErrors.removeValue(forKey: draft.id)
        inflight.insert(action)
        defer { inflight.remove(action) }

        do {
            let data = try await notion.invokeTool("rephraseDraft", input: [
                "draftId": draft.id,
                "tone": lower,
            ])
            let parsed = try Self.parseRephrase(data)
            applyRephrase(draftId: draft.id, displayTone: displayTone, rewrite: parsed)
            NSLog("[CompostAction] rephraseDraft[%@/%@] success", draft.id, lower)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            draftErrors[draft.id] = msg
            NSLog("[CompostAction] rephraseDraft[%@/%@] failed: %@", draft.id, lower, msg)
        }
    }

    private static func parseRephrase(_ data: Data) throws -> String {
        let raw: Any? = (try? JSONSerialization.jsonObject(with: data))
            ?? jsonObjectFromTail(data)
        guard let dict = raw as? [String: Any] else {
            throw NotionError.toolFailed("rephraseDraft: malformed response")
        }
        let ok = (dict["ok"] as? Bool) ?? false
        if !ok {
            throw NotionError.toolFailed((dict["error"] as? String) ?? "rephraseDraft returned ok=false")
        }
        guard let rewrite = dict["rewrite"] as? String, !rewrite.isEmpty else {
            throw NotionError.toolFailed("rephraseDraft: empty rewrite")
        }
        return rewrite
    }

    /// Optimistic local update so the UI swaps immediately. The next
    /// poll will re-read the canonical Worker-managed properties.
    private func applyRephrase(draftId: String, displayTone: String, rewrite: String) {
        guard let idx = summary.drafts.firstIndex(where: { $0.id == draftId }) else { return }
        localDraftRewriteVariants[draftId, default: [:]][displayTone] = rewrite
        localDraftRewriteVariants[draftId, default: [:]]["__activeTone"] = displayTone
        persistLocalDraftRewriteVariants()

        var updated = summary.drafts
        updated[idx].rewrites[displayTone] = rewrite
        updated[idx].activeTone = displayTone
        let visible = NotchSummary(
            proposalCount: summary.proposalCount,
            proposals: summary.proposals,
            draftCount: updated.count,
            drafts: updated,
            digestReady: summary.digestReady,
            digestUrl: summary.digestUrl,
            currentCue: summary.currentCue,
            memoryCount: summary.memoryCount,
            memory: summary.memory,
            lastError: summary.lastError
        )
        summary = visible
    }

    private static func loadLocalDraftRewriteVariants() -> [String: [String: String]] {
        guard let data = UserDefaults.standard.data(forKey: localDraftRewriteVariantsKey),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func persistLocalDraftRewriteVariants() {
        guard let data = try? JSONEncoder().encode(localDraftRewriteVariants) else { return }
        UserDefaults.standard.set(data, forKey: Self.localDraftRewriteVariantsKey)
    }

    /// Push-to-talk end. Stops the recorder, runs recognition, then either
    /// hands the transcript to the local router (photos / drafts / cue /
    /// tidy / collapse) or — for anything else — to the Worker `voiceReply`
    /// tool for a grounded answer + TTS speakback.
    func endVoiceCapture() async {
        guard voiceStage == .listening else { return }
        voiceStage = .transcribing
        ampTimer?.cancel()
        ampTimer = nil
        voiceAmplitude = 0

        voiceTask?.cancel()
        voiceTask = Task { [weak self] in
            guard let self else { return }
            let text: String
            do {
                text = try await self.voice.stopAndTranscribe()
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                await MainActor.run { self.voiceStage = .failed(msg) }
                NSLog("[CompostAction] voiceCapture stopAndTranscribe failed: %@", msg)
                return
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                self.voiceTranscript = trimmed
                self.lastSuccess = .voiceCaptured(trimmed)
            }
            NSLog("[CompostAction] voiceCapture transcript: %@", trimmed.isEmpty ? "(empty)" : trimmed)
            if trimmed.isEmpty {
                // Nothing heard — set finished so the UI shows the empty
                // state instead of staying stuck on "transcribing".
                await MainActor.run { self.voiceStage = .finished("") }
                return
            }
            await self.requestVoiceReply(for: trimmed)
        }
    }

    /// Exit voice mode and restore the summary surface. Called by the
    /// "Tap to end" button and by quick-action routing.
    func exitVoice() {
        voiceTask?.cancel(); voiceTask = nil
        ampTimer?.cancel(); ampTimer = nil
        voice.stopSpeaking()
        voiceStage = .idle
        voiceTranscript = ""
        voiceAmplitude = 0
        surface = previousSurfaceBeforeVoice ?? .summary
        previousSurfaceBeforeVoice = nil
    }

    /// Dock-driven scene navigation. Switches the focused surface and
    /// ensures the notch is expanded. Voice gets a special path that
    /// starts capture; the others just slot the matching view into the
    /// expanded shell.
    func openScene(_ scene: NotchSurface) async {
        userCollapsed = false
        if scene == .voice {
            await beginVoiceCapture()
            return
        }
        // If we were in voice mode, tear it down before switching.
        if surface == .voice {
            voiceTask?.cancel(); voiceTask = nil
            ampTimer?.cancel(); ampTimer = nil
            voice.stopSpeaking()
            voiceStage = .idle
            voiceTranscript = ""
            voiceAmplitude = 0
            previousSurfaceBeforeVoice = nil
        }
        surface = scene
        if state != .expanded {
            transition(to: .expanding)
            await notch?.expand()
            transition(to: .expanded)
        }
    }

    /// Dock-driven collapse. Shrinks the notch back to the peek capsule so
    /// the user still has a visible leaf badge they can tap to expand, and
    /// the floating dock stays in place. Only fully hides the notch when
    /// there is genuinely nothing pending.
    func collapseToHidden() async {
        userCollapsed = true
        if surface == .voice { exitVoice() }
        surface = .summary
        let total = summary.proposalCount + summary.draftCount + summary.memoryCount + (summary.digestReady ? 1 : 0)
        if total > 0 {
            transition(to: .peek(badge: total))
            await notch?.compact()
        } else {
            await notch?.hide()
            transition(to: .hidden)
        }
    }

    var isVisible: Bool {
        switch state {
        case .hidden: return false
        default: return true
        }
    }

    /// Whether the expanded card is up (vs collapsed to peek or hidden).
    /// Dock uses this to flip Collapse ↔ Expand.
    var isExpanded: Bool {
        switch state {
        case .expanded, .expanding: return true
        default: return false
        }
    }

    // MARK: - Memory tagging

    /// Append a tag to a notionMemory row directly via the Notion API.
    /// No worker tool involvement — this is a pure metadata write the user
    /// already has permission for via the integration token.
    func tagMemory(_ item: MemoryItem, tag: String) async {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let action = InflightAction.tagMemory(item.id)
        memoryErrors.removeValue(forKey: item.id)
        inflight.insert(action)
        defer { inflight.remove(action) }

        do {
            _ = try await notion.appendMemoryTag(pageId: item.id, tag: trimmed)
            lastSuccess = .memoryTagged(item.title, trimmed)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if case .memoryTagged = self?.lastSuccess { self?.lastSuccess = nil }
            }
            await poller.refreshNow()
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            memoryErrors[item.id] = msg
        }
    }

    // MARK: - State transitions

    private func applySummary(_ s: NotchSummary) async {
        let visibleDrafts = s.drafts
            .filter { !resolvedDraftIds.contains($0.id) }
            .map { draft in
                var merged = draft
                if let local = localDraftRewriteVariants[draft.id] {
                    for (tone, rewrite) in local where tone != "__activeTone" && !rewrite.isEmpty {
                        merged.rewrites[tone] = rewrite
                    }
                    if let active = local["__activeTone"], !active.isEmpty {
                        merged.activeTone = active
                    }
                }
                return merged
            }
        let visibleProposals = s.proposals.filter {
            // Optimistic-hide: drop rows we already applied this session.
            // Keyed by proposalId (the worker addresses by Proposal ID, not
            // page id) so the right row vanishes even if Notion takes a tick
            // to reflect Applied=true.
            !resolvedProposalIds.contains($0.proposalId)
        }
        let visible = NotchSummary(
            proposalCount: visibleProposals.count,
            proposals: visibleProposals,
            draftCount: visibleDrafts.count,
            drafts: visibleDrafts,
            digestReady: s.digestReady,
            digestUrl: s.digestUrl,
            currentCue: s.currentCue,
            memoryCount: s.memory.count,
            memory: s.memory,
            lastError: s.lastError
        )

        summary = visible
        if visible.lastError == nil { hasLoadedOnce = true }
        // Drop stale per-proposal errors for proposals that are no longer
        // in the summary (applied, archived, or otherwise gone).
        let liveProposalIds = Set(visible.proposals.map { $0.proposalId })
        proposalErrors = proposalErrors.filter { liveProposalIds.contains($0.key) }
        // Garbage-collect resolvedProposalIds against the raw (pre-filter) list
        // so we don't accumulate forever — once Notion stops returning the row
        // we can forget we ever hid it.
        let rawProposalIds = Set(s.proposals.map { $0.proposalId })
        let pruned = resolvedProposalIds.filter { rawProposalIds.contains($0) }
        if pruned != resolvedProposalIds {
            resolvedProposalIds = pruned
            UserDefaults.standard.set(Array(resolvedProposalIds), forKey: Self.resolvedProposalIdsKey)
        }
        let liveDraftIds = Set(visible.drafts.map { $0.id })
        draftErrors = draftErrors.filter { liveDraftIds.contains($0.key) }
        let liveLocalVariants = localDraftRewriteVariants.filter { liveDraftIds.contains($0.key) }
        if liveLocalVariants.count != localDraftRewriteVariants.count {
            localDraftRewriteVariants = liveLocalVariants
            persistLocalDraftRewriteVariants()
        }
        let liveMemoryIds = Set(visible.memory.map { $0.id })
        memoryErrors = memoryErrors.filter { liveMemoryIds.contains($0.key) }
        let total = visible.proposalCount + visible.draftCount + visible.memoryCount + (visible.digestReady ? 1 : 0)
        if total == 0 {
            if case .peek = state {
                await notch?.hide()
                transition(to: .hidden)
            }
            return
        }
        if userCollapsed {
            return
        }

        let shouldAutoGreet = !hasAutoGreetedFirstLoad
        hasAutoGreetedFirstLoad = true

        switch state {
        case .hidden, .retracting:
            transition(to: .peek(badge: total))
            await notch?.compact()
        case .peek:
            transition(to: .peek(badge: total))
            await notch?.compact()
        case .expanding, .expanded:
            break
        }

        if shouldAutoGreet {
            Task { @MainActor [weak self] in
                await self?.greet()
            }
        }
    }

    func greet() async {
        guard summary.hasAnything, !userCollapsed else { return }
        transition(to: .expanding)
        await notch?.expand()
        transition(to: .expanded)
        try? await Task.sleep(for: .seconds(4))
        if state == .expanded { await retract() }
    }

    func toggle() async {
        switch state {
        case .hidden, .peek: await expand()
        case .expanded:      await retract()
        case .expanding, .retracting: break
        }
    }

    func tidyNow() async {
        await runAction(.tidyNow, success: .tidied) {
            _ = try await self.notion.invokeTool("tidyNow", input: [:])
        }
    }

    /// "Refresh" button. Fires `tidyNow({})` and the fast bridge refresh for
    /// memory. Cue remains Worker-sync-managed; the Notion sync or a manual
    /// `ntn workers sync trigger cue` publishes those rows.
    /// in parallel and aggregates the result. Semantics are honest:
    ///   • tidyNow failure → red error, no success ping
    ///   • refreshBridge ok=false with non-empty errors → red error
    ///   • refreshBridge ok=true with informational notes (the expected
    ///     "Cue Cards are Worker-sync managed…" beat) → logged only, NOT
    ///     surfaced as a UI error.
    /// Either tool returning ok still triggers a poller refresh so the
    /// memory/tidy sections visibly update on the next tick.
    func refreshAll() async {
        let action = InflightAction.tidyNow
        inflight.insert(action)
        defer { inflight.remove(action) }

        async let tidyResult: Result<Void, Error> = doInvoke("tidyNow", input: [:])
        async let bridgeResult: Result<BridgeReply, Error> = doInvokeBridge()
        let (tidy, bridge) = await (tidyResult, bridgeResult)

        var errors: [String] = []
        if case .failure(let e) = tidy {
            errors.append("Tidy: \((e as? LocalizedError)?.errorDescription ?? String(describing: e))")
        }
        if case .failure(let e) = bridge {
            errors.append("Bridge: \((e as? LocalizedError)?.errorDescription ?? String(describing: e))")
        }
        if case .success(let br) = bridge {
            if !br.ok && !br.errors.isEmpty {
                errors.append("Bridge: \(br.errors.joined(separator: "; "))")
            }
            // Notes (e.g. "Cue Cards are Worker-sync managed…") are
            // expected, not errors. Log + move on.
            for note in br.notes {
                NSLog("[CompostAction] refreshBridge note: %@", note)
            }
        }

        if errors.isEmpty {
            lastActionError = nil
            lastSuccess = .workspaceRefreshed
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.lastSuccess == .workspaceRefreshed { self?.lastSuccess = nil }
            }
        } else {
            lastSuccess = nil
            lastActionError = "Refresh failed: \(errors.joined(separator: " · "))"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                if self?.lastActionError != nil { self?.lastActionError = nil }
            }
        }

        await poller.refreshNow()
    }

    private func doInvoke(_ tool: String, input: [String: Any]) async -> Result<Void, Error> {
        do {
            _ = try await notion.invokeTool(tool, input: input)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private struct BridgeReply {
        let ok: Bool
        let errors: [String]
        let notes: [String]
    }

    private func doInvokeBridge() async -> Result<BridgeReply, Error> {
        do {
            let data = try await notion.invokeTool("refreshBridge", input: ["surface": "memory"])
            return .success(Self.parseBridge(data))
        } catch {
            return .failure(error)
        }
    }

    private static func parseBridge(_ data: Data) -> BridgeReply {
        let raw: Any? = (try? JSONSerialization.jsonObject(with: data))
            ?? jsonObjectFromTail(data)
        guard let dict = raw as? [String: Any] else {
            return BridgeReply(ok: true, errors: [], notes: [])
        }
        let ok = (dict["ok"] as? Bool) ?? true
        let errs = (dict["errors"] as? [String])
            ?? (dict["errors"] as? [Any])?.compactMap { $0 as? String }
            ?? []
        // The Worker may include a single "note" field (per the cue-sync
        // case) or a "notes" array. Accept either; both are informational.
        var notes: [String] = []
        if let n = dict["note"] as? String, !n.isEmpty { notes.append(n) }
        if let arr = dict["notes"] as? [String] { notes.append(contentsOf: arr) }
        return BridgeReply(ok: ok, errors: errs, notes: notes)
    }

    func applyApproved() async {
        await runAction(.applyApproved, success: .applied) {
            _ = try await self.notion.invokeTool("applyApproved", input: [:])
        }
    }

    func reviewDraft(draftId: String, approve: Bool) async {
        let action = InflightAction.reviewDraft(draftId)
        let success = SuccessPing.reviewed(draftId)
        // Clear the stale error eagerly — the user just chose to retry, so
        // the red banner should vanish the moment the spinner appears, not
        // wait for the next refresh.
        draftErrors.removeValue(forKey: draftId)
        inflight.insert(action)
        defer { inflight.remove(action) }

        do {
            _ = try await notion.invokeTool("reviewDraft", input: [
                "draftId": draftId,
                "decision": approve ? "approve" : "reject",
            ])
            markDraftResolved(draftId)
            lastActionError = nil
            lastSuccess = success
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.lastSuccess == success { self?.lastSuccess = nil }
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription
                  ?? String(describing: error)
            draftErrors[draftId] = msg
            lastSuccess = nil
        }

        await poller.refreshNow()
    }

    private func markDraftResolved(_ draftId: String) {
        guard !draftId.isEmpty else { return }
        resolvedDraftIds.insert(draftId)
        UserDefaults.standard.set(Array(resolvedDraftIds), forKey: Self.resolvedDraftIdsKey)
    }

    private func markProposalResolved(_ proposalId: String) {
        guard !proposalId.isEmpty else { return }
        resolvedProposalIds.insert(proposalId)
        UserDefaults.standard.set(Array(resolvedProposalIds), forKey: Self.resolvedProposalIdsKey)
        // Republish so the row disappears immediately rather than waiting
        // for the next poll cycle.
        let visible = NotchSummary(
            proposalCount: summary.proposals.filter { $0.proposalId != proposalId }.count,
            proposals: summary.proposals.filter { $0.proposalId != proposalId },
            draftCount: summary.draftCount,
            drafts: summary.drafts,
            digestReady: summary.digestReady,
            digestUrl: summary.digestUrl,
            currentCue: summary.currentCue,
            memoryCount: summary.memoryCount,
            memory: summary.memory,
            lastError: summary.lastError
        )
        summary = visible
    }

    /// Approve and apply a single proposal in one click. Calls the Worker
    /// `applyProposal` tool with the proposal's stable id, tracks per-row
    /// inflight state, and writes any worker error into `proposalErrors[pid]`
    /// so the failing row can render the message inline. Per task: "Do not
    /// fake success" — only a clean tool return sets `lastSuccess`.
    func applyProposal(_ proposal: Proposal) async {
        let pid = proposal.proposalId
        guard !pid.isEmpty else {
            // Without a stable id we can't address the row server-side.
            proposalErrors[proposal.id] = "Missing Proposal ID — cannot apply"
            return
        }

        let action = InflightAction.applyProposal(pid)
        let success = SuccessPing.proposalApplied(proposal.title)
        // Clear the stale error eagerly so the red banner doesn't linger
        // while the user is watching the spinner on a retry.
        proposalErrors.removeValue(forKey: pid)
        inflight.insert(action)
        defer { inflight.remove(action) }

        do {
            _ = try await notion.invokeTool("applyProposal", input: ["proposalId": pid])
            markProposalResolved(pid)
            lastActionError = nil
            lastSuccess = success
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.lastSuccess == success { self?.lastSuccess = nil }
            }
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription
                  ?? String(describing: error)
            proposalErrors[pid] = msg
            lastSuccess = nil
        }

        await poller.refreshNow()
    }

    /// Wrap a worker tool call with inflight tracking. Only sets `lastSuccess`
    /// when the body returns without throwing. A throw goes into
    /// `lastActionError` so the UI can show a red pip instead of a misleading
    /// green ✓. Either way we trigger an immediate refresh so the badge
    /// reflects whatever (if anything) the tool changed.
    private func runAction(_ action: InflightAction,
                           success: SuccessPing,
                           body: () async throws -> Void) async {
        inflight.insert(action)
        defer { inflight.remove(action) }

        do {
            try await body()
            lastActionError = nil
            lastSuccess = success
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if self?.lastSuccess == success { self?.lastSuccess = nil }
            }
        } catch {
            lastSuccess = nil
            lastActionError = Self.describeActionError(error, for: action)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                if self?.lastActionError != nil { self?.lastActionError = nil }
            }
        }

        // Always refresh — even on failure — so the user sees the real state.
        await poller.refreshNow()
    }

    private static func describeActionError(_ error: Error, for action: InflightAction) -> String {
        let verb: String = {
            switch action {
            case .tidyNow:         return "Tidy"
            case .applyApproved:   return "Apply"
            case .applyProposal:   return "Apply"
            case .reviewDraft:     return "Review"
            case .voiceCapture:    return "Voice capture"
            case .tagMemory:       return "Tag memory"
            case .rephraseDraft:   return "Rephrase"
            }
        }()
        let detail = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return "\(verb) failed: \(detail)"
    }

    private func expand() async {
        userCollapsed = false
        transition(to: .expanding)
        await notch?.expand()
        transition(to: .expanded)
    }

    private func retract() async {
        transition(to: .retracting)
        let total = summary.proposalCount + summary.draftCount + summary.memoryCount + (summary.digestReady ? 1 : 0)
        if total > 0 {
            transition(to: .peek(badge: total))
            await notch?.compact()
        } else {
            await notch?.hide()
            transition(to: .hidden)
        }
    }

    private func transition(to s: NotchState) { state = s }

    // MARK: - Previews

    static var preview: NotchManager {
        let client = NotionClient(token: "", ids: .empty)
        return NotchManager(notion: client)
    }
}

struct ContentRouter: View {
    @ObservedObject var manager: NotchManager
    var body: some View {
        switch manager.state {
        case .hidden, .retracting:
            EmptyView()
        case .peek(let badge):
            PeekView(
                badge: badge,
                // imminent only when we have a real positive countdown <10m;
                // 0/missing means the row had no Minutes Until Next value
                imminentCue: {
                    let m = manager.summary.currentCue?.minutesUntilNext ?? 0
                    return m > 0 && m < 10
                }(),
                offline: manager.summary.lastError != nil
            )
            .contentShape(Capsule())
            .onTapGesture {
                Task { await manager.toggle() }
            }
            .help("Open Compost")
            .accessibilityAddTraits(.isButton)
        case .expanding, .expanded:
            switch manager.surface {
            case .voice:   VoiceView(manager: manager)
            case .summary: ExpandedView(manager: manager)
            case .cue:     CueScene(manager: manager)
            case .drafts:  DraftsScene(manager: manager)
            case .photos:  PhotosScene(manager: manager)
            }
        }
    }
}
