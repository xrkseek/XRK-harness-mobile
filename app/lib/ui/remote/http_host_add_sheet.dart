import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../l10n/l10n.dart';
import '../../remote/http/http_host_parse.dart';
import '../common/app_sheet.dart';
import '../common/sheet_title_bar.dart';
import '../settings/settings_widgets.dart';
import '../theme/app_icons.dart';
import 'http_host_form.dart';

/// Choose how to add an HTTP Face host: type an address or scan a QR.
Future<void> showHttpHostAddSheet(BuildContext context) {
  return showAppSheet<void>(
    context,
    builder: (sheet) => const _HttpHostAddSheet(),
  );
}

class _HttpHostAddSheet extends StatelessWidget {
  const _HttpHostAddSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitleBar('添加 HTTP 主机'),
          SheetGroup(
            margin: const EdgeInsets.fromLTRB(SheetTitleBar.inset, 0, SheetTitleBar.inset, 12),
            children: [
              SettingsTile(
                icon: AppIcons.webConsole,
                tinted: false,
                title: '输入地址',
                subtitle: '如 http://192.168.1.20:8787',
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(builder: (_) => const HttpHostFormPage()),
                    ),
                  );
                },
              ),
              SettingsTile(
                icon: AppIcons.qrCode,
                tinted: false,
                title: '扫描二维码',
                subtitle: '含主机地址的分享码',
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_openScanner(context));
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

Future<void> _openScanner(BuildContext context) async {
  final raw = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const _HttpQrScanPage()),
  );
  if (raw == null || !context.mounted) return;
  await _openFromRaw(context, raw);
}

Future<void> _openFromRaw(BuildContext context, String raw) async {
  final parsed = parseHttpHostInput(raw) ?? parseHttpHostPairing(raw);
  if (parsed == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.remoteSshAddressRequired)),
      );
    }
    return;
  }
  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => HttpHostFormPage(
        initialOrigin: parsed.origin,
        initialName: parsed.suggestedName,
      ),
    ),
  );
}

class _HttpQrScanPage extends StatefulWidget {
  const _HttpQrScanPage();

  @override
  State<_HttpQrScanPage> createState() => _HttpQrScanPageState();
}

class _HttpQrScanPageState extends State<_HttpQrScanPage> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  var _reported = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _report(BarcodeCapture capture) {
    if (_reported) return;
    for (final code in capture.barcodes) {
      final text = code.rawValue;
      if (text == null || text.isEmpty) continue;
      _reported = true;
      unawaited(_controller.stop());
      Navigator.of(context).pop(text);
      return;
    }
  }

  Future<void> _fromImage() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    } catch (_) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.remotePairImageNoCode)));
      return;
    }
    if (picked == null || !mounted) return;
    BarcodeCapture? capture;
    try {
      capture = await _controller.analyzeImage(picked.path, formats: const [BarcodeFormat.qrCode]);
    } catch (_) {
      capture = null;
    }
    if (!mounted) return;
    if (capture == null || capture.barcodes.every((b) => (b.rawValue ?? '').isEmpty)) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.remotePairImageNoCode)));
      return;
    }
    _report(capture);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l10n.remotePairFromImage,
            onPressed: () => unawaited(_fromImage()),
            icon: const Icon(AppIcons.gallery),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _report,
        errorBuilder: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? l10n.remotePairCameraDenied
                  : l10n.remotePairCameraFailed,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
