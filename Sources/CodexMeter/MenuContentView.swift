import AppKit
import Charts
import SwiftUI

private enum UsageRange: String, CaseIterable, Identifiable {
    case day = "日"
    case week = "周"
    case month = "月"

    var id: String { rawValue }
    var sectionTitle: String { self == .day ? "今日用量" : self == .week ? "本周用量" : "本月用量" }
    var chartCaption: String { self == .day ? "近 7 日" : self == .week ? "近 8 周" : "近 6 个月" }

    func dateLabel(_ date: Date) -> String {
        switch self {
        case .day: return Self.chineseDayFormatter.string(from: date)
        case .week:
            let end = Calendar.current.date(byAdding: .day, value: 6, to: date) ?? date
            return "\(Self.chineseDayFormatter.string(from: date))–\(Self.chineseDayFormatter.string(from: end))"
        case .month: return Self.chineseMonthFormatter.string(from: date)
        }
    }

    func axisLabel(_ date: Date) -> String {
        self == .month ? Self.axisMonthFormatter.string(from: date) : Self.axisDayFormatter.string(from: date)
    }

    private static let chineseDayFormatter = formatter("M月d日")
    private static let chineseMonthFormatter = formatter("yyyy年M月")
    private static let axisDayFormatter = formatter("M/d")
    private static let axisMonthFormatter = formatter("M月")

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = format
        return formatter
    }
}

struct MenuContentView: View {
    @EnvironmentObject private var store: UsageStore
    @Environment(\.openSettings) private var openSettings
    @State private var showTurnHistory = false
    @State private var expandedHistoryTasks = Set<String>()
    @State private var usageRange: UsageRange = .day

    var body: some View {
        ZStack {
            LiquidGlassBackground(accent: quotaColor)
            ScrollView {
                menuSections
            }
            .scrollIndicators(.hidden)
            .verticalScrollLocked()
        }
        .frame(width: 420, height: 760)
        .foregroundStyle(MeterTheme.primaryText)
        .background(MenuWindowTransparencyBridge().frame(width: 0, height: 0))
        .onAppear { store.markOfficialResetNoticeRead() }
    }

    private var menuSections: some View {
        VStack(spacing: 12) {
            header
            quotaHero
            paceCard
            latestTurnCard
            todayTrendCard
            otherInfoCard
            footer
        }
        .padding(14)
    }

    private var officialResetNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: store.officialResetNotice == nil ? "checkmark.shield.fill" : "megaphone.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MeterTheme.cyan)
                .frame(width: 23, height: 23)
                .background(MeterTheme.cyan.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                SectionEyebrow(text: "OpenAI 官方重置动态")
                if let notice = store.officialResetNotice {
                    Text(officialResetHeadline(notice))
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(officialResetDetail(notice))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(MeterTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if let date = notice.createdAt {
                        Text("官方动态·\(TokenFormat.relativeDate(date))")
                            .font(.system(size: 8, design: .rounded))
                            .foregroundStyle(MeterTheme.secondaryText.opacity(0.72))
                    }
                } else {
                    Text("暂无官方统一重置公告")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(MeterTheme.secondaryText)
                    Text("每 5 分钟检查一次")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundStyle(MeterTheme.secondaryText.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func officialResetHeadline(_ notice: WorkspaceMessage) -> String {
        guard let resetAt = notice.announcedResetAt else {
            return "OpenAI 已宣布将统一重置额度"
        }
        if resetAt > Date() {
            return "官方将于 \(officialResetDateText(resetAt)) 重置额度"
        }
        if store.isOfficialResetConfirmed(notice) {
            return "官方统一重置已完成"
        }
        return "官方计划的重置时间已到"
    }

    private func officialResetDetail(_ notice: WorkspaceMessage) -> String {
        guard let resetAt = notice.announcedResetAt else {
            return "官方暂未提供可识别的具体时间"
        }
        if resetAt > Date() {
            return "距离重置还有 \(remainingTimeText(resetAt))·按本地时间显示"
        }
        if store.isOfficialResetConfirmed(notice) {
            return "已检测到额度窗口恢复或变更"
        }
        return "正在确认额度是否已经恢复"
    }

    private func officialResetDateText(_ date: Date) -> String {
        let calendar = Calendar.current
        let prefix: String
        if calendar.isDateInToday(date) {
            prefix = "今天"
        } else if calendar.isDateInTomorrow(date) {
            prefix = "明天"
        } else {
            prefix = date.formatted(.dateTime.month().day())
        }
        return "\(prefix) \(date.formatted(.dateTime.hour().minute()))"
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 9) {
                CodexLogoView().frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Codex Meter")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(lastSyncText)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(MeterTheme.secondaryText)
                }
            }
            Spacer()
            StatusPill(text: store.connection.label, color: connectionColor)
            Button { Task { await store.refreshAll() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
            }
            .buttonStyle(GlassIconButtonStyle())
            .help("刷新")
        }
        .padding(.horizontal, 2)
    }

    private var quotaHero: some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack {
                    SectionEyebrow(text: "剩余用量")
                    Spacer()
                    Text(store.quota?.planType?.uppercased() ?? "CODEX")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .modifier(ClearGlassCapsuleModifier())
                        .overlay(Capsule().strokeBorder(MeterTheme.line, lineWidth: 0.7))
                }

                HStack(spacing: 18) {
                    DualQuotaRing(
                        weeklyRemaining: store.weeklyWindow?.remainingPercent,
                        shortRemaining: store.shortWindow?.remainingPercent,
                        size: 100
                    )
                    VStack(alignment: .leading, spacing: 11) {
                        quotaWindowRow(
                            "1 周额度",
                            window: store.weeklyWindow,
                            color: ringColor(for: store.weeklyWindow, base: MeterTheme.cyan)
                        )
                        Divider().overlay(MeterTheme.line)
                        quotaWindowRow(
                            "5 小时额度",
                            window: store.shortWindow,
                            color: ringColor(for: store.shortWindow, base: MeterTheme.mint)
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var paceCard: some View {
        GlassCard {
            HStack(spacing: 13) {
                ZStack {
                    Circle().fill(weeklyPaceColor.opacity(0.13))
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(weeklyPaceColor)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        SectionEyebrow(text: "本周额度节奏")
                        Spacer()
                        Text(weeklyPaceTitle)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(weeklyPaceColor)
                    }
                    Text(weeklyPaceDescription)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(MeterTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var latestTurnCard: some View {
        if let turn = store.turns.first {
            GlassCard {
                VStack(alignment: .leading, spacing: 17) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionEyebrow(text: "最近一轮消耗")
                            Text(store.conversationLabel(for: turn))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .lineLimit(1)
                            Text(turnMeta(turn))
                                .font(.system(size: 9, weight: .medium, design: .rounded))
                                .foregroundStyle(MeterTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 12)
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text(TokenFormat.compact(turn.tokens.total))
                                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text("tokens")
                                    .font(.system(size: 8, weight: .medium, design: .rounded))
                                    .foregroundStyle(MeterTheme.secondaryText)
                            }
                            PlainQuotaImpactLabel(impact: store.quotaImpact(for: turn))
                        }
                    }
                    HStack(spacing: 8) {
                        Button {
                            if !showTurnHistory, expandedHistoryTasks.isEmpty,
                               let latestTask = historyGroups.first?.threadID {
                                expandedHistoryTasks.insert(latestTask)
                            }
                            withAnimation(.snappy(duration: 0.32, extraBounce: 0.04)) {
                                showTurnHistory.toggle()
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: showTurnHistory ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                Text(showTurnHistory ? "收起复盘" : "用量复盘")
                            }
                        }
                        .buttonStyle(CompactGlassButtonStyle())
                        Spacer()
                        if let ratio = store.latestTurnRatio { RatioBadge(ratio: ratio) }
                    }

                    if showTurnHistory {
                        VStack(spacing: 8) {
                            Divider().overlay(MeterTheme.line)
                            turnHistory
                        }
                        .transition(
                            .scale(scale: 0.985, anchor: .top)
                                .combined(with: .opacity)
                        )
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            GlassCard {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(MeterTheme.mint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("等待下一轮完成").font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("完成一次 Codex 对话后，这里会出现完整 Token 构成。")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(MeterTheme.secondaryText)
                    }
                }
            }
        }
    }

    private var todayTrendCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    SectionEyebrow(text: usageRange.sectionTitle)
                    Spacer()
                    GlassRangePicker(selection: $usageRange)
                }
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(TokenFormat.compact(selectedRangeTokens))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("tokens")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundStyle(MeterTheme.secondaryText)
                        }
                        QuotaImpactLabel(impact: store.estimatedDailyImpact(tokens: selectedRangeTokens, date: .now))
                    }
                    .frame(width: 128, alignment: .leading)
                    InteractiveUsageChart(points: usagePoints, range: usageRange)
                        .frame(height: 92)
                }
            }
        }
    }

    private var otherInfoCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 14) {
                officialResetNotice
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().overlay(MeterTheme.line).frame(maxHeight: .infinity)

                VStack(alignment: .leading, spacing: 9) {
                    compactSupportingMetric(
                        "免费重置",
                        "\(store.quota?.resetCreditCount ?? 0) 次"
                    )
                    Divider().overlay(MeterTheme.line)
                    compactSupportingMetric(
                        "额外 Credits",
                        store.quota?.unlimitedCredits == true ? "无限" : (store.quota?.creditBalance ?? "0")
                    )
                }
                .frame(width: 108, alignment: .leading)
            }
        }
    }

    private func compactSupportingMetric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(MeterTheme.secondaryText)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MeterTheme.primaryText.opacity(0.82))
                .monospacedDigit()
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("官方用量") { store.openUsageDashboard() }.buttonStyle(GlassActionButtonStyle())
            Spacer()
            Button {
                openSettings()
                NotificationCenter.default.post(name: .bringCodexMeterSettingsToFront, object: nil)
            } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(GlassIconButtonStyle()).help("设置")
            Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                .buttonStyle(GlassIconButtonStyle()).help("退出")
        }
        .padding(.horizontal, 2)
    }

    private var quotaColor: Color { MeterTheme.quotaColor(remaining: store.remainingPercent, available: store.quotaColorAvailable) }

    private var connectionColor: Color {
        switch store.connection {
        case .live: return MeterTheme.mint
        case .connecting: return MeterTheme.yellow
        case .stale: return MeterTheme.orange
        case .unavailable: return .gray
        }
    }

    private var lastSyncText: String {
        switch store.connection {
        case .live(let date), .stale(let date): return "更新于 \(TokenFormat.relativeDate(date))"
        case .connecting: return "正在同步额度与 Token 元数据"
        case .unavailable(let reason): return reason
        }
    }

    private var weeklyPaceTitle: String {
        switch store.weeklyQuotaPace {
        case .unavailable: return "数据不可用"
        case .accumulating, .stable: return (store.weeklyWindow?.remainingPercent ?? 100) < 25 ? "额度紧张" : "节奏平稳"
        case .sustainable: return (store.weeklyWindow?.remainingPercent ?? 100) < 25 ? "额度紧张" : "节奏健康"
        case .exhausts: return "消耗偏快"
        }
    }

    private var weeklyPaceDescription: String {
        if case .unavailable(let reason) = store.connection {
            return "\(reason)；本地 Token 记录仍可查看。"
        }
        guard let weekly = store.weeklyWindow else { return "一周额度窗口待同步。" }
        if let reconciliation = store.accountReconciliation,
           Date().timeIntervalSince(reconciliation.capturedAt) < 1_800,
           reconciliation.unattributedPercent >= 0.5 {
            return "账户下降 \(percentText(reconciliation.observedPercent))；本机约 \(percentText(reconciliation.localEstimatedPercent))，其余 \(percentText(reconciliation.unattributedPercent)) 可能来自其它设备。"
        }
        switch store.weeklyQuotaPace {
        case .unavailable:
            return "连接 Codex 后，将判断本周额度能否撑到重置。"
        case .accumulating:
            return "本周剩余 \(weekly.remainingPercent)% · 距重置 \(weekly.resetsAt.map(remainingTimeText) ?? "待同步")；趋势样本仍在积累。"
        case .stable:
            return "本周剩余 \(weekly.remainingPercent)%；近期额度变化低于 2%，当前消耗平稳。"
        case let .sustainable(projectedRemaining):
            return "按当前速度可用至周重置，预计届时仍剩约 \(Int(projectedRemaining.rounded()))%。"
        case let .exhausts(date):
            return "按当前速度可能在 \(paceDateText(date)) 耗尽，早于周重置。"
        }
    }

    private var weeklyPaceColor: Color {
        paceColor(store.weeklyQuotaPace, remaining: store.weeklyWindow?.remainingPercent, healthy: MeterTheme.cyan)
    }

    private func paceColor(_ pace: QuotaPace, remaining: Int?, healthy: Color) -> Color {
        guard let remaining else { return .gray }
        if remaining < 25 { return MeterTheme.red }
        switch pace {
        case .exhausts: return MeterTheme.orange
        case let .sustainable(projected) where projected < 20: return MeterTheme.yellow
        default:
            if remaining < 50 { return MeterTheme.orange }
            if remaining <= 80 { return MeterTheme.yellow }
            return healthy
        }
    }

    private func paceDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func percentText(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 1 ? 1 : 0))) + "%"
    }

    private var todayTokens: Int64 {
        let local = store.turns.filter { Calendar.current.isDateInToday($0.completedAt) }.reduce(0) { $0 + $1.tokens.total }
        return store.dailyUsage.last?.tokens ?? local
    }

    private var selectedRangeTokens: Int64 { usagePoints.last?.tokens ?? todayTokens }

    private var baseDailyPoints: [UsageDayPoint] {
        let calendar = Calendar.current
        let localByDay = Dictionary(grouping: store.turns) { calendar.startOfDay(for: $0.completedAt) }
        let official = store.dailyUsage.compactMap { day -> UsageDayPoint? in
            guard let date = Self.dayFormatter.date(from: day.startDate) else { return nil }
            return UsageDayPoint(
                date: date,
                tokens: day.tokens,
                turnCount: localByDay[calendar.startOfDay(for: date), default: []].count,
                impact: store.estimatedDailyImpact(tokens: day.tokens, date: date)
            )
        }
        if !official.isEmpty { return official }
        return localByDay.keys.sorted().map { date in
            let dayTurns = localByDay[date, default: []]
            let tokens = dayTurns.reduce(Int64(0)) { $0 + $1.tokens.total }
            return UsageDayPoint(date: date, tokens: tokens, turnCount: dayTurns.count, impact: store.estimatedDailyImpact(tokens: tokens, date: date))
        }
    }

    private var usagePoints: [UsageDayPoint] {
        let calendar = Calendar.current
        switch usageRange {
        case .day:
            return Array(baseDailyPoints.suffix(7))
        case .week:
            let groups = Dictionary(grouping: baseDailyPoints) { point in
                weekCalendar.dateInterval(of: .weekOfYear, for: point.date)?.start ?? calendar.startOfDay(for: point.date)
            }
            return groups.keys.sorted().suffix(8).map { start in aggregate(groups[start, default: []], date: start) }
        case .month:
            let groups = Dictionary(grouping: baseDailyPoints) { point in
                let components = calendar.dateComponents([.year, .month], from: point.date)
                return calendar.date(from: components) ?? calendar.startOfDay(for: point.date)
            }
            return groups.keys.sorted().suffix(6).map { start in aggregate(groups[start, default: []], date: start) }
        }
    }

    private var weekCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func aggregate(_ points: [UsageDayPoint], date: Date) -> UsageDayPoint {
        let tokens = points.reduce(Int64(0)) { $0 + $1.tokens }
        let turns = points.reduce(0) { $0 + $1.turnCount }
        let impactValues = points.compactMap { $0.impact?.percent }
        let impact = impactValues.isEmpty ? nil : TurnQuotaImpact(
            percent: impactValues.reduce(0, +),
            isBelowResolution: impactValues.reduce(0, +) < 0.1,
            source: .estimated,
            capturedAt: .now
        )
        return UsageDayPoint(
            date: date,
            tokens: tokens,
            turnCount: turns,
            impact: impact
        )
    }

    private var turnHistory: some View {
        ScrollViewReader { historyProxy in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(historyGroups, id: \.threadID) { group in
                        let isExpanded = expandedHistoryTasks.contains(group.threadID)
                        Section {
                            if isExpanded {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(group.turns) { historicalTurn in
                                        TurnHistoryRow(
                                            turn: historicalTurn,
                                            title: store.turnTitle(for: historicalTurn),
                                            impact: store.quotaImpact(for: historicalTurn),
                                            maxTokens: historyMaxTokens,
                                            openTask: {
                                                store.openCodexTask(threadID: historicalTurn.threadID)
                                            }
                                        )
                                    }
                                }
                                .padding(.top, 3)
                                .transition(
                                    .scale(scale: 0.985, anchor: .top)
                                        .combined(with: .opacity)
                                )
                            }

                            if group.threadID != historyGroups.last?.threadID {
                                Divider().overlay(MeterTheme.line).padding(.vertical, 5)
                            }
                        } header: {
                            Button {
                                if isExpanded {
                                    // A pinned header is only a visual copy: the
                                    // scroll position can still be deep inside
                                    // the rows that are about to disappear.
                                    // Restore the real header anchor first so
                                    // collapsing cannot leave the viewport past
                                    // the new document height.
                                    var noAnimation = Transaction()
                                    noAnimation.disablesAnimations = true
                                    withTransaction(noAnimation) {
                                        historyProxy.scrollTo(group.threadID, anchor: .top)
                                    }
                                    withAnimation(.snappy(duration: 0.3, extraBounce: 0.025)) {
                                        _ = expandedHistoryTasks.remove(group.threadID)
                                    }
                                } else {
                                    withAnimation(.snappy(duration: 0.3, extraBounce: 0.025)) {
                                        _ = expandedHistoryTasks.insert(group.threadID)
                                    }
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 7.5, weight: .bold))
                                        .foregroundStyle(MeterTheme.secondaryText)
                                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                        .frame(width: 9)
                                    Text(store.taskTitle(for: group.threadID, fallback: group.turns.last ?? group.turns[0]))
                                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(group.turns.first.map { TokenFormat.relativeDate($0.completedAt) } ?? "")
                                        .font(.system(size: 8, weight: .medium, design: .rounded))
                                        .foregroundStyle(MeterTheme.secondaryText)
                                        .lineLimit(1)
                                    Text("\(group.turns.count) 轮")
                                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                        .foregroundStyle(MeterTheme.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .modifier(InteractiveRoundedGlassModifier(cornerRadius: 11))
                            .padding(.vertical, 2)
                            .id(group.threadID)
                            .zIndex(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 5)
            }
            .frame(height: 238)
            .scrollIndicators(.visible)
            .verticalScrollLocked()
            .onChange(of: historyGroups.first?.threadID) { _, latestTask in
                guard showTurnHistory, let latestTask else { return }
                expandedHistoryTasks.insert(latestTask)
            }
        }
    }

    private var historyGroups: [(threadID: String, turns: [TurnUsage])] {
        let recent = Array(store.turns.prefix(30))
        let grouped = Dictionary(grouping: recent, by: \.threadID)
        return grouped.map { (threadID: $0.key, turns: $0.value.sorted { $0.completedAt > $1.completedAt }) }
            .sorted { ($0.turns.first?.completedAt ?? .distantPast) > ($1.turns.first?.completedAt ?? .distantPast) }
    }

    private var historyMaxTokens: Int64 {
        max(1, historyGroups.flatMap(\.turns).map(\.tokens.total).max() ?? 1)
    }

    private func turnMeta(_ turn: TurnUsage) -> String {
        let model = turn.model?.replacingOccurrences(of: "gpt-", with: "GPT ").uppercased() ?? "Codex"
        return "\(turnExecutionTime(turn.completedAt)) · \(model) · \(reasoningLabel(turn.reasoningEffort))"
    }

    private func reasoningLabel(_ effort: String?) -> String {
        switch effort?.lowercased() {
        case "low": return "低推理"
        case "medium": return "中推理"
        case "high": return "高推理"
        case "xhigh": return "极高推理"
        case "max": return "最高推理"
        case "ultra": return "Ultra 推理"
        case let value?: return "\(value.uppercased()) 推理"
        case nil: return "默认推理"
        }
    }

    private func turnExecutionTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 \(Self.turnTimeFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 \(Self.turnTimeFormatter.string(from: date))"
        }
        return Self.turnDateTimeFormatter.string(from: date)
    }

    private static let turnTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let turnDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func quotaWindowRow(_ label: String, window: QuotaWindow?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(MeterTheme.secondaryText)
            }
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    quotaWindowDetail(
                        "重置",
                        window?.resetsAt.map(resetDateText) ?? "待同步"
                    )
                    quotaWindowDetail(
                        "还剩",
                        window?.resetsAt.map(remainingTimeText) ?? "—"
                    )
                }
                Spacer(minLength: 6)
                Text(window.map { "剩余 \($0.remainingPercent)%" } ?? "待同步")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .padding(.leading, 14)
        }
    }

    private func quotaWindowDetail(_ label: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(MeterTheme.secondaryText)
                .frame(width: 26, alignment: .leading)
            Text(value)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func ringColor(for window: QuotaWindow?, base: Color) -> Color {
        guard let window else { return .gray }
        return window.remainingPercent > 80 ? base : MeterTheme.quotaColor(remaining: window.remainingPercent)
    }

    private func compactMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 9, weight: .medium, design: .rounded)).foregroundStyle(MeterTheme.secondaryText)
            Text(value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resetDateText(_ date: Date) -> String { date.formatted(.dateTime.month().day().hour().minute()) }

    private func remainingTimeText(_ date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "等待刷新" }

        // Round up to the next whole minute so 59m 20s never appears as
        // 59 minutes and the countdown does not reach zero prematurely.
        let totalMinutes = max(1, Int(ceil(seconds / 60)))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days) 天 \(hours) 小时" : "\(days) 天"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(hours) 小时"
        }
        return "\(minutes) 分钟"
    }
}

private struct MenuWindowTransparencyBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowProbeView { WindowProbeView() }
    func updateNSView(_ nsView: WindowProbeView, context: Context) { nsView.applyTransparency() }

    final class WindowProbeView: NSView {
        private weak var configuredWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyTransparency()
        }

        func applyTransparency() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window,
                      self.configuredWindow !== window else { return }
                self.configuredWindow = window
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
                window.hasShadow = true
            }
        }
    }
}

private struct UsageDayPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let tokens: Int64
    let turnCount: Int
    let impact: TurnQuotaImpact?
}

private struct VerticalScrollLock: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollProbeView { ScrollProbeView() }
    func updateNSView(_ nsView: ScrollProbeView, context: Context) { nsView.applyLock() }

    final class LockedHorizontalClipView: NSClipView {
        var lockedX: CGFloat = 0

        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var constrained = super.constrainBoundsRect(proposedBounds)
            constrained.origin.x = lockedX
            return constrained
        }

        override func scroll(to newOrigin: NSPoint) {
            super.scroll(to: NSPoint(x: lockedX, y: newOrigin.y))
        }
    }

    final class ScrollProbeView: NSView {
        private weak var observedClipView: NSClipView?
        private weak var observedDocumentView: NSView?
        private var boundsObserver: NSObjectProtocol?
        private var documentFrameObserver: NSObjectProtocol?

        deinit {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            if let documentFrameObserver { NotificationCenter.default.removeObserver(documentFrameObserver) }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyLock()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            applyLock()
        }

        func applyLock() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let scrollView = self.enclosingScrollView else { return }

                // Trackpads often emit a small horizontal delta during a fast
                // vertical flick. Prefer the dominant axis and clamp the clip
                // view so the document can never visibly drift sideways.
                scrollView.usesPredominantAxisScrolling = true
                scrollView.hasHorizontalScroller = false
                scrollView.horizontalScrollElasticity = .none
                scrollView.verticalScrollElasticity = .automatic
                let clipView = self.installLockedClipViewIfNeeded(in: scrollView)
                self.observeAndClampHorizontalPosition(in: clipView)
                self.observeDocumentSize(in: clipView, scrollView: scrollView)
            }
        }

        private func installLockedClipViewIfNeeded(in scrollView: NSScrollView) -> NSClipView {
            if let locked = scrollView.contentView as? LockedHorizontalClipView {
                locked.lockedX = 0
                return locked
            }

            let previous = scrollView.contentView
            let visibleOriginY = previous.bounds.origin.y
            let documentView = previous.documentView
            previous.documentView = nil

            let locked = LockedHorizontalClipView(frame: previous.frame)
            locked.lockedX = 0
            locked.drawsBackground = previous.drawsBackground
            locked.backgroundColor = previous.backgroundColor
            locked.postsBoundsChangedNotifications = true
            locked.documentView = documentView
            scrollView.contentView = locked
            locked.scroll(to: NSPoint(x: 0, y: visibleOriginY))
            scrollView.reflectScrolledClipView(locked)
            return locked
        }

        private func observeAndClampHorizontalPosition(in clipView: NSClipView) {
            if observedClipView !== clipView {
                if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
                observedClipView = clipView
                clipView.postsBoundsChangedNotifications = true
                boundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self, weak clipView] _ in
                    guard self != nil, let clipView else { return }
                    Self.clampHorizontalPosition(of: clipView)
                }
            }
            Self.clampHorizontalPosition(of: clipView)
        }

        private func observeDocumentSize(in clipView: NSClipView, scrollView: NSScrollView) {
            guard let documentView = clipView.documentView else { return }
            guard observedDocumentView !== documentView else { return }
            if let documentFrameObserver { NotificationCenter.default.removeObserver(documentFrameObserver) }
            observedDocumentView = documentView
            documentView.postsFrameChangedNotifications = true
            documentFrameObserver = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification,
                object: documentView,
                queue: .main
            ) { [weak clipView, weak scrollView] _ in
                guard let clipView, let scrollView else { return }
                let constrained = clipView.constrainBoundsRect(clipView.bounds)
                guard abs(constrained.origin.y - clipView.bounds.origin.y) > 0.5 else { return }
                clipView.scroll(to: constrained.origin)
                scrollView.reflectScrolledClipView(clipView)
            }
        }

        private static func clampHorizontalPosition(of clipView: NSClipView) {
            guard abs(clipView.bounds.origin.x) > 0.01 else { return }
            var bounds = clipView.bounds
            bounds.origin.x = 0
            clipView.setBoundsOrigin(bounds.origin)
        }
    }
}

private extension View {
    func verticalScrollLocked() -> some View {
        background(VerticalScrollLock().frame(width: 0, height: 0))
    }

}

private struct GlassRangePicker: View {
    @Binding var selection: UsageRange
    @Namespace private var selectionLens

    var body: some View {
        HStack(spacing: 0) {
            ForEach(UsageRange.allCases) { range in
                Button {
                    withAnimation(.snappy(duration: 0.22, extraBounce: 0.04)) { selection = range }
                } label: {
                    ZStack {
                        if selection == range {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(MeterTheme.controlFill.opacity(0.18))
                                .modifier(ClearGlassRoundedModifier(cornerRadius: 7))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.55)
                                }
                                .matchedGeometryEffect(id: "range-selection-lens", in: selectionLens)
                        }
                        Text(range.rawValue)
                            .font(.system(size: 9.5, weight: selection == range ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(selection == range ? MeterTheme.primaryText : MeterTheme.secondaryText)
                    }
                    .frame(width: 27, height: 22)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .modifier(ClearGlassRoundedModifier(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(MeterTheme.line.opacity(0.45), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("日期范围")
    }
}

private struct QuotaImpactLabel: View {
    let impact: TurnQuotaImpact?

    var body: some View {
        HStack(spacing: 4) {
            Text(impact?.compactValue ?? "待积累")
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(impact.map { "额度·\($0.sourceLabel)" } ?? "额度影响")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(MeterTheme.secondaryText)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .modifier(ClearGlassCapsuleModifier())
        .overlay(Capsule().strokeBorder(MeterTheme.line.opacity(0.7), lineWidth: 0.6))
        .help(impactHelp)
    }

    private var impactHelp: String {
        guard impact != nil else { return "尚未积累足够的账号与本机用量数据" }
        return "按模型费率区分非缓存输入、缓存输入与输出，并结合账号用量覆盖范围估算"
    }
}

private struct PlainQuotaImpactLabel: View {
    let impact: TurnQuotaImpact?

    var body: some View {
        HStack(spacing: 4) {
            Text(impact?.compactValue ?? "待积累")
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(impact.map { "额度·\($0.sourceLabel)" } ?? "额度影响")
                .font(.system(size: 8, weight: .medium, design: .rounded))
        }
        .foregroundStyle(MeterTheme.secondaryText)
        .help(impact == nil
            ? "尚未积累足够的账号与本机用量数据"
            : "按模型费率区分非缓存输入、缓存输入与输出，并结合账号用量覆盖范围估算")
    }
}

private struct TurnHistoryRow: View {
    let turn: TurnUsage
    let title: String?
    let impact: TurnQuotaImpact?
    let maxTokens: Int64
    let openTask: () -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? "第 \(turn.ordinal) 轮")
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .lineLimit(1)
                    Text("第 \(turn.ordinal) 轮 · \(turn.completedAt.formatted(date: .omitted, time: .shortened)) · \(TokenFormat.duration(turn.duration)) · \(turn.toolCallCount) 次工具")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(MeterTheme.secondaryText)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TokenFormat.compact(turn.tokens.total))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(impact.map { "\($0.compactValue) · \($0.sourceLabel)" } ?? "额度待积累")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(MeterTheme.secondaryText)
                }
            }
            ReviewTokenBar(tokens: turn.tokens, maxTokens: maxTokens)
            HStack(alignment: .center, spacing: 7) {
                Text("输入 \(TokenFormat.compact(turn.tokens.input)) · 缓存 \(TokenFormat.compact(turn.tokens.cachedInput)) · 输出 \(TokenFormat.compact(turn.tokens.output)) · 推理 \(TokenFormat.compact(turn.tokens.reasoning))")
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(MeterTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    if !openTask() { NSSound.beep() }
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 7.5, weight: .semibold))
                        .frame(width: 21, height: 21)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .modifier(ClearGlassCircleModifier())
                .overlay(Circle().strokeBorder(MeterTheme.line.opacity(0.55), lineWidth: 0.5))
                .help("在 Codex 中打开任务")
                .accessibilityLabel("在 Codex 中打开任务")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(InsetGlassSurface(cornerRadius: 11))
        .padding(.bottom, 6)
    }
}

/// All review rows share one maximum, so bar length communicates absolute
/// turn size while the internal colours communicate its token composition.
private struct ReviewTokenBar: View {
    let tokens: TokenBreakdown
    let maxTokens: Int64

    private var segments: [(value: Int64, color: Color)] {
        let visibleOutput = max(0, tokens.output - tokens.reasoning)
        return [
            (tokens.uncachedInput, MeterTheme.cyan),
            (tokens.cachedInput, MeterTheme.violet),
            (visibleOutput, MeterTheme.mint),
            (tokens.reasoning, MeterTheme.orange)
        ]
    }

    var body: some View {
        Canvas { context, size in
            let widthRatio = min(1, Double(tokens.total) / Double(max(1, maxTokens)))
            let filledWidth = max(tokens.total > 0 ? 3 : 0, size.width * widthRatio)
            let compositionTotal = max(1, segments.reduce(Int64(0)) { $0 + $1.value })
            var offset: CGFloat = 0

            for segment in segments where segment.value > 0 {
                let segmentWidth = filledWidth * CGFloat(Double(segment.value) / Double(compositionTotal))
                let rect = CGRect(x: offset, y: 0, width: segmentWidth, height: size.height)
                context.fill(Path(rect), with: .color(segment.color.opacity(0.82)))
                offset += segmentWidth
            }
        }
        .frame(height: 5)
        .background(Capsule().fill(MeterTheme.controlFill.opacity(0.42)))
        .clipShape(Capsule())
        .help("条长代表本轮总量；青色为非缓存输入、紫色为缓存、绿色为输出、橙色为推理")
        .accessibilityLabel("本轮共 \(tokens.total) tokens，输入 \(tokens.input)，缓存 \(tokens.cachedInput)，输出 \(tokens.output)，推理 \(tokens.reasoning)")
    }
}

private struct InteractiveUsageChart: View {
    let points: [UsageDayPoint]
    let range: UsageRange
    @State private var hoveredDate: Date?
    @State private var lockedDate: Date?

    private var selectedPoint: UsageDayPoint? {
        nearestPoint(to: lockedDate ?? hoveredDate)
    }

    private var axisDates: [Date] {
        guard !points.isEmpty else { return [] }
        let desired = min(3, points.count)
        guard points.count > desired else { return points.map(\.date) }
        let stride = max(1, Int(ceil(Double(points.count - 1) / Double(desired - 1))))
        var dates = Swift.stride(from: 0, to: points.count, by: stride).map { points[$0].date }
        if dates.last != points.last?.date { dates.append(points.last!.date) }
        return dates
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(x: .value("日期", point.date), y: .value("Tokens", point.tokens))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MeterTheme.cyan.opacity(0.12), MeterTheme.cyan.opacity(0.005)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                LineMark(x: .value("日期", point.date), y: .value("Tokens", point.tokens))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [MeterTheme.cyan.opacity(0.58), MeterTheme.cyan.opacity(0.92)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if points.last?.id == point.id {
                    PointMark(x: .value("最新日期", point.date), y: .value("Tokens", point.tokens))
                        .foregroundStyle(MeterTheme.cyan.opacity(0.14))
                        .symbolSize(38)
                    PointMark(x: .value("最新日期", point.date), y: .value("Tokens", point.tokens))
                        .foregroundStyle(MeterTheme.cyan)
                        .symbolSize(13)
                }
            }

            if let selectedPoint {
                RuleMark(x: .value("选中日期", selectedPoint.date))
                    .foregroundStyle(MeterTheme.secondaryText.opacity(0.28))
                    .lineStyle(StrokeStyle(lineWidth: 0.55))
                PointMark(x: .value("选中日期", selectedPoint.date), y: .value("Tokens", selectedPoint.tokens))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .symbolSize(34)
                PointMark(x: .value("选中日期", selectedPoint.date), y: .value("Tokens", selectedPoint.tokens))
                    .foregroundStyle(MeterTheme.cyan)
                    .symbolSize(14)
            }
        }
        .chartXAxis {
            AxisMarks(values: axisDates) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(range.axisLabel(date)) }
                }
                .font(.system(size: 8.5, weight: .regular, design: .rounded))
                .foregroundStyle(MeterTheme.secondaryText.opacity(0.78))
            }
        }
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 12))
        .overlay {
            ChartInteractionSurface(
                onHover: { normalizedX in
                    let snappedDate = point(atNormalizedX: normalizedX)?.date
                    if hoveredDate != snappedDate { hoveredDate = snappedDate }
                },
                onClick: { normalizedX in
                    let nearest = point(atNormalizedX: normalizedX)?.date
                    lockedDate = lockedDate == nearest ? nil : nearest
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(true)
        }
        .overlay(alignment: .topTrailing) {
            if let selectedPoint {
                HStack(spacing: 4) {
                    Text(range.dateLabel(selectedPoint.date))
                    Text(TokenFormat.compact(selectedPoint.tokens)).fontWeight(.semibold)
                    Text(selectedPoint.impact?.compactValue ?? "额度待积累")
                }
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .foregroundStyle(MeterTheme.primaryText)
                .monospacedDigit()
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .modifier(ClearGlassCapsuleModifier())
                .overlay(Capsule().strokeBorder(MeterTheme.line.opacity(0.42), lineWidth: 0.5))
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                .allowsHitTesting(false)
            }
        }
        .animation(.smooth(duration: 0.22), value: range)
        .animation(.easeOut(duration: 0.14), value: selectedPoint?.id)
        .onChange(of: range) { _, _ in
            hoveredDate = nil
            lockedDate = nil
        }
    }

    private func nearestPoint(to date: Date?) -> UsageDayPoint? {
        guard let date else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private func point(atNormalizedX normalizedX: CGFloat?) -> UsageDayPoint? {
        guard let normalizedX, !points.isEmpty else { return nil }
        guard points.count > 1 else { return points.first }
        // Match the chart's 8 pt leading and 12 pt trailing plot padding while
        // keeping the tracker independent from ChartProxy hit-testing.
        let plotPosition = min(1, max(0, (normalizedX - 0.04) / 0.90))
        let index = Int((plotPosition * CGFloat(points.count - 1)).rounded())
        return points[min(points.count - 1, max(0, index))]
    }
}

/// AppKit tracking is more reliable than a fully transparent SwiftUI hover
/// gesture inside a MenuBarExtra window. The surface reports only a normalized
/// horizontal coordinate, leaving date snapping to the chart.
private struct ChartInteractionSurface: NSViewRepresentable {
    let onHover: (CGFloat?) -> Void
    let onClick: (CGFloat) -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.onHover = onHover
        view.onClick = onClick
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHover = onHover
        nsView.onClick = onClick
    }

    final class TrackingView: NSView {
        var onHover: ((CGFloat?) -> Void)?
        var onClick: ((CGFloat) -> Void)?
        private var mouseTrackingArea: NSTrackingArea?

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            if let mouseTrackingArea { removeTrackingArea(mouseTrackingArea) }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            mouseTrackingArea = area
            super.updateTrackingAreas()
        }

        override func mouseEntered(with event: NSEvent) { onHover?(normalizedX(for: event)) }
        override func mouseMoved(with event: NSEvent) { onHover?(normalizedX(for: event)) }
        override func mouseExited(with event: NSEvent) { onHover?(nil) }
        override func mouseDown(with event: NSEvent) { onClick?(normalizedX(for: event)) }

        override func scrollWheel(with event: NSEvent) {
            nextResponder?.scrollWheel(with: event)
        }

        private func normalizedX(for event: NSEvent) -> CGFloat {
            guard bounds.width > 0 else { return 0 }
            let point = convert(event.locationInWindow, from: nil)
            return min(1, max(0, point.x / bounds.width))
        }
    }
}

private struct MenuTurnDetailView: View {
    let turn: TurnUsage
    var body: some View {
        ZStack {
            LiquidGlassBackground(accent: MeterTheme.violet)
            VStack(alignment: .leading, spacing: 14) {
                SectionEyebrow(text: "本轮详情")
                Text(TokenFormat.full(turn.tokens.total)).font(.system(size: 29, weight: .bold, design: .rounded)).monospacedDigit()
                Text("tokens · \(TokenFormat.duration(turn.duration)) · \(turn.toolCallCount) 次工具调用")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(MeterTheme.secondaryText)
                TokenCompositionBar(tokens: turn.tokens)
                Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                    detail("输入", turn.tokens.input)
                    detail("缓存输入", turn.tokens.cachedInput)
                    detail("非缓存输入", turn.tokens.uncachedInput)
                    detail("输出", turn.tokens.output)
                    detail("推理输出", turn.tokens.reasoning)
                }
            }.padding(20)
        }
        .frame(width: 320, height: 250).foregroundStyle(MeterTheme.primaryText)
    }

    private func detail(_ label: String, _ value: Int64) -> some View {
        GridRow { Text(label).foregroundStyle(MeterTheme.secondaryText); Text(TokenFormat.full(value)).monospacedDigit() }
            .font(.system(size: 11, design: .rounded))
    }
}

struct DualQuotaRing: View {
    let weeklyRemaining: Int?
    let shortRemaining: Int?
    let size: CGFloat
    @State private var animatedWeeklyProgress = 0.0
    @State private var animatedShortProgress = 0.0

    var body: some View {
        ZStack {
            Circle()
                .stroke(windowColor(weeklyRemaining, base: MeterTheme.cyan).opacity(0.15), lineWidth: 15)
            Circle().trim(from: 0, to: animatedWeeklyProgress)
                .stroke(
                    windowColor(weeklyRemaining, base: MeterTheme.cyan),
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: .black.opacity(0.24), radius: 2.5, x: 1.5, y: 1.5)

            Circle()
                .stroke(windowColor(shortRemaining, base: MeterTheme.mint).opacity(0.15), lineWidth: 15)
                .padding(20)
            Circle().trim(from: 0, to: animatedShortProgress)
                .stroke(
                    windowColor(shortRemaining, base: MeterTheme.mint),
                    style: StrokeStyle(lineWidth: 15, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(20)
                .shadow(color: .black.opacity(0.24), radius: 2.5, x: 1.5, y: 1.5)
        }
        .frame(width: size, height: size)
        .onAppear { animate() }
        .onChange(of: weeklyRemaining) { _, _ in animate() }
        .onChange(of: shortRemaining) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func animate() {
        withAnimation(.spring(duration: 0.85, bounce: 0.16)) {
            animatedWeeklyProgress = weeklyRemaining.map { Double($0) / 100 } ?? 0
            animatedShortProgress = shortRemaining.map { Double($0) / 100 } ?? 0
        }
    }

    private func windowColor(_ remaining: Int?, base: Color) -> Color {
        guard let remaining else { return .gray }
        return remaining > 80 ? base : MeterTheme.quotaColor(remaining: remaining)
    }

    private var accessibilityText: String {
        let weekly = weeklyRemaining.map { "本周额度剩余百分之 \($0)" } ?? "本周额度不可用"
        let short = shortRemaining.map { "五小时额度剩余百分之 \($0)" } ?? "五小时额度不可用"
        return "\(weekly)，\(short)"
    }
}

struct TokenCompositionBar: View {
    let tokens: TokenBreakdown
    var body: some View {
        GeometryReader { geometry in
            let total = max(1, Double(tokens.uncachedInput + tokens.cachedInput + tokens.output + tokens.reasoning))
            HStack(spacing: 2) {
                segment(tokens.uncachedInput, total, geometry.size.width, MeterTheme.cyan)
                segment(tokens.cachedInput, total, geometry.size.width, MeterTheme.violet)
                segment(tokens.output, total, geometry.size.width, MeterTheme.mint)
                segment(tokens.reasoning, total, geometry.size.width, MeterTheme.orange)
            }.clipShape(Capsule())
        }
        .frame(height: 7).background(Capsule().fill(MeterTheme.controlFill))
    }
    private func segment(_ value: Int64, _ total: Double, _ width: CGFloat, _ color: Color) -> some View {
        color.frame(width: max(value > 0 ? 2 : 0, width * Double(value) / total))
    }
}

struct RatioBadge: View {
    let ratio: Double
    var body: some View {
        let color = ratio >= 2 ? MeterTheme.red : ratio >= 1.3 ? MeterTheme.orange : MeterTheme.mint
        Text(ratio < 1 ? "轻量 \(ratio, format: .number.precision(.fractionLength(1)))×" : "\(ratio, format: .number.precision(.fractionLength(1)))× 基线")
            .font(.system(size: 9.5, weight: .semibold, design: .rounded)).foregroundStyle(color)
            .frame(width: 82, height: 28)
            .background(Capsule().fill(color.opacity(0.11)))
            .overlay(Capsule().strokeBorder(color.opacity(0.18), lineWidth: 0.7))
    }
}

private extension UsageStore {
    var turnsByDayValues: [Int64] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: turns) { calendar.startOfDay(for: $0.completedAt) }
        return grouped.keys.sorted().suffix(7).map { day in grouped[day, default: []].reduce(0) { $0 + $1.tokens.total } }
    }
}
