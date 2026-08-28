import Foundation

enum PromptTitleFormatter {
    private static let injectedBlockPattern = "(?is)<(?:environment_context|recommended_plugins|app-context|skills_instructions|permissions(?:\\s+instructions)?|collaboration_mode|apps_instructions|plugins_instructions)\\b[^>]*>.*?</(?:environment_context|recommended_plugins|app-context|skills_instructions|permissions|collaboration_mode|apps_instructions|plugins_instructions)>"

    static func title(from rawValue: String) -> String? {
        var raw = rawValue
        let hadImageMarker = raw.range(of: "(?is)</?image\\b|!\\[[^]]*\\]\\(", options: .regularExpression) != nil
        if let marker = raw.range(of: "## My request:", options: .backwards) {
            raw = String(raw[marker.upperBound...])
        }

        raw = raw.replacingOccurrences(
            of: "(?is)<image\\b[^>]*>.*?</image>|</?image\\b[^>]*>|!\\[[^]]*\\]\\([^)]*\\)",
            with: " ",
            options: .regularExpression
        )
        // Codex serializes runtime configuration as role=user messages before
        // the person's actual prompt. These blocks are transport metadata, not
        // conversation text, and must never become a visible title.
        raw = raw.replacingOccurrences(
            of: injectedBlockPattern,
            with: " ",
            options: .regularExpression
        )

        let meaningfulLines = raw.components(separatedBy: .newlines).compactMap { line -> String? in
            var value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty,
                  !value.hasPrefix("# Files mentioned"),
                  !value.hasPrefix("Distinguish instructions"),
                  !value.hasPrefix("<image"),
                  !value.hasPrefix("image name="),
                  !value.hasPrefix("/var/folders/"),
                  !["修改：", "修改:", "调整：", "调整:"].contains(value)
            else { return nil }
            value = value.replacingOccurrences(of: "^\\s*\\d+[\\.、\\)]\\s*", with: "", options: .regularExpression)
            value = value.replacingOccurrences(of: "^[#*•-]+\\s*", with: "", options: .regularExpression)
            return value.isEmpty ? nil : value
        }
        let text = meaningfulLines.joined(separator: " ")
            .replacingOccurrences(of: "`", with: "")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return hadImageMarker ? "图片对话" : nil }
        return clipped(text, limit: 12)
    }

    private static func clipped(_ value: String, limit: Int) -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit - 1)) + "…"
    }
}

struct TokenBreakdown: Codable, Equatable, Sendable {
    var input: Int64 = 0
    var cachedInput: Int64 = 0
    var output: Int64 = 0
    var reasoning: Int64 = 0
    var total: Int64 = 0

    var uncachedInput: Int64 { max(0, input - cachedInput) }
    var cacheHitRate: Double { input == 0 ? 0 : Double(cachedInput) / Double(input) }
}

struct TokenCreditRates: Equatable, Sendable {
    let input: Double
    let cachedInput: Double
    let output: Double
}

enum QuotaCreditWeighting {
    /// Current Codex credit rates per one million tokens. Unknown models use
    /// the Sol rate as a conservative fallback instead of treating every token
    /// as equally expensive.
    static func rates(for model: String?) -> TokenCreditRates {
        let name = model?.lowercased() ?? ""
        if name.contains("5.6-luna") { return .init(input: 5, cachedInput: 0.5, output: 30) }
        if name.contains("5.6-terra") { return .init(input: 50, cachedInput: 5, output: 300) }
        if name.contains("5.6-sol") { return .init(input: 100, cachedInput: 10, output: 500) }
        if name.contains("5.4-mini") { return .init(input: 18.75, cachedInput: 1.875, output: 113) }
        if name.contains("5.5") { return .init(input: 125, cachedInput: 12.5, output: 750) }
        if name.contains("5.4") { return .init(input: 62.5, cachedInput: 6.25, output: 375) }
        return .init(input: 100, cachedInput: 10, output: 500)
    }

    static func credits(for tokens: TokenBreakdown, model: String?) -> Double {
        let rates = rates(for: model)
        let uncached = Double(tokens.uncachedInput) * rates.input
        let cached = Double(tokens.cachedInput) * rates.cachedInput
        let generated = Double(tokens.output + tokens.reasoning) * rates.output
        return (uncached + cached + generated) / 1_000_000
    }

    static func accountCoveredCredits(localCredits: Double, localTokens: Int64, accountTokens: Int64) -> Double {
        guard localCredits > 0, localTokens > 0 else { return 0 }
        let coverage = max(1, Double(accountTokens) / Double(localTokens))
        return localCredits * coverage
    }
}

struct TurnUsage: Identifiable, Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case completed
        case interrupted
        case failed
        case inProgress
    }

    let id: String
    let threadID: String
    /// The native Codex turn identifier when it is present in rollout logs.
    /// Optional so usage cached by earlier Codex Meter builds remains readable.
    let turnID: String?
    let startedAt: Date
    let completedAt: Date
    let tokens: TokenBreakdown
    let status: Status
    let model: String?
    let reasoningEffort: String?
    let toolCallCount: Int
    let contextWindow: Int64?
    let ordinal: Int
    let workspaceName: String?
    let threadTitle: String?

    var duration: TimeInterval { completedAt.timeIntervalSince(startedAt) }
    var contextOccupancy: Double? {
        guard let contextWindow, contextWindow > 0 else { return nil }
        return min(1, Double(tokens.input) / Double(contextWindow))
    }
}

struct TurnQuotaImpact: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case estimated
    }

    let percent: Double?
    let isBelowResolution: Bool
    let source: Source
    let capturedAt: Date

    var compactValue: String {
        if isBelowResolution { return source == .estimated ? "≈<0.1%" : "<1%" }
        guard let percent else { return "—" }
        if percent >= 1, percent.rounded() == percent {
            return "\(Int(percent))%"
        }
        return "≈\(percent.formatted(.number.precision(.fractionLength(1))))%"
    }

    var sourceLabel: String {
        "加权估算"
    }
}

struct AccountUsageReconciliation: Equatable, Sendable {
    let observedPercent: Double
    let localEstimatedPercent: Double
    let unattributedPercent: Double
    let capturedAt: Date
}

struct QuotaObservation: Codable, Equatable, Sendable {
    let fetchedAt: Date
    let usedPercent: Int
    let resetsAt: Date?
    let windowDurationMinutes: Int64?
}

enum QuotaPace: Equatable, Sendable {
    case unavailable
    case accumulating(elapsed: TimeInterval, required: TimeInterval)
    case stable
    case sustainable(projectedRemainingAtReset: Double)
    case exhausts(at: Date)
}

struct DailyUsage: Identifiable, Codable, Equatable, Sendable {
    var id: String { startDate }
    let startDate: String
    let tokens: Int64
}

struct QuotaWindow: Codable, Equatable, Sendable {
    let usedPercent: Int
    let windowDurationMinutes: Int64?
    let resetsAt: Date?

    var remainingPercent: Int { max(0, 100 - usedPercent) }
}

struct AccountQuota: Codable, Equatable, Sendable {
    let planType: String?
    let primary: QuotaWindow?
    let secondary: QuotaWindow?
    let creditBalance: String?
    let hasCredits: Bool
    let unlimitedCredits: Bool
    let resetCreditCount: Int
    let limitReached: Bool
}

struct AccountUsageSummary: Codable, Equatable, Sendable {
    let lifetimeTokens: Int64?
    let peakDailyTokens: Int64?
    let longestRunningTurnSeconds: Int64?
    let currentStreakDays: Int64?
    let longestStreakDays: Int64?
}

struct AccountSnapshot: Codable, Sendable {
    let quota: AccountQuota
    let usage: AccountUsageSummary?
    let dailyUsage: [DailyUsage]?
    let fetchedAt: Date
}

enum ConnectionState: Equatable, Sendable {
    case connecting
    case live(Date)
    case stale(Date)
    case unavailable(String)

    var label: String {
        switch self {
        case .connecting: return "正在连接"
        case .live: return "实时"
        case .stale: return "缓存"
        case .unavailable: return "不可用"
        }
    }
}
