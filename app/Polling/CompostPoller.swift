//
//  CompostPoller.swift
//  Compost — 60s steady-state polling loop with on-demand refresh.
//

import Foundation
import Combine

@MainActor
final class CompostPoller {
    private let client: NotionClient
    private var task: Task<Void, Never>?
    private var callback: ((NotchSummary) -> Void)?

    init(client: NotionClient) {
        self.client = client
    }

    func start(callback: @escaping (NotchSummary) -> Void) async {
        self.callback = callback
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                // Wake early if start() is called again (callback swap) or the
                // task is cancelled mid-sleep.
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// Run one fetch cycle and publish the result. Safe to call from action
    /// handlers — gives the UI an immediate refresh without waiting for the
    /// 60s loop. Does not interrupt the steady-state loop.
    func refreshNow() async {
        await tick()
    }

    /// Single fetch + publish. Errors get classified into a user-facing string
    /// and a sentinel summary so the offline UI can render.
    private func tick() async {
        guard let cb = callback else { return }
        do {
            let proposals = try await client.fetchProposals()
            let drafts = try await client.fetchReadyDrafts()
            let digest = try await client.latestWeeklyDigest()
            let cue = try await client.currentCueCard()
            let memory = try await client.fetchRecentMemory()

            let summary = NotchSummary(
                proposalCount: proposals.count,
                proposals: proposals,
                draftCount: drafts.count,
                drafts: drafts,
                digestReady: digest != nil,
                digestUrl: digest?.url,
                currentCue: cue,
                memoryCount: memory.count,
                memory: memory,
                lastError: nil
            )
            cb(summary)
        } catch {
            print("Polling error: \(error)")
            let summary = NotchSummary(
                proposalCount: 0, proposals: [],
                draftCount: 0, drafts: [],
                digestReady: false, digestUrl: nil,
                currentCue: nil,
                memoryCount: 0, memory: [],
                lastError: describe(error)
            )
            cb(summary)
        }
    }

    private func describe(_ error: Error) -> String {
        if let ne = error as? NotionError {
            switch ne {
            case .httpStatus(let code, _):
                switch code {
                case 401:        return "Token invalid — reconnect"
                case 403:        return "No access to this database"
                case 404:        return "Database not found"
                case 429:        return "Rate-limited — retrying"
                case 500...599:  return "Notion is having a moment"
                default:         return "HTTP \(code)"
                }
            case .decoding:    return "Couldn't read Notion response"
            case .toolFailed(let msg): return msg
            }
        }
        return "Offline"
    }

    deinit {
        task?.cancel()
    }
}
