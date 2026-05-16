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

                    let summary = NotchSummary(
                        proposalCount: proposals.count,
                        proposals: proposals,
                        draftCount: drafts.count,
                        drafts: drafts,
                        digestReady: digest != nil,
                        digestUrl: digest?.url
                    )
                    await callback(summary)
                } catch {
                    print("Polling error: \(error)")
                }

                if forceRefreshFlag {
                    forceRefreshFlag = false
                } else {
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        }
    }

    func forceRefresh() {
        forceRefreshFlag = true
    }

    deinit {
        task?.cancel()
    }
}
