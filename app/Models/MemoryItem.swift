//
//  MemoryItem.swift
//  Compost — one row from the `notionMemory` managed DB.
//
//  Mirrors the CueCard / Proposal init?(_ page: NotionPage) pattern so the
//  poller can build these from the standard Notion property bag.
//

import Foundation

struct MemoryItem: Identifiable {
    enum Kind: String {
        case photo
        case note
        case clip
        case unknown
    }

    let id: String           // Notion page id of the memory row
    let title: String
    let sourcePageId: String
    let kind: Kind
    let content: String      // for `.photo`: external image URL; for `.note`: raw text
    let caption: String
    let capturedAt: Date?
    let tags: [String]

    init?(_ page: NotionPage) {
        self.id = page.id
        self.title = page.properties["Title"]?.plainText ?? "Untitled memory"
        self.sourcePageId = page.properties["Source Page ID"]?.plainText ?? ""
        self.kind = Kind(rawValue: (page.properties["Type"]?.plainText ?? "").lowercased())
            ?? .unknown
        self.content = page.properties["Content"]?.plainText ?? ""
        self.caption = page.properties["Caption"]?.plainText ?? ""
        self.capturedAt = Self.parseDate(page.properties["Captured At"]?.date?.start)
        // Tags is multi_select; plainText would be empty for that type. For v1
        // we don't render tags so leave empty — the property is still in the
        // worker's write surface for filtering later.
        self.tags = []
    }

    private static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }

    /// True when the memory is a photo with a usable URL — drives the
    /// thumbnail vs note-text branch in the view layer.
    var hasPhoto: Bool {
        kind == .photo && URL(string: content) != nil
    }

    /// Notion deep link to the source page so tapping a memory row opens
    /// the page it came from.
    var sourceURL: URL? {
        let id = sourcePageId.replacingOccurrences(of: "-", with: "")
        guard !id.isEmpty else { return nil }
        return URL(string: "notion://www.notion.so/\(id)")
    }
}
