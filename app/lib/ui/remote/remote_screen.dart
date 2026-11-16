import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/local_footprint.dart';
import '../../runtime/runtime_state.dart';
import '../../state/connection_state.dart';
import '../../state/hosts_state.dart';
import '../common/overview_card.dart';
import '../common/status_chip.dart';
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'host_key_dialog.dart';
import 'host_status.dart';
import 'http_host_add_sheet.dart';
import 'http_host_form.dart';
import 'link_progress.dart';

/// HTTP 主机：本机以外，用 URL 打开远端 Face（PIN 由 Host 页面处理）。
class RemoteScreen extends ConsumerWidget {
  const RemoteScreen({super.key});

  Future<void> _use(BuildContext context, WidgetRef ref, HostRef host) async {
    final navigator = Navigator.of(context);
    if (ref.read(activeHostProvider) == host) {
      final failed = ref.read(hostLinkStatusProvider(host)).value?.phase == HostLinkPhase.failed;
      if (!failed) {
        navigator.maybePop();
        return;
      }
      if (await activateHost(context, ref, host)) {
        ref.read(httpHostLinkProvider(host))?.retry();
      }
      return;
    }
    final ok = await activateHost(context, ref, host);
    if (ok && navigator.mounted) {
      Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _addHttp(BuildContext context) async {
    await showHttpHostAddSheet(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final http = ref.watch(hostsProvider.select((s) => s.http));
    final active = ref.watch(activeHostProvider);
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    return AppPage.list(
      title: 'HTTP 主机',
      subtitle: const Text('用地址连接电脑或公网上的 XRK Face；打开后按页面输入 PIN'),
      children: [
        _ActiveCard(active: active),
        SettingsSection(
          title: '已保存',
          footer: const Text('扫码或输入如 http://host:8787；无需 SSH 或云中继'),
          children: [
            for (final h in http)
              _HttpRow(
                config: h,
                active: active == HostRef.http(h.id),
                onTap: () => unawaited(_use(context, ref, HostRef.http(h.id))),
                onEdit: () => push(HttpHostFormPage(existing: h)),
              ),
            SettingsTile(
              icon: AppIcons.add,
              tinted: false,
              title: http.isEmpty ? '添加 HTTP 主机' : '再添加一台',
              subtitle: '扫码 / 输入地址',
              onTap: () => unawaited(_addHttp(context)),
            ),
          ],
        ),
        if (http.isNotEmpty)
          SettingsSection(
            title: context.l10n.remoteStartupSection,
            children: [
              SettingsSwitchTile(
                key: const ValueKey('remote-auto-connect'),
                spot: Spots.remoteAutoConnect,
                subtitle: context.l10n.remoteAutoConnectOnStartupHint,
                value: ref.watch(remoteAutoConnectProvider),
                onChanged: (value) => unawaited(ref.read(remoteAutoConnectProvider.notifier).set(value)),
              ),
            ],
          ),
      ],
    );
  }
}

class _ActiveCard extends ConsumerWidget {
  const _ActiveCard({required this.active});

  final HostRef active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    if (active.isLocal || active.kind != HostKind.http) return const SizedBox.shrink();
    final status = ref.watch(hostLinkStatusProvider(active)).value ?? HostLinkStatus.idle;
    final view = HostStatusView.ofLink(status);
    final name = ref.watch(hostNameProvider(active)) ?? l10n.commonRemoteHost;
    final http = ref.watch(hostsProvider).httpById(active.id);
    final error = status.error;
    final needsSettings = http != null && error != null && !error.retryable;
    void reconnect() => ref.read(httpHostLinkProvider(active))?.retry();
    final failed = status.phase == HostLinkPhase.failed && error != null;
    final canGoLocal = ref.watch(localRuntimeProvider.select((s) => !s.status.runtimeMissing));
    final address = http?.origin;
    return OverviewCard(
      leading: OverviewGlyph(hostKindIcon(active.kind), tint: hostKindTint(active.kind)),
      title: Text(l10n.remoteActiveHost(name)),
      subtitle: Row(
        children: [
          AnimatedStatusDot(tone: view.tone, size: 7),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status.phase == HostLinkPhase.connected && address != null
                  ? address
                  : view.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: canGoLocal
          ? TextButton(
              onPressed: () => ref.read(activeHostProvider.notifier).select(HostRef.local),
              child: Text(l10n.remoteSwitchToPhone),
            )
          : null,
      footer: failed
          ? Padding(
              padding: const EdgeInsets.only(left: OverviewCard.inset, right: OverviewCard.inset - 12),
              child: LinkErrorBox(
                error: error,
                action: needsSettings
                    ? (
                        l10n.remoteHostSettings,
                        () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => HttpHostFormPage(existing: http),
                              ),
                            ),
                      )
                    : (l10n.commonRetry, reconnect),
              ),
            )
          : null,
    );
  }
}

class _HttpRow extends ConsumerWidget {
  const _HttpRow({required this.config, required this.active, required this.onTap, required this.onEdit});

  final HttpHostConfig config;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final view = active ? watchHostStatus(ref, HostRef.http(config.id)) : null;
    return Semantics(
      selected: active,
      inMutuallyExclusiveGroup: true,
      child: SettingsTile(
        icon: hostKindIcon(HostKind.http),
        tinted: false,
        title: config.name,
        subtitle: config.origin,
        onTap: onTap,
        value: view == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedStatusDot(tone: view.tone, size: 7),
                  const SizedBox(width: 6),
                  Text(view.label),
                ],
              ),
        trailing: IconButton(
          tooltip: l10n.commonEdit,
          visualDensity: VisualDensity.compact,
          color: XrkColors.of(context).textTertiary,
          icon: const Icon(AppIcons.configure, size: 20),
          onPressed: onEdit,
        ),
      ),
    );
  }
}
