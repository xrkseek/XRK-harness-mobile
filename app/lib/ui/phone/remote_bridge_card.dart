import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../remote/bridge/remote_bridge_status.dart';
import '../../state/hosts_state.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import 'phone_widgets.dart';

/// HTTP Host remote phone-bridge status on 手机操控.
///
/// Complements local guest phone_* : this card is about the **outbound** bridge
/// to a Desktop/AGT Host Settings whitelist.
class RemoteBridgeCard extends ConsumerWidget {
  const RemoteBridgeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(activeHostProvider);
    if (host.kind != HostKind.http) return const SizedBox.shrink();

    return ValueListenableBuilder<RemoteBridgeSnapshot>(
      valueListenable: remoteBridgeStatus,
      builder: (context, snap, _) {
        final tone = snap.dangerTone
            ? NoteTone.danger
            : snap.warnTone
                ? NoteTone.warn
                : snap.okTone
                    ? NoteTone.info
                    : NoteTone.info;
        final key = snap.deviceKey;
        final theme = Theme.of(context);
        final onInfo = XrkColors.of(context).onInfoContainer;
        return PhoneNote(
          tone: tone,
          icon: AppIcons.link,
          title: snap.titleZh,
          text: snap.bodyZh,
          action: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (key != null && key.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: key));
                    if (!context.mounted) return;
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('已复制 deviceKey')),
                    );
                  },
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    '复制 deviceKey · ${key.length > 10 ? '${key.substring(0, 10)}…' : key}',
                    style: theme.textTheme.labelMedium?.copyWith(color: onInfo),
                  ),
                ),
              TextButton(
                onPressed: () {
                  requestRemoteBridgeResync();
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                    const SnackBar(content: Text('正在重新报到 Host…')),
                  );
                },
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  snap.phase == RemoteBridgePhase.needPin || snap.phase == RemoteBridgePhase.error
                      ? '重新报到（先确认 Face 已 PIN）'
                      : '重新报到',
                  style: theme.textTheme.labelMedium?.copyWith(color: onInfo),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
