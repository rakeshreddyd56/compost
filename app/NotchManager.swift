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

    init(notion: NotionClient) {
        self.notion = notion
        self.poller = CompostPoller(client: notion)
        self.wake = WakeTrigger()
        self.hotkey = HotkeyManager()
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
        summary = s
        if s.lastError == nil { hasLoadedOnce = true }
        // Drop stale per-proposal errors for proposals that are no longer
        // in the summary (applied, archived, or otherwise gone).
        let liveProposalIds = Set(s.proposals.map { $0.proposalId })
        proposalErrors = proposalErrors.filter { liveProposalIds.contains($0.key) }
        let liveDraftIds = Set(s.drafts.map { $0.id })
        draftErrors = draftErrors.filter { liveDraftIds.contains($0.key) }
        let total = s.proposalCount + s.draftCount + (s.digestReady ? 1 : 0)
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
