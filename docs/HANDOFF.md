# 交接计划：XRK-harness-mobile

> 给接手的人（明天由 Cursor 主攻）。这份文档的目标是：**看完就能开工，不需要再问人**。
> 最后更新：2026-11-08 · 所有"已验证"都实测过，"待验证"会明确标出。

---

## 0. 一页速览

### 目标
做一个 Android App，把 XRK Harness Host 直接跑在手机里（不依赖电脑），并让模型能操作手机本身。

### 结论（最重要的判断）
上游 `dsh-Go` 的价值**不在它的 UI**，而在 6 块工程。我们的策略是 **换壳留核**：

| 层 | 上游 dsh-Go | 我们的处理 |
|---|---|---|
| proot 运行时 | 把 Ubuntu + Node + 引擎塞进 APK | **沿用骨架**，引擎换 `@xrkseek/harness-cli` |
| Direct Engine | 绕过 proot 直跑 Node（性能模式） | **沿用**，先跑通 proot 再说 |
| 手机操控 | AccessibilityService 全套 | **沿用分层**，工具语义对齐我们 |
| 原生插件协议 | Kotlin ↔ Node 双向协议 v1.2 | **沿用**，a11y 工具走它注册 |
| 文件/媒体处理 | 权限最小化 + 竞态安全 | **抄模式**（9 条边界） |
| Remote 模式 | App 当纯客户端连远程 Host | **沿用**，可提前发布 |
| Flutter UI | 4200 文件重写的一套聊天 UI | **砍掉**，WebView 加载我们的 web UI |
| 引擎补丁 | 130+ 个针对 DSH 源码的 diff | **作废** |
| Dart API 客户端 | `dsh_client` 对接 DSH Web API | **重写** |

### 当前状态（2026-11-09）
- ✅ x86_64 runtime 构建成功，已拉回本地（`rootfs-x86_64.tar.xz` 160.44 MiB / 26762 文件 / ELF 审计 0 错）
- ✅ arm64-v8a runtime 构建成功（`build-arm.log` 末尾 `arm64-v8a done`），已拉回 `.tmp/runtime-out/arm64-v8a/`（`rootfs-arm64-v8a.tar.xz` 152.15 MiB / 26770 文件 / ELF 审计 0 错）
- ✅ 两份 manifest：`jniLibs.*.machine` = `x86-64` / `aarch64`；build-report `wrong-arch: 0`
- ⬜ 代码改造尚未开始；下一刀 M1 换引擎

### 接手第一件事
读 §9「差异清单」（我们 CLI 与 DSH 完全不同），再按 §10「里程碑」从 **M1** 开始（M0 已收口）。

---

## 1. 仓库与环境

### 1.1 仓库
```
本地路径：C:\Users\xrkseek\Desktop\主仓库\XRK-harness-mobile
git：已 init，master，0 commit（全部 untracked）
许可：AGPL-3.0（沿用上游）；来源与 commit 写在 ATTRIBUTION.md
上游基线：dsh-Go v1.0.13 / commit 2432cbdcc92f4a2ced6e8ffeba648af0f832eb98
```
已移除上游：`.github/`、`.agents/`（上游治理）。
保留：`app/`（Flutter + Android）、`android/`、`runtime/`、`packages/`、`services/`、`sdk/`、`market/`、`docs/`、`examples/`、`infra/`、`site/`、`tooling/`。

### 1.2 本机工具链（已验证）
| 项 | 值 |
|---|---|
| JDK | 21（Temurin） |
| Android SDK | `C:\Users\xrkseek\AppData\Local\Android\Sdk` |
| platforms | android-35、android-36 |
| build-tools | 35.0.0、36.0.0 |
| cmdline-tools | latest（licenses 全部接受） |
| Flutter | 3.47.9 / Dart 3.13.7，`C:\tools\flutter` |

`flutter doctor` 唯一红项是 Chrome，与项目无关；Web 调试时设 `CHROME_EXECUTABLE`。

### 1.3 构建主机（AGT）
```
103.236.89.174:46184（root）
密码：主仓库 XRK-harness/.agents/skills/xrk-desktop-update-feed/.agt-password
规格：16 核 / 15G / x86_64 / Ubuntu 24.04 / Node 26.8.1
工作目录：/root/xrk-mobile（仓库 runtime/ 的副本）
磁盘：29G 总量，剩 ~4G（紧张）
代理：socks5h://127.0.0.1:1080 可用；127.0.0.1:7890 不通
```
**铁律**：不设全局代理，只在单条命令内联 `https_proxy=http_proxy=socks5h://127.0.0.1:1080`。

构建命令（后台）：
```bash
cd /root/xrk-mobile && setsid nohup env RUNTIME_OUT=/root/xrk-mobile/out \
  https_proxy=socks5h://127.0.0.1:1080 http_proxy=socks5h://127.0.0.1:1080 \
  /bin/bash runtime/build-runtime.sh <x86_64|arm64-v8a> > /root/xrk-mobile/build.log 2>&1 < /dev/null &
```
轮询用 `tail + pgrep -fc build-runtime`。**paramiko 读超时经常误报，进程其实还活着，以日志为准。**

### 1.4 本地产物
```
XRK-harness-mobile/.tmp/runtime-out/x86_64/     ← 已拉回，162 MB
  assets/runtime/rootfs-x86_64.tar.xz            160.44 MiB
  assets/runtime/manifest.json                   1.2 KB（关键契约，见 §3.2）
  assets/runtime/licenses/*.txt
  jniLibs/x86_64/lib{proot,proot-loader,talloc,android-shmem}.so
  build-report.json                              324 KB（ELF 审计）
```
`.tmp/` 在 .gitignore 内，不提交。

---

## 2. 上游资产评估总表

接手时请按这张表决定"每块代码要不要留"。**不要全局替换 `dsh`**（仓库里 3 万+ 处，大多在 docs/examples/market 里）。

### S 级：对我们的产品有直接价值，要抄
| 模块 | 路径 | 一句话 |
|---|---|---|
| proot 运行时 | `runtime/build-runtime.sh`、`app/android/.../runtime/` | 把 Linux + Node 塞进 APK 的完整工程（§3） |
| Direct Engine | `runtime/direct/` | 绕过 proot 直跑 Node，性能模式（§4） |
| 手机操控 | `app/android/.../phone/` | 观察/动作/工具目录/任务四层（§5） |
| 原生插件协议 | `runtime/bridge/dsh-go-bridge/` | Kotlin ↔ Node 双向协议（§6） |
| 文件与媒体 | `app/android/.../files/`、`nativefiles/`、`media/`、`links/`、`nativemedia/` | 权限最小化 + 竞态安全（§7） |
| Remote 模式 | `app/lib/remote/` | App 当纯客户端连远程 Host（§8） |

### A 级：值得抄的实现细节
| 模块 | 亮点 |
|---|---|
| `nativemedia/MicArbiter` | 麦克风仲裁（语音输入/通话/播放抢麦排队） |
| `nativemedia/SpeechGate`、`VoiceCapture` | 语音闸门与采集 |
| `diagnostics/SystemIme*` | 输入法问题自动化取证（Evidence/Logcat/Prompt） |
| `islands/IslandWebViews` | 悬浮窗里跑 WebView |
| `icons/LauncherIconPlugin`、`PictureShortcutPlugin` | 运行时换图标 / 图片快捷方式 |
| `runtime/boot/boot-cache.mjs` | 冷启动缓存 |
| `sdk/plugin-kit` | 插件开发 SDK（工具卡/表单/面板 + check/preview CLI） |
| `market/` | 插件市场（静态扫描 + audit.json 证据 + 自动合并） |
| `services/share-worker` | Cloudflare Worker 对话分享页 |
| `files/*`（详见 §7） | 9 条边界，逐个可抄 |
| `runtime/media/dsh-media` | 5 家供应商的媒体生成插件，取消语义诚实 |
| `companion/recall-*` | 长期记忆召回引擎 |
| `update/`、`performance/`、`usage/` | 应用内自更新 / 性能 / 用量 |

### B 级：与我们无关，不要碰
`pets/`（桌宠）、`wallpaper/`、`forum/`、`l10n/`、`launch/`（启动屏主题）、`share_code/`。
碰它们只会拖慢主线。

---

## 3. 资产 A：proot 运行时

### 3.1 APK 结构
```
assets/runtime/rootfs-<abi>.tar.xz     整棵 Linux 根（Ubuntu + Node + 引擎 + 依赖）
assets/runtime/manifest.json           版本/sha256/启动模板（唯一契约）
assets/runtime/licenses/*.txt
jniLibs/<abi>/libproot.so              改名后的 proot（DYN，依赖 libtalloc.so / libandroid-shmem.so）
jniLibs/<abi>/libproot-loader.so       loader（EXEC）
jniLibs/<abi>/libtalloc.so             SONAME 改成 libtalloc.so
jniLibs/<abi>/libandroid-shmem.so      ashmem 兼容层
```

三个 Android 硬约束（上游已解决，照抄）：
1. Android 10+ 禁私有目录 exec → `targetSdk = 28`
2. 可执行必须来自 `nativeLibraryDir` → 改名 `lib*.so` + `useLegacyPackaging = true`
3. 体积 → 按 ABI 分 Gradle flavor

### 3.2 manifest：唯一契约（关键段）
```jsonc
"launch": {
  "argv": ["{NATIVE_LIB_DIR}/libproot.so", "--kill-on-exit", "--link2symlink", "--sysvipc",
           "-L", "-0", "--rootfs={ROOTFS}", "--cwd=/root",
           "-b","/dev","-b","/dev/urandom:/dev/random","-b","/proc","-b","/proc/self/fd:/dev/fd",
           "-b","/proc/self/fd/0:/dev/stdin","-b","/proc/self/fd/1:/dev/stdout","-b","/proc/self/fd/2:/dev/stderr",
           "-b","/sys","-b","{ROOTFS}/var/lib/dsh-app/empty:/sys/fs/selinux",
           "-b","{ROOTFS}/var/lib/dsh-app/shm:/dev/shm","-b","/system","-b","/apex",
           "/usr/bin/env","-i","HOME=/root",...,"DSH_HOME=/root/.dsh",...,"{GUEST_ENV}",
           "/bin/sh","-c","echo $$ > /tmp/dsh-web.pid; exec /usr/local/bin/dsh web --patch ... --host 127.0.0.1 --port {PORT} --no-open"],
  "env": { "PROOT_LOADER": "{NATIVE_LIB_DIR}/libproot-loader.so", "PROOT_TMP_DIR": "{TMP}",
           "PROOT_L2S_DIR": "{ROOTFS}/root/.l2s", "LD_LIBRARY_PATH": "{NATIVE_LIB_DIR}" },
  "stop": { "pidFile": "{ROOTFS}/tmp/dsh-web.pid",
            "graceful": "SIGTERM 到 pidFile 的 pid",
            "fallback": "SIGQUIT 到 proot（proot 忽略 SIGTERM/SIGINT/SIGHUP；destroy() 无效，destroyForcibly() 会让 node 变孤儿）" }
}
```
**不要写死路径**：Android 侧只做占位符替换 + `ProcessBuilder`。
`-b` 绑定清单别删（`/sys/fs/selinux`、`/dev/shm` 落空目录是必要技巧）；`PROOT_L2S_DIR` 必须存在。

### 3.3 安装/启动（Kotlin 侧要保留）
`runtime/RuntimeInstaller.kt`：
- `rootfs/`（活动根）+ `staging/`（解压中），**解压完原子切换**，失败不毁上一份
- 解压前按 `manifest.rootfsSha256` 校验；`.xz` 用流式 `TarExtractor`，回调 `(已读, 总量)` 给进度条
- `installedVersion()` / `isCurrent()` 判重装

`runtime/DshProcess` + `DshService`（前台服务）+ `RuntimePlugin`（`MethodChannel dsh/runtime`：getStatus/install/start/stop/getLogs/getLogSnapshot/reset；`EventChannel` 推 progress/status/logs，日志 ~100ms 一批、带自增 `seq`，先订阅再取快照、只接 `seq > throughSeq`，不重叠不漏行）。

> 具体行号接手时用 Find in Files 定位方法名即可。

---

## 4. 资产 B：Direct Engine（性能模式）

**原理**：proot 每次 syscall 都要翻译，Host 是 I/O 密集型（sqlite / 文件 / HTTP），开销可感。Direct Engine 让 Node **直接跑在 Android 上**，用一个 `--require` 预加载脚本来伪装 Linux 环境。

`runtime/direct/` 四个 seam：

| 文件 | 职责 |
|---|---|
| `paths.mjs` | Linux 路径（`/usr/…`、`/opt/…`）→ rootfs 物理路径 |
| `dns.mjs` + `proot-dns.mjs` | DNS：Android 没有 `/etc/resolv.conf`，走系统 resolver |
| `processes.mjs` | 拦截子进程：exec rootfs 里的 ELF 时自己拉起 |
| `modules.mjs` | 模块解析 / `.node` native addon 加载 |

`preload.mjs` 头注释要点：
- **versioned runtime-owned preload**：配置只含 paths/argv，**凭据与调用方环境永远不写进去**
- `config.schema !== 2 || config.rootfs !== rootfs` → 直接拒绝（防止配置与 rootfs 不匹配）

**安全闸（compatibilityGate）**：检测 `rootfs/root/.l2s`（proot 的 fake hard link 目录）非空 → 拒绝 direct、回退 proot。原因：那套文件语义只有 proot 能解释。
manifest 里：`directEngine.safeMode = "proot"`、`pnpmPackageImportMethod = "copy"`。

**对我们的用法**：M0-M3 阶段**先不管它**。等 proot 跑通、Host 稳定后，再开 direct 做性能对比。它的价值在"给用户一个卡的时候能切的开关"。

---

## 5. 资产 C：手机操控（Android 版 computer_use）

`app/android/app/src/main/kotlin/io/github/ccch1mneyyy/dsh_app/phone/`，三层。

### 5.1 观察（`phone/a11y/`）
- `PhoneA11yService`：`typeWindowStateChanged|typeWindowContentChanged|typeWindowsChanged|typeViewTextChanged`，`canRetrieveWindowContent=true`，`canPerformGestures=true`
- `ScreenObservation` → `ScreenFormat` → `ScreenDigest`：节点树 → **带编号文本行**（`[12] 按钮 发送`），并做 previous/current **差分摘要**
- `ScreenMask` 遮罩敏感信息；`ScreenShooter` 截图兜底
- 屏幕寻址 `SCREEN_ID`：`s7` 主屏 / `b3` 后台屏

### 5.2 动作（`phone/background/`）
- `PrivilegedTreeAccess` / `TreeTransactions`：直接 `ACTION_CLICK` / `ACTION_SET_TEXT` / 滚动，**不注入坐标**（不抢用户、不受分辨率影响）
- `PrivilegedActionGate`：权限门 + 风险分级
- `InputProbe`：输入通道取证
- 兜底才用 `tap_xy`

### 5.3 工具目录（`PhoneToolCatalog.kt`，14 个）
```
apps  open  intent  notify  clipboard  screen  collect
tap   type  scroll  key     tap_xy     handoff
```
+ 系统开关：`home / wifi / bluetooth / mobile_network / airplane / display / sound / battery / location / date / language / storage / nfc / app_notifications`

设计取舍：**窄接口**（看屏 / 收候选 / 按编号点 / 交还控制权），不是把 Android API 全暴露。

### 5.4 任务与沉淀
- `PhoneTaskDriver / PhoneTasks / PhoneTaskJournal / PhoneTaskReturn`：observe → act → verify，带日志、重试、回退
- `phone/skills/`：`PhoneSkillBridge / PhoneSkillDrafts / PhoneSkillLifecycle`——跑通的任务沉淀成 skill
- `PhoneSelfCheck` + `PhoneSelfCheckTargetActivity`：授权自检

---

## 6. 资产 D：原生插件协议 + 记忆召回

### 6.1 协议（`runtime/bridge/dsh-go-bridge/`）
package.json 原文：
> native plugin protocol v1 (`dshGo` service, `contributions`, `views`, `stream`, `invoke`; v1.2 capabilities: `media`, `micro`, `capability events`), and a route guard on hosts whose webserver is not patched.

`lib/`：`client.js`、`config-source.js`、`index.js`、`plugin-config.js`、`session-deletion.js`。

**为什么重要**：这是我们 a11y 工具注册进 Host 的正确入口。不要自己另发明一层 Kotlin ↔ Node 协议。
代价：`route guard` 依赖 DSH web server 的补丁，换引擎后要重写（但协议骨架可留）。

### 6.2 记忆召回（`lib/companion/`）
`full-context.js` / `recall-context.js` / `recall-engine.js` / `recall-markers.js`
——长期记忆的上下文组织、召回、标记。值得单独研究（我们的 curated memory 是另一套思路，可以对照）。

### 6.3 媒体插件（`runtime/media/dsh-media`）
5 家供应商：OpenAI（GPT Image）、Gemini（Flash Image）、火山方舟（Seedream/Seedance）、阿里百炼（Wan）、硅基流动（Qwen Image / Wan T2V-I2V）。
最值得抄的是**取消语义的诚实处理**：
> 停止本地等待不等于供应商停止计费；仅 queued/PENDING 才真正 DELETE，然后**回查确认**。

我们的 `image_generate` / `video_generate` 目前没有这层。

---

## 7. 资产 E：文件与媒体（9 条边界）

这块的价值不在功能，在**边界**。逐条都可以直接抄。

### 7.1 上传（选文件给 Agent）
| # | 边界 | 出处 |
|---|---|---|
| 1 | **只用系统选择器**：不开存储权限、不写、不持久 URI 授权、**不复制到缓存**（流式 `InputStream`） | `nativefiles/NativeFilesPlugin.kt` 类注释 |
| 2 | **自己定体积规则**，不信任 provider 的 `SIZE` 列：普通 ≤4 文件 / 单个 8 MB / 总 16 MB；`own` 模式 ≤30 MB 且插件拿不到 | `nativefiles/SelectedFileBudget.kt` |
| 3 | **权限请求串行化**：多个保存共享一次系统权限框；`retire()` 让晚期 worker 失效 | `media/MediaPermissionQueue.kt` |

### 7.2 打开（"以什么方式打开"）
| # | 边界 | 出处 |
|---|---|---|
| 4 | `open {path,mime,name,chooser}` → **ACTION_VIEW 走自己的 FileProvider**；错误码区分 `no_app` / `missing` / `permission` / `failed` | `files/FilesPlugin.kt` L39 |
| 5 | 存 Downloads 用 **`IS_PENDING` 两段式**（占位→写完发布），别的 App 看不到半截文件；**回查 MediaStore 拿真实文件名**再回显 | 同上 L245-261 |
| 6 | PDF **内置预览**（`PdfRenderer` 单线程、一次一个文档、按宽度渲染白底 PNG） | `files/PdfPages.kt` |
| 7 | 重名冲突用 **`CREATE_NEW` 独占**，不做 delete/reopen（并发安全） | `files/LegacyDownloads.kt` |

### 7.3 被别的 App 打开
| # | 边界 | 出处 |
|---|---|---|
| 8 | **LinkTrampolineActivity**：intent filter 不放 MainActivity。微信这类会在自己 task 里起 VIEW，不带 `NEW_TASK`，指向 MainActivity 会**造第二个 Flutter activity**。转发带 `NEW_TASK|SINGLE_TOP|CLEAR_TOP`，`onNewIntent` 送达；`content:` 读权限随 intent 传 | `links/LinkTrampolineActivity.kt` |
| 9 | 用 **method call 而非 EventChannel**：Dart 可 probe `ready`，把"原生不存在"（widget test / desktop）当"没有链接"而不报错 | `links/LinksPlugin.kt` |

### 7.4 附加（播放与路径）
- `nativemedia/ClipPath.kt`：白名单精确到 `<cache>/native-media/<owner>/clip`，真实文件 1B–16MiB，**绝不接受 URL / content URI / 其他路径**
- `nativemedia/ClipPlayer.kt`：一次一个 clip + **generation 号保护回调**（stop 后已排队的 onPrepared 不能再出声）+ 音频焦点 transient（别人 duck、失焦即结束）
- `links/LinkCopySlots.kt`：槽位创建与登记共锁，不会出现"未保护新槽位"；Provider I/O 放锁外
- `files/GuestFiles.kt`：guest 路径 → Android 物理路径；`--link2symlink` 的 **host-absolute 目标要在 guest 世界 rebase** 后再跟随，`MAX_LINKS=16` 防循环

**映射到我们**：手机选文件传给 Host → #1/#2；Host 产出文件给用户 → #4/#5；微信点链接进 App → #8；浏览 proot 内文件 → `GuestFiles`。

---

## 8. 资产 F：Remote 模式

`app/lib/remote/`。README 原文："远程连接：通过 SSH 或 DSHarness Remote 使用电脑、服务器上的 DSH。"

模式：**App 不跑本机引擎**，只做客户端连远程 Host。

**对我们的价值（高）**：本机 runtime 还没稳之前，用户可以先连自己电脑/服务器的 XRK Host。这意味着我们可以**先发一个"远程客户端"版本**，不必等整机 proot 全通。建议列为 M2 的备选交付形态。

---

## 9. 差异清单：DSH vs XRK（**最容易踩错**）

| 项 | 上游 dsh-Go | 我们 `@xrkseek/harness-cli` 0.7.15 |
|---|---|---|
| 启动命令 | `dsh web --patch … --host 127.0.0.1 --port 3080 --no-open` | `xrkh serve --host 127.0.0.1 --port 8787`（`web` 是别名） |
| 默认端口 | 3080 | **8787** |
| 启动输出 | `dsh web: http://127.0.0.1:3080/?token=<43 chars>`（仅一次） | `xrkh serve  http://127.0.0.1:8787/` + `workspace=`/`preset=`/`ui=`/`sessions=` 行 |
| 认证 | token URL → 303 + `Set-Cookie dsh-auth-<id>`，WebView 必须带 cookie | **loopback 无认证**，直接访问；只有 `--host 0.0.0.0` 才启用 PIN gate / `XRK_API_KEY` |
| 健康检查 | 无 cookie 401 / 有 cookie 200 | TCP 可连 + `GET /` 200 |
| 家目录 | `DSH_HOME=/root/.dsh` | `XRK_HOME=/root/.xrk` |
| 二进制 | `/usr/local/bin/dsh` | `/usr/local/bin/xrkh`（别名 `xr-harness`） |
| 引擎补丁 | `runtime/patches/*.diff`（130+，pin 在 `pins.json`） | **不适用** |
| bridge 插件 | `/opt/dsh-go/dsh-go-bridge`（把 a11y 注册成 DSH 插件） | 需重写为 XRK 工具注册 |
| Web UI | DSH 自带前端 | `apps/web/dist`（已移动适配：viewport / manifest / `pointer: coarse`） |

**三条结论**：
1. **token 机制整段砍掉**——loopback 不需要。壳只等端口就绪然后加载 `http://127.0.0.1:8787/`。
2. **不要用 stdout 正则判就绪**（我们的启动行是日志级输出，格式可能变），用 TCP + `GET /` 探活。
3. **停止逻辑照抄两段式**（pid SIGTERM → proot SIGQUIT），我们 Host 用 pid 文件或 host-lock。

---

## 10. 里程碑计划

每个里程碑都有**可验证的 Done**。估时只给量级，仅供参考。

### M0 · 打通 runtime（✅ 2026-11-09 完成）
**目标**：arm64-v8a 出一份完整产物，证明两个 ABI 都能建。
- [x] `build-arm.log` 末尾出现 `arm64-v8a done`
- [x] 产物拉回 `.tmp/runtime-out/arm64-v8a/`
- [x] 两份 manifest 的 `jniLibs.*.machine` 分别 = `aarch64` / `x86-64`，`wrong-arch: 0`
- [x] 本地仓库首次提交（只提基础设施：`.gitignore` / `ATTRIBUTION.md` / `docs/`）

**验收**：AGT `/root/xrk-mobile/out/<abi>/` 与本地 `.tmp/runtime-out/<abi>/` 两套齐全，`build-report.json` warnings 空、ELF wrong-arch 0。
**备注**：磁盘仍紧（AGT `/` 约 3.2G 可用）；`.work/` 已不在（总占用约 2.1G）。

### M1 · 换引擎（核心）
**目标**：rootfs 里跑的是我们的 Host，不是 DSH。
- [ ] `install_dsh()` → `install_engine()`：`npm install --os=linux --cpu=<x64|arm64> --save-exact @xrkseek/harness-cli@0.7.15`
- [ ] 删除 `patching DSH` 段与 `dsh-go-bridge` 安装段
- [ ] `/opt/dsh-go/` → `/opt/xrk-harness/`；`/usr/local/bin/dsh` → `xrkh`
- [ ] manifest：`dshVersion`→`engineVersion`、删 `dshPatches`、删 `tokenLine`、`DSH_HOME`→`XRK_HOME`
- [ ] `launch.argv` 末尾改 `exec /usr/local/bin/xrkh serve --host 127.0.0.1 --port {PORT}`

**验收**：服务器上 `runtime/test-host.sh` 能在 proot 里起 Host，`curl 127.0.0.1:8787` 返回 200。
**前置风险（最高）**：native 模块（`node-pty` / `better-sqlite3` / `sharp`）的 `linux-arm64` 预编译是否齐全。**这一项要在 M1 一开始就验证**，不齐就得换纯 JS 实现或自己编。

### M2 · 换壳
**目标**：App 能打开、能加载我们的 UI。
- [ ] `app/lib/main.dart` → 单页 WebView（建议 `flutter_inappwebview`）
- [ ] 启动流程：起 runtime → 等 `127.0.0.1:{port}` 就绪 → `loadUrl`
- [ ] `android:usesCleartextTraffic="true"`（或 network-security-config 允许 loopback 明文）
- [ ] 保留 `launch/LaunchScreen.kt`（原生启动页，质量不错）
- [ ] 备选交付：若本机 runtime 不顺，先发 **Remote 模式**版本（连电脑/服务器 Host）

**验收**：真机装上 → 打开 → 看到我们的聊天界面 → 能发一句话得到回复。
**风险**：WebView 与 Host 的 WS/Cookie 兼容；移动端键盘遮挡输入框。

### M3 · 原生层改名与 a11y 对接
- [ ] 包名 `io.github.ccch1mneyyy.dsh_app` → `com.xrkseek.harness`
- [ ] `MethodChannel dsh/runtime` → `xrk/runtime`；`DshProcess`/`DshService` → `HostProcess`/`HostService`
- [ ] a11y 工具经原生插件协议注册进 Host（§6.1），工具语义对齐桌面 `computer_use` 命名
- [ ] 手机 preset 关闭桌面 `computer_use`（Windows UIA），替换为 a11y 工具集

**验收**：模型能通过工具完成"打开微信→给某人发一条消息"这类多步任务，且 `PhoneSelfCheck` 全绿。
**风险**：国内 ROM 的自启动/后台限制；a11y 需要用户手动开启，引导要做。

### M4 · 打包与发布
- [ ] 按 ABI 分 flavor 打包，`targetSdk=28`，`minSdk=24`
- [ ] 体积评估（预计 150–250 MB / ABI）
- [ ] 签名与更新通道

---

## 11. 风险登记

| 级别 | 风险 | 应对 |
|---|---|---|
| 🔴 高 | native 模块无 `linux-arm64` 预编译 | M1 第一步就验证；不行则换实现或自编 |
| 🔴 高 | 磁盘只有 4G | 清 `.work/`、只留最新两版桌面包 |
| 🟡 中 | `targetSdk=28` 长期不可上架 Play | 自发行无碍；要上架需另做 exec 方案 |
| 🟡 中 | APK 体积 150–250MB | 可分 ABI 分发；或首启动下载 rootfs（放弃离线开箱） |
| 🟡 中 | a11y 授权门槛（国内 ROM） | 做分步引导 + `PhoneSelfCheck` |
| 🟢 低 | 我们 CLI 的 token 机制差异 | 已确认可整段砍掉（§9） |

---

## 12. 踩过的坑（别重踩）

| # | 坑 | 现象 | 解法 |
|---|---|---|---|
| 1 | 脚本 CRLF | `bash: $'\r': command not found` | `find . -name '*.sh' -exec sed -i 's/\r$//' {} +` |
| 2 | Ubuntu deb 版本漂移 | `ca-certificates_…` 404 | `UPDATE_DEB_LOCK=1`，或删 `runtime/locks/ubuntu-noble-<arch>.json` |
| 3 | python-build-standalone 走 GitHub | 超时 | 脚本 `PBS_OFFICIAL`（约 L65）改 npmmirror |
| 4 | termux proot pin 失效 | `5.1.107.98` 不存在 | 升 `5.1.107.102`，**三处 sha256 同步** |
| 5 | proot 源码 zip 要 GitHub | 超时 | 预置 `runtime/.cache/termux/proot-v5.1.107.102.zip` |
| 6 | **ABI 名写错** | `unknown ABI aarch64 (use arm64-v8a or x86_64)` | 必须 `arm64-v8a` / `x86_64` |
| 7 | 磁盘 | 29G 满 | 只清自己建的：`/root/xrk-release`、`/root/xrk-npm`、旧桌面 exe、3 天前日志 |
| 8 | 代理 | GitHub/npm 超时 | 单条命令内联 `socks5h://127.0.0.1:1080`，**不设全局** |
| 9 | SFTP 路径 | python `expandvars("%CD%")` 不展开 | 用绝对路径或 `os.getcwd()` |
| 10 | paramiko 读超时 | 报异常但构建在跑 | 以 `pgrep` + 日志为准，别重跑（会撞锁） |

`.tmp/` 不提交。git 目前 0 commit，首次提交只提基础设施，不要一把全提。

---

## 13. 待决策

1. **包名 / 应用名**：`com.xrkseek.harness`？中文名？
2. **签名**：自签还是复用桌面端签名体系？
3. **是否保留 Flutter 薄壳**：建议保留（复用 RuntimePlugin/启动页/媒体插件），只换 UI。
4. **体积红线**：150–250 MB / ABI 能接受吗？不能的话要不要做"首启动下载 rootfs"？
5. **Direct Engine 什么时候做**：建议 M4 之后，作为性能开关。
6. **Remote 模式是否先发**：建议作为 M2 的备选交付形态（不等本机 runtime 全通）。

---

## 14. 参考

- 上游：dsh-Go v1.0.13 / `2432cbdcc92f4a2ced6e8ffeba648af0f832eb98`（见 `ATTRIBUTION.md`）
- 本轮技术分析：`docs/report-proot-and-phone-control.md`
- 本地 runtime 产物与 manifest 全文：`.tmp/runtime-out/x86_64/`
- 我们 CLI 启动实现：主仓库 `apps/cli/src/commands/serve.ts`（L160-240 是启动输出）、`apps/cli/src/parse-args.ts`
