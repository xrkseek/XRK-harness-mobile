# 示例插件

[English](#english)

| 插件 | 展示 | 要桥接 |
|---|---|---|
| [`xrk-example-weather`](xrk-example-weather/) | 工具卡：工具结果画成原生天气卡（`presentationMeta`） | 不要，任何主机 |
| [`xrk-example-usage`](xrk-example-usage/) | 状态条 + 面板 + 实时推数据：本对话 / 今日 token 用量 | 要 |
| [`xrk-example-quick`](xrk-example-quick/) | 胶囊（静态效果、调用）+ 消息菜单 + 延后效果（用默认模型翻译剪贴板） | 要 |
| [`xrk-example-readaloud`](xrk-example-readaloud/) | v1.2 能力：朗读一条回复、开口即停、每秒 10 次的字幕、悬浮字幕 | 要 |
| [`xrk-example-styles`](xrk-example-styles/) | 视图 v2：语义文字、富文本、可读颜色、卡片与比例列，保留 v1 文字回退 | 要 |
| [`xrk-example-album`](xrk-example-album/) | 聊天页「插件」弹层：图集、空状态、环形进度、趋势线，跟随 App 主题色 | 要 |
| [`xrk-example-toolbox`](xrk-example-toolbox/) | 较新的位置：加号面板工具、对话操作、回合尾注、插件详情页面板、弹层面板 | 要 |

安装：`dsh plugin --profile web add /绝对路径/<插件目录>`。端到端：`e2e/host-e2e.sh`（真 XRK + 桥接，按用户的方式安装三个示例）。MIT © XRK-TUI (xrkseek)。

## English

| Plugin | Shows | Needs the bridge |
|---|---|---|
| [`xrk-example-weather`](xrk-example-weather/) | A tool card: a tool result drawn as a native weather card (`presentationMeta`) | No, any host |
| [`xrk-example-usage`](xrk-example-usage/) | Status strip + panel + live data: tokens of this chat / today | Yes |
| [`xrk-example-quick`](xrk-example-quick/) | Capsules (static and invoked) + reply menu + a deferred result (clipboard translated by the default model) | Yes |
| [`xrk-example-readaloud`](xrk-example-readaloud/) | v1.2 capabilities: read a reply aloud, stop on speech, a 10-per-second caption, a floating caption | Yes |
| [`xrk-example-styles`](xrk-example-styles/) | View v2: semantic text, spans, readable colours, cards and proportional columns with v1 text fallbacks | Yes |
| [`xrk-example-album`](xrk-example-album/) | The chat page's Plugins sheet: a gallery, an empty state, a ring and a trend, in the app's palette | Yes |
| [`xrk-example-toolbox`](xrk-example-toolbox/) | Newer places: plus panel tools, chat actions, turn notes, a panel on the plugin page, a panel as a sheet | Yes |

Install: `dsh plugin --profile web add /absolute/path/to/<plugin>`. End to end: `e2e/host-e2e.sh` (real XRK + bridge, installs the three the way a person does). MIT © XRK-TUI (xrkseek).
