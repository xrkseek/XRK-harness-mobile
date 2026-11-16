import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/local_footprint.dart';
import '../../runtime/runtime_bridge.dart';
import '../../runtime/runtime_state.dart';
import '../../state/connection_state.dart';
import '../../state/hosts_state.dart';
import '../common/app_dialog.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../common/status_chip.dart';
import '../onboarding/local_install.dart';
import '../settings/settings_widgets.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'host_key_dialog.dart';
import 'host_status.dart';
import 'http_host_add_sheet.dart';

/// Drawer-header chip: `● 本机 · 运行中 ⌄` / `● 电脑 · 已连接 ⌄`. Opens the
/// host sheet.
class HostChip extends ConsumerWidget {
  const HostChip({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final host = ref.watch(activeHostProvider);
    final name = ref.watch(hostNameProvider(host)) ?? (host.isLocal ? l10n.commonThisPhone : l10n.commonRemoteHost);
    final view = watchHostStatus(ref, host);
    return Semantics(
      button: true,
      onTap: onTap,
      label: l10n.remoteHostSwitcherSemantics(name, view.label),
      child: ExcludeSemantics(
        child: GlassSurface(
          tier: GlassTier.pill,
          stadium: true,
          onTap: onTap,
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedStatusDot(tone: view.tone, size: 7),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  '$name · ${view.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.tabular(theme.textTheme.labelMedium!.copyWith(color: scheme.onSurfaceVariant)),
                ),
              ),
              const SizedBox(width: 2),
              Icon(AppIcons.dropdown, size: 16, color: XrkColors.of(context).textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// "切换主机": 本机 + saved HTTP hosts. [onManage] opens the HTTP hosts page.
Future<void> showHostSheet(BuildContext context, {required VoidCallback onManage}) {
  return showAppSheet<void>(context, isScrollControlled: true, builder: (sheet) => HostSheet(onManage: onManage));
}

class HostSheet extends ConsumerWidget {
  const HostSheet({super.key, required this.onManage});

  final VoidCallback onManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final active = ref.watch(activeHostProvider);
    final http = ref.watch(hostsProvider.select((s) => s.http));

    Future<void> pick(HostRef host) async {
      if (host == active) {
        Navigator.of(context).pop();
        return;
      }
      final navigator = Navigator.of(context);
      final ok = await activateHost(context, ref, host);
      if (ok && navigator.mounted) navigator.pop();
    }

    final localMissing = ref.watch(localRuntimeProvider.select((s) => s.status.runtimeMissing));
    void installLocal() {
      final navigator = Navigator.of(context);
      navigator.pop();
      unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => const LocalInstallPage(useWhenDone: true))));
    }

    final localPhase = ref.watch(localRuntimeProvider.select((s) => s.status.phase));
    final localRunning = localPhase == RuntimePhase.running || localPhase == RuntimePhase.starting;

    Future<void> stopLocalEngine() async {
      final ok = await showAppDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(l10n.phoneEngineStopTitle),
          content: Text(l10n.phoneEngineStopBody),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(l10n.commonCancel)),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(l10n.commonStop),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await ref.read(localRuntimeProvider.notifier).stop();
      } catch (_) {}
    }

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetTitleBar(l10n.remoteSwitchHost),
              SheetGroup(
                margin: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 0, SheetTitleBar.inset, 12),
                children: [
                  _HostRow(
                    host: HostRef.local,
                    title: l10n.commonThisPhone,
                    subtitle: l10n.remoteThisPhoneDsh,
                    active: active.isLocal,
                    onTap: localMissing ? installLocal : () => pick(HostRef.local),
                  ),
                  for (final h in http)
                    _HostRow(
                      host: HostRef.http(h.id),
                      title: h.name,
                      subtitle: h.origin,
                      active: active == HostRef.http(h.id),
                      onTap: () => pick(HostRef.http(h.id)),
                    ),
                ],
              ),
              if (localRunning)
                SheetGroup(
                  margin: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 0, SheetTitleBar.inset, 12),
                  children: [
                    SettingsTile(
                      icon: AppIcons.stop,
                      tinted: false,
                      title: '停止本机引擎',
                      subtitle: active.isLocal ? '关掉当前本机 Host' : '远程界面下仍可关掉后台本机 Host',
                      onTap: () => unawaited(stopLocalEngine()),
                    ),
                  ],
                ),
              SheetGroup(
                margin: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 0, SheetTitleBar.inset, 12),
                children: [
                  SettingsTile(
                    icon: AppIcons.add,
                    tinted: false,
                    title: '添加 HTTP 主机',
                    subtitle: '扫码 / 输入地址',
                    onTap: () {
                      Navigator.of(context).pop();
                      unawaited(showHttpHostAddSheet(context));
                    },
                  ),
                  SettingsTile(
                    icon: http.isEmpty ? AppIcons.add : AppIcons.configure,
                    tinted: false,
                    title: http.isEmpty ? '管理 HTTP 主机' : l10n.remoteManageHosts,
                    subtitle: '本机以外只用 HTTP Face 地址',
                    onTap: () {
                      Navigator.of(context).pop();
                      onManage();
                    },
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

class _HostRow extends ConsumerWidget {
  const _HostRow({
    required this.host,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  final HostRef host;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    // Always probe: inactive remote rows still show reachable / 已连接 green.
    // (Previously only active|local watched status → switch to 本机 hid remote green.)
    final view = watchHostStatus(ref, host);
    return Semantics(
      key: ValueKey('host-row-${host.kind.name}-${host.id}'),
      selected: active,
      inMutuallyExclusiveGroup: true,
      child: SettingsTile(
        icon: hostKindIcon(host.kind),
        tinted: false,
        title: title,
        subtitle: subtitle,
        onTap: onTap,
        value: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedStatusDot(tone: view.tone, size: 7),
            const SizedBox(width: 6),
            Text(view.label),
          ],
        ),
        trailing: active ? Icon(AppIcons.selected, size: 20, color: scheme.primary) : const SizedBox(width: 20),
      ),
    );
  }
}
