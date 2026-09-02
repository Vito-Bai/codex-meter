import AppKit
import SwiftUI

extension Notification.Name {
    static let simulateCodexMeterFirstLaunch = Notification.Name("simulateCodexMeterFirstLaunch")
    static let showCodexMeterSupport = Notification.Name("showCodexMeterSupport")
}

enum OnboardingPage: Int, CaseIterable {
    case welcome
    case connection
    case menuBar
    case launchAtLogin
    case completion

    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }
}

struct OnboardingFlow: View {
    static let currentVersion = 1

    @EnvironmentObject private var store: UsageStore
    @State private var page: OnboardingPage
    @State private var supportChannel: SupportChannel?
    let onFinish: () -> Void

    init(startingAt: OnboardingPage = .welcome, onFinish: @escaping () -> Void) {
        _page = State(initialValue: startingAt)
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground(accent: pageAccent)
            VStack(spacing: 0) {
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 48)
                    .padding(.top, 28)
                    .padding(.bottom, 20)

                Divider().overlay(MeterTheme.line)
                footer
                    .frame(height: 64)
                    .padding(.horizontal, 24)
            }
        }
        .frame(width: 640, height: 470)
        .foregroundStyle(MeterTheme.primaryText)
        .sheet(item: $supportChannel) { channel in
            SupportQRCodeSheet(channel: channel)
        }
        .onAppear { store.start() }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .welcome: welcomePage
        case .connection: connectionPage
        case .menuBar: menuBarPage
        case .launchAtLogin: launchAtLoginPage
        case .completion: completionPage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 18) {
            Spacer()
            OnboardingQuotaRings(
                weekly: store.weeklyWindow?.remainingPercent ?? 82,
                short: store.shortWindow?.remainingPercent ?? 68,
                size: 104
            )
            VStack(spacing: 8) {
                Text("欢迎使用 Codex Meter")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("更直观了解 Codex 额度还剩多少")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(MeterTheme.secondaryText)
                Text("在菜单栏查看 1 周与 5 小时额度，并了解自己的使用节奏。")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(MeterTheme.secondaryText)
            }
            Label("独立开发 · 本机运行 · 无需托管 Codex 账号", systemImage: "lock.shield")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(MeterTheme.secondaryText)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .modifier(ClearGlassCapsuleModifier())
            Spacer()
        }
    }

    private var connectionPage: some View {
        VStack(spacing: 18) {
            onboardingHeader(
                "确认数据已经接通",
                "Meter 会在本机读取额度与 Token 用量元数据。"
            )
            GlassCard {
                VStack(spacing: 13) {
                    connectionRow("已找到 Codex", state: connectionSucceeded, icon: "terminal")
                    Divider().overlay(MeterTheme.line)
                    connectionRow("已读取当前账号额度", state: store.quota != nil, icon: "gauge.with.dots.needle.67percent")
                    Divider().overlay(MeterTheme.line)
                    connectionRow("用量记录仅保存在本机", state: true, icon: "internaldrive")
                }
            }
            if let weekly = store.weeklyWindow, let short = store.shortWindow {
                Text("已连接 · 1 周剩余 \(weekly.remainingPercent)% · 5 小时剩余 \(short.remainingPercent)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MeterTheme.mint)
                    .monospacedDigit()
            } else {
                Button(store.isRefreshing ? "正在检测…" : "重新检测") {
                    Task { await store.refreshAll() }
                }
                .buttonStyle(GlassActionButtonStyle(prominent: true))
                .disabled(store.isRefreshing)
            }
            Text("不保存工具参数与输出；Prompt 仅在开启会话标题时于本地提炼，不保存原文。")
                .font(.system(size: 9.5, design: .rounded))
                .foregroundStyle(MeterTheme.secondaryText)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    private var menuBarPage: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            onboardingHeader(
                "一眼看懂菜单栏",
                "默认关注 1 周额度；短周期告急或出现官方动态时主动切换。"
            )
            HStack(spacing: 10) {
                menuPreviewCard(
                    title: "平时",
                    value: "91%",
                    detail: "显示 1 周剩余额度",
                    shortAlert: false,
                    officialNotice: false
                )
                menuPreviewCard(
                    title: "5 小时告急",
                    value: "5h 18%",
                    detail: "低于 25% 时自动切换",
                    shortAlert: true,
                    officialNotice: false
                )
                menuPreviewCard(
                    title: "官方动态",
                    value: "官方重置",
                    detail: "有新消息时优先显示",
                    shortAlert: false,
                    officialNotice: true
                )
            }
            VStack(spacing: 7) {
                Label("点击“官方重置”查看动态，阅读后自动恢复额度百分比", systemImage: "megaphone")
                Label("将鼠标停在图标上，可同时查看两个额度周期", systemImage: "cursorarrow.motionlines")
            }
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(MeterTheme.secondaryText)
            Spacer(minLength: 0)
        }
    }

    private var launchAtLoginPage: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            onboardingHeader(
                "保持随时可见",
                "登录 Mac 后，让 Meter 自动回到菜单栏。"
            )
            VStack(spacing: 11) {
                launchChoice(
                    title: "登录时自动启动",
                    detail: "推荐；无需每次手动打开。",
                    icon: "checkmark.circle.fill",
                    selected: store.launchAtLoginEnabled
                ) { store.setLaunchAtLogin(true) }
                launchChoice(
                    title: "需要时手动打开",
                    detail: "不注册为登录项。",
                    icon: "circle",
                    selected: !store.launchAtLoginEnabled
                ) { store.setLaunchAtLogin(false) }
            }
            if let message = store.launchAtLoginMessage {
                HStack(spacing: 8) {
                    Text(message)
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(MeterTheme.orange)
                    Button("打开登录项设置") { store.openLoginItemsSettings() }
                        .buttonStyle(.link)
                }
            }
            Text("这个选择之后可以随时在“设置 → 体验”中修改。")
                .font(.system(size: 9.5, design: .rounded))
                .foregroundStyle(MeterTheme.secondaryText)
            Spacer(minLength: 0)
        }
    }

    private var completionPage: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(MeterTheme.mint)
            VStack(spacing: 6) {
                Text("一切准备就绪")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("Codex Meter 将持续免费提供核心功能。")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MeterTheme.secondaryText)
            }
            GlassCard {
                VStack(spacing: 11) {
                    Text("如果它帮你更安心地使用 Codex，可以自愿请作者喝杯咖啡，支持后续维护和更新。")
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(MeterTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        supportButton(.alipay)
                        supportButton(.wechat)
                    }
                    Text("自愿支持，无需付款也可正常使用全部核心功能。")
                        .font(.system(size: 8.5, design: .rounded))
                        .foregroundStyle(MeterTheme.secondaryText.opacity(0.85))
                }
                .frame(maxWidth: .infinity)
            }
            Text("额度已经显示在屏幕右上角的菜单栏中。")
                .font(.system(size: 9.5, design: .rounded))
                .foregroundStyle(MeterTheme.secondaryText)
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Button("上一步") {
                if let previous = page.previous { withAnimation(.easeInOut(duration: 0.18)) { page = previous } }
            }
            .buttonStyle(GlassActionButtonStyle())
            .disabled(page.previous == nil)
            .opacity(page.previous == nil ? 0 : 1)

            Spacer()
            HStack(spacing: 6) {
                ForEach(OnboardingPage.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == page ? MeterTheme.mint : MeterTheme.line)
                        .frame(width: item == page ? 18 : 6, height: 6)
                }
            }
            Spacer()

            Button(page == .completion ? "开始使用" : "继续") {
                if let next = page.next {
                    withAnimation(.easeInOut(duration: 0.18)) { page = next }
                } else {
                    onFinish()
                }
            }
            .buttonStyle(GlassActionButtonStyle(prominent: true))
        }
    }

    private func onboardingHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 23, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(MeterTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    private func connectionRow(_ title: String, state: Bool, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(state ? MeterTheme.mint : MeterTheme.secondaryText)
                .frame(width: 30, height: 30)
                .background(InsetGlassSurface(cornerRadius: 9))
            Text(title).font(.system(size: 12, weight: .medium, design: .rounded))
            Spacer()
            Image(systemName: state ? "checkmark.circle.fill" : "ellipsis.circle")
                .foregroundStyle(state ? MeterTheme.mint : MeterTheme.yellow)
        }
    }

    private func menuPreviewCard(
        title: String,
        value: String,
        detail: String,
        shortAlert: Bool,
        officialNotice: Bool
    ) -> some View {
        GlassCard {
            VStack(spacing: 11) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(MeterTheme.secondaryText)
                HStack(spacing: 7) {
                    OnboardingQuotaRings(weekly: 91, short: shortAlert ? 18 : 61, size: 26)
                    Text(value)
                        .font(.system(size: officialNotice ? 12 : 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.horizontal, officialNotice ? 10 : 12)
                .padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.76)))
                .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(MeterTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private func launchChoice(
        title: String,
        detail: String,
        icon: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? MeterTheme.mint : MeterTheme.secondaryText)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(detail).font(.system(size: 9.5, design: .rounded)).foregroundStyle(MeterTheme.secondaryText)
                }
                Spacer()
            }
            .padding(15)
            .contentShape(Rectangle())
            .background(InsetGlassSurface(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? MeterTheme.mint.opacity(0.7) : .clear, lineWidth: 1.2)
            }
        }
        .buttonStyle(.plain)
    }

    private func supportButton(_ channel: SupportChannel) -> some View {
        Button {
            supportChannel = channel
        } label: {
            Label(channel.buttonTitle, systemImage: channel.symbol)
                .frame(minWidth: 100)
        }
        .buttonStyle(GlassActionButtonStyle())
    }

    private var connectionSucceeded: Bool {
        switch store.connection {
        case .live, .stale: return true
        case .connecting, .unavailable: return false
        }
    }

    private var pageAccent: Color {
        switch page {
        case .welcome, .connection: return MeterTheme.cyan
        case .menuBar: return MeterTheme.yellow
        case .launchAtLogin: return MeterTheme.violet
        case .completion: return MeterTheme.mint
        }
    }
}

enum SupportChannel: String, Identifiable {
    case alipay
    case wechat

    var id: String { rawValue }
    var buttonTitle: String { self == .alipay ? "支付宝支持" : "微信支持" }
    var scanTitle: String { self == .alipay ? "使用支付宝扫码" : "使用微信扫码" }
    var symbol: String { self == .alipay ? "a.circle.fill" : "message.fill" }
    var tint: Color { self == .alipay ? MeterTheme.cyan : MeterTheme.mint }
}

private struct SupportQRCodeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let channel: SupportChannel

    var body: some View {
        ZStack {
            LiquidGlassBackground(accent: channel.tint)
            VStack(spacing: 14) {
                Text(channel.scanTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                if let image = SupportAsset.qrImage(for: channel) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 248, height: 248)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                } else {
                    ContentUnavailableView("未找到收款码", systemImage: "qrcode", description: Text("请检查 App 资源是否完整。"))
                        .frame(width: 268, height: 268)
                }
                Text("自愿支持，不预设金额，也不会影响任何功能。")
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(MeterTheme.secondaryText)
                Button("完成") { dismiss() }
                    .buttonStyle(GlassActionButtonStyle(prominent: true))
            }
            .padding(24)
        }
        .frame(width: 360, height: 390)
        .foregroundStyle(MeterTheme.primaryText)
    }
}

private enum SupportAsset {
    static func qrImage(for channel: SupportChannel) -> NSImage? {
        let filename = channel.rawValue
        let candidates = [
            Bundle.main.url(forResource: filename, withExtension: "jpg", subdirectory: "Support"),
            Bundle.main.resourceURL?.appendingPathComponent("Support/\(filename).jpg"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Support/\(filename).jpg")
        ]
        return candidates.compactMap { $0 }.lazy.compactMap(NSImage.init(contentsOf:)).first
    }
}

private struct OnboardingQuotaRings: View {
    let weekly: Int
    let short: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            ring(value: weekly, color: MeterTheme.cyan, width: size * 0.105)
                .padding(size * 0.06)
            ring(value: short, color: MeterTheme.yellow, width: size * 0.105)
                .padding(size * 0.245)
        }
        .frame(width: size, height: size)
    }

    private func ring(value: Int, color: Color, width: CGFloat) -> some View {
        ZStack {
            Circle().stroke(MeterTheme.line.opacity(0.55), lineWidth: width)
            Circle()
                .trim(from: 0, to: min(max(CGFloat(value) / 100, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
