---
# xrk-mobile:managed — the xrk-mobile app keeps this skill up to date; delete this line to keep your own edits.
name: xrk-guide
description: >-
  xrk-mobile 手机壳使用说明（中文 / English）：手机操控开关与无障碍、本机引擎、外观与启动画面、检查更新。用户问「悬浮条透明度」「无障碍怎么开」「引擎怎么重置」「启动画面」时先加载它。
  对话 / 模型 / Agent Team / 会话设置在 guest Web（xrkh）里，不在本 skill。
  用 phone_* 操作手机 → 产品种子 skill **xrk-phone**（不是本 skill）。
  The phone App shell guide — phone control, engine, appearance, updates. Guest Web owns chat/models/team. phone_* playbook is skill xrk-phone.
whenToUse: >-
  The user asks how to use the xrk-mobile App shell (phone control page, engine,
  appearance, update). Not for phone_* tool steps (xrk-phone), layout edits
  (xrk-ui), or writing a plugin (xrk-plugin).
---

# xrk-mobile 使用说明

说明文件都在本技能目录里：`README.md`、`zh/`、`en/`，按需读取。

1. 先读 `README.md`：适用版本和每页的内容。再只读和问题相关的一两页：用户说中文读 `zh/`，其他语言读 `en/`，用用户的语言回答。
2. **壳 vs guest：** 手机操控 / 引擎 / 外观 / 更新 → 本 skill。对话、模型、干员、会话权限 → 告诉用户在 guest 网页壳（本地引擎 WebView）的设置里改，不要用已删除的原生页顶替。
3. **操作手机（点按、开应用）** → `skill` 加载 **`xrk-phone`**，再用 `phone_*`；本 skill 只讲 App 设置入口。
4. 只照说明回答。入口路径和按钮名照页面原文写；说明里没有的，直说说明里没有写到，不猜、不编。
5. 先给结论，再给入口和步骤，越短越好。
6. 入口行后面带 `xrkharness://open/…` 链接的，回答里原样附上；只用说明里出现过的链接。
7. 涉及删除、重置、卸载、授予权限、放宽确认的，先讲清后果。
8. 只读不改：不替用户改设置、不执行命令、不操作手机。用户让你直接改，告诉他在哪里改。
