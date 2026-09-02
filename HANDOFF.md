# Codex Meter 开发交接

最后更新：2026-08-28

这份文件是跨设备继续开发的首要入口。新设备上的 Codex 应先完整阅读本文件、`README.md`、`CHANGELOG.md` 和 `docs/product-spec.md`，再修改代码。

## 1. 产品定位

Codex Meter 是本地优先的 macOS 菜单栏应用，用于展示：

- Codex 当前额度窗口、剩余百分比和重置时间。
- 最近一轮及历史轮次的 Token 消耗。
- 输入、缓存输入、输出和推理 Token 构成。
- 按日、周、月查看的用量趋势。
- 基于模型权重与本地窗口数据估算的额度影响。

它只监测 Codex 任务，不监测 ChatGPT Chat 模式。不要把 ChatGPT 对话的粗略估算混入 Codex 数据。

## 2. 当前实现状态

### 已完成

- 原生 SwiftUI 菜单栏应用，无 Dock 图标。
- 菜单栏 Codex 图标、额度环和百分比。
- 通过 ChatGPT/Codex 内置 `codex app-server --stdio` 读取账户额度。
- 从 `~/.codex/sessions` 与 `~/.codex/archived_sessions` 增量扫描 rollout JSONL。
- 逐轮 Token 聚合、个人中位数基线和加权额度估算。
- 最近一轮一级卡片与可折叠“用量复盘”二级内容。
- 历史任务按最新对话置顶、任务折叠、粘性任务标题和纯纵向滚动。
- 对话标题默认取用户 Prompt 并截断；图片 Prompt 显示“图片对话”。
- 已过滤 `<environment_context>`、`<recommended_plugins>` 等系统注入内容，避免代码成为标题。
- 日、周、月趋势图和鼠标悬停定位。
- macOS 26 使用原生 `glassEffect`，旧系统使用兼容材质。
- 额度快照缓存、额度观察历史、网络瞬断重试和离线降级。
- 任务级 Codex 深链跳转。
- 现有体验与隐私设置持久化，并支持登录时自动启动。
- Apple Watch 风格双层圆环同时展示一周额度与 5 小时限额；菜单栏、额度影响和节奏分析以一周额度为主，不分析 5 小时节奏。

### 重要边界

- ChatGPT Chat 模式不会写入 Codex rollout，因此无法提供准确逐轮 Token。
- Codex 目前只有任务级深链，没有公开的 turn/message 锚点，无法精确跳到某条消息。
- 额度百分比影响是加权估算，不是官方逐轮扣减结果；跨设备用量不能归因给本机某轮。
- 账户额度依赖 Codex App Server 的内部账户方法，版本变化时需要做兼容验证。
- 当前公开预览版使用 ad-hoc 签名，用户首次打开时需要通过 Finder 右键选择“打开”；正式分发仍应使用 Developer ID 签名并完成 Apple 公证。

## 3. 代码结构

| 路径 | 作用 |
| --- | --- |
| `Sources/CodexMeter/CodexMeterApp.swift` | 应用入口、菜单栏状态项与图标绘制 |
| `Sources/CodexMeter/MenuContentView.swift` | 主面板、历史复盘、趋势图、滚动行为 |
| `Sources/CodexMeter/DesignSystem.swift` | Liquid Glass、颜色、卡片和按钮设计系统 |
| `Sources/CodexMeter/UsageStore.swift` | 状态管理、刷新、缓存、额度节奏与估算 |
| `Sources/CodexMeter/CodexAppServerClient.swift` | 启动 Codex App Server 并解析额度/用量 |
| `Sources/CodexMeter/SessionUsageScanner.swift` | 增量扫描 rollout JSONL 并聚合轮次 |
| `Sources/CodexMeter/CodexThreadTitleReader.swift` | 从 Codex SQLite 读取任务标题 |
| `Sources/CodexMeter/Models.swift` | 数据模型、标题清洗、加权额度公式 |
| `Sources/CodexMeter/SettingsView.swift` | 设置界面 |
| `Tests/CodexMeterTests/` | 独立 smoke/self-test 程序 |
| `scripts/package_app.sh` | Release 构建、组装和 ad-hoc 签名 `.app` |

## 4. 核心数据链路

### 额度

1. 定位 ChatGPT/Codex App 内置或系统安装的 `codex` 可执行文件。
2. 启动 `codex app-server --stdio`。
3. 调用 `account/rateLimits/read` 和 `account/usage/read`。
4. 成功快照保存到 `~/Library/Application Support/CodexMeter/account-snapshot-v1.json`。
5. 正常状态每 5 分钟刷新一次，Timer 带容差以降低唤醒成本。
6. 明确的网络传输失败只在失败路径快速重试一次；之后按 5、15、30 秒恢复。期间保留最近有效快照。

### 轮次

1. 每 5 秒检查 Codex rollout 文件是否追加。
2. 只从上次 offset 继续读取，不反复扫描全文。
3. 按 `task_started` 到 `task_complete` 聚合 Token、模型、推理等级和工具次数。
4. 标题候选必须跳过系统注入块；找不到真实 Prompt 时继续等待下一条 `role=user` 消息。
5. 扫描缓存位于 `~/Library/Application Support/CodexMeter/session-scan-cache-v1.json`。

## 5. 产品与 UI 决策

- 颜色阈值：剩余 `>80%` 绿色，`50%–80%` 黄色，`25%–50%` 橙色，`<25%` 或触限红色，不可用灰色。
- 面板核心分区：双周期额度概览、额度节奏、最近一轮消耗、今日/周期用量、Credits/重置信息。
- 一周额度是长期预算和界面主指标；5 小时额度是短时压力指标，不能再按 App Server 的 `primary`/`secondary` 顺序决定展示优先级。
- 最近一轮一级卡片只保留标题、执行时间、模型与推理强度、Token、额度估算、基线和“用量复盘”入口。
- 二级复盘以任务为组、轮次为子项；任务可折叠，标题随内容滚动保持可操作。
- 整体风格克制，优先使用真实透明 Liquid Glass，不使用大面积彩色渐变伪装玻璃。
- 快速滚动不能有横向位移、顶部/底部吸附跳动或折叠后空白。

关键视觉基准位于 `docs/ui-reference/`。

## 6. 构建与验证

要求：macOS 14+、Swift 6；完整 Liquid Glass 视觉需要 macOS 26。

```bash
swift build

swiftc Sources/CodexMeter/Models.swift \
  Sources/CodexMeter/SessionUsageScanner.swift \
  Tests/CodexMeterTests/SessionUsageScannerTests.swift \
  -o /tmp/codex-meter-parser-test
/tmp/codex-meter-parser-test

swiftc Sources/CodexMeter/Models.swift \
  Sources/CodexMeter/CodexAppServerClient.swift \
  Tests/CodexMeterTests/AppServerClientSmoke.swift \
  -o /tmp/codex-meter-app-server-smoke
/tmp/codex-meter-app-server-smoke

./scripts/package_app.sh
open "outputs/Codex Meter.app"
```

App Server smoke test依赖本机安装并登录 ChatGPT/Codex，也需要网络可用。

## 7. 新电脑恢复步骤

```bash
git clone https://github.com/Vito-Bai/codex-meter.git codex-meter
cd codex-meter
swift build
```

然后在 Codex 中添加该目录为项目，并发送：

> 请先完整阅读 HANDOFF.md、README.md、CHANGELOG.md 和 docs/product-spec.md，运行现有测试确认基线，再继续当前需求。保留已有产品决策，不要重新设计已确认的交互。

如需迁移个人额度趋势，先退出 Meter，再把旧电脑的以下目录复制到新电脑相同位置：

```text
~/Library/Application Support/CodexMeter/
```

该目录只能线下迁移，不要提交到 GitHub。Codex 登录凭证、Cookie 和 `~/.codex/sessions` 也不要提交。

## 8. GitHub 推送

当前机器没有安装 GitHub CLI。创建一个名为 `codex-meter` 的私有仓库后，在本目录执行：

```bash
git remote add origin git@github.com:<YOUR_ACCOUNT>/codex-meter.git
git push -u origin main
```

也可以使用 HTTPS remote，但不要把 Personal Access Token 写进 remote URL、文件或命令记录。

## 9. 后续优先级

1. Developer ID 签名、公证与稳定分发。
2. 为 App Server 协议变化增加兼容测试与用户可理解的错误提示。
3. 使用 Instruments 持续验证快速滚动、内存和后台能耗。
4. 评估正式更新通道；复盘分析能力确认价值后再扩展，避免重新堆叠信息。
