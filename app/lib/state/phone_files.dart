import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_bridge.dart';
import '../runtime/runtime_state.dart';
import 'engine_control.dart';
import 'settings_state.dart';

/// Cascade for Settings →「访问手机文件」:
/// preference → OS grant → DocumentsProvider「手机存储」root → engine `/sdcard` bind.
///
/// Enable and disable both refresh SAF roots; a running/starting engine restarts
/// so proot binds (and the AI's view of `/sdcard`) match the switch.
abstract final class PhoneFilesControl {
  /// Applies [enabled]. Returns false when the user cancelled or the OS denied
  /// storage (preference left unchanged). [confirmEnable] runs only when turning on.
  ///
  /// When [alreadyGranted] is true (onboarding already proved storage is on),
  /// skips the system prompt and writes the preference immediately.
  /// When [restartEngine] is false, the caller coordinates a single restart
  /// (e.g. with 手机操控 enable).
  static Future<bool> setEnabled(
    ProviderContainer container, {
    required bool enabled,
    Future<bool> Function()? confirmEnable,
    bool alreadyGranted = false,
    bool restartEngine = true,
  }) async {
    final bridge = container.read(runtimeBridgeProvider);
    final settings = container.read(settingsProvider.notifier);

    if (enabled && !alreadyGranted) {
      if (confirmEnable != null && !await confirmEnable()) return false;
      var access = await bridge.requestStorage();
      if (!access.granted && access.permission && !access.legacy) {
        await bridge.openAllFilesAccess();
        access = await bridge.storageStatus();
      }
      if (!access.granted) return false;
    }

    await settings.setPhoneStorage(enabled);
    // SAF roots follow the preference even when the engine is stopped.
    await bridge.refreshDocumentRoots();

    if (restartEngine) {
      final phase = container.read(localRuntimeProvider).status.phase;
      if (phase == RuntimePhase.running || phase == RuntimePhase.starting) {
        unawaited(EngineControl.restart(container));
      }
    }
    return true;
  }

  /// Re-query OS grant + refresh SAF roots (e.g. after returning from system settings).
  static Future<StorageAccess> refreshStatus(ProviderContainer container) async {
    final bridge = container.read(runtimeBridgeProvider);
    final access = await bridge.storageStatus();
    // Explicit refresh (storageStatus is read-only; no side-effect notify).
    await bridge.refreshDocumentRoots();
    return access;
  }
}
