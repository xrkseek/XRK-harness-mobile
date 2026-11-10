// Hands the diagnostics bundle to the system share sheet
// (`SharePlus`). Product never dumps a silent copy into Downloads —
// people cannot find it.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/l10n.dart';
import 'diagnostics_bundle.dart';

/// Where an export is; the UI says it in words.
enum DiagnosticsStep { collecting, packing, sharing }

class DiagnosticsExporter {
  DiagnosticsExporter({
    required this.collect,
    Future<ShareResultStatus> Function(ShareParams params)? share,
    Future<Directory> Function()? cacheRoot,
    DateTime Function()? clock,
  }) : _share = share ?? _systemShare,
       _cacheRoot = cacheRoot ?? getTemporaryDirectory,
       _clock = clock ?? DateTime.now;

  final Future<DiagnosticsSnapshot> Function(DateTime at) collect;
  final Future<ShareResultStatus> Function(ShareParams params) _share;
  final Future<Directory> Function() _cacheRoot;
  final DateTime Function() _clock;

  static Future<ShareResultStatus> _systemShare(ShareParams params) async =>
      (await SharePlus.instance.share(params)).status;

  /// Builds the bundle into the app cache (`diagnostics/`, older bundles
  /// replaced) and returns it.
  Future<File> build({void Function(DiagnosticsStep step)? onStep}) => _build(onStep: onStep);

  Future<File> _build({void Function(DiagnosticsStep step)? onStep}) async {
    final at = _clock();
    onStep?.call(DiagnosticsStep.collecting);
    final snapshot = await collect(at);
    onStep?.call(DiagnosticsStep.packing);
    final bytes = DiagnosticsBundle.build(snapshot);
    final dir = Directory('${(await _cacheRoot()).path}/diagnostics');
    await dir.create(recursive: true);
    for (final old in dir.listSync().whereType<File>()) {
      if (old.path.endsWith('.zip')) old.deleteSync();
    }
    final file = File('${dir.path}/${DiagnosticsBundle.fileName(at)}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// The system share sheet with a fresh bundle; true when it was sent
  /// somewhere.
  Future<bool> share({void Function(DiagnosticsStep step)? onStep}) async {
    final file = await build(onStep: onStep);
    onStep?.call(DiagnosticsStep.sharing);
    final name = file.uri.pathSegments.last;
    final status = await _share(
      ShareParams(
        files: [XFile(file.path, mimeType: DiagnosticsBundle.mime, name: name)],
        fileNameOverrides: [name],
        subject: appL10n.stateDiagnosticsSubject,
      ),
    );
    return status == ShareResultStatus.success;
  }
}

/// What went wrong, in words.
String diagnosticsErrorText(Object error) => switch (error) {
  PlatformException(code: 'permission') => appL10n.stateStoragePermission,
  FileSystemException() => appL10n.stateDiagnosticsStorageFull,
  _ => appL10n.stateDiagnosticsExportFailed,
};

final diagnosticsExporterProvider = Provider<DiagnosticsExporter>(
  (ref) => DiagnosticsExporter(
    collect: (at) => collectDiagnostics(ref, at, includeSystemIme: true),
  ),
);
