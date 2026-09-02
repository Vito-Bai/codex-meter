import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: UsageStore

    var body: some View {
        ZStack {
            LiquidGlassBackground(accent: MeterTheme.violet)
            TabView {
                experienceTab
                    .tabItem { Label("体验", systemImage: "sparkles") }
                privacyTab
                    .tabItem { Label("隐私与连接", systemImage: "hand.raised.fill") }
            }
            .padding(.top, 8)
        }
        .foregroundStyle(MeterTheme.primaryText)
        .onAppear { store.refreshLaunchAtLoginStatus() }
    }

    private var experienceTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                settingsHeader("体验设置", "控制菜单栏反馈、快捷入口与提醒")

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow(text: "启动")
                        settingToggle(
                            "登录时自动启动",
                            detail: "登录 Mac 后在菜单栏自动运行 Codex Meter。",
                            isOn: Binding(
                                get: { store.launchAtLoginEnabled },
                                set: { store.setLaunchAtLogin($0) }
                            )
                        )
                        if let message = store.launchAtLoginMessage {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(message)
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(MeterTheme.orange)
                                Spacer()
                                Button("打开登录项设置") { store.openLoginItemsSettings() }
                                    .buttonStyle(.link)
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow(text: "逐轮反馈")
                        settingToggle("每轮结束后显示 Token", detail: "在菜单栏短暂提示刚完成一轮的处理量。", isOn: $store.menuFeedbackEnabled)
                        Divider().overlay(MeterTheme.line)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("显示时长")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                    Text("完成一轮后，菜单栏临时显示本轮 Token 数；这里控制它停留多久。")
                                        .font(.system(size: 9, design: .rounded))
                                        .foregroundStyle(MeterTheme.secondaryText)
                                }
                                Spacer()
                                Text("\(Int(store.menuFeedbackSeconds)) 秒")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(MeterTheme.mint)
                                    .monospacedDigit()
                            }
                            Slider(value: $store.menuFeedbackSeconds, in: 3...15, step: 1).tint(MeterTheme.mint)
                        }
                        Divider().overlay(MeterTheme.line)
                        settingToggle("保存逐轮 Token 历史", detail: "在本机保存 Token、模型、时长等用量元数据。", isOn: $store.turnHistoryEnabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow(text: "提醒")
                        settingToggle("单轮高消耗提醒", detail: "超过近 20 轮中位数 2 倍时提醒，默认关闭。", isOn: $store.highUsageNotificationsEnabled)
                            .onChange(of: store.highUsageNotificationsEnabled) { _, enabled in
                                if enabled { store.requestNotificationPermission() }
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 13) {
                        SectionEyebrow(text: "关于")
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Codex Meter")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                Text("从欢迎页模拟新用户第一次打开软件。")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(MeterTheme.secondaryText)
                            }
                            Spacer()
                            Button("使用引导") {
                                NotificationCenter.default.post(name: .simulateCodexMeterFirstLaunch, object: nil)
                            }
                            .buttonStyle(GlassActionButtonStyle())
                            Button("支持开发") {
                                NotificationCenter.default.post(name: .showCodexMeterSupport, object: nil)
                            }
                            .buttonStyle(GlassActionButtonStyle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
    }

    private var privacyTab: some View {
        ScrollView {
            VStack(spacing: 14) {
                settingsHeader("隐私与连接", "本地优先、只读访问、最小数据范围")

                GlassCard {
                    VStack(alignment: .leading, spacing: 13) {
                        SectionEyebrow(text: "读取范围")
                        settingToggle(
                            "从 Prompt 生成会话标题",
                            detail: "默认开启；仅在本地提炼并保存短标题，不保存 Prompt 原文。",
                            isOn: $store.promptTitlesEnabled
                        )
                        Divider().overlay(MeterTheme.line)
                        privacyRow("对话正文", store.promptTitlesEnabled ? "仅提炼标题" : "不读取", "text.bubble")
                        privacyRow("工具参数与输出", "不保存", "hammer")
                        privacyRow("鉴权信息", "不托管", "key")
                        privacyRow("逐轮元数据", store.turnHistoryEnabled ? "本地保存" : "不保存", "externaldrive")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionEyebrow(text: "Codex 连接")
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("当前状态").font(.system(size: 12, weight: .medium, design: .rounded))
                                Text("通过本机 App Server 读取额度和 Token 元数据")
                                    .font(.system(size: 9, design: .rounded))
                                    .foregroundStyle(MeterTheme.secondaryText)
                            }
                            Spacer()
                            StatusPill(text: store.connection.label, color: connectionColor)
                        }
                        Button("立即刷新") { Task { await store.refreshAll() } }
                            .buttonStyle(GlassActionButtonStyle(prominent: true))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
    }

    private func settingsHeader(_ title: String, _ subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 10, design: .rounded)).foregroundStyle(MeterTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func settingToggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium, design: .rounded))
                Text(detail).font(.system(size: 9, design: .rounded)).foregroundStyle(MeterTheme.secondaryText)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(MeterTheme.mint)
                .frame(width: 42, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func privacyRow(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(MeterTheme.cyan)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(MeterTheme.cyan.opacity(0.1)))
            Text(title).font(.system(size: 11, weight: .medium, design: .rounded))
            Spacer()
            Text(value).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(MeterTheme.secondaryText)
        }
    }

    private var connectionColor: Color {
        switch store.connection {
        case .live: return MeterTheme.mint
        case .connecting: return MeterTheme.yellow
        case .stale: return MeterTheme.orange
        case .unavailable: return .gray
        }
    }
}
