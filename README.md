# Codex Meter

一个本地优先的 macOS 菜单栏应用，用于查看 Codex 套餐额度、逐轮 token 消耗和个人使用趋势。

## 当前开发预览

- 读取官方 Codex App Server 额度与账户 token 数据。
- 从本地 Codex rollout 聚合逐轮 token；默认仅提取用户 Prompt 的短标题，可在设置中关闭。
- 菜单栏额度环、轮次完成反馈、token 构成和最近轮次。
- 面板内可折叠查看逐轮 Token、额度影响与历史任务。
- 本地隐私设置与高消耗通知开关。

## 构建

需要 macOS 14 及以上和 Swift 6 工具链：

```bash
swift build
```

生成可运行 `.app`：

```bash
chmod +x scripts/package_app.sh
./scripts/package_app.sh
open "outputs/Codex Meter.app"
```

当前包使用 ad-hoc 签名，适合本机开发预览。公开分发前需要 Developer ID 签名、公证和正式更新通道。

## 跨设备继续开发

新设备首先阅读 [HANDOFF.md](HANDOFF.md) 和 [迁移清单](docs/MIGRATION.md)。源码通过 GitHub 私有仓库同步；个人额度快照与会话日志不得提交到仓库。

## 验证

当前命令行工具链未附带 XCTest/Swift Testing 模块，因此自检使用独立 smoke executable：

```bash
swiftc Sources/CodexMeter/Models.swift \
  Sources/CodexMeter/SessionUsageScanner.swift \
  Tests/CodexMeterTests/SessionUsageScannerTests.swift \
  -o /tmp/codex-meter-parser-test
/tmp/codex-meter-parser-test
```
