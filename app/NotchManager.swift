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

/// What's filling the expanded card right now. The voice surface replaces
/// the standard expanded view instead of being a section, so the manager
/// owns this enum directly.
enum NotchSurface: Equatable {
    case summary
    case voice
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

    init(notion: NotionClient, voice: VoiceClient = AppleVoiceClient()) {
        self.notion = notion
        self.poller = CompostPoller(client: notion)
        self.wake = WakeTrigger()
        self.hotkey = HotkeyManager()
        self.voiceHotkey = VoiceCaptureHotkey()
        self.voice = voice
        self.resolvedDraftIds = Set(UserDefaults.standard.stringArray(forKey: Self.resolvedDraftIdsKey) ?? [])
        self.resolvedProposalIds = Set(UserDefaults.standard.stringArray(forKey: Self.resolvedProposalIdsKey) ?? [])
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

    /// Push-to-talk start. Switches the expanded card into voice mode and
    /// kicks the recorder. Called from the global ⌥⌘V monitor.
    func beginVoiceCapture() async {
        guard voiceStage != .listening, voiceStage != .transcribing else { return }
        surface = .voice
        voiceStage = .listening
        voiceTranscript = ""
        if state != .expanded {
            transition(to: .expanding)
            await notch?.expand()
            transition(to: .expanded)
        }

        // Amplitude polling — drives the waveform envelope while the user holds.
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

        voiceTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Long max — we'll cut it short when the user releases the key.
                let text = try await self.voice.transcribe(maxDuration: 8.0)
                await MainActor.run {
                    self.voiceTranscript = text
                    self.lastSuccess = .voiceCaptured(text)
                    self.voiceStage = .replying
                }
                NSLog("[CompostAction] voiceCapture success: %@", text)
                await self.requestVoiceReply(for: text)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                await MainActor.run { self.voiceStage = .failed(msg) }
                NSLog("[CompostAction] voiceCapture failed: %@", msg)
            }
            await MainActor.run { self.voiceAmplitude = 0 }
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

    /// Push-to-talk end. The transcribe task is already running with its
    /// own timeout; releasing the key just transitions the visible stage.
    func endVoiceCapture() async {
        guard voiceStage == .listening else { return }
        voiceStage = .transcribing
        ampTimer?.cancel()
        ampTimer = nil
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
        surface = .summary
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
        let visibleDrafts = s.drafts.filter { !resolvedDraftIds.contains($0.id) }
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
        guard summary.hasAnything else { return }
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

    /// "Refresh" button. Fires `tidyNow({})` and `refreshBridge({surface:"all"})`
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
            let data = try await notion.invokeTool("refreshBridge", input: ["surface": "all"])
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
        transition(to: .expanding)
        await notch?.expand()
        transition(to: .expanded)
    }

    private func retract() async {
        transition(to: .retracting)
        let total = summary.proposalCount + summary.draftCount + (summary.digestReady ? 1 : 0)
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
            }
        }
    }
}
