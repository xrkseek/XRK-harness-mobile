import 'dart:math' as math;

/// One saved HTTP Face host (Desktop share / `xrkh serve` on a reachable IP).
///
/// Persisted as JSON in SharedPreferences. Session cookies live in
/// [SecretStore] under [HttpHostSecrets], never here.
class HttpHostConfig {
  const HttpHostConfig({
    required this.id,
    required this.name,
    required this.origin,
  });

  /// Stable id (`http-<hex>`); also the secret-store namespace.
  final String id;

  /// What the person calls it ("家里的电脑", "公网 8787").
  final String name;

  /// Canonical origin, e.g. `http://103.236.89.174:8787` (no path, no trailing slash).
  final String origin;

  /// Fields that require a new probe / cookie jar when they change (name does not).
  String get connectionKey => origin;

  Uri get originUri => Uri.parse(origin);

  HttpHostConfig copyWith({String? name, String? origin}) => HttpHostConfig(
        id: id,
        name: name ?? this.name,
        origin: origin ?? this.origin,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'origin': origin,
      };

  static HttpHostConfig? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final origin = raw['origin'];
    if (id is! String || origin is! String || id.isEmpty || origin.isEmpty) return null;
    final normalized = normalizeHttpOrigin(origin);
    if (normalized == null) return null;
    final name = raw['name'];
    return HttpHostConfig(
      id: id,
      name: name is String && name.trim().isNotEmpty ? name.trim() : defaultNameForOrigin(normalized),
      origin: normalized,
    );
  }

  static String newId() {
    final n = math.Random.secure().nextInt(0x7fffffff);
    return 'http-${n.toRadixString(16).padLeft(8, '0')}';
  }
}

/// Cookie / device-session keys for one [HttpHostConfig.id].
abstract final class HttpHostSecrets {
  static String deviceTokenKey(String id) => 'http.$id.device';
  static String sessionTokenKey(String id) => 'http.$id.session';
  static String csrfTokenKey(String id) => 'http.$id.csrf';
}

/// Strip path/query/fragment; require http(s); no trailing slash.
String? normalizeHttpOrigin(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (!text.contains('://')) {
    text = 'http://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.host.isEmpty) return null;
  final port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  final defaultPort = uri.scheme == 'https' ? 443 : 80;
  final authority = port == defaultPort ? uri.host : '${uri.host}:$port';
  return '${uri.scheme}://$authority';
}

String defaultNameForOrigin(String origin) {
  final uri = Uri.tryParse(origin);
  if (uri == null || uri.host.isEmpty) return origin;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// Same origin after [normalizeHttpOrigin] (case-insensitive host).
bool sameHttpOrigin(String a, String b) {
  final na = normalizeHttpOrigin(a);
  final nb = normalizeHttpOrigin(b);
  if (na == null || nb == null) return false;
  return na.toLowerCase() == nb.toLowerCase();
}
