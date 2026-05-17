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
    let memoryCount: Int
    let memory: [MemoryItem]
    let lastError: String?  // non-nil means most recent poll failed

    var hasAnything: Bool {
        proposalCount + draftCount + memoryCount + (digestReady ? 1 : 0) > 0
    }

    /// Photo-only slice of memory for the slideshow surface.
    var memoryPhotos: [MemoryItem] {
        memory.filter { $0.kind == .photo }
    }

    static let empty = NotchSummary(
        proposalCount: 0, proposals: [],
        draftCount: 0, drafts: [],
        digestReady: false, digestUrl: nil,
        currentCue: nil,
        memoryCount: 0, memory: [],
        lastError: nil
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
        let proposalId = page.properties["Proposal ID"]?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = page.properties["Title"]?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let action = page.properties["Action"]?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let targetPageId = page.properties["Target Page ID"]?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Notion agents can create body-only proposal pages when managed DB
        // properties are read-only to them. Those are useful audit artifacts,
        // but the app can only apply canonical Worker-stamped proposal rows.
        guard !proposalId.isEmpty, !title.isEmpty, !action.isEmpty, !targetPageId.isEmpty else {
            return nil
        }

        self.proposalId = proposalId
        self.title = title
        self.action = action
        self.reason = page.properties["Reason"]?.plainText ?? ""
        self.targetPageId = targetPageId
    }
}

struct FrozenDraft: Identifiable {
    let id: String        // page id (the frozenDrafts row)
    let title: String
    let sourcePageId: String
    let original: String
    /// Per-tone rewrites keyed by tone name. The current contract exposes a
    /// single `Rewrite` field, so the parser inserts that under "Calmer".
    /// When the v0.5 worker tool `rephraseDraft` lands and writes a
    /// `Rewrite Variants` JSON blob, this dictionary will grow without any
    /// schema change on the app side.
    /// Mutable so NotchManager.rephraseDraft can drop a fresh tone variant
    /// into the row without rebuilding the whole summary. Worker is still the
    /// source of truth on the next poll; this is just the in-flight optimistic
    /// update so the diff pane swaps instantly.
    var rewrites: [String: String]
    var activeTone: String
    let frozenAt: String

    /// Back-compat: existing callers still read `.rewrite`. Returns the
    /// active tone's text, or the first available tone, or empty.
    var rewrite: String {
        rewrites[activeTone] ?? rewrites["Calmer"] ?? rewrites.values.first ?? ""
    }

    var availableTones: [String] {
        // Preserve a stable ordering for the picker. Anything in the dict
        // that isn't in the known list still renders at the end.
        let known = ["Calmer", "Crisp", "Diplomatic"]
        let inDict = Set(rewrites.keys)
        let primary = known.filter { inDict.contains($0) }
        let extras = rewrites.keys.filter { !known.contains($0) }.sorted()
        return primary + extras
    }

    init?(_ page: NotionPage) {
        self.id = page.id
        let title = page.properties["Title"]?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sourcePageId = page.properties["Source Page ID"]?.plainText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let original = page.properties["Original Snapshot"]?.plainText ?? ""
        self.title = title.isEmpty ? "Untitled draft" : title
        self.sourcePageId = sourcePageId
        self.original = original
        self.frozenAt = page.properties["Frozen At"]?.date?.start ?? ""

        let activeRaw = page.properties["Active Tone"]?.plainText ?? ""
        let active = Self.displayToneName(activeRaw)
        self.activeTone = active

        var dict: [String: String] = [:]

        // Variants blob (future). When present, prefer it as the source of
        // truth. The Worker contract uses lowercase keys, but older app
        // builds used display-case keys, so normalize both into display names.
        let variantsRaw = page.properties["Rewrite Variants"]?.plainText ?? ""
        if !variantsRaw.isEmpty,
           let data = variantsRaw.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            dict = Dictionary(uniqueKeysWithValues: parsed.map { (Self.displayToneName($0.key), $0.value) })
        }

        let canonical = page.properties["Rewrite"]?.plainText ?? ""
        if !canonical.isEmpty, dict[active] == nil {
            dict[active] = canonical
        }
        if dict.isEmpty, !canonical.isEmpty { dict["Calmer"] = canonical }

        // Same body-only issue as proposals: Notion AI can create draft pages
        // with the structured fields in the page content, but Worker/app action
        // paths require canonical DB properties.
        guard !sourcePageId.isEmpty, !original.isEmpty, !dict.isEmpty else { return nil }
        self.rewrites = dict
    }

    private static func displayToneName(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "crisp": return "Crisp"
        case "diplomatic": return "Diplomatic"
        default: return "Calmer"
        }
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
    let generatedAt: Date?  // for picking the newest when multiple rows exist
    let currentTime: Date?  // for tie-breaks

    init?(_ page: NotionPage) {
        self.id = page.id
        self.sourcePageId = page.properties["Source Page ID"]?.plainText ?? ""
        self.sourceTitle = page.properties["Source Title"]?.plainText ?? ""
        self.currentHeading = page.properties["Current Heading"]?.plainText ?? ""
        self.currentBullets = page.properties["Current Bullets"]?.plainText ?? ""
        self.nextHeading = page.properties["Next Heading"]?.plainText ?? ""
        self.nextBullets = page.properties["Next Bullets"]?.plainText ?? ""
        if let n = page.properties["Minutes Until Next"]?.number {
            self.minutesUntilNext = Int(n)
        } else {
            self.minutesUntilNext = 0
        }
        self.calmCue = page.properties["Calm Cue"]?.plainText ?? ""
        self.generatedAt = Self.parseDate(page.properties["Generated At"]?.date?.start)
        self.currentTime = Self.parseDate(page.properties["Current Time"]?.date?.start)
    }

    /// Lazily-parsed checklist items from `Current Bullets`. Each non-empty
    /// line becomes one item; leading "- " / "• " / "* " markers are stripped.
    var bulletItems: [String] {
        currentBullets
            .split(whereSeparator: \.isNewline)
            .map { line -> String in
                var s = String(line).trimmingCharacters(in: .whitespaces)
                for prefix in ["- [ ]", "- [x]", "- ", "• ", "* "] {
                    if s.hasPrefix(prefix) {
                        s = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                        break
                    }
                }
                return s
            }
            .filter { !$0.isEmpty }
    }

    /// "12m" / "1h 5m" / "2d 4h" — never bare 3-digit minute counts.
    static func formatMinutes(_ m: Int) -> String {
        let total = max(0, m)
        if total < 60 { return "\(total)m" }
        if total < 60 * 24 {
            let h = total / 60
            let r = total % 60
            return r == 0 ? "\(h)h" : "\(h)h \(r)m"
        }
        let d = total / (60 * 24)
        let h = (total % (60 * 24)) / 60
        return h == 0 ? "\(d)d" : "\(d)d \(h)h"
    }

    /// Pretty "10:30 AM" for the time strip; empty when no currentTime.
    func currentTimeLabel(now: Date = Date()) -> String {
        guard let currentTime else { return "" }
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "h:mm a"
        return f.string(from: currentTime)
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
}
