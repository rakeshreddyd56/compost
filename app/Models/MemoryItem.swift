//
//  MemoryItem.swift
//  Compost — notionMemory row, mirrors the schema added in INTERFACE.md.
//
//  One row per ingested memory: photo / note / clip. The notch's Memory
//  section reads these directly via NotionClient.fetchRecentMemory(); the
//  worker (Codex) is responsible for ingesting source pages into this DB
//  and stamping Caption + Captured At.
//

import Foundation

struct MemoryItem: Identifiable {
    enum Kind: String {
        case photo
        case note
        case clip
        case unknown
    }

    let id: String              // Notion page id (the notionMemory row)
    let title: String
    let sourcePageId: String
    let kind: Kind
    /// For photo: an http(s) URL pointing at the asset.
    /// For note/clip: the text body. Empty when missing.
    let content: String
    let caption: String
    let capturedAt: Date?
    let tags: [String]

    init?(_ page: NotionPage) {
        self.id = page.id
        self.title = page.properties["Title"]?.plainText ?? "Untitled"
        self.sourcePageId = page.properties["Source Page ID"]?.plainText ?? ""
        self.kind = Kind(rawValue: page.properties["Type"]?.plainText.lowercased() ?? "") ?? .unknown
        self.content = page.properties["Content"]?.plainText ?? ""
        self.caption = page.properties["Caption"]?.plainText ?? ""
        self.tags = page.properties["Tags"]?.multiSelectNames ?? []
        let raw = page.properties["Captured At"]?.date?.start ?? ""
        self.capturedAt = MemoryItem.parseDate(raw)
    }

    /// Convenience for the photo slideshow. Only photo-kind rows expose a
    /// usable asset URL; everything else returns nil so the viewer can fall
    /// back to a text card.
    var assetURL: URL? {
        guard kind == .photo, !content.isEmpty else { return nil }
        return URL(string: content)
    }

    /// Open the source Notion page (where the user dropped the photo / note).
    var sourceURL: URL? {
        let trimmed = sourcePageId.replacingOccurrences(of: "-", with: "")
        guard !trimmed.isEmpty else { return nil }
        return URL(string: "notion://www.notion.so/\(trimmed)")
    }

    /// "self-sighting" if the user (or worker) tagged the item with
    /// `compost-sighting`. Drives the mascot easter-egg in PhotosView.
    var mascotReaction: MemoryReaction? {
        let lc = tags.map { $0.lowercased() }
        if lc.contains("compost-sighting") { return .selfSighting }
        if lc.contains("delighted")        { return .delighted }
        if lc.contains("nostalgic")        { return .nostalgic }
        return nil
    }

    func timeLabel(now: Date = Date()) -> String {
        guard let capturedAt else { return "" }
        let cal = Calendar.current
        let f = DateFormatter()
        f.locale = .current
        if cal.isDateInToday(capturedAt) {
            f.dateFormat = "'today' · h:mm a"
        } else if cal.isDateInYesterday(capturedAt) {
            f.dateFormat = "'yesterday' · h:mm a"
        } else {
            f.dateFormat = "MMM d · h:mm a"
        }
        return f.string(from: capturedAt)
    }

    private static func parseDate(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}

enum MemoryReaction: String {
    case selfSighting
    case delighted
    case nostalgic

    var bubbleCopy: String {
        switch self {
        case .selfSighting: return "yes — that's me! logged it."
        case .delighted:    return "this one's good. tag it for the moodboard?"
        case .nostalgic:    return "oh — this was a while back."
        }
    }
}
