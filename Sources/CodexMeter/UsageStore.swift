import AppKit
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var quota: AccountQuota?
    @Published private(set) var accountUsage: AccountUsageSummary?
    @Published private(set) var dailyUsage: [DailyUsage] = []
    @Published private(set) var workspaceMessages: [WorkspaceMessage] = []
    @Published private(set) var turns: [TurnUsage] = []
    @Published private(set) var accountReconciliation: AccountUsageReconciliation?
    @Published private(set) var connection: ConnectionState = .connecting
    @Published private(set) var isRefreshing = false
    @Published var transientTurn: TurnUsage?

    @Published var menuFeedbackEnabled: Bool {
        didSet { defaults.set(menuFeedbackEnabled, forKey: PreferenceKey.menuFeedbackEnabled) }
    }
    @Published var menuFeedbackSeconds: Double {
        didSet { defaults.set(menuFeedbackSeconds, forKey: PreferenceKey.menuFeedbackSeconds) }
    }
    @Published var turnHistoryEnabled: Bool {
        didSet { defaults.set(turnHistoryEnabled, forKey: PreferenceKey.turnHistoryEnabled) }
    }
    @Published var highUsageNotificationsEnabled: Bool {
        didSet { defaults.set(highUsageNotificationsEnabled, forKey: PreferenceKey.highUsageNotificationsEnabled) }
    }
    @Published var promptTitlesEnabled: Bool {
        didSet {
            defaults.set(promptTitlesEnabled, forKey: PreferenceKey.promptTitlesEnabled)
            Task { @MainActor [weak self] in
                await self?.refreshTurns(showFeedback: false)
            }
        }
    }
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginMessage: String?

    private let defaults: UserDefaults
    private let client = CodexAppServerClient()
    private let scanner = SessionUsageScanner()
    private let titleReader = CodexThreadTitleReader()
    private var refreshTimer: Timer?
    private var scanTimer: Timer?
    private var feedbackTask: Task<Void, Never>?
    private var accountRetryTask: Task<Void, Never>?
    private var accountRetryAttempt = 0
    private let accountRetryDelays: [UInt64] = [5, 15, 30]
    private var knownTurnIDs = Set<String>()
    private var hasStarted = false
    private var isScanningTurns = false
    private var isRefreshingAccount = false
    private var lastQuotaObservation: QuotaObservation?
    private var quotaObservations: [QuotaObservation] = []
    private var threadTaskTitles: [String: String] = [:]
    private var titlesFetchedAt: Date?
    private var readOfficialResetMessageIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuFeedbackEnabled = defaults.value(for: PreferenceKey.menuFeedbackEnabled, default: true)
        menuFeedbackSeconds = min(max(defaults.value(for: PreferenceKey.menuFeedbackSeconds, default: 8), 3), 15)
        turnHistoryEnabled = defaults.value(for: PreferenceKey.turnHistoryEnabled, default: true)
        highUsageNotificationsEnabled = defaults.value(for: PreferenceKey.highUsageNotificationsEnabled, default: false)
        promptTitlesEnabled = defaults.value(for: PreferenceKey.promptTitlesEnabled, default: true)
        readOfficialResetMessageIDs = Set(defaults.stringArray(forKey: PreferenceKey.readOfficialResetMessageIDs) ?? [])
        refreshLaunchAtLoginStatus()
        loadQuotaHistory()
        loadCachedSnapshot()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLoginMessage = "无法更新登录项：\(error.localizedDescription)"
        }
        refreshLaunchAtLoginStatus()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func refreshLaunchAtLoginStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
        case .requiresApproval:
            launchAtLoginEnabled = false
            if launchAtLoginMessage == nil {
                launchAtLoginMessage = "需要在“系统设置 → 登录项”中允许 Codex Meter。"
            }
        case .notRegistered, .notFound:
            launchAtLoginEnabled = false
        @unknown default:
            launchAtLoginEnabled = false
        }
    }

    var weeklyWindow: QuotaWindow? { quota?.weeklyWindow }
    var shortWindow: QuotaWindow? { quota?.shortWindow }
    var preferredWindow: QuotaWindow? { quota?.preferredWindow }
    var remainingPercent: Int { preferredWindow?.remainingPercent ?? 0 }
    var quotaColorAvailable: Bool { preferredWindow != nil }
    var recentTurns: [TurnUsage] { Array(turns.prefix(10)) }
    var officialResetNotice: WorkspaceMessage? {
        workspaceMessages
            .filter(\.isCodexUsageResetNotice)
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
            .first
    }
    var hasUnreadOfficialResetNotice: Bool {
        guard let notice = officialResetNotice else { return false }
        return !readOfficialResetMessageIDs.contains(notice.messageID)
    }

    func markOfficialResetNoticeRead() {
        guard let notice = officialResetNotice,
              readOfficialResetMessageIDs.insert(notice.messageID).inserted
        else { return }
        defaults.set(Array(readOfficialResetMessageIDs).sorted(), forKey: PreferenceKey.readOfficialResetMessageIDs)
        objectWillChange.send()
    }

    func isOfficialResetConfirmed(_ notice: WorkspaceMessage) -> Bool {
        guard let resetAt = notice.announcedResetAt, resetAt <= Date() else { return false }
        let nearby = quotaObservations
            .filter { abs($0.fetchedAt.timeIntervalSince(resetAt)) <= 24 * 60 * 60 }
            .sorted { $0.fetchedAt < $1.fetchedAt }
        guard let before = nearby.last(where: { $0.fetchedAt < resetAt }),
              let after = nearby.first(where: { $0.fetchedAt >= resetAt })
        else { return false }
        let usageRestored = after.usedPercent + 2 < before.usedPercent
        let resetWindowChanged = !sameReset(before.resetsAt, after.resetsAt)
        return usageRestored || resetWindowChanged
    }

    var weeklyQuotaPace: QuotaPace { quotaPace(for: weeklyWindow) }

    private func quotaPace(for window: QuotaWindow?) -> QuotaPace {
        guard let window,
              let reset = window.resetsAt,
              let durationMinutes = window.windowDurationMinutes
        else { return .unavailable }

        let relevant = quotaObservations
            .filter { sameReset($0.resetsAt, reset) && $0.fetchedAt <= Date() }
            .sorted { $0.fetchedAt < $1.fetchedAt }
        guard let first = relevant.first, let last = relevant.last else {
            return .accumulating(elapsed: 0, required: minimumPaceSampleDuration(for: durationMinutes))
        }

        let elapsed = last.fetchedAt.timeIntervalSince(first.fetchedAt)
        let required = minimumPaceSampleDuration(for: durationMinutes)
        guard elapsed >= required else { return .accumulating(elapsed: elapsed, required: required) }

        let change = last.usedPercent - first.usedPercent
        guard change >= 2, elapsed > 0 else { return .stable }

        let percentPerSecond = Double(change) / elapsed
        let secondsUntilReset = max(0, reset.timeIntervalSince(last.fetchedAt))
        let projectedUse = percentPerSecond * secondsUntilReset
        let projectedRemaining = Double(max(0, 100 - last.usedPercent)) - projectedUse
        if projectedRemaining > 0 {
            return .sustainable(projectedRemainingAtReset: projectedRemaining)
        }
        let exhaustion = last.fetchedAt.addingTimeInterval(Double(max(0, 100 - last.usedPercent)) / percentPerSecond)
        return .exhausts(at: exhaustion)
    }

    var medianTurnTokens: Int64? {
        let values = turns.prefix(20).map(\.tokens.total).sorted()
        guard !values.isEmpty else { return nil }
        return values[values.count / 2]
    }

    var latestTurnRatio: Double? {
        guard let latest = turns.first, let median = medianTurnTokens, median > 0 else { return nil }
        return Double(latest.tokens.total) / Double(median)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        Task { await refreshAll() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAccount(resetRetryBudget: true) }
        }
        refreshTimer?.tolerance = 30
        scanTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshTurns(showFeedback: true) }
        }
        scanTimer?.tolerance = 1
    }

    func stop() {
        refreshTimer?.invalidate()
        scanTimer?.invalidate()
        feedbackTask?.cancel()
        accountRetryTask?.cancel()
        refreshTimer = nil
        scanTimer = nil
        accountRetryTask = nil
        hasStarted = false
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        async let account: Void = refreshAccount(resetRetryBudget: true)
        async let sessionTurns: Void = refreshTurns(showFeedback: false)
        _ = await (account, sessionTurns)
        isRefreshing = false
    }

    func refreshAccount(resetRetryBudget: Bool = false) async {
        guard !isRefreshingAccount else { return }
        if resetRetryBudget, accountRetryTask == nil { accountRetryAttempt = 0 }
        isRefreshingAccount = true
        defer { isRefreshingAccount = false }
        if quota == nil { connection = .connecting }
        do {
            let snapshot = try await client.fetchSnapshot()
            quota = snapshot.quota
            if let usage = snapshot.usage { accountUsage = usage }
            if let usage = snapshot.dailyUsage { dailyUsage = usage }
            if let messages = snapshot.workspaceMessages {
                let existing = Dictionary(uniqueKeysWithValues: workspaceMessages.map { ($0.messageID, $0) })
                workspaceMessages = messages
                    .filter(\.isActive)
                    .map { $0.preservingAnnouncedResetAt(from: existing[$0.messageID]) }
            }
            if let window = snapshot.quota.weeklyWindow ?? snapshot.quota.preferredWindow {
                let observation = QuotaObservation(
                    fetchedAt: snapshot.fetchedAt,
                    usedPercent: window.usedPercent,
                    resetsAt: window.resetsAt,
                    windowDurationMinutes: window.windowDurationMinutes
                )
                recordQuotaObservation(observation)
            }
            if let weekly = snapshot.quota.weeklyWindow ?? snapshot.quota.preferredWindow {
                lastQuotaObservation = QuotaObservation(
                    fetchedAt: snapshot.fetchedAt,
                    usedPercent: weekly.usedPercent,
                    resetsAt: weekly.resetsAt,
                    windowDurationMinutes: weekly.windowDurationMinutes
                )
            }
            connection = .live(snapshot.fetchedAt)
            accountRetryAttempt = 0
            accountRetryTask?.cancel()
            accountRetryTask = nil
            saveCachedSnapshot(snapshot)
        } catch {
            if quota != nil {
                // A transient outage must not erase an already useful snapshot.
                let lastValidDate = lastQuotaObservation?.fetchedAt ?? .now
                connection = .stale(lastValidDate)
            } else if hasStarted, accountRetryAttempt < accountRetryDelays.count {
                // Do not flash a low-level network error while the bounded
                // recovery sequence is still in progress.
                connection = .connecting
            } else {
                connection = .unavailable(error.localizedDescription)
            }
            scheduleAccountRetry()
        }
    }

    private func scheduleAccountRetry() {
        guard hasStarted, accountRetryTask == nil else { return }
        guard accountRetryAttempt < accountRetryDelays.count else { return }
        let delay = accountRetryDelays[accountRetryAttempt]
        accountRetryAttempt += 1
        accountRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.accountRetryTask = nil
            await self.refreshAccount()
        }
    }

    func refreshTurns(showFeedback: Bool) async {
        guard !isScanningTurns else { return }
        isScanningTurns = true
        defer { isScanningTurns = false }

        if titlesFetchedAt.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
            let freshTitles = await titleReader.fetchTitles()
            if !freshTitles.isEmpty { threadTaskTitles = freshTitles }
            titlesFetchedAt = .now
        }
        let scanned = await scanner.scanRecentTurns(includePromptTitles: promptTitlesEnabled)
        let oldIDs = knownTurnIDs
        let newTurns = scanned.filter { !oldIDs.contains($0.id) }
        // Publishing an identical array invalidates the entire SwiftUI menu.
        // Keep polling cheap without forcing a full layout during scrolling.
        if scanned != turns { turns = scanned }
        knownTurnIDs = Set(scanned.map(\.id))

        guard showFeedback, let newest = newTurns.first, !oldIDs.isEmpty else { return }
        let before = lastQuotaObservation
        await refreshAccount()
        reconcileAccountUsage(localTurns: newTurns, before: before, after: lastQuotaObservation)
        showTurnFeedback(newest)
    }

    func conversationLabel(for turn: TurnUsage) -> String {
        if let title = turn.threadTitle.flatMap(PromptTitleFormatter.title), !title.isEmpty {
            return title
        }
        let alias = String(turn.threadID.replacingOccurrences(of: "-", with: "").suffix(4)).uppercased()
        if let workspace = turn.workspaceName, !workspace.isEmpty {
            return "\(workspace) · 会话 #\(alias)"
        }
        return "会话 #\(alias)"
    }

    func turnTitle(for turn: TurnUsage) -> String? {
        turn.threadTitle.flatMap(PromptTitleFormatter.title)
    }

    func taskTitle(for threadID: String, fallback turn: TurnUsage) -> String {
        if let title = threadTaskTitles[threadID].flatMap(PromptTitleFormatter.title) {
            return title
        }
        return turn.threadTitle.flatMap(PromptTitleFormatter.title) ?? conversationAlias(for: turn)
    }

    /// Opens the native Codex task. Codex currently exposes a task-level deep
    /// link, but no public message/turn anchor; `turnID` is retained separately
    /// so the UI can adopt exact positioning if that becomes available.
    @discardableResult
    func openCodexTask(threadID: String) -> Bool {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard let encodedID = threadID.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "codex://threads/\(encodedID)")
        else { return false }
        return NSWorkspace.shared.open(url)
    }

    private func conversationAlias(for turn: TurnUsage) -> String {
        let alias = String(turn.threadID.replacingOccurrences(of: "-", with: "").suffix(4)).uppercased()
        if let workspace = turn.workspaceName, !workspace.isEmpty {
            return "\(workspace) · 会话 #\(alias)"
        }
        return "会话 #\(alias)"
    }

    func quotaImpact(for turn: TurnUsage) -> TurnQuotaImpact? {
        estimatedImpact(for: turn)
    }

    func estimatedDailyImpact(tokens: Int64, date: Date) -> TurnQuotaImpact? {
        guard tokens > 0,
              let interval = activeQuotaInterval(),
              let denominator = weightedWindowCredits(in: interval),
              denominator > 0
        else { return nil }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date
        let overlapStart = max(dayStart, interval.start)
        let overlapEnd = min(dayEnd, interval.end)
        guard overlapStart < overlapEnd else { return nil }
        let dayTurns = turns.filter { $0.completedAt >= overlapStart && $0.completedAt < overlapEnd }
        let localRaw = dayTurns.reduce(Int64(0)) { $0 + $1.tokens.total }
        let localCredits = dayTurns.reduce(0.0) { $0 + QuotaCreditWeighting.credits(for: $1.tokens, model: $1.model) }

        let numerator: Double
        if localRaw > 0, localCredits > 0 {
            numerator = localCredits * max(1, Double(tokens) / Double(localRaw))
        } else {
            let windowTurns = turns.filter { $0.completedAt >= interval.start && $0.completedAt <= interval.end }
            let windowRaw = windowTurns.reduce(Int64(0)) { $0 + $1.tokens.total }
            let windowLocalCredits = windowTurns.reduce(0.0) { $0 + QuotaCreditWeighting.credits(for: $1.tokens, model: $1.model) }
            guard windowRaw > 0, windowLocalCredits > 0 else { return nil }
            numerator = Double(tokens) * windowLocalCredits / Double(windowRaw)
        }
        return makeEstimatedImpact(windowUsedPercent: interval.usedPercent, numerator: numerator, denominator: denominator)
    }

    func openUsageDashboard() {
        if let url = URL(string: "https://chatgpt.com/codex/settings/usage") {
            NSWorkspace.shared.open(url)
        }
    }

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func showTurnFeedback(_ turn: TurnUsage) {
        guard menuFeedbackEnabled else { return }
        transientTurn = turn
        feedbackTask?.cancel()
        feedbackTask = Task { [weak self] in
            let nanoseconds = UInt64(max(1, self?.menuFeedbackSeconds ?? 8) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.transientTurn = nil
        }

        guard highUsageNotificationsEnabled,
              let median = medianTurnTokens,
              median > 0,
              Double(turn.tokens.total) / Double(median) >= 2
        else { return }

        let content = UNMutableNotificationContent()
        content.title = "这一轮有点重"
        content.body = "使用了 \(TokenFormat.compact(turn.tokens.total)) tokens，超过近期中位数 2 倍。"
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: turn.id, content: content, trigger: nil))
    }

    private func reconcileAccountUsage(
        localTurns: [TurnUsage],
        before: QuotaObservation?,
        after: QuotaObservation?
    ) {
        guard let before, let after,
              let firstStart = localTurns.map(\.startedAt).min(),
              let lastCompletion = localTurns.map(\.completedAt).max(),
              before.fetchedAt <= firstStart,
              after.fetchedAt >= lastCompletion,
              sameReset(before.resetsAt, after.resetsAt),
              after.usedPercent >= before.usedPercent
        else { return }

        let observed = Double(after.usedPercent - before.usedPercent)
        guard observed > 0 else { return }
        let localEstimate = localTurns.compactMap { estimatedImpact(for: $0)?.percent }.reduce(0, +)
        accountReconciliation = AccountUsageReconciliation(
            observedPercent: observed,
            localEstimatedPercent: localEstimate,
            unattributedPercent: max(0, observed - localEstimate),
            capturedAt: after.fetchedAt
        )
    }

    private func estimatedImpact(for turn: TurnUsage) -> TurnQuotaImpact? {
        guard let interval = currentWindow(containing: turn.completedAt) else { return nil }
        let turnCredits = QuotaCreditWeighting.credits(for: turn.tokens, model: turn.model)
        guard turnCredits > 0, let denominator = weightedWindowCredits(in: interval), denominator > 0 else { return nil }
        return makeEstimatedImpact(windowUsedPercent: interval.usedPercent, numerator: turnCredits, denominator: denominator)
    }

    private struct ActiveQuotaInterval {
        let start: Date
        let end: Date
        let usedPercent: Int
    }

    private func currentWindow(containing date: Date) -> ActiveQuotaInterval? {
        guard let interval = activeQuotaInterval(), date >= interval.start, date <= interval.end else { return nil }
        return interval
    }

    private func activeQuotaInterval() -> ActiveQuotaInterval? {
        guard let weekly = weeklyWindow,
              weekly.usedPercent > 0,
              let reset = weekly.resetsAt,
              let duration = weekly.windowDurationMinutes
        else { return nil }
        let start = reset.addingTimeInterval(-Double(duration) * 60)
        return ActiveQuotaInterval(start: start, end: reset, usedPercent: weekly.usedPercent)
    }

    private func weightedWindowCredits(in interval: ActiveQuotaInterval) -> Double? {
        let localTurns = turns.filter { $0.completedAt >= interval.start && $0.completedAt <= interval.end }
        let localRawTokens = localTurns.reduce(Int64(0)) { $0 + $1.tokens.total }
        let localCredits = localTurns.reduce(0.0) { $0 + QuotaCreditWeighting.credits(for: $1.tokens, model: $1.model) }
        guard localRawTokens > 0, localCredits > 0 else { return nil }

        // account/usage/read is account-scoped and can include work completed on
        // other devices. Expand the local weighted denominator by that coverage
        // ratio so remote work is not attributed to the newest local turn.
        let officialRawTokens = dailyUsage.reduce(Int64(0)) { partial, day in
            guard let dayDate = Self.dayFormatter.date(from: day.startDate),
                  dayDate >= Calendar.current.startOfDay(for: interval.start),
                  dayDate <= interval.end
            else { return partial }
            return partial + day.tokens
        }
        return QuotaCreditWeighting.accountCoveredCredits(
            localCredits: localCredits,
            localTokens: localRawTokens,
            accountTokens: officialRawTokens
        )
    }

    private func makeEstimatedImpact(windowUsedPercent: Int, numerator: Double, denominator: Double) -> TurnQuotaImpact {
        let value = min(Double(windowUsedPercent), Double(windowUsedPercent) * numerator / denominator)
        return TurnQuotaImpact(
            percent: value,
            isBelowResolution: value < 0.1,
            source: .estimated,
            capturedAt: .now
        )
    }

    private func sameReset(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case let (.some(a), .some(b)): return abs(a.timeIntervalSince(b)) < 2
        case (nil, nil): return true
        default: return false
        }
    }

    private func minimumPaceSampleDuration(for windowMinutes: Int64) -> TimeInterval {
        let window = Double(windowMinutes) * 60
        return min(2 * 60 * 60, max(30 * 60, window * 0.15))
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private var snapshotCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("CodexMeter", isDirectory: true)
            .appendingPathComponent("account-snapshot-v1.json")
    }

    private var quotaHistoryURL: URL {
        snapshotCacheURL.deletingLastPathComponent().appendingPathComponent("quota-history-v1.json")
    }

    private func loadQuotaHistory() {
        guard let data = try? Data(contentsOf: quotaHistoryURL),
              let decoded = try? JSONDecoder().decode([QuotaObservation].self, from: data)
        else { return }
        quotaObservations = prunedQuotaObservations(decoded)
    }

    private func recordQuotaObservation(_ observation: QuotaObservation) {
        // Quota refreshes every five minutes. Keep changed values, but only one
        // unchanged heartbeat per fifteen minutes to avoid needless disk writes.
        if let last = quotaObservations.last(where: {
            sameReset($0.resetsAt, observation.resetsAt)
                && $0.windowDurationMinutes == observation.windowDurationMinutes
        }),
           sameReset(last.resetsAt, observation.resetsAt),
           last.usedPercent == observation.usedPercent,
           observation.fetchedAt.timeIntervalSince(last.fetchedAt) < 15 * 60 {
            return
        }
        quotaObservations.append(observation)
        quotaObservations = prunedQuotaObservations(quotaObservations)
        guard let data = try? JSONEncoder().encode(quotaObservations) else { return }
        try? FileManager.default.createDirectory(at: quotaHistoryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: quotaHistoryURL, options: .atomic)
    }

    private func prunedQuotaObservations(_ observations: [QuotaObservation]) -> [QuotaObservation] {
        let cutoff = Date().addingTimeInterval(-14 * 24 * 60 * 60)
        return Array(observations
            .filter { $0.fetchedAt >= cutoff }
            .sorted { $0.fetchedAt < $1.fetchedAt }
            .suffix(512))
    }

    private func loadCachedSnapshot() {
        guard let data = try? Data(contentsOf: snapshotCacheURL),
              let snapshot = try? JSONDecoder().decode(AccountSnapshot.self, from: data)
        else { return }
        quota = snapshot.quota
        accountUsage = snapshot.usage
        dailyUsage = snapshot.dailyUsage ?? []
        workspaceMessages = snapshot.workspaceMessages?.filter(\.isActive) ?? []
        if let window = snapshot.quota.weeklyWindow ?? snapshot.quota.preferredWindow {
            let observation = QuotaObservation(
                fetchedAt: snapshot.fetchedAt,
                usedPercent: window.usedPercent,
                resetsAt: window.resetsAt,
                windowDurationMinutes: window.windowDurationMinutes
            )
            recordQuotaObservation(observation)
        }
        if let weekly = snapshot.quota.weeklyWindow ?? snapshot.quota.preferredWindow {
            lastQuotaObservation = QuotaObservation(
                fetchedAt: snapshot.fetchedAt,
                usedPercent: weekly.usedPercent,
                resetsAt: weekly.resetsAt,
                windowDurationMinutes: weekly.windowDurationMinutes
            )
        }
        connection = .stale(snapshot.fetchedAt)
    }

    private func saveCachedSnapshot(_ snapshot: AccountSnapshot) {
        let merged = AccountSnapshot(
            quota: snapshot.quota,
            usage: snapshot.usage ?? accountUsage,
            dailyUsage: snapshot.dailyUsage ?? dailyUsage,
            workspaceMessages: snapshot.workspaceMessages ?? workspaceMessages,
            fetchedAt: snapshot.fetchedAt
        )
        guard let data = try? JSONEncoder().encode(merged) else { return }
        try? FileManager.default.createDirectory(at: snapshotCacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: snapshotCacheURL, options: .atomic)
    }

}
