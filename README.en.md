<p align="center">
  <a href="README.md">简体中文</a> · <b>English</b>
</p>

<div align="center">

# XRK Harness · Mobile

**[XRK-Harness](https://github.com/xrkseek/XRK-harness) on your phone.**

A local-first Android client: run `xrkh` on-device, or connect to a Host on your computer.

[![Android 8+](https://img.shields.io/badge/Android-8%2B-4B67B4?style=flat-square&logo=android&logoColor=white&labelColor=2B3245)](https://github.com/xrkseek/XRK-harness-mobile/releases/latest)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-4B67B4?style=flat-square&labelColor=2B3245)](LICENSE)
[![GitHub](https://img.shields.io/badge/github-xrkseek%2FXRK--harness--mobile-black.svg?style=flat-square&labelColor=2B3245)](https://github.com/xrkseek/XRK-harness-mobile)

</div>

---

## Download

Application id **`com.xrkseek.harness`**. On a phone, use the **arm64** APK.

<p align="center">
  <a href="https://github.com/xrkseek/XRK-harness-mobile/releases/latest"><img alt="Download from GitHub Releases" src="https://img.shields.io/badge/GitHub%20Releases-Download%20APK-4B67B4?style=for-the-badge&logo=github&logoColor=white&labelColor=2B3245"></a>
</p>

| Item | Convention | Example |
| --- | --- | --- |
| tag | `v` + version | `v0.7.16` |
| APK | `xrk-harness-<version>-arm64.apk` | `xrk-harness-0.7.16-arm64.apk` |
| Manifest | `update.json` on the same Release | `…/latest/download/update.json` |

See [docs/release.md](docs/release.md) and the [user guide](docs/guide/README.md).

## What this is

| Layer | Role |
| --- | --- |
| **Shell** | Flutter / Kotlin — launch, permissions, files, notifications, updates |
| **On-device engine** | `@xrkseek/harness-cli` (`xrkh`) in proot; home `/root/.xrk` |
| **Chat UI** | Host web shell inside the guest |

Shares Host contracts with desktop and CLI. The download page lives in the main repo [`apps/site`](https://github.com/xrkseek/XRK-harness/tree/main/apps/site).

## Features

- On-device Ubuntu + Node + `xrkh` (no Root)
- Remote Host on a computer or server
- Chat, tool approvals, attachments, voice
- Phone control (with permission; stop anytime)
- Themes, icons, pets

## Install

Android 8.0+. Install the arm64 APK from Releases, set up the on-device runtime or a remote host, configure a model, then chat. Keep about 1 GB free for the local engine.

## Build from source

Linux x86_64 (on Windows use the ASCII build tree; see skill `xrk-mobile-apk` in the main repo):

```bash
git clone https://github.com/xrkseek/XRK-harness-mobile.git
cd XRK-harness-mobile
bash tooling/setup-toolchain.sh && source tooling/env.sh
bash runtime/build-runtime.sh arm64-v8a
bash tooling/build-apk.sh -f arm64 --keep-daemon
```

Output: `app/build/app/outputs/flutter-apk/app-arm64-release.apk`.

## Layout

| Path | Contents |
| --- | --- |
| `app/` | Flutter shell and Android Kotlin |
| `packages/` | Host / Remote Dart clients |
| `runtime/` | guest rootfs, bridge, engine patches |
| `sdk/` · `examples/` | plugin author kit and samples |
| `docs/` | product and maintainer docs |
| `tooling/` | toolchain and APK build |

## License

[AGPL-3.0](LICENSE); `sdk/` and `examples/` are MIT. Engine contracts live in [XRK-Harness](https://github.com/xrkseek/XRK-harness). Third-party: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

---

向阳而生，驭光而行
