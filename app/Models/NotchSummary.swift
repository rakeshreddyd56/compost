//
//  NotchSummary.swift
//  Compost — aggregate driving the UI.
//

import Foundation

struct NotchSummary {
    let proposalCount: Int
    let proposals: [Proposal]
    let draftCount: Int
    let drafts: [FrozenDraft]
    let digestReady: Bool
    let digestUrl: URL?

    var hasAnything: Bool {
        proposalCount + draftCount + (digestReady ? 1 : 0) > 0
    }

    static let empty = NotchSummary(
        proposalCount: 0, proposals: [],
        draftCount: 0, drafts: [],
        digestReady: false, digestUrl: nil
    )
}

struct Proposal: Identifiable {
    let id: String        // page id (the compostPile row)
    let proposalId: String
    let title: String
    let action: String    // "archive" | "merge" | ...
    let reason: String
    let targetPageId: String

    init?(_ page: NotionPage) {
        self.id = page.id
        self.proposalId = page.properties["Proposal ID"]?.plainText ?? ""
        self.title = page.properties["Title"]?.plainText ?? "Untitled"
        self.action = page.properties["Action"]?.plainText ?? "archive"
        self.reason = page.properties["Reason"]?.plainText ?? ""
        self.targetPageId = page.properties["Target Page ID"]?.plainText ?? ""
    }
}

struct FrozenDraft: Identifiable {
    let id: String        // page id (the frozenDrafts row)
    let draftId: String
    let title: String
    let sourcePageId: String
    let original: String
    let rewrite: String
    let frozenAt: String

    init?(_ page: NotionPage) {
        self.id = page.id
        self.draftId = page.properties["Draft ID"]?.plainText ?? ""
        self.title = page.properties["Title"]?.plainText ?? "Untitled"
        self.sourcePageId = page.properties["Source Page ID"]?.plainText ?? ""
        self.original = page.properties["Original"]?.plainText ?? ""
        self.rewrite = page.properties["Rewrite"]?.plainText ?? ""
        self.frozenAt = page.properties["Frozen At"]?.plainText ?? ""
    }
}

struct WeeklyDigest {
    let weekStart: Date
    let url: URL?
    let stats: String

    init?(_ page: NotionPage) {
        let weekStartStr = page.properties["Week Start"]?.plainText ?? ""
        let f = ISO8601DateFormatter()
        guard let ws = f.date(from: weekStartStr) ?? Self.tryParse(weekStartStr) else { return nil }
        self.weekStart = ws
        let pageId = page.properties["Digest Page ID"]?.plainText ?? ""
        self.url = URL(string: "notion://www.notion.so/\(pageId.replacingOccurrences(of: "-", with: ""))")
        self.stats = page.properties["Stats"]?.plainText ?? ""
    }

    private static func tryParse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s.prefix(10).description)
    }
}
