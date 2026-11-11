// 设置 › 个性化: App-owned toggles that rewrite the managed guest AGENTS.md
// on the next engine start (today:「可视化回复」). Reply prefs / Agent presets
// stay in in-guest Web Settings.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/runtime_bridge.dart' show RuntimePhase;
import '../../runtime/runtime_state.dart';
import '../../state/engine_control.dart';
import '../../state/hosts_state.dart';
import '../../state/settings_state.dart';
import '../common/list_page_row.dart';
import '../features/feature_widgets.dart' show FeatureNote;
import '../shell/page_frame.dart';
import 'index/spots.dart';

class PersonalizationPage extends ConsumerStatefulWidget {
  const PersonalizationPage({super.key});

  @override
  ConsumerState<PersonalizationPage> createState() => _PersonalizationPageState();
}

class _PersonalizationPageState extends ConsumerState<PersonalizationPage> {
  bool _dirty = false;

  Future<void> _setVisualReplies(bool next) async {
    await ref.read(settingsProvider.notifier).setVisualReplies(next);
    if (mounted) setState(() => _dirty = true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final local = ref.watch(activeHostProvider).isLocal;
    final visual = ref.watch(settingsProvider.select((s) => s.visualReplies));
    final phase = ref.watch(localRuntimeProvider.select((s) => s.status.phase));
    final running = phase == RuntimePhase.running || phase == RuntimePhase.starting;
    final needsRestart = local && running && _dirty;

    return AppPage.list(
      title: l10n.hubPersonalization,
      children: [
        if (!local)
          FeatureNote(l10n.hubSettingsVisualRepliesHint)
        else ...[
          ListPageCard(
            children: [
              MergeSemantics(
                child: ListPageRow(
                  spot: Spots.visualReplies,
                  title: l10n.hubSettingsVisualReplies,
                  subtitle: needsRestart ? l10n.hubSettingsRestartRequired : l10n.hubSettingsVisualRepliesHint,
                  trailing: Switch(value: visual, onChanged: (v) => unawaited(_setVisualReplies(v))),
                ),
              ),
            ],
          ),
          if (needsRestart)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    unawaited(EngineControl.restart(ProviderScope.containerOf(context, listen: false)));
                    setState(() => _dirty = false);
                  },
                  child: Text(l10n.hubSettingsRestartNow),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
