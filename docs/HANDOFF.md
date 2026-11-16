# 手机仓交接 · Mobile handoff

> **读者**：维护者 · Coding Agent  
> **Audience**: Maintainers · Coding Agents

手机专属面（相对主仓 xrkh）；发版 / 打 APK / 改 `phone_*` 前读。

**App 现行：`0.7.19`**（首发 `0.7.16`；包名 `com.xrkseek.harness`）。勿把前身 XRK Go `1.0.x` / `0.9.x` 当现行号。

## 三层（勿混）

| 层 | 落点 | 进 APK？ |
|----|------|----------|
| Flutter 壳 | `app/` | 只重打壳 |
| guest `xrkh` | 主仓 `apps/cli` + `packages/*` → ENGINE_TGZ → `runtime/out` | 须重编 runtime |
| 手机独属工具 / 技能 | 见下表 | 随壳或随 runtime |

**设置球**：壳层逃生口（Host 挂了仍可进引擎状态）。真源：[architecture.md](./architecture.md)「产品壳 · 设置球」· `app/lib/shell/shell_ball_visibility.dart`。

## 手机独属上下文 / 工具面

| 面 | 真源 | 何时进 guest |
|----|------|----------------|
| `phone_*` 工具 | `PhoneToolCatalog.kt` → `PhoneGuest.generateToolsPlugin()` → `$XRK_HOME/plugins/xrk-mobile` | 每次引擎启动重写 |
| 手机 prompt（短） | `assets/xrk-mobile-prompt/plugin.mjs`（操控开） | 同上 |
| AGENTS 追加节（短） | `PhoneGuest.AGENTS_SECTION` | 操控开时写 `$XRK_HOME/AGENTS.md` |
| playbook **`xrk-phone`**（长） | 主仓 `apps/cli/seeds/mobile/skills/xrk-phone` | **runtime 构建** merge → establish |
| App HOWTO | Flutter `assets/skills/xrk-guide` · `xrk-ui` · `xrk-support` | managed install |

**一事一处：** 清单 / 禁项 / 顺序在 **`xrk-phone`**；AGENTS 与 prompt 只指路 + 硬边界。

**禁止：** `xrk-phone` 进通用 `seeds/skills/`；establish 加 `XRK_MOBILE_*`；提示词写已废的 `mcp__phone__*`。

## 发行命名（对齐主仓）

| 项 | 约定 |
|----|------|
| App 版本名 | `app/pubspec.yaml` → `X.Y.Z`（常与 guest `harness-cli` 同号，如 `0.7.18`） |
| Git tag | `vX.Y.Z` |
| APK 文件 | `xrk-harness-X.Y.Z-arm64.apk`（构建脚本 stage 名可带 `-release`） |
| 发行说明 | 主仓 `docs/releases/vX.Y.Z.md`（引擎/壳契约）；手机仓 `docs/changelog.md`（App 面）或发版 notes |
| runtime 版本串 | `manifest.runtimeVersion`（含 `xrk0.7.18` 等） |

细节：`docs/release.md` · 主仓 skill `xrk-mobile-apk` · `xrk-dev-surfaces` 面 C。

## 会话写锁（单 Host）

手机每次 guest 启动前、以及 `needInstall`/carry 还原 `/root` 后，只删 `sessions.write.lock`（不扫其它 `*.lock`，以免误伤 LastKnownGood / memory 旁路锁）。设置内 APK 安装前 best-effort `stop`（超时仍继续装；下次启动清锁）。guest 注入 `XRK_SESSIONS_LOCK_RECLAIM=1` 作双保险。Desktop/多 Host 勿开该 env。勿把「残留写锁」当成需进安全模式的数据损坏。

## 验收清单（改 phone / 技能后）

1. stage / ENGINE_TGZ 含 `seeds/mobile/skills/xrk-phone/SKILL.md`
2. AGT `build-runtime` 日志有 `merged mobile skill seed → seeds/skills/xrk-phone`
3. 真机：`skill` → `xrk-phone` 非 unknown；`phone_intent` settings 页可跳
4. 操控关：无 `xrk-mobile-prompt` 催促 phone_*
