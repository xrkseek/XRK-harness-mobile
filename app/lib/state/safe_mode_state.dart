import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../runtime/runtime_bridge.dart';
import '../runtime/runtime_state.dart';

/// What "恢复上次正常配置" would change right now. Refreshes whenever the engine's
/// phase, mode or failure changes.
final lastKnownGoodProvider = FutureProvider.autoDispose<LastKnownGood>((ref) async {
  ref.watch(localRuntimeProvider.select((s) => (s.status.phase, s.status.mode, s.status.failure?.at)));
  try {
    return await ref.read(runtimeBridgeProvider).lastKnownGood();
  } catch (_) {
    return const LastKnownGood.none();
  }
});

/// Home-level files that would also break the safe profile (`/root/.xrk/.env`,
/// `.env` files with launch-only variables).
final safePreflightProvider = FutureProvider.autoDispose<List<SafeHazard>>((ref) async {
  ref.watch(localRuntimeProvider.select((s) => (s.status.phase, s.status.mode)));
  try {
    return await ref.read(runtimeBridgeProvider).safePreflight();
  } catch (_) {
    return const [];
  }
});

/// One short Chinese clause for a failure, e.g. "启动失败，可疑插件：foo".
String failureOneLiner(RuntimeFailure f) {
  final what = switch (f.kind) {
    FailureKind.launchFailed => appL10n.phoneFailureLaunch,
    FailureKind.startupFailed => appL10n.stateSafeStartupFailed,
    FailureKind.crashedEarly => appL10n.stateSafeCrashedEarly,
    FailureKind.crashedLate => appL10n.stateSafeCrashedLate,
    FailureKind.killed => appL10n.stateSafeKilled,
    FailureKind.noSpace => appL10n.commonStorageFull,
  };
  final culprits = f.culprits;
  if (f.kind != FailureKind.launchFailed && culprits.isNotEmpty) {
    return appL10n.stateSafeSuspectPlugins(what, culprits.take(3).join(appL10n.stateListSeparator));
  }
  if (f.kind != FailureKind.launchFailed && f.requiredRows.isNotEmpty) {
    return appL10n.stateSafePreflightFailed(what, f.requiredRows.take(3).join(appL10n.stateListSeparator));
  }
  final summary = f.summary;
  if (summary != null && summary.isNotEmpty) {
    return appL10n.stateActionReason(what, summary.length > 120 ? '${summary.substring(0, 119)}…' : summary);
  }
  return what;
}

/// Truncates a failure line for the composer without cutting mid-codepoint.
String _clipFailureDetail(String text, {int max = 280}) {
  final trimmed = text.trim();
  if (trimmed.length <= max) return trimmed;
  return '${trimmed.substring(0, max - 1)}…';
}

/// The text 「帮我修复」 pre-fills into the composer (not sent). Includes the failure
/// one-liner plus any raw summary so the agent sees the error without opening logs first.
/// The native Safe mode briefing still has the full playbook.
String repairPrompt(RuntimeStatus status) {
  final f = status.mainFailure ?? status.failure;
  final what = f == null ? appL10n.stateSafeManualEntry : failureOneLiner(f);
  final summary = f?.summary?.trim();
  final detail = (summary != null && summary.isNotEmpty && !what.contains(summary))
      ? _clipFailureDetail(summary)
      : null;
  return detail == null ? appL10n.stateSafeRepairPrompt(what) : appL10n.stateSafeRepairPromptWithDetail(what, detail);
}
