# 来源与许可

本项目（XRK Harness Mobile）以 [dsh-Go](https://github.com/ccch1mneyyy/dsh-Go) 的完整代码为
**技术基线**，在此基础上改造成 XRK Harness 的手机端。

**这不是 GitHub fork**：本仓库是独立仓库、独立历史，不向上游回推 PR / issue，也不参与上游的
协作流程。上游维护者不会因为本项目收到任何通知或负担。

## 借用基线

| 项 | 值 |
|---|---|
| 上游仓库 | https://github.com/ccch1mneyyy/dsh-Go |
| 上游 commit | `2432cbdcc92f4a2ced6e8ffeba648af0f832eb98` |
| 上游版本 | `1.0.13`（`app/pubspec.yaml`） |
| 基线日期 | 2026-11-08 |
| 上游许可 | AGPL-3.0 |

## 许可

本项目随上游采用 **AGPL-3.0-or-later**，全文见 `LICENSE`。

- 从上游直接复用/改写的代码，保留其原始版权与许可声明。
- 上游的 `THIRD_PARTY_NOTICES.md` 一并保留。
- 我们新增的代码同样以 AGPL-3.0-or-later 发布。

## 我们的改造清单（随进度更新）

- 品牌与包名：`dsh` / `DeepSeek Harness` → XRK Harness（进行中）
- 运行时（`runtime/`）：proot 内的 Node 版本与安装包替换为 XRK Harness CLI（进行中）
- 仓库治理：移除上游 CI、issue 模板、agent 资产，本仓库自建
- 连接协议：由 DSH Web API 适配到 XRK Host 的 HTTP/WebSocket 接口（进行中）
