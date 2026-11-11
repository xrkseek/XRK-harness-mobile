# 参与贡献

[English](CONTRIBUTING.en.md) · [项目首页](README.md)

## 欢迎 Pull Request

本仓库**欢迎外部 Pull Request**（代码、文档、测试、插件示例均可）。

- 功能建议、改进想法或问题反馈：可先[开 Issue](https://github.com/xrkseek/XRK-harness-mobile/issues/new/choose)，写清使用场景和期望行为；也可直接开 PR。
- 影响协议、数据格式、权限或手机操控安全边界的较大改动，建议先开 Issue 对齐方案。
- 安全问题请按 [SECURITY.md](SECURITY.md) 私密报告，不要开公开 Issue / PR 贴利用细节。

## 许可证与版权

- 本仓库自有代码默认 [AGPL-3.0](LICENSE)。`sdk/`、`examples/` 另见其目录内说明（MIT）。
- 产品名与标识为 **XRK Harness**（包名 `com.xrkseek.harness`）。当前 App 首发 / 现行版本 **0.7.16**。
- 第三方代码与随包组件见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。界面图标与字体以 Notices「素材」一节为准（Phosphor、Material、JetBrains Mono 等）。
- **不把 DeepSeek / 前身品牌的官方美术立绘当作本产品资产或版权主张**。可选桌宠主题包（如 `deepy-whale`）是独立粉丝主题，见包内 README；与产品标识无关，也不是上游官方素材授权。
- 新增或移植第三方内容时：写明项目、版本或提交、源文件与许可证，保留必要署名与修改说明，并确认与目标目录许可兼容。

## 提交问题

使用仓库的 Bug 或功能建议模板。说明 App 版本、Android 版本、主机连接方式，以及可重复的最小步骤。界面问题附截图或短视频；提交前遮盖隐私。

## 准备开发环境

按 [README](README.md) 完成工具链与运行时准备。普通 App 开发不需要维护者的签名密钥、内测通道令牌或生产部署凭据。

- Flutter/Dart：使用仓库对应的 Flutter 版本和 App 的 Dart SDK 要求。
- Android：JDK 17，运行时 ABI 与 APK flavor 匹配。
- 插件 SDK：Node.js 22.19 或更新版本。SDK 在 `sdk/plugin-kit/` 内使用，尚未发布到 npm。

## 修改范围

一个 PR 解决一个可单独审阅的问题。说明原来的行为、触发条件和改后的行为；避免夹带无关重命名、格式化和目录调整。

- UI 文案按现有中英文结构维护，优先使用项目已有组件和图标。
- 对行为改动补充能覆盖问题的测试；仅改文字或布局时，给出检查或截图即可。
- 修改客户端、桥接或插件协议时，同时检查兼容性和另一端的调用方。
- 不手工编辑生成文件；修改源文件并运行对应生成器。

## 常用检查

从仓库根目录运行。按改动范围选择；在 PR 中写明实际执行的命令和结果。缺设备 / 依赖时写明「未运行」和原因。

若仓库配置了 CI，以 Actions 结果为准；CI 通常不碰真机和真实账号，真机路径仍需单独验证。

**Flutter 应用：**

```bash
(cd app && flutter pub get && flutter analyze && flutter test)
```

**真机调界面（热重载）：** `tooling/dev-run.sh` 把 debug 包覆盖安装到手机上已有的 release 版，再挂上 Flutter，按 `r` 几秒内生效。它用 `adb install -r` 加 `flutter attach`，不用 `flutter run`（后者安装失败时会先卸载并清掉数据）。debug 模式动画偏卡，只用来看布局；流畅度请打 release。需要 `app/android/key.properties` 与手机上的包同一把 key。

**Dart 通信包：**

```bash
(cd packages/xrk_client && dart pub get && dart analyze && dart test)
(cd packages/xrk_remote && dart pub get && dart analyze && dart test)
```

**插件 SDK：**

```bash
(cd sdk/plugin-kit && npm install && npm test)
```

SDK 类型检查需要开发依赖 TypeScript；未安装时相应测试会跳过——勿把跳过写成通过。生成器与同步顺序见 [SDK 维护说明](sdk/plugin-kit/README.md)。

**界面文案：** 修改 `app/lib/l10n/parts/` 的中英文 ARB，再生成并检查：

```bash
python3 app/tool/l10n_merge.py
python3 app/tool/l10n_merge.py --check
```

**用户指南：** 修改 `docs/guide/`，同步 App 内置的教学技能：

```bash
python3 app/tool/guide_sync.py
python3 app/tool/guide_sync.py --check
```

**插件教学技能：** 修改 `sdk/plugin-kit/skill/` 或 SDK 对应输入，再同步：

```bash
node sdk/plugin-kit/scripts/sync-skill.mjs
node sdk/plugin-kit/scripts/sync-skill.mjs --check
```

需要 APK 验证时，使用 README 中的构建入口。涉及 Android 进程、PRoot、直接启动、手机操控或更新安装的改动，应说明测试的 ABI、Android 版本、启动方式和设备；桌面测试不能替代真机。

`services/` 和 `infra/` 的线上检查、部署和发布脚本不属于普通贡献检查。修改配套服务时，只测自己的本地环境；不要用生产凭据。

## 提交 PR

填写默认 PR 模板（中文或英文均可）：

1. 问题是什么，为什么需要改，以及改后的行为。
2. 关联 Issue、主要受影响模块与兼容性影响。
3. 实际运行的检查、结果和未验证范围。
4. UI 改动的前后截图或录屏；使用测试数据，遮盖个人内容。
5. 新引入内容的来源、许可证和必须同步的声明。

提交前检查差异，排除密钥、个人配置、真实对话、设备序列号、构建缓存与私有运维资料。诊断包和日志也需要人工检查。

评论请围绕问题、证据和实现。使用 AI 辅助的改动也需由提交者读懂、验证并承担维护责任。
