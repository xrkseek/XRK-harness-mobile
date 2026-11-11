/// 可交互回复（xrk-ui）：模型在回复里写 ```` ```xrk-ui ```` 围栏，里面是一份
/// JSON 蓝图，App 用原生组件画出来（旧会话里的 ```` ```dsh-ui ```` 仍认）。
///
/// 接入点：
/// - `MarkdownBody._codeBuilder`：语言是 `xrk-ui` / `dsh-ui` 时返回 [XrkUiBlock]；
/// - `MarkdownBody.repairBareViews`：模型忘了写围栏时，裸 JSON 也按视图画
///   （[fenceBareXrkUiViews] 补围栏）；
/// - `AssistantMessage` 外面包 [XrkUiScope]（状态用 [xrkUiStateFor] 推）；
/// - 用户气泡：[parseXrkUiReply] 认出回复，画 [XrkUiReply.chipLabel]；
/// - 复制 / 分享 / 导出：[xrkUiPlainText] 把块换成一行摘要。
library;

export 'xrk_ui_block.dart' show XrkUiBlock, XrkUiFallback, xrkUiReplyChip;
export 'xrk_ui_model.dart';
export 'xrk_ui_reply.dart';
export 'xrk_ui_reply_chip.dart';
export 'xrk_ui_scope.dart';
export 'xrk_ui_skeleton.dart' show XrkUiSkeleton, guessXrkUiShape;
export 'xrk_ui_widgets.dart' show XrkUiCard;
