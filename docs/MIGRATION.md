# 新设备迁移清单

## 推荐方式

使用 GitHub 私有仓库同步源码，使用离线迁移包保底。GitHub 不承载个人额度快照、Codex 会话日志或登录凭证。

## 旧电脑

1. 确认仓库已推送到私有 GitHub remote。
2. 保存 `outputs/Codex-Meter-migration-*.zip` 及其 `.sha256` 文件。
3. 如需保留额度趋势，退出 Meter 后单独复制：

   `~/Library/Application Support/CodexMeter/`

4. 不要复制或上传 ChatGPT Cookie、Codex 登录凭证和完整 `~/.codex/sessions`。

## 新电脑

1. 安装 Xcode Command Line Tools：`xcode-select --install`。
2. 安装并登录 ChatGPT/Codex。
3. 克隆私有仓库或解压离线迁移包。
4. 在项目根目录执行 `swift build`。
5. 按 `HANDOFF.md` 运行两个 smoke test。
6. 执行 `./scripts/package_app.sh` 生成本机应用。
7. 在 Codex 中将仓库目录保存为项目。
8. 如需恢复趋势，退出 Meter 后还原 `~/Library/Application Support/CodexMeter/`。

## 验收

- 菜单栏出现 Codex 图标、额度环和百分比。
- 面板能够读取额度窗口和重置时间。
- 完成一轮 Codex 对话后，最近一轮标题与 Token 正常更新。
- 日/周/月趋势可以切换，图表可以悬停定位。
- 快速纵向滚动没有横向晃动或边缘跳动。

