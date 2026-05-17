//
//  NotionClient.swift
//  Compost
//
//  Thin wrapper around the Notion REST API.
//

import Foundation

struct NotionDbIds {
    let compostPile: String
    let frozenDrafts: String
    let weeklyDigests: String
    let cueCards: String
    let notionMemory: String
    let parentPage: String
    /// Parent page under which `createMemoryNote` writes voice-captured notes.
    /// The `memoryIngest` worker picks them up from there on its next tick.
    let memoryParentPage: String

    static let empty = NotionDbIds(
        compostPile: "", frozenDrafts: "", weeklyDigests: "", cueCards: "",
        notionMemory: "", parentPage: "", memoryParentPage: ""
    )
}

enum NotionError: Error, LocalizedError {
    case httpStatus(Int, String)
    case decoding
    case toolFailed(String)  // ntn CLI non-zero exit OR worker returned { ok: false }

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code, let body): return "HTTP \(code): \(body)"
        case .decoding: return "Couldn't decode Notion response"
        case .toolFailed(let reason): return reason
        }
    }
}

final class NotionClient {
    let token: String
    let ids: NotionDbIds
    private let base = URL(string: "https://api.notion.com/v1")!
    private let version = "2022-06-28"
    private let session = URLSession.shared

    init(token: String, ids: NotionDbIds) {
        self.token = token
        self.ids = ids
    }

    private func authed(_ url: URL) -> URLRequest {
        var req = URLRequest(url: url)
        req.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.addValue(version, forHTTPHeaderField: "Notion-Version")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    // MARK: - Queries

    func queryDatabase(_ dbId: String, filter: [String: Any]? = nil) async throws -> [NotionPage] {
        var req = authed(base.appendingPathComponent("databases/\(dbId)/query"))
        req.httpMethod = "POST"
        if let filter {
            req.httpBody = try JSONSerialization.data(withJSONObject: ["filter": filter])
        } else {
            req.httpBody = "{}".data(using: .utf8)
        }
        let (data, resp) = try await sendWithRetry(req)
        guard let http = resp as? HTTPURLResponse else { throw NotionError.httpStatus(-1, "no response") }
        guard http.statusCode == 200 else {
            throw NotionError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(NotionQueryResponse.self, from: data)
        return decoded.results
    }

    /// One-shot retry on HTTP 429 (Notion rate limit) honoring Retry-After.
    /// Notion limit is ~3 rps avg per workflows/notch-app.md; the poller paces
    /// itself at 60s but bursts can still trip when multiple syncs run.
    private func sendWithRetry(_ req: URLRequest) async throws -> (Data, URLResponse) {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 429 else {
            return (data, resp)
        }
        let retryAfter = (http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)) ?? 1.0
        let nanos = UInt64(min(retryAfter, 5.0) * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanos)
        return try await session.data(for: req)
    }

    func fetchProposals() async throws -> [Proposal] {
        let pages = try await queryDatabase(ids.compostPile, filter: [
            "and": [
                ["property": "Approved", "checkbox": ["equals": false]],
                ["property": "Applied",  "checkbox": ["equals": false]],
            ]
        ])
        let proposals = pages.compactMap(Proposal.init)
        var visible: [Proposal] = []
        for proposal in proposals {
            guard !proposal.targetPageId.isEmpty else {
                visible.append(proposal)
                continue
            }
            if try await isPageArchivedOrMissing(proposal.targetPageId) {
                continue
            }
            visible.append(proposal)
        }
        return visible
    }

    func fetchReadyDrafts() async throws -> [FrozenDraft] {
        let pages = try await queryDatabase(ids.frozenDrafts, filter: [
            "property": "Status",
            "select": ["equals": "frozen"],
        ])
        // Newest `Frozen At` first so the most recent late-night write shows
        // at the top. The string is ISO-8601 → lexicographic sort is correct.
        return pages
            .compactMap(FrozenDraft.init)
            .sorted { $0.frozenAt > $1.frozenAt }
    }

    func latestWeeklyDigest() async throws -> WeeklyDigest? {
        guard !ids.weeklyDigests.isEmpty else { return nil }
        let pages = try await queryDatabase(ids.weeklyDigests, filter: nil)
        return pages.compactMap(WeeklyDigest.init).max(by: { $0.weekStart < $1.weekStart })
    }

    func currentCueCard() async throws -> CueCard? {
        guard !ids.cueCards.isEmpty else { return nil }
        let pages = try await queryDatabase(ids.cueCards, filter: nil)
        // Multiple cueCards rows may exist (one per Cue source page).
        // Pick the most recently generated so the notch always reflects
        // the freshest "right now" rather than whatever Notion returned first.
        return pages
            .compactMap(CueCard.init)
            .sorted { lhs, rhs in
                let lg = lhs.generatedAt ?? .distantPast
                let rg = rhs.generatedAt ?? .distantPast
                if lg != rg { return lg > rg }
                let lc = lhs.currentTime ?? .distantPast
                let rc = rhs.currentTime ?? .distantPast
                return lc > rc
            }
            .first
    }

    /// Newest 12 memory items by Captured At desc. Empty when the user hasn't
    /// configured a Notion Memory DB ID — the 🧠 Memory section silently
    /// hides itself in that case.
    func fetchRecentMemory(limit: Int = 12) async throws -> [MemoryItem] {
        guard !ids.notionMemory.isEmpty else { return [] }
        let pages = try await queryDatabase(ids.notionMemory, filter: nil)
        return pages
            .compactMap(MemoryItem.init)
            .sorted { (lhs, rhs) in
                (lhs.capturedAt ?? .distantPast) > (rhs.capturedAt ?? .distantPast)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Create a new memory page under the user's `memoryParentPage`. Used by
    /// the voice-capture flow (STT) to file transcribed notes. The
    /// `memoryIngest` worker picks it up on its next 15-min tick and writes
    /// the row into `notionMemory`.
    /// Throws `NotionError.toolFailed` when `memoryParentPage` isn't set or
    /// when Notion returns non-2xx.
    func createMemoryNote(text: String) async throws -> String {
        guard !ids.memoryParentPage.isEmpty else {
            throw NotionError.toolFailed(
                "Memory parent page not configured. Set it in Settings."
            )
        }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let title = "[!memory] Voice note \(nowISO.prefix(19))"
        let payload: [String: Any] = [
            "parent": ["page_id": ids.memoryParentPage],
            "properties": [
                "title": [["text": ["content": title]]]
            ],
            "children": [
                [
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [["type": "text", "text": ["content": text]]]
                    ]
                ]
            ]
        ]
        var req = authed(base.appendingPathComponent("pages"))
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, resp) = try await sendWithRetry(req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NotionError.httpStatus(
                (resp as? HTTPURLResponse)?.statusCode ?? -1,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        let decoded = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return decoded?["id"] as? String ?? ""
    }

    // MARK: - Tool invocation
    //
    // Two paths, try in order:
    //  (A) Notion REST endpoint for invoking a Worker tool. When 200, trust it.
    //  (B) Shell out to `ntn workers exec <toolName> -d '<json>'` from the
    //      workers project cwd. We dropped `--remote` (S13): the certified
    //      worker now serves both local exec and remote invocation through the
    //      same path, and `--remote` was masking failures during the demo.

    func invokeTool(_ toolName: String, input: [String: Any]) async throws -> Data {
        // Try (A): direct REST.
        do {
            var req = authed(base.appendingPathComponent("workers/tools/\(toolName)/invoke"))
            req.httpMethod = "POST"
            req.httpBody = try JSONSerialization.data(withJSONObject: input)
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 {
                try Self.validateToolResponse(data)
                return data
            }
        } catch let e as NotionError {
            // A REST tool response that parsed as {ok:false} is a real failure —
            // don't fall through to the CLI just to retry; surface the failure.
            if case .toolFailed = e { throw e }
        } catch { /* network/etc: fall through to CLI */ }

        // (B): shell-out fallback.
        let ntn = try Self.resolveNtnBinary()
        let json = try JSONSerialization.data(withJSONObject: input)
        let jsonString = String(data: json, encoding: .utf8) ?? "{}"

        let task = Process()
        task.executableURL = ntn
        task.arguments = ["workers", "exec", toolName, "-d", jsonString]
        task.currentDirectoryURL = Self.workersDirectoryURL()

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        if task.terminationStatus != 0 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NotionError.toolFailed(
                Self.describeCliFailure(body, toolName: toolName, status: task.terminationStatus)
            )
        }

        try Self.validateToolResponse(data)
        return data
    }

    private func isPageArchivedOrMissing(_ pageId: String) async throws -> Bool {
        var req = authed(base.appendingPathComponent("pages/\(pageId)"))
        req.httpMethod = "GET"
        let (data, resp) = try await sendWithRetry(req)
        guard let http = resp as? HTTPURLResponse else { throw NotionError.httpStatus(-1, "no response") }
        if http.statusCode == 404 { return true }
        guard http.statusCode == 200 else {
            throw NotionError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(NotionPage.self, from: data)
        return decoded.archived == true
    }

    /// Resolve the `ntn` CLI binary by trying, in order:
    ///   1. `$NTN_BIN` environment override (if set and executable)
    ///   2. `/usr/local/bin/ntn`  (Intel Homebrew + manual installs)
    ///   3. `/opt/homebrew/bin/ntn`  (Apple Silicon Homebrew)
    ///   4. `~/.local/bin/ntn`  (user-local install)
    /// Throws `NotionError.toolFailed` with a clear message when nothing is
    /// found so the failing row shows the user how to fix it instead of a
    /// generic "ntn workers exec exited 127".
    private static func resolveNtnBinary() throws -> URL {
        let fm = FileManager.default
        var candidates: [String] = []

        if let override = ProcessInfo.processInfo.environment["NTN_BIN"],
           !override.isEmpty {
            candidates.append((override as NSString).expandingTildeInPath)
        }
        candidates.append("/usr/local/bin/ntn")
        candidates.append("/opt/homebrew/bin/ntn")
        let home = fm.homeDirectoryForCurrentUser
        candidates.append(home.appendingPathComponent(".local/bin/ntn").path)

        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        throw NotionError.toolFailed(
            "ntn CLI not found. Set $NTN_BIN or install at /usr/local/bin/ntn, "
            + "/opt/homebrew/bin/ntn, or ~/.local/bin/ntn"
        )
    }

    /// Parse the tool response and throw if it is a JSON object whose `ok`
    /// field is explicitly false. Tools without an `ok` field (e.g. tidyNow)
    /// are considered successful by virtue of a zero exit / 200 response.
    private static func validateToolResponse(_ data: Data) throws {
        // ntn sometimes prefixes JSON with diagnostic lines — pull the last
        // full JSON object if the whole blob isn't directly parseable.
        let parsed: Any? = (try? JSONSerialization.jsonObject(with: data))
            ?? jsonObjectFromLastObject(of: data)
        guard let dict = parsed as? [String: Any] else { return }
        if let ok = dict["ok"] as? Bool, ok == false {
            let err = (dict["error"] as? String) ?? "tool reported ok=false"
            throw NotionError.toolFailed(err)
        }
    }

    private static func describeCliFailure(_ body: String, toolName: String, status: Int32) -> String {
        let clean = body
            .replacingOccurrences(
                of: "\u{001B}\\[[0-9;]*m",
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            return "ntn workers exec \(toolName) exited \(status)"
        }

        if clean.contains("Cannot modify read-only property") {
            return "Worker could not stamp the managed Notion row because Notion keeps it read-only. The action may have completed; refresh and retry."
        }

        if let errorRange = clean.range(of: "Error: ") {
            let detail = clean[errorRange.upperBound...]
                .split(whereSeparator: \.isNewline)
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let detail, !detail.isEmpty {
                return detail
            }
        }

        let firstLine = clean
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
            ?? clean
        return "ntn \(toolName) failed: \(String(firstLine.prefix(160)))"
    }

    private static func jsonObjectFromLastObject(of data: Data) -> Any? {
        guard let s = String(data: data, encoding: .utf8) else { return nil }
        var searchEnd = s.endIndex
        while let range = s.range(of: "{", options: .backwards, range: s.startIndex..<searchEnd) {
            let candidate = String(s[range.lowerBound...])
            if let d = candidate.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: d) {
                return obj
            }
            searchEnd = range.lowerBound
        }
        return nil
    }

    private static func workersDirectoryURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["COMPOST_WORKERS_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("compost/workers")
    }
}

// MARK: - DTOs

struct NotionQueryResponse: Decodable {
    let results: [NotionPage]
    let next_cursor: String?
    let has_more: Bool
}

struct NotionPage: Decodable {
    let id: String
    let properties: [String: NotionProperty]
    let last_edited_time: String?
    let archived: Bool?
}

struct NotionProperty: Decodable {
    let type: String
    let title: [NotionText]?
    let rich_text: [NotionText]?
    let `select`: NotionSelect?
    let checkbox: Bool?
    let date: NotionDate?
    let number: Double?
}

struct NotionText: Decodable {
    let plain_text: String
}

struct NotionSelect: Decodable {
    let name: String
}

struct NotionDate: Decodable {
    let start: String
}

extension NotionProperty {
    var plainText: String {
        if let rt = rich_text { return rt.map { $0.plain_text }.joined() }
        if let t = title { return t.map { $0.plain_text }.joined() }
        if let s = `select` { return s.name }
        if let c = checkbox { return c ? "true" : "false" }
        if let n = number { return String(n) }
        return ""
    }
}
