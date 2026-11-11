// The new conversation's options on the empty state: the agent preset it
// starts with and the drawer folder it is filed in. Permission tiers stay in
// Web / CLI. Preset picks are held in pendingNewChatModesProvider and applied
// when the first message creates the session (chat_screen.dart `_ensureSession`).

import 'dart:async';

import 'package:xrk_client/xrk_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/features_state.dart';
import '../../state/models_state.dart' show modelSelectionScopeProvider;
import '../../state/new_chat_modes.dart';
import '../../state/sessions_state.dart' show currentSessionProvider;
import '../common/app_sheet.dart';
import '../common/list_page_row.dart';
import '../common/sheet_title_bar.dart';
import '../features/feature_format.dart';
import '../theme/app_icons.dart';
import 'empty_actions.dart';

/// The longest a single option may grow before its label is cut.
const _itemMaxWidth = 200.0;

/// Retired Host presets (old companion shell) — never offered on a new chat.
bool isRetiredNewChatPreset(String id) =>
    id == 'xrk-mobile-companion-full' || id.startsWith('xrk-mobile-companion-');

/// Presets a new chat can start with, in the Host's order (product tool surfaces).
List<AgentPresetInfo> newChatPresets(List<AgentPresetInfo>? all) => [
  ...?all?.where((p) => !isRetiredNewChatPreset(p.id)),
];

/// The Host's default preset among [presets] (the first when none is marked).
AgentPresetInfo? defaultPreset(List<AgentPresetInfo> presets) {
  for (final preset in presets) {
    if (preset.isDefault) return preset;
  }
  return presets.isEmpty ? null : presets.first;
}

/// The preset to apply to a new session for [picked] (null: keep Host default),
/// given the Host's list [all]. A pick the Host no longer offers falls back to
/// keeping the Host default (null). When the Host default itself is retired,
/// apply the first offered preset explicitly so the chip matches the session.
String? newChatPresetToApply(List<AgentPresetInfo>? all, String? picked) {
  if (all == null) return picked;
  final offered = newChatPresets(all);
  if (picked != null) {
    return offered.any((p) => p.id == picked && p.broken == null) ? picked : null;
  }
  final hostDefault = defaultPreset(all);
  if (hostDefault != null && isRetiredNewChatPreset(hostDefault.id)) {
    return defaultPreset(offered)?.id;
  }
  return null;
}

IconData presetIcon(String id) => switch (id) {
  'standard' => AppIcons.presetStandard,
  'ptc' => AppIcons.presetPtc,
  'minimal' => AppIcons.presetMinimal,
  'cordis' => AppIcons.presetCordis,
  _ => AppIcons.configure,
};

/// The options row: the agent preset and (with folders) the drawer folder —
/// light items in one centred line. The preset appears once the Host has said
/// what it offers, and only when there is a real choice.
class NewChatOptions extends ConsumerWidget {
  const NewChatOptions({super.key, this.folderLabel, this.onFolder});

  /// The drawer-folder item, when there are folders.
  final String? folderLabel;
  final VoidCallback? onFolder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final pending = ref.watch(pendingNewChatModesProvider);

    final presets = newChatPresets(ref.watch(agentPresetsProvider).value);
    final fallbackPreset = defaultPreset(presets);
    AgentPresetInfo? shownPreset = fallbackPreset;
    for (final preset in presets) {
      if (preset.id == pending.preset && preset.broken == null) shownPreset = preset;
    }

    Widget item(Key key, IconData icon, String label, String name, VoidCallback onTap) => ConstrainedBox(
      key: key,
      constraints: const BoxConstraints(maxWidth: _itemMaxWidth),
      child: SetupItem(
        icon: icon,
        label: label,
        semanticsLabel: '$name: $label',
        onTapHint: l10n.viewNewChatChange,
        onTap: onTap,
      ),
    );

    final items = <Widget>[
      if (presets.length > 1 && shownPreset != null)
        item(
          const ValueKey('new-chat-preset'),
          presetIcon(shownPreset.id),
          agentPresetName(shownPreset),
          l10n.featuresAgentPresets,
          () => unawaited(_pickPreset(context, ref)),
        ),
      if (folderLabel != null && onFolder != null)
        item(const ValueKey('new-chat-folder'), AppIcons.folder, folderLabel!, l10n.viewNewChatFolder, onFolder!),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(alignment: WrapAlignment.center, spacing: 2, children: items);
  }

  /// A pick belongs to the screen it was made on: the same host/connection
  /// and still no session.
  static bool Function() _owner(WidgetRef ref) {
    final scope = ref.read(modelSelectionScopeProvider);
    return () => identical(ref.read(modelSelectionScopeProvider), scope) && ref.read(currentSessionProvider) == null;
  }

  Future<void> _pickPreset(BuildContext context, WidgetRef ref) async {
    final current = _owner(ref);
    final presets = newChatPresets(ref.read(agentPresetsProvider).value);
    final fallback = defaultPreset(presets);
    if (presets.isEmpty || fallback == null) return;
    final selected = ref.read(pendingNewChatModesProvider).preset ?? fallback.id;
    final pick = await showAppSheet<String>(
      context,
      isScrollControlled: true,
      builder: (sheet) => _ChoiceSheet(
        title: sheet.l10n.viewNewChatPresetTitle,
        rows: [
          for (final preset in presets)
            _Choice(
              value: preset.id,
              icon: presetIcon(preset.id),
              title: agentPresetName(preset),
              subtitle: preset.broken != null ? sheet.l10n.viewNewChatUnavailable : agentPresetDescription(preset),
              meta: preset.id == fallback.id ? sheet.l10n.viewNewChatDefault : null,
              enabled: preset.broken == null,
            ),
        ],
        selected: selected,
      ),
    );
    if (pick == null || !context.mounted || !current()) return;
    ref.read(pendingNewChatModesProvider.notifier).selectPreset(pick == fallback.id ? null : pick);
  }
}

class _Choice {
  const _Choice({
    required this.value,
    required this.icon,
    required this.title,
    this.subtitle,
    this.meta,
    this.enabled = true,
  });

  final String value;
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? meta;
  final bool enabled;
}

/// One short list to pick from: the rows, a check on the selected one.
class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({required this.title, required this.rows, required this.selected});

  final String title;
  final List<_Choice> rows;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitleBar(title),
              SheetGroup(
                margin: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 0, SheetTitleBar.inset, 12),
                children: [
                  for (final row in rows)
                    ListPageRow(
                      icon: row.icon,
                      title: row.title,
                      subtitle: row.subtitle,
                      subtitleMaxLines: 2,
                      meta: row.meta,
                      trailing: row.value == selected
                          ? Icon(AppIcons.selected, size: 20, color: scheme.primary)
                          : const SizedBox(width: 20),
                      onTap: row.enabled ? () => Navigator.of(context).pop(row.value) : null,
                    ),
                ],
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
