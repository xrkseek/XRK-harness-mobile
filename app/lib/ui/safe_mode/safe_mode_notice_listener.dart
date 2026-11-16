import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../runtime/runtime_state.dart';

/// Shows the runtime's one-off notices ("已用安全模式启动", "已恢复正常模式") as snack
/// bars. Wrap the product shell (below the MaterialApp) with it once.
///
/// Uses a floating, long-lived bar so auto-entry after update / crash is
/// unmistakable on the dark LocalHostShell surface.
class SafeModeNoticeListener extends ConsumerWidget {
  const SafeModeNoticeListener({super.key, required this.child});

  final Widget child;

  static const _duration = Duration(seconds: 8);
  static const _bg = Color(0xFFF0B429);
  static const _fg = Color(0xFF1A1400);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<RuntimeNotice?>(localRuntimeProvider.select((s) => s.notice), (previous, next) {
      if (next == null || next.seq == previous?.seq) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              next.text,
              style: const TextStyle(color: _fg, fontWeight: FontWeight.w600, height: 1.35),
            ),
            backgroundColor: _bg,
            behavior: SnackBarBehavior.floating,
            duration: _duration,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          ),
        );
    });
    return child;
  }
}
