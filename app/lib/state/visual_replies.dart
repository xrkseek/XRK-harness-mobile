import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_bridge.dart' show RuntimePhase;
import '../runtime/runtime_state.dart';
import 'engine_control.dart';
import 'settings_state.dart';

/// Cascade for Settings →「可视化回复」:
/// preference → next engine start rewrites managed guest AGENTS.md (xrk-ui).
///
/// A running/starting engine restarts so the AI sees the new section immediately
/// (same bounce pattern as [PhoneFilesControl]).
abstract final class VisualRepliesControl {
  static Future<void> setEnabled(
    ProviderContainer container, {
    required bool enabled,
  }) async {
    await container.read(settingsProvider.notifier).setVisualReplies(enabled);
    final phase = container.read(localRuntimeProvider).status.phase;
    if (phase == RuntimePhase.running || phase == RuntimePhase.starting) {
      unawaited(EngineControl.restart(container));
    }
  }
}
