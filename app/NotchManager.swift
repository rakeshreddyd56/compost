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
    case readAloud(String)       // row id currently speaking
    case captureVoice            // ⌘⇧V push-to-talk
}

/// One-shot success ping consumed by the view layer to flash a brief "✓ done"
/// affordance after a worker tool call returns.
enum SuccessPing: Equatable {
    case tidied
    case applied
    case proposalApplied(String) // payload = proposal title for the pip text
    case reviewed(String)
    case voiceCaptured(String)   // payload = transcribed text preview
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

    /// Which row is currently reading aloud (CueRow / DraftRow / MemoryItem id).
    /// View layer uses this to toggle the speaker icon between play/stop.
    @Published private(set) var speakingId: String?
    /// True while a push-to-talk voice capture is recording.
    @Published private(set) var isCapturingVoice: Bool = false

    let notion: NotionClient
    private var notch: DynamicNotch<AnyView>?
    private let poller: CompostPoller
    private let wake: WakeTrigger
    private let hotkey: HotkeyManager
    private let voice: VoiceClient = AppleVoiceClient()
    private let recorder = AudioRecorder()
    private let voiceHotkey = VoiceCaptureHotkey()
    private var hasAutoGreetedFirstLoad = false
    private static let resolvedDraftIdsKey = "compost.resolvedDraftIds"
    private var resolvedDraftIds: Set<String>

    init(notion: NotionClient) {
        self.notion = notion
        self.poller = CompostPoller(client: notion)
        self.wake = WakeTrigger()
        self.hotkey = HotkeyManager()
        self.resolvedDraftIds = Set(UserDefaults.standard.stringArray(forKey: Self.resolvedDraftIdsKey) ?? [])
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

    // MARK: - Voice (TTS + STT, Apple frameworks)

    func readAloud(text: String, id: String) async {
        guard !text.isEmpty else { return }
        // Stop anything currently speaking — only one row at a time.
        if speakingId != nil { voice.stop() }
        speakingId = id
        let action = InflightAction.readAloud(id)
        inflight.insert(action)
        let start = Date()
        NSLog("[CompostAction] readAloud[%@] start", id)
        do {
            try await voice.speak(text: text)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            NSLog("[CompostAction] readAloud[%@] success in %dms", id, ms)
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            NSLog("[CompostAction] readAloud[%@] failed in %dms: %@", id, ms, msg)
            lastActionError = "Read aloud failed: \(msg)"
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(4))
                if self?.lastActionError != nil { self?.lastActionError = nil }
            }
        }
        if speakingId == id { speakingId = nil }
        inflight.remove(action)
    }

    func stopReadAloud() {
        voice.stop()
        if let id = speakingId {
            inflight.remove(.readAloud(id))
        }
        speakingId = nil
    }

    private func beginVoiceCapture() async {
        // Don't double-start.
        guard !isCapturingVoice else { return }
        let allowed = await AudioRecorder.ensureMicrophonePermission()
        guard allowed else {
            lastActionError = "Microphone permission denied"
            scheduleClearActionError()
            return
        }
        do {
            try recorder.start()
            isCapturingVoice = true
            inflight.insert(.captureVoice)
            NSLog("[CompostAction] captureVoice start")
        } catch {
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            NSLog("[CompostAction] captureVoice failed to start: %@", msg)
            lastActionError = "Couldn't start mic: \(msg)"
            scheduleClearActionError()
        }
    }

    private func endVoiceCapture() async {
        guard isCapturingVoice else { return }
        isCapturingVoice = false
        let url = recorder.stop()
        let start = Date()
        defer { inflight.remove(.captureVoice) }
        guard let url else { return }
        do {
            let text = try await voice.transcribe(audioURL: url)
            try? FileManager.default.removeItem(at: url)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                NSLog("[CompostAction] captureVoice empty in %dms", ms)
                lastActionError = "No speech detected"
                scheduleClearActionError()
                return
            }
            _ = try await notion.createMemoryNote(text: trimmed)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let preview = String(trimmed.prefix(80))
            NSLog("[CompostAction] captureVoice success in %dms: %@", ms, preview)
            lastSuccess = .voiceCaptured(preview)
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                if case .voiceCaptured = self?.lastSuccess { self?.lastSuccess = nil }
            }
            // Refresh so the new memory row shows up (also picked up by next
            // 60s tick; doing both is harmless and snappier).
            Task { @MainActor [weak self] in
                await self?.poller.refreshNow()
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            let msg = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            NSLog("[CompostAction] captureVoice failed in %dms: %@", ms, msg)
            lastActionError = "Voice capture failed: \(msg)"
            scheduleClearActionError()
        }
    }

    private func scheduleClearActionError() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.lastActionError != nil { self?.lastActionError = nil }
        }
    }

    // MARK: - State transitions

    private func applySummary(_ s: NotchSummary) async {
        let visibleDrafts = s.drafts.filter { !resolvedDraftIds.contains($0.id) }
        let visible = NotchSummary(
            proposalCount: s.proposals.count,
            proposals: s.proposals,
            draftCount: visibleDrafts.count,
            drafts: visibleDrafts,
            digestReady: s.digestReady,
            digestUrl: s.digestUrl,
            currentCue: s.currentCue,
            memory: s.memory,
            lastError: s.lastError
        )

        summary = visible
        if visible.lastError == nil { hasLoadedOnce = true }
        // Drop stale per-proposal errors for proposals that are no longer
        // in the summary (applied, archived, or otherwise gone).
        let liveProposalIds = Set(visible.proposals.map { $0.proposalId })
        proposalErrors = proposalErrors.filter { liveProposalIds.contains($0.key) }
        let liveDraftIds = Set(visible.drafts.map { $0.id })
        draftErrors = draftErrors.filter { liveDraftIds.contains($0.key) }
        let total = visible.proposalCount + visible.draftCount + (visible.digestReady ? 1 : 0)
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
            case .readAloud:       return "Read aloud"
            case .captureVoice:    return "Voice capture"
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
            ExpandedView(manager: manager)
        }
    }
}
