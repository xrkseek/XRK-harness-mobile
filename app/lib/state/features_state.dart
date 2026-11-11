import 'dart:async';

import 'package:xrk_client/xrk_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_state.dart';

/// The active host's client, or null while not connected.
XrkClient? _client(Ref ref) => ref.watch(activeConnectionProvider).value?.client;

/// Re-runs [ref]'s provider when the Host emits one of [events].
void _refreshOn(Ref ref, XrkClient client, Set<String> events) {
  final sub = client.hostEvents.listen((event) {
    if (event is HostReadyEvent || (event is UnknownHostEvent && events.contains(event.event))) {
      ref.invalidateSelf();
    }
  });
  ref.onDispose(() => unawaited(sub.cancel()));
}

// ── 自动化任务 ────────────────────────────────────────────────────────────────

/// Every automation task on the active host (`schedule/catalog`), refreshed
/// on `schedule/changed`. Null while not connected.
final schedulesProvider = FutureProvider.autoDispose<List<ScheduleTask>?>((ref) async {
  final client = _client(ref);
  if (client == null) return null;
  _refreshOn(ref, client, const {'schedule/changed'});
  final tasks = await client.scheduleCatalog();
  // Active first, then by next run; inactive ones by when they last ran.
  tasks.sort((a, b) {
    if (a.active != b.active) return a.active ? -1 : 1;
    final at = a.scheduledAt ?? DateTime(9999);
    final bt = b.scheduledAt ?? DateTime(9999);
    return a.active ? at.compareTo(bt) : bt.compareTo(at);
  });
  return tasks;
});

/// Delivered runs of one task, newest first (first page).
final scheduleHistoryProvider = FutureProvider.autoDispose.family<ScheduleHistory, ScheduleTask>((ref, task) async {
  final client = _client(ref);
  if (client == null) return const ScheduleHistory();
  return client.scheduleHistory(task);
});

// ── 后台任务 ──────────────────────────────────────────────────────────────────

/// A session's background jobs (`job/list`): the whole set on every change,
/// running ones first.
final jobsProvider = StreamProvider.autoDispose.family<List<JobInfo>, String>((ref, sessionId) {
  final client = _client(ref);
  if (client == null) return const Stream.empty();
  return client.watchJobs(sessionId).map((jobs) {
    final sorted = [...jobs]
      ..sort((a, b) {
        if (a.live != b.live) return a.live ? -1 : 1;
        final at = a.startedAt ?? DateTime(0);
        final bt = b.startedAt ?? DateTime(0);
        return bt.compareTo(at);
      });
    return sorted;
  });
});

// ── 技能 ──────────────────────────────────────────────────────────────────────

/// Skills the user can call with `/name` in [sessionId]; refreshed when a
/// plugin changes the command catalog.
final skillsProvider = FutureProvider.autoDispose.family<List<SkillInfo>?, String>((ref, sessionId) async {
  final client = _client(ref);
  if (client == null) return null;
  _refreshOn(ref, client, const {'commands/change', 'plugin-manager/changed'});
  final skills = await client.listSkills(sessionId);
  return skills..sort((a, b) => a.name.compareTo(b.name));
});

// ── Agent 预设 ────────────────────────────────────────────────────────────────

/// Agent presets in the Host's order; refreshed when the default changes.
final agentPresetsProvider = FutureProvider.autoDispose<List<AgentPresetInfo>?>((ref) async {
  final client = _client(ref);
  if (client == null) return null;
  _refreshOn(ref, client, const {'agent-preset/selected', 'settings/document-updated'});
  return client.listAgentPresets();
});

/// One preset's YAML.
final agentPresetDocumentProvider = FutureProvider.autoDispose.family<AgentPresetDocument, String>((ref, id) async {
  final client = _client(ref);
  if (client == null) throw const DshClosedException('not connected');
  return client.readAgentPreset(id);
});
