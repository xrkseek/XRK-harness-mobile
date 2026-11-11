// 「访问手机文件」: App-owned cascade (preference → OS grant → SAF → /sdcard).
// Lives on 手机操控; Host permission tiers stay in Web / CLI.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/runtime_bridge.dart';
import '../../state/hosts_state.dart';
import '../../state/phone_files.dart';
import '../../state/settings_state.dart';
import '../common/list_page_row.dart';
import '../common/risk_notice.dart';
import '../settings/index/spots.dart';

/// Card with the phone-files switch; empty when the active host is not local.
class PhoneFilesCard extends ConsumerStatefulWidget {
  const PhoneFilesCard({super.key});

  @override
  ConsumerState<PhoneFilesCard> createState() => _PhoneFilesCardState();
}

class _PhoneFilesCardState extends ConsumerState<PhoneFilesCard> with WidgetsBindingObserver {
  bool _busy = false;
  StorageAccess? _storage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_refreshStorage()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshStorage());
  }

  Future<void> _refreshStorage() async {
    if (!ref.read(activeHostProvider).isLocal) return;
    try {
      final access = await PhoneFilesControl.refreshStatus(ProviderScope.containerOf(context, listen: false));
      if (mounted) setState(() => _storage = access);
    } catch (_) {
      // Bridge unavailable offline / mid-restart.
    }
  }

  String _subtitle(L10n l10n, bool phoneFiles) {
    final access = _storage;
    if (!phoneFiles) return l10n.hubSettingsPhoneFilesHint;
    if (access == null) return l10n.hubSettingsPhoneFilesHint;
    if (!access.granted) return l10n.hubSettingsPhoneFilesNeedGrant;
    if (access.bound) return l10n.hubSettingsPhoneFilesActive;
    return l10n.hubSettingsRestartRequired;
  }

  Future<void> _onPhoneFiles(bool next) async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = context.l10n;
    final container = ProviderScope.containerOf(context, listen: false);
    final alreadyOn = ref.read(settingsProvider).phoneStorage;
    try {
      final ok = await PhoneFilesControl.setEnabled(
        container,
        enabled: next,
        confirmEnable: next && !alreadyOn ? () => confirmRisk(context, RiskNotices.phoneFiles) : null,
      );
      if (!ok && next && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l10n.hubSettingsStorageDenied)));
      }
      await _refreshStorage();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(activeHostProvider).isLocal) return const SizedBox.shrink();
    final l10n = context.l10n;
    final phoneFiles = ref.watch(settingsProvider.select((s) => s.phoneStorage));
    final needGrant = phoneFiles && _storage != null && !_storage!.granted;
    return ListPageCard(
      children: [
        MergeSemantics(
          child: ListPageRow(
            spot: Spots.phoneFiles,
            subtitle: _subtitle(l10n, phoneFiles),
            onTap: _busy ? null : () => unawaited(_onPhoneFiles(needGrant ? true : !phoneFiles)),
            trailing: Switch(
              value: phoneFiles,
              onChanged: _busy ? null : (v) => unawaited(_onPhoneFiles(v)),
            ),
          ),
        ),
      ],
    );
  }
}
