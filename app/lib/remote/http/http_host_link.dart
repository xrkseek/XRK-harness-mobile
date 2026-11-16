import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../l10n/l10n.dart';
import '../link_status.dart';
import '../secret_store.dart';
import 'http_host_config.dart';

/// Cookie jar the WebView needs after a successful native-pair / renew / PIN.
class HttpHostSession {
  const HttpHostSession({
    required this.deviceToken,
    required this.sessionToken,
    this.csrfToken,
    this.lanPinCookie = '',
    this.wanPinCookie = '',
  });

  final String deviceToken;
  final String sessionToken;
  final String? csrfToken;

  /// LAN / WAN PIN digests — Face gate often has only these (no dsh_ma_device).
  final String lanPinCookie;
  final String wanPinCookie;

  /// Paired device + session (native-pair / renew).
  bool get isReady => deviceToken.isNotEmpty && sessionToken.isNotEmpty;

  /// Enough for phone-bridge ticket (PIN-only Face included).
  bool get hasOperatorProof =>
      isReady ||
      sessionToken.isNotEmpty ||
      lanPinCookie.isNotEmpty ||
      wanPinCookie.isNotEmpty;
}

/// Connects to an HTTP Face host (Desktop share / `xrkh serve` on a reachable IP).
///
/// Probe → optional native-pair / renew → [connected]. No [XrkClient]; the shell
/// loads the Face URL in a WebView with the session cookies.
class HttpHostLink {
  HttpHostLink({
    required HttpHostConfig config,
    required SecretStore secrets,
    this.pairingToken,
    this.deviceLabel,
    this.httpClient,
    Stream<void>? kicks,
    this.retryFirstOpen = true,
  })  : _config = config,
        _secrets = secrets,
        _kicks = kicks ?? const Stream.empty();

  HttpHostConfig _config;
  final SecretStore _secrets;
  final String? pairingToken;
  final String? deviceLabel;
  final http.Client? httpClient;
  final Stream<void> _kicks;
  final bool retryFirstOpen;

  final _statuses = StreamController<HostLinkStatus>.broadcast(sync: true);
  final _delay = InterruptibleDelay();
  final _backoff = Backoff();
  StreamSubscription<void>? _kickSub;
  HostLinkStatus _status = HostLinkStatus.idle;
  HttpHostSession? _session;
  Future<HttpHostSession>? _opening;
  bool _closed = false;
  bool _recovering = false;
  /// Reused across probe / pair / renew — WAN TLS handshakes are expensive.
  http.Client? _ownedClient;

  static const deviceCookie = 'dsh_ma_device';
  static const sessionCookie = 'dsh_ma_session';
  static const csrfCookie = 'dsh_ma_csrf';
  static const lanPinCookie = 'dsh_ma_lan';
  static const wanPinCookie = 'dsh_ma_wan';
  static const operatorUiCookie = 'xrk_operator_ui';

  HttpHostConfig get config => _config;

  HttpHostSession? get session => _status.isConnected ? _session : null;

  /// Face entry URL once connected (origin root).
  Uri? get faceUri => _status.isConnected ? Uri.parse('${_config.origin}/') : null;

  HostLinkStatus get status => _status;

  Stream<HostLinkStatus> get statuses => _statuses.stream;

  void updateConfig(HttpHostConfig next) {
    _config = _config.copyWith(name: next.name, origin: next.origin);
  }

  http.Client get _http => httpClient ?? (_ownedClient ??= http.Client());

  void _emit(HostLinkStatus next) {
    if (_closed && next.phase != HostLinkPhase.idle) return;
    _status = next;
    _statuses.add(next);
  }

  Future<HttpHostSession> open() {
    if (_closed) return Future.error(StateError('link closed'));
    final ready = _session;
    if (ready != null && _status.isConnected) return Future.value(ready);
    return _opening ??= _openFirst().whenComplete(() => _opening = null);
  }

  Future<HttpHostSession> _openFirst() async {
    _backoff.reset();
    _emit(const HostLinkStatus(HostLinkPhase.connecting, step: HostLinkStep.connect));
    _kickSub ??= _kicks.listen((_) => kick());
    try {
      return await _connectOnce();
    } on HostLinkError catch (e) {
      if (!e.retryable || !retryFirstOpen) {
        _fail(e);
        rethrow;
      }
      return _recover(e);
    } catch (e) {
      final error = HostLinkError(
        HostLinkErrorKind.other,
        appL10n.commonConnectionFailed,
        detail: '$e',
        retryable: true,
      );
      if (!retryFirstOpen) {
        _fail(error);
        throw error;
      }
      return _recover(error);
    }
  }

  Future<HttpHostSession> _connectOnce() async {
    _emit(_status.withStep(HostLinkStep.connect, detail: appL10n.remoteStepConnect));
    await _probe();

    // Optional native-pair / renew only when a token or stored jar exists.
    // Bare URL: connect after probe; Face WAN/LAN PIN runs inside the WebView.
    final hasToken = (pairingToken?.trim().isNotEmpty ?? false);
    final stored = await _loadSecrets();
    if (hasToken || (stored != null && stored.isReady)) {
      _emit(_status.withStep(HostLinkStep.login));
    }
    final session = await _ensureSession();
    _session = session;
    _emit(const HostLinkStatus(HostLinkPhase.connected));
    return session;
  }

  Future<void> _probe() async {
    final uri = Uri.parse('${_config.origin}/mobile-access/health');
    try {
      final res = await _http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HostLinkError(
          HostLinkErrorKind.unreachable,
          appL10n.commonConnectionFailed,
          detail: 'health ${res.statusCode}',
          retryable: true,
        );
      }
      final body = jsonDecode(res.body);
      if (body is Map && body['ok'] != true) {
        throw HostLinkError(
          HostLinkErrorKind.unavailable,
          appL10n.commonConnectionFailed,
          detail: 'health not ok',
          retryable: true,
        );
      }
    } on HostLinkError {
      rethrow;
    } on TimeoutException {
      throw HostLinkError(
        HostLinkErrorKind.unreachable,
        appL10n.commonConnectionFailed,
        detail: 'health timeout',
        retryable: true,
      );
    } catch (e) {
      if (e is HostLinkError) rethrow;
      throw HostLinkError(
        HostLinkErrorKind.unreachable,
        appL10n.commonConnectionFailed,
        detail: '$e',
        retryable: true,
      );
    }
  }

  Future<HttpHostSession> _ensureSession() async {
    final stored = await _loadSecrets();
    if (stored != null && stored.isReady) {
      final renewed = await _tryRenew(stored);
      if (renewed != null) return renewed;
    }
    final token = pairingToken?.trim();
    if (token != null && token.isNotEmpty) {
      return _nativePair(token);
    }
    if (stored != null && stored.isReady) {
      // Stored cookies may still work in WebView even if renew failed offline.
      return stored;
    }
    // No native-pair token: open Face anyway. WAN/LAN PIN pages set cookies
    // inside the WebView; the shell loads origin without injecting a jar.
    return const HttpHostSession(deviceToken: '', sessionToken: '');
  }

  Future<HttpHostSession?> _loadSecrets() async {
    try {
      final device = await _secrets.read(HttpHostSecrets.deviceTokenKey(_config.id));
      final session = await _secrets.read(HttpHostSecrets.sessionTokenKey(_config.id));
      final csrf = await _secrets.read(HttpHostSecrets.csrfTokenKey(_config.id));
      if (device == null || device.isEmpty || session == null || session.isEmpty) return null;
      return HttpHostSession(deviceToken: device, sessionToken: session, csrfToken: csrf);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(HttpHostSession session) async {
    await _secrets.write(HttpHostSecrets.deviceTokenKey(_config.id), session.deviceToken);
    await _secrets.write(HttpHostSecrets.sessionTokenKey(_config.id), session.sessionToken);
    final csrf = session.csrfToken;
    if (csrf == null || csrf.isEmpty) {
      await _secrets.delete(HttpHostSecrets.csrfTokenKey(_config.id));
    } else {
      await _secrets.write(HttpHostSecrets.csrfTokenKey(_config.id), csrf);
    }
  }

  Future<HttpHostSession> _nativePair(String token) async {
    final uri = Uri.parse('${_config.origin}/mobile-access/auth/native-pair');
    try {
      final res = await _http
          .post(
            uri,
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'token': token,
              if (deviceLabel != null && deviceLabel!.trim().isNotEmpty) 'label': deviceLabel!.trim(),
            }),
          )
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 401) {
        throw HostLinkError(
          HostLinkErrorKind.authFailed,
          appL10n.commonSignIn,
          detail: 'native-pair 401',
          retryable: false,
        );
      }
      if (res.statusCode == 409) {
        throw HostLinkError(
          HostLinkErrorKind.unavailable,
          appL10n.commonConnectionFailed,
          detail: 'mobile access not running',
          retryable: true,
        );
      }
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw HostLinkError(
          HostLinkErrorKind.loginFailed,
          appL10n.commonSignIn,
          detail: 'native-pair ${res.statusCode}',
          retryable: true,
        );
      }
      final body = jsonDecode(res.body);
      if (body is! Map) {
        throw HostLinkError(HostLinkErrorKind.loginFailed, appL10n.commonSignIn, detail: 'bad body');
      }
      final deviceToken = '${body['deviceToken'] ?? ''}'.trim();
      final sessionToken = '${body['sessionToken'] ?? ''}'.trim();
      final csrfToken = '${body['csrfToken'] ?? ''}'.trim();
      if (deviceToken.isEmpty || sessionToken.isEmpty) {
        throw HostLinkError(HostLinkErrorKind.loginFailed, appL10n.commonSignIn, detail: 'missing tokens');
      }
      final session = HttpHostSession(
        deviceToken: deviceToken,
        sessionToken: sessionToken,
        csrfToken: csrfToken.isEmpty ? null : csrfToken,
      );
      await _persist(session);
      return session;
    } on HostLinkError {
      rethrow;
    } on TimeoutException {
      throw HostLinkError(
        HostLinkErrorKind.unreachable,
        appL10n.commonConnectionFailed,
        detail: 'native-pair timeout',
        retryable: true,
      );
    } catch (e) {
      if (e is HostLinkError) rethrow;
      throw HostLinkError(
        HostLinkErrorKind.loginFailed,
        appL10n.commonSignIn,
        detail: '$e',
        retryable: true,
      );
    }
  }

  Future<HttpHostSession?> _tryRenew(HttpHostSession stored) async {
    final uri = Uri.parse('${_config.origin}/mobile-access/auth/renew');
    try {
      final res = await _http
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'cookie': '$deviceCookie=${Uri.encodeComponent(stored.deviceToken)}',
            },
            body: '{}',
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      // Set-Cookie may refresh session; fall back to stored if absent.
      final cookies = _parseSetCookie(res.headers['set-cookie']);
      final nextSession = cookies[sessionCookie] ?? stored.sessionToken;
      final nextCsrf = cookies[csrfCookie] ?? stored.csrfToken;
      final next = HttpHostSession(
        deviceToken: stored.deviceToken,
        sessionToken: nextSession,
        csrfToken: nextCsrf,
      );
      await _persist(next);
      return next;
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _parseSetCookie(String? header) {
    if (header == null || header.isEmpty) return const {};
    final out = <String, String>{};
    // dart:http may join multiple Set-Cookie with commas; split carefully on name=.
    for (final part in header.split(RegExp(r',(?=\s*[^;=]+=)'))) {
      final first = part.split(';').first.trim();
      final eq = first.indexOf('=');
      if (eq <= 0) continue;
      out[first.substring(0, eq).trim()] = first.substring(eq + 1).trim();
    }
    return out;
  }

  void _fail(HostLinkError error) {
    _emit(HostLinkStatus(HostLinkPhase.failed, step: _status.step, completed: _status.completed, error: error));
  }

  Future<HttpHostSession> _recover(HostLinkError error) async {
    if (_recovering) throw error;
    _recovering = true;
    try {
      while (!_closed) {
        if (_backoff.exhausted) {
          _fail(error);
          throw error;
        }
        final wait = _backoff.next();
        _emit(
          HostLinkStatus(
            HostLinkPhase.reconnecting,
            step: _status.step,
            completed: _status.completed,
            error: error,
            attempt: _backoff.attempt,
            nextRetryAt: DateTime.now().add(wait),
          ),
        );
        await _delay.wait(wait);
        if (_closed) throw error;
        try {
          return await _connectOnce();
        } on HostLinkError catch (e) {
          if (!e.retryable) {
            _fail(e);
            throw e;
          }
          error = e;
        }
      }
      throw error;
    } finally {
      _recovering = false;
    }
  }

  void kick() => _delay.skip();

  void retry() {
    if (_closed) return;
    if (_status.phase == HostLinkPhase.reconnecting) {
      _delay.skip();
      return;
    }
    if (_status.phase == HostLinkPhase.failed) {
      _opening = null;
      _session = null;
      unawaited(open().catchError((_) => const HttpHostSession(deviceToken: '', sessionToken: '')));
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _kickSub?.cancel();
    _kickSub = null;
    _delay.cancel();
    _session = null;
    final owned = _ownedClient;
    _ownedClient = null;
    owned?.close();
    _emit(HostLinkStatus.idle);
    await _statuses.close();
  }
}
