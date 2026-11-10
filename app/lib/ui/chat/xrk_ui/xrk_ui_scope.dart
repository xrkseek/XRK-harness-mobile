import 'package:flutter/widgets.dart';

import 'xrk_ui_reply.dart';

/// 发一条用户消息；送不出去时返回 false（视图恢复成可点）。
typedef XrkUiSend = Future<bool> Function(String text);

/// 一条助手消息里的视图要的上下文。`MarkdownBody` 的 `codeBuilder` 必须是
/// 静态 tear-off（gpt_markdown 按身份比较配置），所以交互需要的东西由
/// `AssistantMessage` 外面包的这一层提供，`XrkUiBlock` 从 context 里读。
///
/// 没有它时视图只读展示（例如在别的页面里预览一段 Markdown）。
class XrkUiScope extends InheritedWidget {
  const XrkUiScope({
    super.key,
    required this.sessionId,
    required this.messageId,
    required this.state,
    this.onReply,
    this.onAskResend,
    required super.child,
  });

  final String sessionId;

  /// 这条助手消息的 id（`AssistantChatItem.id`）。
  final String messageId;

  /// 由 `xrkUiStateFor` 从消息顺序推出来的交互状态。
  final XrkUiState state;

  /// 用户点了选项 / 确认：发出 `[dsh-ui reply]` 消息（`ChatController.send`）。
  final XrkUiSend? onReply;

  /// 视图格式有误时「让它重发」：发出一条说明错误的消息。
  final XrkUiSend? onAskResend;

  static XrkUiScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<XrkUiScope>();

  @override
  bool updateShouldNotify(XrkUiScope old) =>
      old.sessionId != sessionId ||
      old.messageId != messageId ||
      old.state != state ||
      old.onReply != onReply ||
      old.onAskResend != onAskResend;
}
