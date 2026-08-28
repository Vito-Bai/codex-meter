import Darwin
import Foundation

final class SessionUsageScanner: @unchecked Sendable {
    private struct ParserState: Codable {
        var threadID: String
        var currentTurnID: String?
        var startedAt: Date?
        var latestAt: Date?
        var latestTokens: TokenBreakdown?
        var model: String?
        var effort: String?
        var workspaceName: String?
        var threadTitle: String?
        var currentPromptTitle: String?
        var currentPromptHadImage = false
        var tools = 0
        var ordinal = 0
        var turns: [TurnUsage] = []

        init(fallbackThreadID: String) {
            threadID = fallbackThreadID
        }
    }

    private struct CachedFile {
        var parser: ParserState
        var offset: UInt64 = 0
        var pendingLine = Data()
        var modifiedAt: Date?
    }

    private struct PersistedCache: Codable {
        let version: Int
        let promptTitlesIncluded: Bool
        let files: [PersistedFile]
    }

    private struct PersistedFile: Codable {
        let path: String
        let parser: ParserState
        let offset: UInt64
        let modifiedAt: Date?
    }

    private let fileManager = FileManager.default
    private let scanLock = NSLock()
    private var cachedFiles: [URL: CachedFile] = [:]
    private var cacheIncludesPromptTitles = false
    private var lastCacheSaveAt: Date?
    private let readChunkSize = 1_048_576
    private let directTitleMigrationKey = "CodexMeterPromptTitlesDirectV1"

    private let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let relevantMarkers = [
        "session_meta", "task_started", "turn_context", "custom_tool_call",
        "function_call", "mcp_tool_call", "web_search_call", "token_count", "task_complete",
        "\"role\":\"user\""
    ].map { Data($0.utf8) }

    init() {
        loadPersistentCache()
    }

    func scanRecentTurns(days: Int = 30, includePromptTitles: Bool = true) async -> [TurnUsage] {
        await Task.detached(priority: .background) {
            let turns = self.scanLock.withLock {
                self.scan(days: days, includePromptTitles: includePromptTitles)
            }
            // Large historical JSON lines make Darwin's allocator retain empty
            // regions after the one-time backfill. Return those pages promptly
            // so this menu-bar utility reaches its small steady-state footprint.
            malloc_zone_pressure_relief(nil, 0)
            return turns
        }.value
    }

    func parse(data: Data, fallbackThreadID: String = "local", includePromptTitles: Bool = true) -> [TurnUsage] {
        var parser = ParserState(fallbackThreadID: fallbackThreadID)
        consumeCompleteData(data, parser: &parser, includePromptTitles: includePromptTitles)
        return parser.turns
    }

    func parse(lines: [String], fallbackThreadID: String) -> [TurnUsage] {
        var parser = ParserState(fallbackThreadID: fallbackThreadID)
        for line in lines {
            autoreleasepool {
                consumeLine(Data(line.utf8), parser: &parser, includePromptTitles: true)
            }
        }
        return parser.turns
    }

    private func scan(days: Int, includePromptTitles: Bool) -> [TurnUsage] {
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".codex/archived_sessions", isDirectory: true)
        ]
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey]
        var seenFiles = Set<URL>()
        var results: [TurnUsage] = []
        var cacheChanged = false

        if includePromptTitles, !cacheIncludesPromptTitles, !cachedFiles.isEmpty {
            cachedFiles.removeAll()
            cacheChanged = true
        }

        if includePromptTitles,
           !cachedFiles.isEmpty,
           !UserDefaults.standard.bool(forKey: directTitleMigrationKey) {
            if refreshRecentPromptTitles(limit: 5) { cacheChanged = true }
            UserDefaults.standard.set(true, forKey: directTitleMigrationKey)
        }

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      (values.contentModificationDate ?? .distantPast) >= cutoff
                else { continue }

                seenFiles.insert(url)
                let fileSize = UInt64(max(0, values.fileSize ?? 0))
                let hadCachedFile = cachedFiles[url] != nil
                var cached = cachedFiles[url] ?? CachedFile(
                    parser: ParserState(fallbackThreadID: url.deletingPathExtension().lastPathComponent)
                )
                if !hadCachedFile { cacheChanged = true }

                // Rollout files are append-only. If one is replaced or truncated,
                // discard its cursor and rebuild just that file.
                if fileSize < cached.offset {
                    cached = CachedFile(
                        parser: ParserState(fallbackThreadID: url.deletingPathExtension().lastPathComponent)
                    )
                    cacheChanged = true
                }

                if fileSize > cached.offset {
                    readAppendedBytes(from: url, through: fileSize, cached: &cached, includePromptTitles: includePromptTitles)
                    cacheChanged = true
                }

                cached.modifiedAt = values.contentModificationDate
                cachedFiles[url] = cached
                if includePromptTitles {
                    results.append(contentsOf: cached.parser.turns)
                } else {
                    results.append(contentsOf: cached.parser.turns.map(Self.removingPromptTitle))
                }
            }
        }

        if cachedFiles.keys.contains(where: { !seenFiles.contains($0) }) { cacheChanged = true }
        cachedFiles = cachedFiles.filter { seenFiles.contains($0.key) }
        cacheIncludesPromptTitles = includePromptTitles
        // Active sessions append frequently. Serializing the complete parser
        // cache on every poll competes with menu animation, while the in-memory
        // cursor is already sufficient between durable checkpoints.
        if cacheChanged,
           lastCacheSaveAt.map({ Date().timeIntervalSince($0) >= 30 }) ?? true {
            savePersistentCache()
            lastCacheSaveAt = .now
        }
        return results.sorted { $0.completedAt > $1.completedAt }
    }

    private var cacheURL: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("CodexMeter", isDirectory: true)
            .appendingPathComponent("session-scan-cache-v1.json")
    }

    private func loadPersistentCache() {
        guard let data = try? Data(contentsOf: cacheURL),
              let persisted = try? JSONDecoder().decode(PersistedCache.self, from: data),
              persisted.version == 5
        else { return }

        cacheIncludesPromptTitles = persisted.promptTitlesIncluded

        cachedFiles = Dictionary(uniqueKeysWithValues: persisted.files.map { file in
            (
                URL(fileURLWithPath: file.path),
                CachedFile(
                    parser: file.parser,
                    offset: file.offset,
                    pendingLine: Data(),
                    modifiedAt: file.modifiedAt
                )
            )
        })
    }

    private func savePersistentCache() {
        let files = cachedFiles.map { url, cached in
            // An unterminated line has not been parsed. Re-read it on launch;
            // never persist its bytes because it could contain conversation text.
            PersistedFile(
                path: url.path,
                parser: cached.parser,
                offset: cached.offset - UInt64(cached.pendingLine.count),
                modifiedAt: cached.modifiedAt
            )
        }
        let persisted = PersistedCache(version: 5, promptTitlesIncluded: cacheIncludesPromptTitles, files: files)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        do {
            try fileManager.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // The in-memory cache remains valid; a later scan can retry saving.
        }
    }

    private func readAppendedBytes(from url: URL, through targetOffset: UInt64, cached: inout CachedFile, includePromptTitles: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: cached.offset)
            var remaining = targetOffset - cached.offset

            while remaining > 0 {
                let requested = min(readChunkSize, Int(remaining))
                guard let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else { break }
                cached.offset += UInt64(chunk.count)
                remaining -= UInt64(chunk.count)
                consumeChunk(chunk, cached: &cached, includePromptTitles: includePromptTitles)
            }
        } catch {
            // Keep the last valid offset. The next scan retries only the unread tail.
        }
    }

    private func consumeChunk(_ chunk: Data, cached: inout CachedFile, includePromptTitles: Bool) {
        // Append in place so a multi-megabyte JSONL record does not cause the
        // entire pending prefix to be copied again for every 1 MB read chunk.
        cached.pendingLine.append(chunk)

        var lineStart = cached.pendingLine.startIndex
        for index in cached.pendingLine.indices where cached.pendingLine[index] == 0x0A {
            if index > lineStart {
                let line = cached.pendingLine.subdata(in: lineStart..<index)
                autoreleasepool {
                    consumeLine(line, parser: &cached.parser, includePromptTitles: includePromptTitles)
                }
            }
            lineStart = cached.pendingLine.index(after: index)
        }

        if lineStart == cached.pendingLine.endIndex {
            cached.pendingLine.removeAll(keepingCapacity: true)
        } else if lineStart > cached.pendingLine.startIndex {
            cached.pendingLine.removeSubrange(cached.pendingLine.startIndex..<lineStart)
        }
    }

    private func consumeCompleteData(_ data: Data, parser: inout ParserState, includePromptTitles: Bool) {
        var lineStart = data.startIndex
        for index in data.indices where data[index] == 0x0A {
            if index > lineStart {
                autoreleasepool {
                    consumeLine(data.subdata(in: lineStart..<index), parser: &parser, includePromptTitles: includePromptTitles)
                }
            }
            lineStart = data.index(after: index)
        }
        if lineStart < data.endIndex {
            autoreleasepool {
                consumeLine(data.subdata(in: lineStart..<data.endIndex), parser: &parser, includePromptTitles: includePromptTitles)
            }
        }
    }

    private func consumeLine(_ data: Data, parser: inout ParserState, includePromptTitles: Bool) {
        guard Self.relevantMarkers.contains(where: { data.range(of: $0) != nil }),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let type = object["type"] as? String
        let payload = object["payload"] as? [String: Any] ?? [:]
        let payloadType = payload["type"] as? String
        let timestamp = (object["timestamp"] as? String).flatMap(isoFormatter.date)
        if let timestamp { parser.latestAt = timestamp }

        if type == "session_meta", let id = payload["id"] as? String {
            parser.threadID = id
            if let cwd = payload["cwd"] as? String {
                parser.workspaceName = URL(fileURLWithPath: cwd).lastPathComponent
            }
            parser.threadTitle = payload["title"] as? String
        }

        if type == "event_msg", payloadType == "task_started" {
            parser.currentTurnID = payload["turn_id"] as? String
            parser.startedAt = timestamp ?? parser.latestAt ?? .now
            parser.latestTokens = nil
            parser.model = nil
            parser.effort = nil
            parser.tools = 0
            parser.currentPromptTitle = nil
            parser.currentPromptHadImage = false
            parser.ordinal += 1
            return
        }

        if includePromptTitles,
           type == "response_item",
           payloadType == "message",
           payload["role"] as? String == "user",
           parser.currentPromptTitle == nil,
           let content = payload["content"] as? [[String: Any]] {
            let inputTexts = content.compactMap { item -> String? in
                guard item["type"] as? String == "input_text" else { return nil }
                return item["text"] as? String ?? item["input_text"] as? String
            }
            // Do not lock onto the first role=user envelope. A turn can begin
            // with injected environment/plugin metadata and record the person's
            // real prompt in a following message.
            let promptTitle = inputTexts.compactMap(PromptTitleFormatter.title).first
            parser.currentPromptHadImage = content.contains { item in
                let type = item["type"] as? String ?? ""
                return type.contains("image")
            } || inputTexts.contains { $0.localizedCaseInsensitiveContains("<image") }
            parser.currentPromptTitle = promptTitle
                ?? (parser.currentPromptHadImage ? "图片对话" : nil)
        }

        if type == "turn_context" {
            parser.model = payload["model"] as? String ?? parser.model
            parser.effort = payload["effort"] as? String ?? payload["reasoning_effort"] as? String ?? parser.effort
        }

        if type == "response_item",
           ["custom_tool_call", "function_call", "mcp_tool_call", "web_search_call"].contains(payloadType ?? "") {
            parser.tools += 1
        }

        if type == "event_msg", payloadType == "token_count",
           let info = payload["info"] as? [String: Any] {
            if let last = info["last_token_usage"] as? [String: Any] {
                let increment = Self.tokens(last)
                parser.latestTokens = Self.add(parser.latestTokens ?? TokenBreakdown(), increment)
            } else if let total = info["total_token_usage"] as? [String: Any] {
                // Older rollout formats omit last_token_usage. In that format
                // the newest total is the best available value for the turn.
                parser.latestTokens = Self.tokens(total)
            }
        }

        if type == "event_msg", payloadType == "task_complete",
           let start = parser.startedAt,
           let tokens = parser.latestTokens {
            let end = timestamp ?? parser.latestAt ?? start
            let statusText = payload["status"] as? String
            let status: TurnUsage.Status = statusText == "failed" ? .failed : statusText == "interrupted" ? .interrupted : .completed
            parser.turns.append(TurnUsage(
                id: "\(parser.threadID)-\(Int(start.timeIntervalSince1970))-\(parser.ordinal)",
                threadID: parser.threadID,
                turnID: parser.currentTurnID,
                startedAt: start,
                completedAt: end,
                tokens: tokens,
                status: status,
                model: parser.model,
                reasoningEffort: parser.effort,
                toolCallCount: parser.tools,
                contextWindow: nil,
                ordinal: parser.ordinal,
                workspaceName: parser.workspaceName,
                threadTitle: parser.currentPromptTitle ?? parser.threadTitle
            ))
            parser.startedAt = nil
            parser.latestTokens = nil
            parser.currentTurnID = nil
        }
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return 0
    }

    private static func tokens(_ object: [String: Any]) -> TokenBreakdown {
        TokenBreakdown(
            input: int64(object["input_tokens"]),
            cachedInput: int64(object["cached_input_tokens"]),
            output: int64(object["output_tokens"]),
            reasoning: int64(object["reasoning_output_tokens"]),
            total: int64(object["total_tokens"])
        )
    }

    private static func add(_ lhs: TokenBreakdown, _ rhs: TokenBreakdown) -> TokenBreakdown {
        TokenBreakdown(
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            output: lhs.output + rhs.output,
            reasoning: lhs.reasoning + rhs.reasoning,
            total: lhs.total + rhs.total
        )
    }

    private static func removingPromptTitle(_ turn: TurnUsage) -> TurnUsage {
        replacingPromptTitle(turn, with: nil)
    }

    private static func replacingPromptTitle(_ turn: TurnUsage, with title: String?) -> TurnUsage {
        TurnUsage(
            id: turn.id,
            threadID: turn.threadID,
            turnID: turn.turnID,
            startedAt: turn.startedAt,
            completedAt: turn.completedAt,
            tokens: turn.tokens,
            status: turn.status,
            model: turn.model,
            reasoningEffort: turn.reasoningEffort,
            toolCallCount: turn.toolCallCount,
            contextWindow: turn.contextWindow,
            ordinal: turn.ordinal,
            workspaceName: turn.workspaceName,
            threadTitle: title
        )
    }

    private func refreshRecentPromptTitles(limit: Int) -> Bool {
        var remaining = limit
        var changed = false
        let files = cachedFiles.keys.sorted {
            (cachedFiles[$0]?.modifiedAt ?? .distantPast) > (cachedFiles[$1]?.modifiedAt ?? .distantPast)
        }

        for url in files where remaining > 0 {
            guard var cached = cachedFiles[url], !cached.parser.turns.isEmpty,
                  let handle = try? FileHandle(forReadingFrom: url)
            else { continue }
            defer { try? handle.close() }

            let targetTurns = cached.parser.turns.sorted { $0.startedAt > $1.startedAt }.prefix(remaining)
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let rawSize = attributes[.size] as? NSNumber
            else { continue }
            let fileSize = rawSize.uint64Value
            let tailSize = min(fileSize, 6 * 1_048_576)

            do {
                try handle.seek(toOffset: fileSize - tailSize)
                guard var data = try handle.readToEnd(), !data.isEmpty else { continue }
                if tailSize < fileSize, let firstNewline = data.firstIndex(of: 0x0A) {
                    data.removeSubrange(data.startIndex...firstNewline)
                }

                var tailParser = ParserState(fallbackThreadID: cached.parser.threadID)
                tailParser.threadID = cached.parser.threadID
                consumeCompleteData(data, parser: &tailParser, includePromptTitles: true)

                for parsed in tailParser.turns.reversed() {
                    guard let title = parsed.threadTitle,
                          let target = targetTurns.first(where: { abs($0.startedAt.timeIntervalSince(parsed.startedAt)) < 1 }),
                          let index = cached.parser.turns.firstIndex(where: { $0.id == target.id })
                    else { continue }
                    cached.parser.turns[index] = Self.replacingPromptTitle(cached.parser.turns[index], with: title)
                    remaining -= 1
                    changed = true
                    if remaining == 0 { break }
                }
                cachedFiles[url] = cached
            } catch {
                continue
            }
        }
        return changed
    }
}
