import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../runtime/local_footprint.dart';
import '../runtime/runtime_state.dart';
import '../state/hosts_state.dart';
import '../ui/remote/host_key_dialog.dart' show activateHost;
import '../ui/remote/http_host_add_sheet.dart';
import '../ui/shell/brand_mark.dart';
import '../ui/theme/app_icons.dart';

/// Post-splash / per-launch pick: start the on-device Host, or open a remote
/// HTTP Face without waking the local engine (saves battery).
class SessionEntryPage extends ConsumerWidget {
  const SessionEntryPage({
    super.key,
    required this.onPicked,
  });

  /// [choseLocal] true → boot on-device Host; false → remote Face only (Host stays down).
  final void Function(bool choseLocal) onPicked;

  Future<void> _pickLocal(BuildContext context, WidgetRef ref) async {
    final missing = ref.read(localRuntimeProvider).status.runtimeMissing;
    if (missing) {
      // Keep entry until install exists; Host switcher / settings own install.
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(context.l10n.localEnvPhoneNeedsRuntime)),
      );
      return;
    }
    final ok = await activateHost(context, ref, HostRef.local);
    if (ok) onPicked(true);
  }

  Future<void> _pickHttp(BuildContext context, WidgetRef ref, String id) async {
    final ok = await activateHost(context, ref, HostRef.http(id));
    if (ok) onPicked(false);
  }

  Future<void> _addHttp(BuildContext context, WidgetRef ref) async {
    await showHttpHostAddSheet(context);
    if (!context.mounted) return;
    final active = ref.read(activeHostProvider);
    if (active.kind == HostKind.http) onPicked(false);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final hosts = ref.watch(hostsProvider);
    final http = hosts.http;
    final localMissing = ref.watch(localRuntimeProvider.select((s) => s.status.runtimeMissing));

    return ColoredBox(
      color: const Color(0xFF0B0B0C),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BrandMark(size: 40),
              const SizedBox(height: 28),
              const Text(
                '这次怎么用',
                style: TextStyle(
                  color: Color(0xFFE8E8E6),
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '进此页不会启动本机 Host。选本机才启动；选远程只连对面，本机保持关闭。选本机后再切远程，本机可继续在后台跑。',
                style: TextStyle(color: Color(0xFFB8B8B4), fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 28),
              if (!hosts.loaded)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE8E8E6)),
                    ),
                  ),
                )
              else ...[
                _EntryCard(
                  icon: AppIcons.thisPhone,
                  title: l10n.commonThisPhone,
                  subtitle: localMissing ? l10n.localEnvPhoneNeedsRuntime : '启动本机 Host，在手机上直接用',
                  onTap: () => unawaited(_pickLocal(context, ref)),
                ),
                const SizedBox(height: 12),
                if (http.isEmpty)
                  _EntryCard(
                    icon: AppIcons.remoteHost,
                    title: '远程 HTTP Host',
                    subtitle: '添加地址或扫码 · 不启动本机引擎',
                    onTap: () => unawaited(_addHttp(context, ref)),
                  )
                else ...[
                  for (final h in http) ...[
                    _EntryCard(
                      icon: AppIcons.remoteHost,
                      title: h.name.isNotEmpty ? h.name : l10n.commonRemoteHost,
                      subtitle: '${h.origin} · 不启动本机引擎',
                      onTap: () => unawaited(_pickHttp(context, ref, h.id)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextButton(
                    onPressed: () => unawaited(_addHttp(context, ref)),
                    child: const Text('添加其他远程 Host'),
                  ),
                ],
              ],
              const Spacer(),
              const Text(
                '之后可在设置球 → 切换主机随时改。本机起来后再切远程不会关引擎；要停用通知栏长按、球内引擎页，或切换主机里的「停止本机引擎」。',
                style: TextStyle(color: Color(0xFF8A8A86), fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF161618),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFE8E8E6), size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFFE8E8E6),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFFB8B8B4), fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),
              const Icon(AppIcons.disclosure, color: Color(0xFF8A8A86)),
            ],
          ),
        ),
      ),
    );
  }
}
