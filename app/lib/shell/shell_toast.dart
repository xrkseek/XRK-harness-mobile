// Shell-only toast / guide notices. Separate from Host Web SnackBars and from
// the native chat composer toast — the thin LocalHostShell owns these.

import 'package:flutter/material.dart';

import '../ui/common/brief_notice.dart';

/// Floating toast above the gesture bar / IME, with optional action
/// (「去开启」→ native PhoneControl / a11y).
void showShellToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final bottom = MediaQuery.paddingOf(context).bottom;
  final margin = EdgeInsets.fromLTRB(16, 0, 16, bottom + 16);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      actionLabel == null || onAction == null
          ? briefNoticeBar(message, margin: margin)
          : SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
              margin: margin,
              duration: duration ?? const Duration(seconds: 6),
              persist: false,
              action: SnackBarAction(label: actionLabel, onPressed: onAction),
            ),
    );
}
