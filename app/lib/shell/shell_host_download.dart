// Host WebView session-log / attachment downloads: Android WebView ignores
// `<a download>`, and webview_flutter turns DownloadListener into a navigation
// that is dropped when `onNavigationRequest` is null. The thin shell catches
// `XrkShell` `{op:'download'}` (and injects an `<a download>` click shim) then
// GETs the URL with WebView cookies, saves under Downloads/XRK-Harness, and
// offers open-with / share.
//
// Desktop Electron and ordinary browsers never inject `XrkShell` — Host
// `downloadUrl` keeps using `<a download>` there. Guest Termux-in-container
// without the Flutter shell also stays on `<a download>` / browser DL.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n/l10n.dart';
import '../state/artifacts.dart';
import '../ui/common/app_sheet.dart';
import '../ui/common/brief_notice.dart';
import '../ui/common/list_page_row.dart';
import '../ui/theme/app_icons.dart';

/// True when [url] is the Host session-log ZIP route (DownloadListener fallback).
bool isHostSessionExportUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final path = uri.path;
  return path == '/api/session.export' ||
      path == '/api/face/session.export' ||
      path.endsWith('/session.export');
}

/// True when [url] is a document-local object URL the shell cannot HTTP-GET.
bool isObjectDownloadUrl(String url) {
  final t = url.trim().toLowerCase();
  return t.startsWith('blob:') || t.startsWith('data:');
}

/// Resolve a Host download URL against the WebView page when [url] is relative.
Uri resolveHostDownloadUri(String url, {String? pageUrl}) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    throw StateError('下载地址为空');
  }
  if (isObjectDownloadUrl(trimmed)) {
    // Flutter HttpClient cannot fetch blob:/data:; Host must send downloadBytes.
    throw StateError('附件需经壳内字节通道导出（勿把 blob: 当 HTTP 地址）');
  }
  final parsed = Uri.parse(trimmed);
  if (parsed.hasScheme) return parsed;
  final baseRaw = pageUrl?.trim();
  if (baseRaw == null || baseRaw.isEmpty) {
    throw StateError('相对下载地址缺少当前页 URL');
  }
  final base = Uri.tryParse(baseRaw);
  if (base == null || !base.hasScheme) {
    throw StateError('相对下载地址无法解析');
  }
  return base.resolveUri(parsed);
}

String hostDownloadFilename(String url, String? suggested) {
  final fromShell = suggested?.trim();
  if (fromShell != null && fromShell.isNotEmpty) {
    return fromShell.replaceAll(RegExp(r'[/\\]'), '_');
  }
  final uri = Uri.tryParse(url);
  final sessionId = uri?.queryParameters['sessionId']?.trim();
  if (sessionId != null && sessionId.isNotEmpty) {
    final safe = sessionId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'xrk-session-$safe.zip';
  }
  final last = uri?.pathSegments.isNotEmpty == true ? uri!.pathSegments.last : 'download.bin';
  return last.isEmpty ? 'download.bin' : last;
}

/// Injected after every Host page load so detached `a[download].click()` still
/// reaches the shell even before a rebuilt Host bundle lands in the guest.
const hostDownloadBridgeJs = r'''
(function(){
  if (window.__xrkDownloadBridge) return;
  window.__xrkDownloadBridge = true;
  function shell() {
    return (typeof XrkShell !== 'undefined' && XrkShell && typeof XrkShell.postMessage === 'function') ? XrkShell : null;
  }
  function b64(bytes) {
    var chunk = 0x8000, binary = '', i = 0;
    for (; i < bytes.length; i += chunk) {
      binary += String.fromCharCode.apply(null, bytes.subarray(i, Math.min(i + chunk, bytes.length)));
    }
    return btoa(binary);
  }
  function postBytes(filename, mime, bytes) {
    var s = shell();
    if (!s) return false;
    s.postMessage(JSON.stringify({
      op: 'downloadBytes',
      filename: String(filename || 'download.bin'),
      mime: String(mime || 'application/octet-stream'),
      base64: b64(bytes)
    }));
    return true;
  }
  function post(url, filename) {
    var s = shell();
    if (!s) return false;
    try {
      var u = String(url || '');
      var name = String(filename || '');
      if (u.indexOf('blob:') === 0 || u.indexOf('data:') === 0) {
        fetch(u).then(function(r) {
          if (!r.ok) throw new Error('HTTP ' + r.status);
          return r.blob();
        }).then(function(blob) {
          return blob.arrayBuffer().then(function(buf) {
            var mime = (blob.type || 'application/octet-stream').split(';')[0] || 'application/octet-stream';
            postBytes(name, mime, new Uint8Array(buf));
          });
        }).catch(function(err) {
          try {
            s.postMessage(JSON.stringify({
              op: 'downloadError',
              message: String(err && err.message ? err.message : err),
              filename: name
            }));
          } catch (e) {}
        });
        return true;
      }
      s.postMessage(JSON.stringify({op:'download', url:u, filename:name}));
      return true;
    } catch (e) {}
    return false;
  }
  var proto = HTMLAnchorElement.prototype;
  var orig = proto.click;
  proto.click = function() {
    if (this.hasAttribute('download') && this.href) {
      if (post(this.href, this.getAttribute('download') || '')) return;
    }
    return orig.apply(this, arguments);
  };
})();
''';

enum _AfterHostDownload { open, share }

/// Fetch [url] with WebView cookies → Downloads → optional open/share.
Future<void> handleHostShellDownload(
  BuildContext context, {
  required String url,
  String? filename,
  String? pageUrl,
  FilesChannel files = const FilesChannel(),
}) async {
  final l10n = context.l10n;
  showBriefNotice(context, l10n.featuresExportTitle);
  try {
    final uri = resolveHostDownloadUri(url, pageUrl: pageUrl);
    final name = hostDownloadFilename(uri.toString(), filename);
    final bytes = await _fetchWithWebViewCookies(uri);
    await _finishHostDownload(context, bytes: bytes, name: name, files: files);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${l10n.stateExportFailed}: ${_friendlyDownloadError(error)}')),
      );
    }
  }
}

/// Persist bytes already fetched in the WebView (blob:/data: → base64).
Future<void> handleHostShellDownloadBytes(
  BuildContext context, {
  required Uint8List bytes,
  required String filename,
  String? mime,
  FilesChannel files = const FilesChannel(),
}) async {
  final l10n = context.l10n;
  showBriefNotice(context, l10n.featuresExportTitle);
  try {
    final name = hostDownloadFilename('', filename);
    await _finishHostDownload(context, bytes: bytes, name: name, files: files, mime: mime);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('${l10n.stateExportFailed}: ${_friendlyDownloadError(error)}')),
      );
    }
  }
}

Future<void> _finishHostDownload(
  BuildContext context, {
  required Uint8List bytes,
  required String name,
  required FilesChannel files,
  String? mime,
}) async {
  final l10n = context.l10n;
  final cache = await getTemporaryDirectory();
  final root = await Directory('${cache.path}/host-downloads').create(recursive: true);
  final op = await root.createTemp('dl-');
  final file = File('${op.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  final resolvedMime = (mime != null && mime.trim().isNotEmpty) ? mime.trim() : _mimeFor(name);
  final where = await files.saveToDownloads(file.path, name: name, mime: resolvedMime);
  if (!context.mounted) return;
  final next = await showAppSheet<_AfterHostDownload>(
    context,
    builder: (sheet) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(l10n.featuresExportSavedTitle),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(l10n.featuresExportSavedTo(where), style: Theme.of(sheet).textTheme.bodyMedium),
          ),
          SheetGroup(
            children: [
              ListPageRow(
                icon: AppIcons.openExternal,
                title: l10n.featuresExportOpenOther,
                subtitle: l10n.featuresExportOpenHint,
                onTap: () => Navigator.pop(sheet, _AfterHostDownload.open),
              ),
              ListPageRow(
                icon: AppIcons.share,
                title: l10n.commonShare,
                subtitle: l10n.featuresExportShareHint,
                onTap: () => Navigator.pop(sheet, _AfterHostDownload.share),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (next == null) {
    showBriefNotice(context, l10n.featuresExportSavedTo(where));
    try {
      await op.delete(recursive: true);
    } catch (_) {}
    return;
  }
  try {
    switch (next) {
      case _AfterHostDownload.open:
        await files.open(file.path, name: name, mime: resolvedMime, chooser: true);
      case _AfterHostDownload.share:
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path, mimeType: resolvedMime, name: name)], fileNameOverrides: [name]),
        );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l10n.featuresExportOpenFailed)));
    }
  }
}

String _friendlyDownloadError(Object error) {
  if (error is SocketException) {
    return '网络不可达（${error.message}）';
  }
  if (error is TimeoutException) {
    return '下载超时';
  }
  if (error is HandshakeException) {
    return 'TLS 握手失败';
  }
  if (error is HttpException) {
    return error.message;
  }
  if (error is StateError) {
    return error.message;
  }
  return error.toString();
}

String _mimeFor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.zip')) return 'application/zip';
  if (lower.endsWith('.json')) return 'application/json';
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
  if (lower.endsWith('.pdf')) return 'application/pdf';
  if (lower.endsWith('.md') || lower.endsWith('.txt')) return 'text/plain';
  return 'application/octet-stream';
}

Future<Uint8List> _fetchWithWebViewCookies(Uri uri) async {
  final manager = WebViewCookieManager();
  // Prefer cookies for the exact Host origin; fall back to host-only lookup.
  var cookies = await manager.getCookies(domain: uri);
  if (cookies.isEmpty && uri.hasAuthority) {
    cookies = await manager.getCookies(
      domain: Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null),
    );
  }
  final header = cookies.map((c) => '${c.name}=${c.value}').join('; ');
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    if (header.isNotEmpty) req.headers.set(HttpHeaders.cookieHeader, header);
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    final res = await req.close().timeout(const Duration(seconds: 120));
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = await res.transform(utf8.decoder).join();
      final snippet = body.trim();
      final short = snippet.length > 160 ? '${snippet.substring(0, 160)}…' : snippet;
      throw StateError('HTTP ${res.statusCode}${short.isEmpty ? '' : ': $short'}');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in res) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  } finally {
    client.close(force: true);
  }
}
