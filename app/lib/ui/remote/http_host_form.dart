import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../remote/http/http_host_config.dart';
import '../../remote/http/http_host_link.dart';
import '../../remote/http/http_host_parse.dart';
import '../../state/connection_state.dart';
import '../../state/hosts_state.dart';
import '../common/app_dialog.dart';
import '../common/discard_guard.dart';
import '../providers/provider_widgets.dart' show FormFieldBlock, FormFieldGroup;
import '../settings/settings_widgets.dart';
import '../shell/page_frame.dart';
import '../theme/theme.dart';
import 'host_key_dialog.dart';
import 'link_progress.dart';

/// Add or edit an HTTP Face host (URL → WebView; Host PIN unlocks Face).
class HttpHostFormPage extends ConsumerStatefulWidget {
  const HttpHostFormPage({
    super.key,
    this.existing,
    this.initialOrigin,
    this.initialName,
    this.initialStatus,
  });

  final HttpHostConfig? existing;
  final String? initialOrigin;
  final String? initialName;

  @visibleForTesting
  final HostLinkStatus? initialStatus;

  @override
  ConsumerState<HttpHostFormPage> createState() => _HttpHostFormPageState();
}

class _HttpHostFormPageState extends ConsumerState<HttpHostFormPage> {
  late final String _id = widget.existing?.id ?? HttpHostConfig.newId();
  late final _name = TextEditingController(
    text: widget.existing?.name ?? widget.initialName ?? '',
  );
  late final _address = TextEditingController(
    text: widget.existing?.origin ?? widget.initialOrigin ?? '',
  );

  bool _saving = false;
  String? _formError;
  String? _addressError;
  HttpHostLink? _test;
  StreamSubscription<HostLinkStatus>? _testSub;
  late HostLinkStatus? _testStatus = widget.initialStatus;

  bool get _editing => widget.existing != null;

  late String _clean;
  late final Listenable _edits = Listenable.merge([_name, _address]);

  String _signature() => jsonEncode({
        'name': _name.text,
        'address': _address.text,
      });

  @override
  void initState() {
    super.initState();
    _clean = _signature();
  }

  @override
  void dispose() {
    unawaited(_testSub?.cancel());
    unawaited(_test?.close());
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  HttpHostInput? _parsedAddress() {
    final raw = _address.text.trim();
    if (raw.isEmpty) return null;
    return parseHttpHostInput(raw) ?? parseHttpHostPairing(raw);
  }

  HttpHostConfig? _draft() {
    final parsed = _parsedAddress();
    if (parsed == null) {
      setState(() {
        _addressError = context.l10n.remoteSshAddressRequired;
        _formError = null;
      });
      return null;
    }
    setState(() => _addressError = null);
    final name = _name.text.trim().isEmpty
        ? (parsed.suggestedName ?? defaultNameForOrigin(parsed.origin))
        : _name.text.trim();
    return HttpHostConfig(id: _id, name: name, origin: parsed.origin);
  }

  Future<void> _runTest() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final config = _draft();
    if (config == null) return;
    await _testSub?.cancel();
    await _test?.close();
    final link = HttpHostLink(
      config: config,
      secrets: ref.read(secretStoreProvider),
      retryFirstOpen: false,
    );
    _test = link;
    setState(() => _testStatus = const HostLinkStatus(HostLinkPhase.connecting, step: HostLinkStep.connect));
    _testSub = link.statuses.listen((s) {
      if (mounted && s.phase != HostLinkPhase.idle) setState(() => _testStatus = s);
    });
    try {
      await link.open();
      // Bare `host:port` may have been upgraded http→https (樱花 HTTPS tunnel).
      if (mounted && link.config.origin != config.origin) {
        _address.text = link.config.origin;
        _clean = _signature();
      }
    } catch (_) {
      // Shown in the progress card.
    } finally {
      await _testSub?.cancel();
      _testSub = null;
      if (identical(_test, link)) _test = null;
      await link.close();
    }
  }

  Future<void> _save({bool connect = false}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final config = _draft();
    if (config == null) return;
    setState(() => _saving = true);
    try {
      final saved = await ref.read(hostsProvider.notifier).saveHttp(config);
      if (!mounted) return;
      if (connect) {
        final ok = await activateHost(context, ref, HostRef.http(saved.id));
        if (!mounted) return;
        if (ok) {
          // Leave settings stack so LocalHostShell shows the HTTP Face.
          Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
          return;
        }
      }
      Navigator.of(context).pop(saved);
    } catch (_) {
      if (mounted) setState(() => _formError = context.l10n.commonSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final name = widget.existing!.name;
    final ok = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(context.l10n.remoteDeleteHostTitle(name)),
        content: Text(context.l10n.remoteDeleteHostBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(context.l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: XrkColors.of(dialog).danger,
              foregroundColor: XrkColors.of(dialog).onDanger,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(hostsProvider.notifier).removeHttp(_id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final testing = _test != null;
    final mono = AppType.mono(size: 15, color: scheme.onSurface, height: 1.4);

    final page = AppPage.list(
      title: _editing ? l10n.remoteEditHost : '添加 HTTP 主机',
      subtitle: _editing ? null : const Text('连接电脑或公网上的 XRK Face；打开后按页面提示输入 PIN'),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSection(
              title: l10n.remoteHostBasicInfo,
              children: [
                FormFieldGroup(
                  children: [
                    FormFieldBlock(
                      label: l10n.commonName,
                      child: TextField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(hintText: l10n.remoteHostNameHint),
                      ),
                    ),
                    FormFieldBlock(
                      error: _addressError,
                      label: '地址',
                      child: TextField(
                        controller: _address,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.done,
                        style: mono,
                        onChanged: (_) {
                          if (_addressError != null) setState(() => _addressError = null);
                        },
                        decoration: InputDecoration(
                          hintText: '192.168.1.20:8787 或 https://…',
                          error: _addressError == null ? null : const SizedBox.shrink(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        '可直接粘贴内网穿透给的 host:port；若对端只认 HTTPS，会自动改用 https 并接受自签证书。PIN 在打开后的 Host 页面填写。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: XrkColors.of(context).textTertiary,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_testStatus != null) ...[
              const SizedBox(height: 12),
              LinkProgressCard(
                status: _testStatus!,
                steps: const [HostLinkStep.connect],
                onRetry: testing ? null : () => unawaited(_runTest()),
              ),
            ],
            if (_formError != null) ...[
              const SizedBox(height: 8),
              Text(_formError!, style: TextStyle(color: XrkColors.of(context).danger)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: testing || _saving ? null : () => unawaited(_runTest()),
              child: Text(l10n.remoteTestConnection),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: testing || _saving ? null : () => unawaited(_save(connect: true)),
              child: Text(_saving ? '…' : '保存并连接'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: testing || _saving ? null : () => unawaited(_save()),
              child: Text(l10n.commonSave),
            ),
            if (_editing) ...[
              const SizedBox(height: 24),
              TextButton(
                onPressed: testing || _saving ? null : () => unawaited(_delete()),
                child: Text(l10n.commonDelete, style: TextStyle(color: XrkColors.of(context).danger)),
              ),
            ],
          ],
        ),
      ],
    );

    return DiscardGuard(
      listenable: _edits,
      isDirty: () => !_saving && _signature() != _clean,
      child: page,
    );
  }
}
