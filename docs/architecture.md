# XRK Harness 手机版 · 架构

> **读者**：维护者 · 贡献者  
> 定稿约定之后代码有扩展（插件、远程、手机操控等），细节以当前源码为准。手机独属工具/技能见 [HANDOFF.md](./HANDOFF.md)。

## 技术栈

| 层 | 选型 | 理由 |
|---|---|---|
| UI | Flutter + Riverpod | 跨 ROM 一致；聊天 / WebView 壳 |
| 原生层 | Kotlin（Flutter 插件，写在 app 内） | 解压运行时、proot、前台服务、手机操控 |
| 本地运行时 | Ubuntu 24.04 base + Node + `@xrkseek/harness-cli`，经 proot | App 自带，免 Root |
| 对话 UI | guest 内已组装的 Web 壳（与 Desktop 同源） | 壳 ≠ 引擎；改对话须更新 runtime |

## 目录

```
XRK-harness-mobile/
  app/                         Flutter 应用（包名 com.xrkseek.harness）
    lib/                       UI · 状态 · 平台通道
    android/.../harness/       Kotlin：runtime · phone · notify
    assets/skills/             xrk-guide / xrk-ui / xrk-support（managed）
  runtime/                     build-runtime.sh · out/<abi>/
  tooling/                     build-apk.sh · release_assets.py
  docs/
```

## 平台通道约定（Dart ↔ Kotlin）

MethodChannel（实现以当前 `RuntimePlugin` 为准；历史名 `dsh/runtime` 已迁）：

| 方法 | 参数 | 返回 |
|---|---|---|
| `getStatus` | — | `RuntimeStatus` map（见下） |
| `install` | — | `null`；进度经事件流推送；已安装且版本一致时立即完成 |
| `start` | `{env: Map<String,String>}`（如 `DEEPSEEK_API_KEY`） | `null`；启动前台服务与进程 |
| `stop` | — | `null` |
| `getLogs` | `{lines: int}` | `List<String>` |
| `getLogSnapshot` | `{lines: int}`（默认 300，最多 2000） | `{entries: [LogEntry], throughSeq: int}`：内存里最后几行，`throughSeq` 是同一时刻已接收的最大序号 |
| `reset` | — | `null`；删除已解压运行时（保留 `/root` 用户数据需另行确认） |

`RuntimeStatus`：
```
{
  abi: "arm64-v8a" | "x86_64",
  bundledVersion: String,        // APK 内运行时版本（manifest.json）
  installedVersion: String?,     // 已解压版本
  phase: "notInstalled" | "installing" | "installed" | "starting" | "running" | "stopping" | "error",
  baseUrl: String?,              // 如 http://127.0.0.1:3080
  token: String?,                // xrkh serve 启动 token
  error: String?
}
```

EventChannel（与 MethodChannel 同插件；事件 map）：
- `{type: "progress", step: "extract"|"verify"|"configure", done: int, total: int}`
- `{type: "status", status: RuntimeStatus}`
- `{type: "logs", entries: [LogEntry]}`：日志约每 100 ms 一批；`LogEntry` 为 `{seq: int, line: String, stream: "stdout"|"stderr"|"system"}`，`line` 已脱敏，`seq` 在进程内递增。App 先订阅再取快照，只接 `seq > throughSeq` 的批次。

## 打包

- Flavor `arm64`（真机产品）/ `x64`（专项）。各风味只带自己的 `runtime/out/<abi>/`。
- 构建：`tooling/build-apk.sh` 或主仓 `xrk-mobile-apk/scripts/build-install-mumu.ps1`（ASCII 树 `C:\xrk-mobile`）。
- guest 须含 merge 后的 `xrk-phone`；`ENGINE_TGZ` 缺 `seeds/mobile` 时 `build-runtime.sh` 失败。
- versionCode / 发版命名：`docs/release.md` · `docs/HANDOFF.md`。

## 本地连接

1. 原生层启动 `xrkh serve`（回环 + token）。
2. Dart / WebView 经 Face 同源会话连 Host（实现以当前壳为准）。
3. 手机操控：`phone_*` 经 App 回环 API（`XRK_MOBILE_API`），不是 MCP。

## 产品壳 · 设置球（LocalHostShell）

对话 UI 在 guest WebView（与 Desktop 同源）；Flutter 壳负责启停引擎与原生能力。全屏 WebView / 启动失败页上都没有 Host 侧栏，因此需要一颗**壳层逃生口**——设置球。

| 项 | 约定 |
|---|---|
| 角色 | 原生快捷入口：不依赖 Host 是否存活 |
| 常驻入口 | 手机操控 · App 设置（引擎 / 保活 / 外观 / 关于 / 更新） |
| Host 就绪 | 第三项 → 对话设置（WebView Host 面板） |
| Host 未就绪（启动中 / code 1 / 已停） | 第三项 → **引擎状态**（日志 · 启停 · 诊断） |
| 何时隐藏 | **仅**软键盘打开时（避免挡输入）；**不**等 `onPageFinished` |
| 代码 | `app/lib/shell/shell_ball*.dart` · `shell_quick_panel.dart` · 显隐真源 `shell_ball_visibility.dart` |

反模式：Host 挂了只剩「重试」、设置球随 WebView 一起消失——人进不了引擎状态与更新。

## 细节

- 运行时 / proot：`runtime/` · `app/android/.../runtime/`
- 手机操控：`app/android/.../phone/` · [HANDOFF.md](./HANDOFF.md)
- 设置球 / 壳逃生口：上文「产品壳 · 设置球」
- 设计规范：`docs/design/`
