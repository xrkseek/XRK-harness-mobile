# 更新日志 · Changelog

> **读者**：终端用户 · 维护者  
> 产品名：**XRK Harness 手机版**。版本号与主仓 `@xrkseek/harness-cli` 同号。

## 0.7.17 · 2026-11-11

### 中文

- 机内 `@xrkseek/harness-cli@0.7.17`
- 覆盖安装：runtime 变更时重装并抬回 `/root`；同 runtime 壳 bump 只软愈合、不重解 rootfs
- 手机文件 / 权限与设置个性化入口完善

### English

- On-device `@xrkseek/harness-cli@0.7.17`
- Overlay install: reinstall + `/root` carry when runtime changes; shell-only bumps soft-heal without rootfs re-extract
- Phone files / permissions and Settings personalization polish

## 0.7.16 · 2026-11-11（App 首发）

### 中文

**XRK Harness 手机版 0.7.16** 是本产品线的**第一个正式 App 版本**（包名 `com.xrkseek.harness`）。

本机 proot 内运行 `@xrkseek/harness-cli@0.7.16`（`xrkh`），也可连接电脑 / 服务器上的 Host。手机独属能力：

- **机内引擎**：Ubuntu + Node + `xrkh`（免 Root）；guest 含手机技能种子 `xrk-phone`（runtime merge）
- **对话**：与桌面同源 Web 壳；会话 / 工具 / Settings
- **手机操控**：授权后 `phone_*` 工具（看屏、点按、输入等）；可随时停
- **访问手机文件**：可选把共享存储挂到 guest `/sdcard`
- **应用内更新**：读 GitHub Releases 的 `update.json`（仓库须对客户端可读）

工程路径致敬 **DSH Go**（DeepSeek Harness 手机端一脉）；引擎与契约以 [XRK-Harness](https://github.com/xrkseek/XRK-harness) 为准。

前身 XRK Go / DSH Go 的旧版记录见 [changelog-legacy.md](./changelog-legacy.md)（归档，非本产品版本号）。

### English

**XRK Harness Mobile 0.7.16** is the **first formal App release** on this product line (application id `com.xrkseek.harness`).

Run `@xrkseek/harness-cli@0.7.16` (`xrkh`) on-device in proot, or connect to a Host on a computer / server. Phone-only surfaces include:

- **On-device engine**: Ubuntu + Node + `xrkh` (no Root); guest ships the `xrk-phone` skill seed (runtime merge)
- **Chat**: same Web shell family as desktop
- **Phone control**: `phone_*` tools after permission; stop anytime
- **Phone files**: optional bind of shared storage at guest `/sdcard`
- **In-app updates**: `update.json` from GitHub Releases (repo/feed must be readable by the client)

Built with respect to the **DSH Go** engineering path; engine contracts live in [XRK-Harness](https://github.com/xrkseek/XRK-harness).

Earlier XRK Go / DSH Go version notes are archived in [changelog-legacy.md](./changelog-legacy.md) (not this product's version numbers).
