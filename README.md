<p align="center">
  <b>简体中文</b> · <a href="README.en.md">English</a>
</p>

<div align="center">

# XRK Harness · 手机版

**把 [XRK-Harness](https://github.com/xrkseek/XRK-harness) 装进手机。**

本地优先的 Android 客户端：本机跑 `xrkh`，也能连电脑上的 Host。

[![Android 8+](https://img.shields.io/badge/Android-8%2B-4B67B4?style=flat-square&logo=android&logoColor=white&labelColor=2B3245)](https://github.com/xrkseek/XRK-harness-mobile/releases/latest)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-4B67B4?style=flat-square&labelColor=2B3245)](LICENSE)
[![GitHub](https://img.shields.io/badge/github-xrkseek%2FXRK--harness--mobile-black.svg?style=flat-square&labelColor=2B3245)](https://github.com/xrkseek/XRK-harness-mobile)

</div>

---

## 下载

包名 **`com.xrkseek.harness`**。真机用 **arm64** APK。

<p align="center">
  <a href="https://github.com/xrkseek/XRK-harness-mobile/releases/latest"><img alt="从 GitHub Releases 下载" src="https://img.shields.io/badge/GitHub%20Releases-%E4%B8%8B%E8%BD%BD%20APK-4B67B4?style=for-the-badge&logo=github&logoColor=white&labelColor=2B3245"></a>
</p>

| 项 | 约定 | 例子 |
| --- | --- | --- |
| tag | `v` + 版本名 | `v0.7.16` |
| APK | `xrk-harness-<版本>-arm64.apk` | `xrk-harness-0.7.16-arm64.apk` |
| 清单 | 同 Release 的 `update.json` | `…/latest/download/update.json` |

发版约定见 [docs/release.md](docs/release.md)。使用说明见 [docs/guide/](docs/guide/README.md)。

## 这是什么

| 层 | 作用 |
| --- | --- |
| **壳** | Flutter / Kotlin：启动、权限、文件、通知、更新安装 |
| **机内引擎** | proot 里的 `@xrkseek/harness-cli`（`xrkh`），家目录 `/root/.xrk` |
| **对话 UI** | 机内 Host 的 Web 壳 |

与桌面 / CLI 共用 XRK-Harness Host 契约。下载页与安装镜像由主仓 [`apps/site`](https://github.com/xrkseek/XRK-harness/tree/main/apps/site) 提供。

## 可以做什么

- 本机安装 Ubuntu + Node + `xrkh`（免 Root）
- 连接电脑 / 服务器上的 Host
- 聊天、工具审批、附件与语音
- 手机操控（授权后可读屏、点按；随时停）
- 主题、图标、桌宠

## 安装

需要 Android 8.0+。从 Releases 装 arm64 包 → 首次引导里装本机运行环境或只连远程 → 配好模型再聊。本机引擎大约预留 1 GB。

## 从源码构建

Linux x86_64（Windows 用 ASCII 构建树，见主仓 skill `xrk-mobile-apk`）：

```bash
git clone https://github.com/xrkseek/XRK-harness-mobile.git
cd XRK-harness-mobile
bash tooling/setup-toolchain.sh && source tooling/env.sh
bash runtime/build-runtime.sh arm64-v8a
bash tooling/build-apk.sh -f arm64 --keep-daemon
```

产物：`app/build/app/outputs/flutter-apk/app-arm64-release.apk`。

## 目录

| 路径 | 内容 |
| --- | --- |
| `app/` | Flutter 壳与 Android Kotlin |
| `packages/` | Host / Remote Dart 客户端 |
| `runtime/` | guest rootfs、桥接、引擎补丁 |
| `sdk/` · `examples/` | 插件作者工具与示例 |
| `docs/` | 产品与维护文档 |
| `tooling/` | 工具链与 APK 构建 |

## 许可证

代码 [AGPL-3.0](LICENSE)；`sdk/`、`examples/` 为 MIT。引擎契约以 [XRK-Harness](https://github.com/xrkseek/XRK-harness) 为准。第三方见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

---

向阳而生，驭光而行
