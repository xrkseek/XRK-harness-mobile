// The official session-log download (`/export`, "下载 Session 日志") for the
// app: the Host's ZIP of a conversation, handed to the share sheet or the
// phone's Downloads instead of a browser download.

import 'dart:io';
import 'dart:typed_data';

import 'package:xrk_client/xrk_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import 'artifacts.dart';
import 'connection_state.dart';

/// A ZIP written under the app cache so share / open / Downloads can all use
/// one immutable file before [dispose].
class SessionLogArchive {
  SessionLogArchive._(this.file, this.name, this._root);

  /// Test-only: a pre-written cache ZIP the page can open/share without Host HTTP.
  @visibleForTesting
  factory SessionLogArchive.testing(File file, String name, Directory root) =>
      SessionLogArchive._(file, name, root);

  final File file;
  final String name;
  final Directory _root;

  static const mime = SessionLogExporter.mime;

  Future<void> dispose() async {
    try {
      await _root.delete(recursive: true);
    } catch (_) {
      // An undeletable temporary directory remains in the app cache.
    }
  }
}

class SessionLogExporter {
  SessionLogExporter({
    required this.connection,
    required this.channel,
    Future<void> Function(ShareParams params)? share,
    Future<Directory> Function()? cacheRoot,
  }) : _share = share ?? _systemShare,
       _cacheRoot = cacheRoot ?? getTemporaryDirectory;

  final HostConnection? connection;
  final FilesChannel channel;
  final Future<void> Function(ShareParams params) _share;
  final Future<Directory> Function() _cacheRoot;

  static const mime = 'application/zip';

  static Future<void> _systemShare(ShareParams params) async {
    await SharePlus.instance.share(params);
  }

  /// False over the relay tunnel: the download is an HTTP route.
  bool get supported => connection?.client.canExportSessionLog ?? false;

  /// Fetches the Host ZIP once into a disposable cache file.
  Future<SessionLogArchive> materialize(String sessionId) async {
    final conn = connection;
    if (conn == null) throw const XrkTransportException('offline');
    final bytes = await conn.client.exportSessionLog(sessionId);
    return _write(bytes, sessionLogZipName(sessionId));
  }

  Future<SessionLogArchive> _write(Uint8List bytes, String name) async {
    final root = await _cacheRoot();
    final exports = await Directory('${root.path}/exports').create(recursive: true);
    final operation = await exports.createTemp('save-');
    final file = File('${operation.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return SessionLogArchive._(file, name, operation);
  }

  /// The system share sheet with this export's own archive.
  Future<void> share(String sessionId) async {
    final archive = await materialize(sessionId);
    try {
      await shareArchive(archive);
    } finally {
      await archive.dispose();
    }
  }

  Future<void> shareArchive(SessionLogArchive archive) => _share(
        ShareParams(
          files: [XFile(archive.file.path, mimeType: mime, name: archive.name)],
          fileNameOverrides: [archive.name],
        ),
      );

  /// Copies into Downloads (`Download/XRK-Harness/…`); returns the shown path.
  /// Caller keeps [archive] until open/share finishes, then [SessionLogArchive.dispose].
  Future<String> saveArchiveToDownloads(SessionLogArchive archive) =>
      channel.saveToDownloads(archive.file.path, name: archive.name, mime: mime);

  /// Fetch once, copy to Downloads, keep the cache file for open/share.
  Future<({SessionLogArchive archive, String where})> saveKeepingArchive(String sessionId) async {
    final archive = await materialize(sessionId);
    try {
      final where = await saveArchiveToDownloads(archive);
      return (archive: archive, where: where);
    } catch (error) {
      await archive.dispose();
      rethrow;
    }
  }

  /// Copies the archive into the phone's Downloads; returns where.
  Future<String> saveToDownloads(String sessionId) async {
    final saved = await saveKeepingArchive(sessionId);
    try {
      return saved.where;
    } finally {
      await saved.archive.dispose();
    }
  }

  /// Opens the local ZIP with another app (chooser). Uses the cache file, not
  /// the MediaStore display path — Downloads paths are not openable that way.
  Future<void> openArchive(SessionLogArchive archive, {bool chooser = true}) =>
      channel.open(archive.file.path, name: archive.name, mime: mime, chooser: chooser);
}

/// What went wrong, in words.
String sessionExportErrorText(Object error) {
  final code = switch (error) {
    XrkRemoteException(:final code) => code,
    PlatformException(:final code) => code,
    XrkTransportException() || DshCarrierLostException() || DshClosedException() => 'offline',
    _ => '',
  };
  return switch (code) {
    'session-export/unsupported' => appL10n.stateExportRelayUnsupported,
    'session-export/http-404' => appL10n.stateExportChatMissing,
    'permission' => appL10n.stateStoragePermission,
    'offline' => appL10n.commonEngineUnreachable,
    'no_app' => appL10n.featuresExportOpenFailed,
    _ when code.startsWith('session-export/http-') => appL10n.stateExportFailed,
    _ => appL10n.stateExportFailed,
  };
}

final sessionLogExporterProvider = Provider<SessionLogExporter>(
  (ref) => SessionLogExporter(
    connection: ref.watch(activeConnectionProvider).value,
    channel: ref.watch(filesChannelProvider),
  ),
);
