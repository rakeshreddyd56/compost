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
}

/// One-shot success ping consumed by the view layer to flash a brief "✓ done"
/// affordance after a worker tool call returns.
enum SuccessPing: Equatable {
    case tidied
    case applied
    case proposalApplied(String) // payload = proposal title for the pip text
    case reviewed(String)
}

@MainActor
final class NotchManager: ObservableObject {
    @Published private(set) var state: NotchState = .hidden
    @Published private(set) var summary: NotchSummary = .empty
    @Published private(set) var hasLoadedOnce: Bool = false
    @Published private(set) var inflight: Set<InflightAction> = []
    /// Wall-clock start time per in-flight action so the UI can render
    /// "Still working in Notion…" (>5s) and "Notion is taking longer than
    /// usual." (>15s) hints. Kept in lockstep with `inflight` via
    /// beginInflight/endInflight.
    @Published private(set) var inflightStartedAt: [InflightAction: Date] = [:]
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

    let notion: NotionClient
    private var notch: DynamicNotch<AnyView>?
    private let poller: CompostPoller
    private let wake: WakeTrigger
    private let hotkey: HotkeyManager
    private var hasAutoGreetedFirstLoad = false
    private static let resolvedDraftIdsKey = "compost.resolvedDraftIds"
    private static let resolvedProposalIdsKey = "compost.resolvedProposalIds"
    private var resolvedDraftIds: Set<String>
    /// Local optimistic hide list for proposals the user successfully applied
    /// in this session. Mirrors `resolvedDraftIds`. Backed by UserDefaults so
    /// the row doesn't briefly reappear between launches if the poller's next
    /// snapshot still includes it.
    private var resolvedProposalIds: Set<String>
    /// Latest RAW summary from the poller, before client-side filters. Stored
    /// so that resolving a proposal/draft locally can re-emit a filtered
    /// summary immediately (no need to wait for the next 60s poll).
    private var latestRawSummary: NotchSummary = .empty

    init(notion: NotionClient) {
        self.notion = notion
        self.poller = CompostPoller(client: notion)
        self.wake = WakeTrigger()
        self.hotkey = HotkeyManager()
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
    }

    // MARK: - State transitions

    private func applySummary(_ s: NotchSummary) async {
        latestRawSummary = s
        await republishVisible(triggerAutoGreet: true)
    }

    /// Recompute the visible summary from the latest raw poll, applying the
    /// local "resolved" hide-lists. Safe to call from action handlers after
    /// they mark a row resolved so the UI updates immediately, without
    /// waiting for the next 60s tick.
    private func republishVisible(triggerAutoGreet: Bool) async {
        let s = latestRawSummary
        let visibleProposals = s.proposals.filter {
            !resolvedProposalIds.contains($0.proposalId)
        }
        let visibleDrafts = s.drafts.filter {
            !resolvedDraftIds.contains($0.id)
        }
        let visible = NotchSummary(
            proposalCount: visibleProposals.count,
            proposals: visibleProposals,
            draftCount: visibleDrafts.count,
            drafts: visibleDrafts,
            digestReady: s.digestReady,
            digestUrl: s.digestUrl,
            currentCue: s.currentCue,
            lastError: s.lastError
        )

        summary = visible
        if visible.lastError == nil { hasLoadedOnce = true }
        // Drop stale per-row errors for rows that are no longer visible
        // (applied, archived, optimistically resolved, or otherwise gone).
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

        let shouldAutoGreet = triggerAutoGreet && !hasAutoGreetedFirstLoad
        if triggerAutoGreet { hasAutoGreetedFirstLoad = true }

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
        let action = InflightAction.tidyNow
        let started = beginInflight(action)
        logAction("tidyNow", phase: "start")
        defer { endInflight(action) }

        do {
            _ = try await notion.invokeTool("tidyNow", input: [:])
            logAction("tidyNow", phase: "success", elapsed: elapsed(since: started))
            lastActionError = nil
            flashSuccess(.tidied)
        } catch {
            let msg = errorMessage(error)
            logAction("tidyNow", phase: "failed", elapsed: elapsed(since: started), detail: msg)
            lastSuccess = nil
            lastActionError = "Refresh failed: \(msg)"
            scheduleClear(\.lastActionError, after: 4)
        }
        // Detach the refresh so the spinner can clear immediately. The
        // background poll updates `summary` when it lands.
        scheduleBackgroundRefresh()
    }

    func applyApproved() async {
        let action = InflightAction.applyApproved
        let started = beginInflight(action)
        logAction("applyApproved", phase: "start")
        defer { endInflight(action) }

        do {
            _ = try await notion.invokeTool("applyApproved", input: [:])
            logAction("applyApproved", phase: "success", elapsed: elapsed(since: started))
            lastActionError = nil
            flashSuccess(.applied)
        } catch {
            let msg = errorMessage(error)
            logAction("applyApproved", phase: "failed", elapsed: elapsed(since: started), detail: msg)
            lastSuccess = nil
            lastActionError = "Apply failed: \(msg)"
            scheduleClear(\.lastActionError, after: 4)
        }
        scheduleBackgroundRefresh()
    }

    func reviewDraft(draftId: String, approve: Bool) async {
        let action = InflightAction.reviewDraft(draftId)
        let success = SuccessPing.reviewed(draftId)
        let label = "reviewDraft[\(approve ? "approve" : "reject"):\(draftId.prefix(8))]"
        // Clear the stale error eagerly — user retrying.
        draftErrors.removeValue(forKey: draftId)
        let started = beginInflight(action)
        logAction(label, phase: "start")
        defer { endInflight(action) }

        do {
            _ = try await notion.invokeTool("reviewDraft", input: [
                "draftId": draftId,
                "decision": approve ? "approve" : "reject",
            ])
            logAction(label, phase: "success", elapsed: elapsed(since: started))
            // Optimistically hide the row immediately — re-emit visible
            // summary with the draft removed from the visible list.
            await markDraftResolved(draftId)
            lastActionError = nil
            flashSuccess(success)
        } catch {
            let msg = errorMessage(error)
            logAction(label, phase: "failed", elapsed: elapsed(since: started), detail: msg)
            draftErrors[draftId] = msg
            lastSuccess = nil
        }
        scheduleBackgroundRefresh()
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
        let label = "applyProposal[\(pid.prefix(8))]"
        // Clear the stale error eagerly so the red banner doesn't linger
        // while the user is watching the spinner on a retry.
        proposalErrors.removeValue(forKey: pid)
        let started = beginInflight(action)
        logAction(label, phase: "start")
        defer { endInflight(action) }

        do {
            _ = try await notion.invokeTool("applyProposal", input: ["proposalId": pid])
            logAction(label, phase: "success", elapsed: elapsed(since: started))
            // Optimistically hide the row immediately. The next background
            // poll should also drop it (Applied=true filters it out server-
            // side); persisting in resolvedProposalIds means we don't briefly
            // re-render it if that poll happens before the worker stamp.
            await markProposalResolved(pid)
            lastActionError = nil
            flashSuccess(success)
        } catch {
            let msg = errorMessage(error)
            logAction(label, phase: "failed", elapsed: elapsed(since: started), detail: msg)
            proposalErrors[pid] = msg
            lastSuccess = nil
        }
        scheduleBackgroundRefresh()
    }

    // MARK: - Inflight / logging / refresh helpers

    private func beginInflight(_ action: InflightAction) -> Date {
        let now = Date()
        inflight.insert(action)
        inflightStartedAt[action] = now
        return now
    }

    private func endInflight(_ action: InflightAction) {
        inflight.remove(action)
        inflightStartedAt.removeValue(forKey: action)
    }

    private func elapsed(since start: Date) -> TimeInterval {
        Date().timeIntervalSince(start)
    }

    private func errorMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    /// NSLog with a stable `[CompostAction]` prefix so the demo box can grep
    /// for action timing without enabling Debug-level unified logging.
    private func logAction(_ name: String, phase: String, elapsed: TimeInterval? = nil, detail: String? = nil) {
        if let elapsed {
            let ms = Int(elapsed * 1000)
            if let detail {
                NSLog("[CompostAction] %@ %@ in %dms: %@", name, phase, ms, detail)
            } else {
                NSLog("[CompostAction] %@ %@ in %dms", name, phase, ms)
            }
        } else {
            NSLog("[CompostAction] %@ %@", name, phase)
        }
    }

    private func flashSuccess(_ ping: SuccessPing) {
        lastSuccess = ping
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.lastSuccess == ping { self?.lastSuccess = nil }
        }
    }

    private func scheduleClear(_ keyPath: ReferenceWritableKeyPath<NotchManager, String?>, after seconds: Double) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?[keyPath: keyPath] = nil
        }
    }

    /// Fire-and-forget poller refresh so action methods can return as soon
    /// as the tool call resolves — the spinner doesn't wait on the 4-DB
    /// re-fetch.
    private func scheduleBackgroundRefresh() {
        Task { @MainActor [weak self] in
            await self?.poller.refreshNow()
        }
    }

    private func markDraftResolved(_ draftId: String) async {
        guard !draftId.isEmpty else { return }
        resolvedDraftIds.insert(draftId)
        UserDefaults.standard.set(Array(resolvedDraftIds), forKey: Self.resolvedDraftIdsKey)
        await republishVisible(triggerAutoGreet: false)
    }

    private func markProposalResolved(_ proposalId: String) async {
        guard !proposalId.isEmpty else { return }
        resolvedProposalIds.insert(proposalId)
        UserDefaults.standard.set(Array(resolvedProposalIds), forKey: Self.resolvedProposalIdsKey)
        await republishVisible(triggerAutoGreet: false)
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
