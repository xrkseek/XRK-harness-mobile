// Older app versions could save the session-only Auto preset as the default
// for new chats (`permission.defaultPreset: auto`; #26 stopped offering it).
// Under Cordis that lived in `profiles/web/cordis.patch.yml`. Under xrkh the
// Face settings document is `$XRK_HOME/settings.yaml`. The app clears a stale
// Auto default there and restarts the Host. A remote host is left alone.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaml/yaml.dart';

import '../runtime/runtime_state.dart';
import '../share_code/guest_fs.dart';
import 'engine_control.dart';

/// Face settings document where permission defaults live for xrkh.
const mainSettingsFile = '${GuestFs.xrkHome}/settings.yaml';

/// Takes a stored Auto default out of the on-device engine's settings and
/// restarts XRK so its permission presets load. Nothing to take out: nothing
/// happens, so this runs on every local connect and acts once.
Future<void> clearAutoDefaultPreset(ProviderContainer container) async {
  try {
    final file = (await container.read(guestFsProvider.future))?.file(mainSettingsFile);
    if (file == null || !file.existsSync()) return;
    final fixed = withoutAutoDefaultPreset(file.readAsStringSync());
    if (fixed == null) return;
    final tmp = File('${file.path}.xrk-mobile-tmp')..writeAsStringSync(fixed, flush: true);
    tmp.renameSync(file.path);
    debugPrint('Permissions: cleared the stored Auto default for new chats');
    // Safe mode runs its own profile; leaving it starts the fixed one.
    if (!container.read(localRuntimeProvider).status.inSafeMode) await EngineControl.restart(container);
  } catch (error) {
    // The next connect tries again.
    debugPrint('Permissions: could not clear the stored Auto default: $error');
  }
}

/// [text] without `defaultPreset: auto` under `permission` (settings.yaml map),
/// or null when there is none / layout is not one field per line.
String? withoutAutoDefaultPreset(String text) {
  final Object? doc;
  try {
    doc = loadYaml(text);
  } on YamlException {
    return null;
  }
  if (doc is! YamlMap) return null;
  final permission = doc.nodes['permission'];
  if (permission is! YamlMap || permission['defaultPreset'] != 'auto') return null;
  final keyNode = permission.nodes.keys.cast<YamlNode>().firstWhere((k) => k.value == 'defaultPreset');
  final valueNode = permission.nodes['defaultPreset']!;
  final key = keyNode.span.start.offset;
  final value = valueNode.span.end.offset;
  final start = text.lastIndexOf('\n', key) + 1;
  final newline = text.indexOf('\n', value);
  final end = newline < 0 ? text.length : newline + 1;
  final rest = text.substring(value, end).trim();
  if (text.substring(start, key).trim().isNotEmpty || rest.isNotEmpty && !rest.startsWith('#')) return null;
  return text.replaceRange(start, end, '');
}
