//
//  CompostPoller.swift
//  Compost — 60-second polling loop
//

import Foundation
import Combine

@MainActor
final class CompostPoller {
    private let client: NotionClient
    private var task: Task<Void, Never>?
    private var forceRefreshFlag = false

    init(client: NotionClient) {
        self.client = client
    }

    func start(callback: @escaping (NotchSummary) -> Void) async {
        // Note: callback is sync, caller must wrap async calls in Task
        task = Task {
            while !Task.isCancelled {
                do {
                    let proposals = try await client.fetchProposals()
                    let drafts = try await client.fetchReadyDrafts()
                    let digest = try await client.latestWeeklyDigest()
                    let cue = try await client.currentCueCard()

                    let summary = NotchSummary(
                        proposalCount: proposals.count,
                        proposals: proposals,
                        draftCount: drafts.count,
                        drafts: drafts,
                        digestReady: digest != nil,
                        digestUrl: digest?.url,
                        currentCue: cue,
                        lastError: nil
                    )
                    await callback(summary)
                } catch {
                    print("Polling error: \(error)")
                    let summary = NotchSummary(
                        proposalCount: 0, proposals: [],
                        draftCount: 0, drafts: [],
                        digestReady: false, digestUrl: nil,
                        currentCue: nil,
                        lastError: describe(error)
                    )
                    await callback(summary)
                }

                if forceRefreshFlag {
                    forceRefreshFlag = false
                } else {
                    try? await Task.sleep(for: .seconds(60))
                }
            }
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
            }
        }
        return "Offline"
    }

    func forceRefresh() {
        forceRefreshFlag = true
    }

    deinit {
        task?.cancel()
    }
}
