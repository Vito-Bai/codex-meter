import Darwin
import Foundation

enum CodexAppServerError: LocalizedError {
    case codexNotFound
    case timedOut
    case malformedResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .codexNotFound: return "未找到 Codex CLI"
        case .timedOut: return "Codex 用量读取超时"
        case .malformedResponse: return "Codex 返回了无法识别的数据"
        case .server(let message): return message
        }
    }
}

struct CodexAppServerClient: Sendable {
    private let timeout: TimeInterval = 12

    func fetchSnapshot() async throws -> AccountSnapshot {
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                return try await Task.detached(priority: .utility) {
                    try fetchSynchronously()
                }.value
            } catch {
                lastError = error
                guard attempt == 0, Self.isTransient(error) else { throw error }
                // Only pay this cost after a transport failure. Successful
                // five-minute polling remains a single request/process.
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        throw lastError ?? CodexAppServerError.malformedResponse
    }

    private static func isTransient(_ error: Error) -> Bool {
        if case CodexAppServerError.timedOut = error { return true }
        guard case CodexAppServerError.server(let message) = error else { return false }
        let text = message.lowercased()
        return text.contains("error sending request")
            || text.contains("timed out")
            || text.contains("connection reset")
            || text.contains("connection refused")
            || text.contains("network")
    }

    private func fetchSynchronously() throws -> AccountSnapshot {
        guard let codex = Self.findCodexExecutable() else {
            throw CodexAppServerError.codexNotFound
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: codex)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        try process.run()

        let requests: [[String: Any]] = [
            ["id": 1, "method": "initialize", "params": [
                "clientInfo": ["name": "codex-meter", "version": "0.1.0"]
            ]],
            ["method": "initialized"],
            ["id": 2, "method": "account/rateLimits/read", "params": NSNull()],
            ["id": 3, "method": "account/usage/read", "params": NSNull()],
            ["id": 4, "method": "account/workspaceMessages/read", "params": NSNull()]
        ]

        for request in requests {
            let data = try JSONSerialization.data(withJSONObject: request)
            input.fileHandleForWriting.write(data)
            input.fileHandleForWriting.write(Data([0x0A]))
        }

        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        var rateResult: [String: Any]?
        var usageResult: [String: Any]?
        var usageFinished = false
        var messagesResult: [String: Any]?
        var messagesFinished = false
        var rateReceivedAt: Date?
        let descriptor = output.fileHandleForReading.fileDescriptor
        let originalFlags = fcntl(descriptor, F_GETFL)
        if originalFlags >= 0 { _ = fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) }

        while Date() < deadline, rateResult == nil || !usageFinished || !messagesFinished {
            if let rateReceivedAt, Date().timeIntervalSince(rateReceivedAt) >= 1.5 { break }
            let hardRemaining = max(0, deadline.timeIntervalSinceNow)
            let graceRemaining = rateReceivedAt.map { max(0, 1.5 - Date().timeIntervalSince($0)) } ?? hardRemaining
            let waitMilliseconds = Int32(max(1, min(hardRemaining, graceRemaining) * 1_000))
            var event = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&event, 1, waitMilliseconds)
            if pollResult == 0 { continue }
            if pollResult < 0 {
                if errno == EINTR { continue }
                break
            }
            guard event.revents & Int16(POLLIN) != 0 else {
                if event.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { break }
                continue
            }
            var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
            let count = Darwin.read(descriptor, &bytes, bytes.count)
            if count < 0, errno == EAGAIN || errno == EWOULDBLOCK { continue }
            guard count > 0 else { break }
            buffer.append(bytes, count: count)

            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard !line.isEmpty,
                      let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
                else { continue }

                if let error = object["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "Codex App Server 请求失败"
                    if Self.int(object["id"]) == 3 {
                        usageFinished = true
                        continue
                    }
                    if Self.int(object["id"]) == 4 {
                        messagesFinished = true
                        continue
                    }
                    terminate(process)
                    throw CodexAppServerError.server(message)
                }

                switch Self.int(object["id"]) {
                case 2:
                    rateResult = object["result"] as? [String: Any]
                    rateReceivedAt = .now
                case 3:
                    usageResult = object["result"] as? [String: Any]
                    usageFinished = true
                case 4:
                    messagesResult = object["result"] as? [String: Any]
                    messagesFinished = true
                default: break
                }
            }
        }

        terminate(process)
        guard let rateResult else {
            throw Date() >= deadline ? CodexAppServerError.timedOut : CodexAppServerError.malformedResponse
        }

        return try Self.parse(
            rateResult: rateResult,
            usageResult: usageResult,
            messagesResult: messagesResult
        )
    }

    private func terminate(_ process: Process) {
        if process.isRunning { process.terminate() }
    }

    static func parse(
        rateResult: [String: Any],
        usageResult: [String: Any]?,
        messagesResult: [String: Any]? = nil
    ) throws -> AccountSnapshot {
        guard let rate = rateResult["rateLimits"] as? [String: Any] else {
            throw CodexAppServerError.malformedResponse
        }

        func window(_ value: Any?) -> QuotaWindow? {
            guard let object = value as? [String: Any], let used = int(object["usedPercent"]) else { return nil }
            let reset = int64(object["resetsAt"]).map { Date(timeIntervalSince1970: TimeInterval($0)) }
            return QuotaWindow(
                usedPercent: used,
                windowDurationMinutes: int64(object["windowDurationMins"]),
                resetsAt: reset
            )
        }

        let credits = rate["credits"] as? [String: Any]
        let resetCredits = rateResult["rateLimitResetCredits"] as? [String: Any]
        let quota = AccountQuota(
            planType: rate["planType"] as? String,
            primary: window(rate["primary"]),
            secondary: window(rate["secondary"]),
            creditBalance: credits?["balance"] as? String,
            hasCredits: credits?["hasCredits"] as? Bool ?? false,
            unlimitedCredits: credits?["unlimited"] as? Bool ?? false,
            resetCreditCount: int(resetCredits?["availableCount"]) ?? 0,
            limitReached: rate["rateLimitReachedType"] is String || rate["spendControlReached"] as? Bool == true
        )

        let summary = usageResult.map { result in
            let summaryObject = result["summary"] as? [String: Any] ?? [:]
            return AccountUsageSummary(
                lifetimeTokens: int64(summaryObject["lifetimeTokens"]),
                peakDailyTokens: int64(summaryObject["peakDailyTokens"]),
                longestRunningTurnSeconds: int64(summaryObject["longestRunningTurnSec"]),
                currentStreakDays: int64(summaryObject["currentStreakDays"]),
                longestStreakDays: int64(summaryObject["longestStreakDays"])
            )
        }

        let daily = usageResult.map { result in
            (result["dailyUsageBuckets"] as? [[String: Any]] ?? []).compactMap { bucket -> DailyUsage? in
                guard let date = bucket["startDate"] as? String, let tokens = int64(bucket["tokens"]) else { return nil }
                return DailyUsage(startDate: date, tokens: tokens)
            }
        }

        let messages = (messagesResult?["messages"] as? [[String: Any]])?.compactMap { message -> WorkspaceMessage? in
            guard let messageID = message["messageId"] as? String,
                  let body = message["messageBody"] as? String,
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return WorkspaceMessage(
                messageID: messageID,
                messageType: message["messageType"] as? String,
                messageBody: body,
                createdAt: Self.unixDate(message["createdAt"]),
                archivedAt: Self.unixDate(message["archivedAt"]),
                announcedResetAt: Self.detectedDate(in: body)
            )
        }

        return AccountSnapshot(
            quota: quota,
            usage: summary,
            dailyUsage: daily,
            workspaceMessages: messages,
            fetchedAt: .now
        )
    }

    private static func findCodexExecutable() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = [
            // The Codex desktop app is currently shipped as ChatGPT.app and
            // includes the same app-server-capable executable. Prefer it so a
            // user does not need to install the CLI separately.
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            home.appendingPathComponent("Applications/ChatGPT.app/Contents/Resources/codex").path,
            "/Applications/Codex.app/Contents/Resources/codex",
            home.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path,
            home.appendingPathComponent(".npm-global/bin/codex").path,
            home.appendingPathComponent(".local/bin/codex").path,
            home.appendingPathComponent(".bun/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        // Also discover renamed or nonstandard desktop installs by bundle ID.
        // This only scans the top level of the two Applications directories.
        let applicationRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in applicationRoots {
            guard let apps = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for app in apps where app.pathExtension == "app" {
                guard Bundle(url: app)?.bundleIdentifier == "com.openai.codex" else { continue }
                candidates.append(app.appendingPathComponent("Contents/Resources/codex").path)
            }
        }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private static func unixDate(_ value: Any?) -> Date? {
        int64(value).map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    private static func detectedDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        return detector.firstMatch(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )?.date
    }
}
