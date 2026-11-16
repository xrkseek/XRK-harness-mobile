import 'http_host_config.dart';

/// What a typed address or QR code decoded to.
class HttpHostInput {
  const HttpHostInput({
    required this.origin,
    this.suggestedName,
    this.pairingInstanceId,
    this.pairingToken,
    this.needsPinPage = false,
  });

  final String origin;
  final String? suggestedName;

  /// From `/mobile-access/pair#instance=…&token=…` or `dsh1.{instance}.{token}`.
  final String? pairingInstanceId;
  final String? pairingToken;

  /// QR / URL pointed at wan-pin / lan-pin — open PIN flow after save.
  final bool needsPinPage;

  bool get hasPairing =>
      pairingInstanceId != null &&
      pairingInstanceId!.isNotEmpty &&
      pairingToken != null &&
      pairingToken!.isNotEmpty;
}

/// Parse a typed URL/IP or a scanned QR into a normalized HTTP host input.
///
/// Accepts:
/// - `103.236.89.174:8787` / `http://host:port/` / https
/// - `…/mobile-access/wan-pin?…` / `lan-pin`
/// - `…/mobile-access/pair#instance=…&token=…`
/// - `dsh1.{instanceId}.{token}`
HttpHostInput? parseHttpHostInput(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  // `dsh1.{instance}.{token}` has no origin — use [parseHttpHostPairing] with
  // a typed address. Do not treat it as `http://dsh1…` hostname.
  if (text.startsWith('dsh1.')) return null;

  // Bare host:port without scheme — normalizeHttpOrigin adds http://.
  final asUri = text.contains('://') ? Uri.tryParse(text) : Uri.tryParse('http://$text');
  if (asUri == null || asUri.host.isEmpty) {
    final originOnly = normalizeHttpOrigin(text);
    if (originOnly == null) return null;
    return HttpHostInput(origin: originOnly, suggestedName: defaultNameForOrigin(originOnly));
  }

  final origin = normalizeHttpOrigin(asUri.origin);
  if (origin == null) return null;

  final path = asUri.path;
  final fragment = asUri.fragment;
  final isPinPage = path.contains('/mobile-access/wan-pin') || path.contains('/mobile-access/lan-pin');
  final isPairPage = path.contains('/mobile-access/pair');

  String? instanceId;
  String? token;
  if (isPairPage && fragment.isNotEmpty) {
    final params = Uri.splitQueryString(fragment);
    instanceId = params['instance']?.trim();
    token = params['token']?.trim();
  }

  return HttpHostInput(
    origin: origin,
    suggestedName: defaultNameForOrigin(origin),
    pairingInstanceId: instanceId,
    pairingToken: token,
    needsPinPage: isPinPage,
  );
}

/// Pair QR that includes origin, or `dsh1` plus a typed origin.
HttpHostInput? parseHttpHostPairing(String raw, {String? fallbackOrigin}) {
  final text = raw.trim();
  if (text.startsWith('dsh1.')) {
    if (fallbackOrigin == null) return null;
    final rest = text.substring(5);
    final dot = rest.indexOf('.');
    if (dot <= 0 || dot >= rest.length - 1) return null;
    final origin = normalizeHttpOrigin(fallbackOrigin);
    if (origin == null) return null;
    final instanceId = rest.substring(0, dot).trim();
    final token = rest.substring(dot + 1).trim();
    if (instanceId.isEmpty || token.isEmpty) return null;
    return HttpHostInput(
      origin: origin,
      suggestedName: defaultNameForOrigin(origin),
      pairingInstanceId: instanceId,
      pairingToken: token,
    );
  }
  return parseHttpHostInput(text);
}
