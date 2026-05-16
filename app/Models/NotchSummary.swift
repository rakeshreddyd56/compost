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
    let currentCue: CueCard?
    let lastError: String?  // non-nil means most recent poll failed

    var hasAnything: Bool {
        proposalCount + draftCount + (digestReady ? 1 : 0) > 0
    }

    static let empty = NotchSummary(
        proposalCount: 0, proposals: [],
        draftCount: 0, drafts: [],
        digestReady: false, digestUrl: nil,
        currentCue: nil, lastError: nil
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
    let title: String
    let sourcePageId: String
    let original: String
    let rewrite: String
    let frozenAt: String

    init?(_ page: NotionPage) {
        self.id = page.id
        self.title = page.properties["Title"]?.plainText ?? "Untitled"
        self.sourcePageId = page.properties["Source Page ID"]?.plainText ?? ""
        self.original = page.properties["Original Snapshot"]?.plainText ?? ""
        self.rewrite = page.properties["Rewrite"]?.plainText ?? ""
        self.frozenAt = page.properties["Frozen At"]?.date?.start ?? ""
    }
}

struct WeeklyDigest {
    let weekStart: Date
    let url: URL?

    init?(_ page: NotionPage) {
        let weekStartStr = page.properties["Week Start"]?.date?.start ?? ""
        let f = ISO8601DateFormatter()
        guard let ws = f.date(from: weekStartStr) ?? Self.tryParse(weekStartStr) else { return nil }
        self.weekStart = ws
        let pageId = page.properties["Summary Page ID"]?.plainText ?? ""
        self.url = URL(string: "notion://www.notion.so/\(pageId.replacingOccurrences(of: "-", with: ""))")
    }

    private static func tryParse(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s.prefix(10).description)
    }
}

struct CueCard: Identifiable {
    let id: String
    let sourcePageId: String
    let sourceTitle: String
    let currentHeading: String
    let currentBullets: String
    let nextHeading: String
    let nextBullets: String
    let minutesUntilNext: Int
    let calmCue: String

    init?(_ page: NotionPage) {
        self.id = page.id
        self.sourcePageId = page.properties["Source Page ID"]?.plainText ?? ""
        self.sourceTitle = page.properties["Source Title"]?.plainText ?? ""
        self.currentHeading = page.properties["Current Heading"]?.plainText ?? ""
        self.currentBullets = page.properties["Current Bullets"]?.plainText ?? ""
        self.nextHeading = page.properties["Next Heading"]?.plainText ?? ""
        self.nextBullets = page.properties["Next Bullets"]?.plainText ?? ""
        let minutesStr = page.properties["Minutes Until Next"]?.plainText ?? "0"
        self.minutesUntilNext = Int(minutesStr) ?? 0
        self.calmCue = page.properties["Calm Cue"]?.plainText ?? ""
    }
}
