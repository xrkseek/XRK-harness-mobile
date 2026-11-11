# 发版与应用内更新

> **读者**：维护者

产品名 **XRK Harness 手机版**。**App 首发与现行版本：`0.7.16`**（与主仓 `@xrkseek/harness-cli` 同号）。更早的 XRK Go / DSH Go 版本号不属本产品线，见 [changelog-legacy.md](./changelog-legacy.md)。

App 以 APK 分发。应用内更新读取 **GitHub Releases**（`xrkseek/XRK-harness-mobile`），校验后调系统安装器。实现：`app/lib/update/`。仓库须对客户端可读（公开，或自托管 `XRK_UPDATE_FEED`），否则检查更新只会「暂时检查不了」。

产品下载页与安装镜像由主仓 [XRK-Harness `apps/site`](https://github.com/xrkseek/XRK-harness/tree/main/apps/site) 提供。

> 正式发版须使用固定发布密钥（见「签名」）。有 `app/android/key.properties` 时用发布密钥；否则本地 release 回落 debug key，不可正式分发。

## 资产约定（与主仓 xrkh 同号习惯）

| 项 | 约定 | 例子 |
|---|---|---|
| 包名 | `com.xrkseek.harness` | — |
| 版本名 | `app/pubspec.yaml` 的 `version: X.Y.Z`；常与 guest `@xrkseek/harness-cli` 同号；**首发 `0.7.16`** | `0.7.16` |
| 构建号 | `tooling/build-apk.sh` 按构建分钟写入 versionCode | `11102145` |
| tag | `v` + 版本名 | `v0.7.16` |
| APK | `xrk-harness-<版本>-arm64.apk` | `xrk-harness-0.7.16-arm64.apk` |
| 校验和 | `SHA256SUMS` | — |
| 清单 | `update.json`（schema 1） | `…/latest/download/update.json` |
| 引擎发行说明 | 主仓 `docs/releases/vX.Y.Z.md` | 契约 / Host |
| App 面变更 | 本仓 `docs/changelog.md`（首发起）；前身归档 `changelog-legacy.md` | 壳 / 手机操控 |

guest 须含 `seeds/mobile`（`xrk-phone`）；缺则 runtime 构建失败。见 [HANDOFF.md](./HANDOFF.md)。

`update.json` 由 `tooling/release_assets.py` 生成。省略 `assets.*.url` 时，App 用 tag + 文件名拼 GitHub 地址。

默认更新源：GitHub + 按时区排序的公开加速器。可选自托管经 `--dart-define=XRK_UPDATE_MIRROR=` / `XRK_UPDATE_FEED=`，默认关闭。

## 构建号

```sh
tooling/build-apk.sh                 # release arm64
tooling/build-apk.sh -f x64          # 专项
```

`versionCode = (年 - 2026) × 10^8 + MMDDhhmm`（UTC+8）。同一版本名重打包不会被当成新版本——要发就升版本名。

## 发版步骤

1. 改 `app/pubspec.yaml` 版本名；需要时同步 `docs/guide/`。
2. 备齐 `runtime/out/arm64-v8a` → `tooling/build-apk.sh`。
3. `apksigner verify …`：非 debug 证书，与上一版一致。
4. `python3 tooling/release_assets.py --notes notes.md` → `dist/`。
5. `gh release create vX.Y.Z dist/* --repo xrkseek/XRK-harness-mobile …`
6. 若下载页要露出手机包：改主仓 `apps/site`。

## 签名

正式包用固定发布密钥。`key.properties` 与 keystore 不入库。

## 应用内更新

设置 → 检查更新 → 读 `update.json` / GitHub API → 下 APK → SHA-256 → PackageInstaller。包名与签名必须与已装版本一致。
