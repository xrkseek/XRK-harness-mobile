# 技术报告：dsh-Go 的两个真亮点，与我们的落地方式

> 基线上游：dsh-Go `1.0.13`（commit `2432cbd`，AGPL-3.0）。本文的事实均来自其源码。

## 0. 一句话结论

dsh-Go 的价值不在 Flutter 那套 UI，而在两块硬工程：

1. **proot 本机运行**——把整套 Linux + Node + 服务塞进 APK，手机上离线跑起来，不依赖电脑。
2. **手机操控**——用 AccessibilityService 让模型能"看屏幕、点按钮、打字"，即 Android 版的 `computer_use`。

壳（Flutter UI）对我们没用：我们的 web UI 本身已做移动端适配。所以策略是**换壳留核**。

---

## 1. 亮点一：proot 本机运行

### 1.1 APK 里到底装了什么

`runtime/build-runtime.sh` 在 **x86_64 Linux 主机上**（不执行任何外来架构代码）组装出每个 ABI 一组资产：

```
runtime/out/<abi>/assets/runtime/rootfs-<abi>.tar.xz   ← Ubuntu 24.04 base + Node + 引擎 + 全部依赖
runtime/out/<abi>/assets/runtime/manifest.json         ← 版本、sha256、启动模板
runtime/out/<abi>/assets/runtime/licenses/...
runtime/out/<abi>/jniLibs/<abi>/lib{proot,proot-loader,talloc,android-shmem}.so
runtime/out/<abi>/build-report.json                    ← ELF 审计、裁剪清单、警告
```

关键设计：**proot 及其加载器是 Termux 的二进制，被改名成 `lib*.so` 放进 jniLibs**，靠
`useLegacyPackaging = true` 让它们在安装时被解压到 `nativeLibraryDir` 从而可执行——因为 Android 不允许
从 assets 直接执行。

### 1.2 安装与启动链路

`RuntimeInstaller.kt` 的行为很值得抄：

- 目录布局 `rootfs/`（proot -r 的活动根）+ `staging/`（解压中的临时区），**解压完成后原子切换**，
  中途失败不会毁掉上一份可用运行时。
- 解压前先按 `manifest.rootfsSha256` 校验；`.xz` 用流式 `TarExtractor`，并回吐
  `(compressedBytesRead, totalCompressedBytes)` 给 UI 进度条。
- `installedVersion()` / `isCurrent()` 判断是否需要重装。

启动侧（Dart ↔ Kotlin，`MethodChannel dsh/runtime`）：`getStatus / install / start / stop / getLogs /
getLogSnapshot / reset`，事件走 `EventChannel`（`progress` / `status` / `logs`）。日志约 100ms 一批，
每条带自增 `seq`，App 先订阅再取快照、只接 `seq > throughSeq` 的批次——**批次与快照既不重叠也不漏行**，
且日志行已脱敏。

服务进程起来后：`dsh web --host 127.0.0.1 --port 3080 --no-open` → 从 stdout 解析 token →
客户端用 token 换 cookie → WebView 兜底直接开 `http://127.0.0.1:3080/?token=…`。

### 1.3 三个非踩不可的坑（它们都写在代码里）

| 坑 | 处理 |
|---|---|
| Android 10+ 禁止应用私有目录 `exec` | `targetSdk = 28`（与 Termux 相同） |
| 可执行文件必须来自 nativeLibraryDir | proot 改名 `lib*.so` + `useLegacyPackaging = true` |
| 单包体积 | 按 ABI 分 Gradle flavor，每个 flavor 只带自己的 `runtime/out/<abi>` 与 jniLibs |

### 1.4 构建脚本本身也是资产

`build-runtime.sh` 不是一坨 `npm install`：

- 所有输入**按 sha256 pin**（Ubuntu base、Node、python-build-standalone、termux 的 proot/talloc/shmem、
  proot 源码 zip），任一不匹配直接 fail。
- 引擎树按 `runtime/patches/*.diff` + `runtime/patches/pins.json` 打补丁，**未审核的版本直接构建失败**。
- Ubuntu 依赖解析走 gpgv 验签 InRelease → Packages.xz 哈希 → 每个 deb 哈希，结果 pin 进
  `runtime/locks/ubuntu-noble-<arch>.json`。
- 产物带 `build-report.json`（ELF 审计：哪些二进制被保留/裁剪/警告）。

---

## 2. 亮点二：手机操控（Android 版 computer_use）

### 2.1 观察：把界面树压成模型能读的文本

`phone/a11y/` 这套是核心：

- `PhoneA11yService`：`canRetrieveWindowContent=true`、`canPerformGestures=true`，监听
  `typeWindowStateChanged / typeWindowContentChanged / typeWindowsChanged / typeViewTextChanged`。
- `ScreenObservation` → `ScreenFormat` → `ScreenDigest`：把无障碍节点树压成**带编号的文本行**
  （`[12] 按钮 发送`），`ScreenDigest` 还做 **previous/current 差分摘要**，避免每轮把整屏塞给模型。
- `ScreenMask`：对敏感信息做遮罩。
- `ScreenShooter`：截图兜底（纯文本树表达不了的界面）。
- 屏幕寻址用 `SCREEN_ID`：`s7` = 主屏、`b3` = 后台屏，取自最近一次返回。

### 2.2 动作：直接操作节点，不靠坐标

`phone/background/` 这一层是"不抢用户鼠标"的等价物：

- `PrivilegedTreeAccess` / `TreeTransactions`：拿到 `AccessibilityNodeInfo` 后直接做
  `ACTION_CLICK` / `ACTION_SET_TEXT` / 滚动，**不注入坐标手势**——不打断用户、不受分辨率影响。
- `PrivilegedActionGate`：动作前的权限门与风险分级。
- `InputProbe`：探测输入通道是否可用（自绘控件点不到时用它诊断）。
- 只有实在没有节点接口时才用 `tap_xy`（`canPerformGestures`）。

### 2.3 暴露给模型的工具清单（14 个）

`PhoneToolCatalog` 里真实存在的工具：

```
apps      open      intent    notify    clipboard  screen    collect
tap       type      scroll    key       tap_xy     handoff
```

外加一组系统设置动作：`home / wifi / bluetooth / mobile_network / airplane / display / sound /
battery / location / date / language / storage / nfc / app_notifications`。

注意它的取舍：`collect` 是"收集候选元素"，`screen` 是"看当前屏"，`tap` 是基于编号点击，
`handoff` 是把控制权交回用户。**这是个为模型设计的窄接口，不是把 Android API 全暴露。**

### 2.4 任务层与沉淀层

- `PhoneTaskDriver / PhoneTasks / PhoneTaskJournal / PhoneTaskReturn`：observe → act → verify 的任务循环，
  带任务日志与结果回传，失败有重试与回退。
- `phone/skills/`：`PhoneSkillBridge / PhoneSkillDrafts / PhoneSkillLifecycle`——把跑通的手机任务沉淀成 skill。
- `PhoneSelfCheck` + `PhoneSelfCheckTargetActivity`：授权状态自检（含一个专门用来被测的 Activity）。

---

## 3. 我们怎么落地：换壳留核

| 层 | 上游 | 我们 |
|---|---|---|
| UI | Flutter 重写 4200 文件 | **砍掉**。Flutter 只留 WebView，加载我们自己的 web UI（已移动适配：`viewport` / `manifest.webmanifest` / `pointer: coarse`） |
| 引擎 | `@deepseek-ai/dsh`（`dsh web --port 3080`） | **换成 `@xrkseek/harness-cli` 0.7.15**：`xrkh --host 127.0.0.1 --port 8787` |
| 运行时管理 | RuntimeInstaller / DshProcess / 前台服务 | **保留结构，改名适配**（启动命令、token 解析、退出码） |
| 打包 | proot→jniLibs、targetSdk 28、ABI flavor | **原样继承**（这几个坑已经有人趟过，不要重踩） |
| 手机操控 | `phone/` + `phone/a11y/` + `phone/background/` | **保留分层，重写工具语义**，与我们桌面 `computer_use` 的命名/参数对齐 |
| 客户端协议 | `dsh_client`（Dart 包，DSH Web API） | **重写**：对接 XRK Host 的 HTTP/WS 与 operator-pin |
| 引擎补丁 | `runtime/patches/*.diff` 针对 DSH 源码 | **作废**：为我们的包重写（bridge 插件同理） |

**关键判断：这两块里唯一不能直接抄的是引擎补丁与 API 客户端**，因为 DSH 的 Web API 与我们的 Host API
完全是两套。runtime 的骨架、proot 打包、a11y 驱动这三块是真正的可复用资产。

---

## 4. 成本与风险（诚实版）

| 项 | 说明 |
|---|---|
| APK 体积 | 基线 rootfs xz 就 100MB 量级，加 Node + 依赖，按 ABI 分包的 APK 预计 150–250MB |
| 兼容性 | `targetSdk=28` 是为 exec 让路，长期上架有风险（Google Play 要求高 targetSdk），自发行无碍 |
| ARM 适配 | 我们有一批 native 依赖（pty / sqlite / sharp 等），要确认 ARM64 预编译可用，否则要自己编 |
| 功能裁剪 | 桌面 `computer_use`（Windows UIA / agent-desktop）在手机上无意义，必须关掉或替换成 a11y |
| 授权门槛 | a11y 服务需要用户手动开启，国内 ROM 还有"后台限制/自启动"要引导 |
| 工程期 | 骨架可跑（壳+WebView+runtime 起来）约数天；手机操控做到能用是周级；打磨到稳定是月级 |

---

## 5. 当前进度（2026-11-08）

- 独立仓库 `XRK-harness-mobile` 已建：上游 5690 文件基线、AGPL-3.0、`ATTRIBUTION.md` 标注 commit 与版本。
- 本机工具链：JDK 21、Android SDK（platform-tools / build-tools 35+36 / platforms 35+36）、Flutter 3.47.9（Dart 3.13.7）。
- 构建主机：我们的 AGT 服务器（16 核 / 15G / Node 26 / x86_64），已腾出 5G+ 空间。
- runtime 构建：`build-runtime.sh x86_64` 已跑通下载→验签→npm 树→补丁→jniLibs 修补，正在压缩 rootfs。
  期间解决 5 个环境问题：CRLF 行尾、`ca-certificates` 版本 404、python-build-standalone 的 GitHub 超时、
  termux proot pin 失效（5.1.107.98 → 5.1.107.102）、proot 源码 zip 预置缓存。
