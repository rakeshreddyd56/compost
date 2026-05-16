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
    let parentPage: String

    static let empty = NotionDbIds(compostPile: "", frozenDrafts: "", weeklyDigests: "", cueCards: "", parentPage: "")
}

enum NotionError: Error {
    case httpStatus(Int, String)
    case decoding
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
        return pages.compactMap(Proposal.init)
    }

    func fetchReadyDrafts() async throws -> [FrozenDraft] {
        let pages = try await queryDatabase(ids.frozenDrafts, filter: [
            "property": "Status",
            "select": ["equals": "frozen"],
        ])
        return pages.compactMap(FrozenDraft.init)
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

    // MARK: - Tool invocation
    //
    // Two paths, try in order:
    //  (A) Notion REST endpoint for invoking a Worker tool (verify Sat AM).
    //  (B) Shell out to `ntn workers exec <toolName> --remote -d '<json>'`.

    func invokeTool(_ toolName: String, input: [String: Any]) async throws -> Data {
        // Try (A): direct REST. Endpoint path is TBD — adjust on Saturday.
        do {
            var req = authed(base.appendingPathComponent("workers/tools/\(toolName)/invoke"))
            req.httpMethod = "POST"
            req.httpBody = try JSONSerialization.data(withJSONObject: input)
            let (data, resp) = try await session.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 200 { return data }
        } catch { /* fall through */ }

        // (B): shell-out fallback to `ntn workers exec`.
        // `ntn` reads workers.json from the current working directory to find
        // the worker ID — without cwd it fails with "No worker ID found" when
        // the app is launched from the .app bundle. Resolve workers dir from
        // env override first, then the canonical ~/compost/workers path.
        let json = try JSONSerialization.data(withJSONObject: input)
        let jsonString = String(data: json, encoding: .utf8) ?? "{}"

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/local/bin/ntn")
        task.arguments = ["workers", "exec", toolName, "--remote", "-d", jsonString]
        task.currentDirectoryURL = Self.workersDirectoryURL()

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        return pipe.fileHandleForReading.readDataToEndOfFile()
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
