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
                    self.voiceStage = .finished(text)
                    self.voiceTranscript = text
                    self.lastSuccess = .voiceCaptured(text)
                }
                NSLog("[CompostAction] voiceCapture success: %@", text)
            } catch {
                let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
                await MainActor.run { self.voiceStage = .failed(msg) }
                NSLog("[CompostAction] voiceCapture failed: %@", msg)
            }
            await MainActor.run { self.voiceAmplitude = 0 }
        }
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
