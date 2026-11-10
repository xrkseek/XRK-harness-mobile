// Hosted conversation links (share host). Product builds leave this empty:
// install / update go through GitHub Releases (+ XRK's own site/worker).
// Wire a host with `--dart-define=XRK_SHARE_ORIGIN=https://…`, or in tests
// assign [shareHostOriginOverride].

const _shareHostOriginDefine = String.fromEnvironment('XRK_SHARE_ORIGIN');

/// Test-only override; empty in production.
String shareHostOriginOverride = '';

/// Share-host origin (`https://…`). Empty = hosted links / market pages off.
String get shareHostOrigin {
  final override = shareHostOriginOverride.trim();
  if (override.isNotEmpty) return override.replaceFirst(RegExp(r'/+$'), '');
  final defined = _shareHostOriginDefine.trim();
  if (defined.isEmpty) return '';
  return defined.replaceFirst(RegExp(r'/+$'), '');
}

/// Origins that count as hosted links. Empty when [shareHostOrigin] is unset.
List<String> get hostedOrigins => shareHostOrigin.isEmpty ? const <String>[] : <String>[shareHostOrigin];
