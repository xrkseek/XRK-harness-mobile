import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../phone/phone_channel.dart';
import '../http/http_host_config.dart';
import '../http/http_host_link.dart';
import '../link_status.dart';
import 'remote_bridge_status.dart';

const _clientDeviceIdKey = 'phone_bridge.client_device_id';

/// Stable per-install id so PIN-only Face (no dsh_ma_device) can still ticket.
Future<String> ensureBridgeClientDeviceId() async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_clientDeviceIdKey)?.trim() ?? '';
  if (existing.length >= 8) return existing;
  final id =
      'xrk-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}-${Object().hashCode.toRadixString(36)}';
  await prefs.setString(_clientDeviceIdKey, id);
  return id;
}

/// Fingerprint Face operator cookies so the controller can restart on PIN remint.
String operatorProofFingerprint(HttpHostSession session) {
  return [
    session.deviceToken,
    session.sessionToken,
    session.lanPinCookie,
    session.wanPinCookie,
    session.csrfToken ?? '',
  ].join('|');
}

bool _isInvalidTicket(Map<String, dynamic>? out) =>
    out != null && '${out['error'] ?? ''}' == 'invalid-ticket';

/// Outbound long-poll client: Face operator cookies → Host phone-bridge → [PhoneChannel].
///
/// PIN-only Face is supported via LAN/WAN PIN cookies + [clientDeviceId].
class PhoneBridgeClient {
  PhoneBridgeClient({
    required this.origin,
    required HttpHostSession session,
    required this.phone,
    required this.clientDeviceId,
    this.label = 'XRK-phone',
    this.httpClient,
    bool pollEnabled = false,
  })  : _session = session,
        _pollEnabled = pollEnabled;

  final String origin;
  final PhoneChannel phone;
  final String clientDeviceId;
  final String label;
  final http.Client? httpClient;

  HttpHostSession _session;
  HttpHostSession get session => _session;

  bool _pollEnabled;
  bool get pollEnabled => _pollEnabled;
  set pollEnabled(bool value) {
    if (_pollEnabled == value) return;
    _pollEnabled = value;
    _wakeLoop();
    final snap = remoteBridgeStatus.value;
    if (!value &&
        (snap.phase == RemoteBridgePhase.online || snap.phase == RemoteBridgePhase.allowed)) {
      _publish(RemoteBridgePhase.allowed, deviceKey: deviceKey ?? snap.deviceKey);
    } else if (value &&
        (snap.phase == RemoteBridgePhase.allowed || snap.phase == RemoteBridgePhase.connecting)) {
      // 操控+无障碍刚打开：马上跟 Settings「在线」对齐，loop 会立刻发 poll。
      _publish(RemoteBridgePhase.online, deviceKey: deviceKey ?? snap.deviceKey);
    }
  }

  String? _ticket;
  String? deviceKey;
  var _running = false;
  var _loopGen = 0;
  Completer<void>? _wake;
  /// Owned HTTP client reused across long-polls (TLS handshakes are expensive on WAN).
  http.Client? _ownedClient;
  final _backoff = Backoff(maxAttempts: null);

  /// Last session id bound on Host (avoid repeat POSTs).
  String? _boundSessionId;
  /// Desired Face session affinity — retried after whitelist / Host restart.
  String? _wantBindSessionId;

  static const _prefix = '/xrk-phone-bridge';

  bool get running => _running;

  http.Client get _http {
    if (httpClient != null) return httpClient!;
    return _ownedClient ??= http.Client();
  }

  Map<String, String> get _cookieHeader {
    final parts = <String>[];
    void add(String name, String value) {
      if (value.isEmpty) return;
      // WebView CookieManager returns decoded values; encode for the Cookie header.
      parts.add('$name=${Uri.encodeComponent(value)}');
    }

    add(HttpHostLink.deviceCookie, _session.deviceToken);
    add(HttpHostLink.sessionCookie, _session.sessionToken);
    add(HttpHostLink.lanPinCookie, _session.lanPinCookie);
    add(HttpHostLink.wanPinCookie, _session.wanPinCookie);
    final csrf = _session.csrfToken;
    if (csrf != null && csrf.isNotEmpty) {
      add(HttpHostLink.csrfCookie, csrf);
    }
    return parts.isEmpty ? const {} : {'cookie': parts.join('; ')};
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(origin);
    return base.replace(path: path, queryParameters: query);
  }

  void _wakeLoop() {
    final wake = _wake;
    if (wake != null && !wake.isCompleted) wake.complete();
  }

  Future<void> _waitOrWake(Duration delay) async {
    final wake = Completer<void>();
    _wake = wake;
    try {
      await Future.any<void>([
        Future<void>.delayed(delay),
        wake.future,
      ]);
    } finally {
      if (identical(_wake, wake)) _wake = null;
    }
  }

  void _publish(RemoteBridgePhase phase, {String? message, String? deviceKey}) {
    remoteBridgeStatus.value = RemoteBridgeSnapshot(
      phase: phase,
      deviceKey: deviceKey ?? this.deviceKey,
      message: message,
      pollEnabled: _pollEnabled,
    );
  }

  /// Refresh Face cookies without tearing down the long-poll loop when possible.
  void updateSession(HttpHostSession next) {
    _session = next;
  }

  Future<Map<String, dynamic>?> _json(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    try {
      final uri = _uri(path, query);
      final headers = <String, String>{
        ..._cookieHeader,
        if (body != null) 'content-type': 'application/json; charset=utf-8',
        'accept': 'application/json',
      };
      late http.Response res;
      if (method == 'GET') {
        res = await _http.get(uri, headers: headers).timeout(timeout ?? const Duration(seconds: 35));
      } else {
        res = await _http
            .post(uri, headers: headers, body: body == null ? null : jsonEncode(body))
            .timeout(timeout ?? const Duration(seconds: 30));
      }
      if (res.body.isEmpty) return {'ok': res.statusCode < 300, 'status': res.statusCode};
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      return {'ok': false, 'error': 'bad-json'};
    } catch (e) {
      if (kDebugMode) debugPrint('[phone-bridge] $method $path: $e');
      return null;
    }
  }

  Future<void> _waitBackoff() async {
    await _waitOrWake(_backoff.next());
  }

  void _noteOk() => _backoff.reset();

  RemoteBridgePhase _phaseFrom(Map<String, dynamic>? reg, {required bool registeredOk}) {
    if (registeredOk) {
      // Host marks online as soon as poll arrives. With 操控+无障碍 we are about to
      // poll — mirror that immediately so Settings「在线」and App UI do not diverge
      // for the full long-poll window (~25s).
      if (_pollEnabled) return RemoteBridgePhase.online;
      return RemoteBridgePhase.allowed;
    }
    final err = '${reg?['error'] ?? ''}';
    if (err == 'not-whitelisted' || reg?['phase'] == 'pending') {
      return RemoteBridgePhase.pending;
    }
    if (err == 'not-operator' || err == 'missing-device-id') {
      return RemoteBridgePhase.needPin;
    }
    if (err == 'invalid-ticket') {
      return RemoteBridgePhase.connecting;
    }
    return RemoteBridgePhase.error;
  }

  /// Mint a fresh ticket (Host restart drops in-memory tickets; whitelist stays).
  Future<bool> _reticket() async {
    final ticketOut = await _json('POST', '$_prefix/ticket', body: {
      'label': label,
      'clientDeviceId': clientDeviceId,
    });
    if (ticketOut == null || ticketOut['ok'] != true) {
      final err = '${ticketOut?['error'] ?? ''}';
      final phase = (err == 'not-operator' || err == 'missing-device-id')
          ? RemoteBridgePhase.needPin
          : RemoteBridgePhase.error;
      _publish(
        phase,
        message: '${ticketOut?['error'] ?? ticketOut?['message'] ?? 'ticket failed'}',
      );
      return false;
    }
    final ticket = '${ticketOut['ticket'] ?? ''}';
    if (ticket.isEmpty) {
      _publish(RemoteBridgePhase.error, message: 'empty ticket');
      return false;
    }
    _ticket = ticket;
    deviceKey = '${ticketOut['deviceKey'] ?? ''}';
    _boundSessionId = null;
    if (kDebugMode) {
      debugPrint('[phone-bridge] reticket via=${ticketOut['authVia']} deviceKey=$deviceKey');
    }
    return true;
  }

  Future<Map<String, dynamic>?> _register() async {
    final ticket = _ticket;
    if (ticket == null) return {'ok': false, 'error': 'invalid-ticket'};
    return _json('POST', '$_prefix/register', body: {
      'ticket': ticket,
      'label': label,
    });
  }

  /// Register; on invalid-ticket mint again once (Host process restart).
  Future<Map<String, dynamic>?> _registerRecovering() async {
    var reg = await _register();
    if (_isInvalidTicket(reg)) {
      if (!await _reticket()) return reg;
      reg = await _register();
    }
    return reg;
  }

  Future<bool> start() async {
    if (_running) return true;
    if (!_session.hasOperatorProof) return false;
    _publish(RemoteBridgePhase.connecting);
    _backoff.reset();

    if (!await _reticket()) return false;

    final reg = await _registerRecovering();
    final ok = reg != null && reg['ok'] == true;
    if (ok) _noteOk();
    _publish(
      _phaseFrom(reg, registeredOk: ok),
      message: ok ? null : '${reg?['message'] ?? reg?['error'] ?? ''}',
    );
    if (kDebugMode) {
      debugPrint('[phone-bridge] register: $reg deviceKey=$deviceKey poll=$_pollEnabled');
    }

    // Keep looping while pending / allowed so Host allow → online without App restart.
    _running = true;
    if (ok) unawaited(_tryBindWanted());
    final gen = ++_loopGen;
    unawaited(_loop(gen));
    return true;
  }

  /// Stop the loop. [silent] skips publishing idle (controller is replacing us).
  Future<void> stop({bool silent = false}) async {
    final ticket = _ticket;
    _running = false;
    _loopGen++;
    _wakeLoop();
    if (ticket != null) {
      await _json('POST', '$_prefix/offline', body: {'ticket': ticket});
    }
    _ticket = null;
    deviceKey = null;
    _boundSessionId = null;
    final owned = _ownedClient;
    _ownedClient = null;
    owned?.close();
    if (!silent) _publish(RemoteBridgePhase.idle);
  }

  Future<void> bindSession(String sessionId) async {
    final id = sessionId.trim();
    if (id.isEmpty) return;
    _wantBindSessionId = id;
    await _tryBindWanted();
  }

  /// Bind Face session when whitelisted; no-ops while pending / offline ticket.
  Future<void> _tryBindWanted() async {
    final id = _wantBindSessionId;
    final ticket = _ticket;
    if (!_running || ticket == null || id == null || id.isEmpty) return;
    if (_boundSessionId == id) return;
    var out = await _json('POST', '$_prefix/bind-session', body: {
      'ticket': ticket,
      'sessionId': id,
    });
    if (_isInvalidTicket(out)) {
      if (!await _reticket()) return;
      final reg = await _register();
      if (reg == null || reg['ok'] != true) return;
      out = await _json('POST', '$_prefix/bind-session', body: {
        'ticket': _ticket,
        'sessionId': id,
      });
    }
    if (out != null && out['ok'] == true) {
      _boundSessionId = id;
      _noteOk();
      if (kDebugMode) debugPrint('[phone-bridge] bound session $id');
      return;
    }
    // not-whitelisted / pending: keep _wantBindSessionId for a later retry.
    if (kDebugMode && out != null) {
      debugPrint('[phone-bridge] bind deferred: ${out['error'] ?? out}');
    }
  }

  Future<void> _loop(int gen) async {
    while (_running && gen == _loopGen) {
      if (_ticket == null) {
        if (!await _reticket()) {
          await _waitBackoff();
          continue;
        }
      }

      if (!_pollEnabled) {
        // Keep pending lastSeen warm via register; Host allow → next register ok.
        final reg = await _registerRecovering();
        final ok = reg != null && reg['ok'] == true;
        if (ok) {
          _noteOk();
          unawaited(_tryBindWanted());
        }
        _publish(
          _phaseFrom(reg, registeredOk: ok),
          message: ok ? null : '${reg?['message'] ?? ''}',
        );
        await _waitOrWake(ok ? const Duration(seconds: 3) : const Duration(seconds: 5));
        continue;
      }

      // Align with Host: online flips when the poll request is accepted, not when
      // the long-poll HTTP response finally returns (empty wait can be ~25s).
      _publish(RemoteBridgePhase.online);
      unawaited(_tryBindWanted());
      var out = await _json(
        'POST',
        '$_prefix/poll',
        body: {'ticket': _ticket, 'wait': 25000},
        timeout: const Duration(seconds: 40),
      );
      if (!_running || gen != _loopGen) break;

      if (_isInvalidTicket(out)) {
        if (!await _reticket()) {
          await _waitBackoff();
          continue;
        }
        final reg = await _register();
        if (reg == null || reg['ok'] != true) {
          _publish(
            _phaseFrom(reg, registeredOk: false),
            message: '${reg?['message'] ?? reg?['error'] ?? ''}',
          );
          await _waitBackoff();
          continue;
        }
        _noteOk();
        unawaited(_tryBindWanted());
        // Retry poll with the fresh ticket on the next iteration.
        continue;
      }

      if (out == null) {
        _publish(RemoteBridgePhase.connecting, message: '网络中断，正在重连…');
        await _waitBackoff();
        continue;
      }
      if (out['ok'] != true) {
        if (kDebugMode) debugPrint('[phone-bridge] poll: $out');
        final err = '${out['error'] ?? ''}';
        if (err == 'not-operator') {
          _publish(RemoteBridgePhase.needPin, message: '${out['message'] ?? err}');
          await _waitBackoff();
          continue;
        }
        final reg = await _registerRecovering();
        final ok = reg != null && reg['ok'] == true;
        if (ok) {
          _noteOk();
          unawaited(_tryBindWanted());
        }
        _publish(_phaseFrom(reg, registeredOk: ok), message: err);
        if (ok) {
          await _waitOrWake(const Duration(seconds: 2));
        } else {
          await _waitBackoff();
        }
        continue;
      }
      _noteOk();
      _publish(RemoteBridgePhase.online);
      final invokes = out['invokes'];
      if (invokes is! List || invokes.isEmpty) continue;
      for (final raw in invokes) {
        if (!_running || gen != _loopGen) break;
        if (raw is! Map) continue;
        final id = '${raw['id'] ?? ''}';
        final name = '${raw['name'] ?? ''}';
        if (id.isEmpty || name.isEmpty) continue;
        final argsRaw = raw['args'];
        final args = <String, Object?>{};
        if (argsRaw is Map) {
          argsRaw.forEach((k, v) {
            if (k is String) args[k] = v;
          });
        }
        final result = await phone.invokeTool(name, args);
        final body = <String, Object?>{
          'ticket': _ticket,
          'id': id,
          'content': result.content,
          'isError': result.isError,
        };
        if (result.imageBase64 != null && result.imageMime != null) {
          body['imageBase64'] = result.imageBase64;
          body['imageMime'] = result.imageMime;
        }
        final submitted = await _json('POST', '$_prefix/result', body: body);
        if (_isInvalidTicket(submitted)) {
          // Ticket lost mid-batch: Host will time out this invoke; re-arm for next.
          await _reticket();
          await _register();
          break;
        }
      }
    }
  }
}

class PhoneBridgeController {
  PhoneBridgeClient? _client;
  String? _proofFp;
  var _syncGen = 0;

  PhoneBridgeClient? get client => _client;

  Future<void> sync({
    required HostKindIsHttp isHttp,
    required HttpHostConfig? config,
    required HttpHostSession? session,
    required bool phoneEnabled,
    required bool a11yOk,
    required PhoneChannel phone,
    String? bindSessionId,
  }) async {
    final gen = ++_syncGen;

    if (!isHttp || config == null) {
      await _client?.stop();
      if (gen != _syncGen) return;
      _client = null;
      _proofFp = null;
      remoteBridgeStatus.value = RemoteBridgeSnapshot.idle;
      return;
    }
    if (session == null || !session.hasOperatorProof) {
      await _client?.stop();
      if (gen != _syncGen) return;
      _client = null;
      _proofFp = null;
      remoteBridgeStatus.value = const RemoteBridgeSnapshot(
        phase: RemoteBridgePhase.needPin,
        message: '用 PIN 打开 Face 后会自动报到 Host。',
      );
      return;
    }

    final wantPoll = phoneEnabled && a11yOk;
    final origin = config.origin;
    final fp = operatorProofFingerprint(session);
    final clientId = await ensureBridgeClientDeviceId();
    if (gen != _syncGen) return;

    final sameHost = _client != null && _client!.origin == origin && _client!.running;
    final sameProof = sameHost && _proofFp == fp;

    if (sameProof) {
      _client!.updateSession(session);
      _client!.pollEnabled = wantPoll;
      final sid = bindSessionId?.trim();
      if (sid != null && sid.isNotEmpty) {
        unawaited(_client!.bindSession(sid));
      }
      return;
    }

    final previous = _client;
    _client = null;
    await previous?.stop(silent: true);
    if (gen != _syncGen) return;

    final next = PhoneBridgeClient(
      origin: origin,
      session: session,
      phone: phone,
      clientDeviceId: clientId,
      label: config.name.isNotEmpty ? config.name : 'XRK-phone',
      pollEnabled: wantPoll,
    );
    final ok = await next.start();
    if (gen != _syncGen) {
      await next.stop(silent: true);
      return;
    }
    if (ok) {
      _client = next;
      _proofFp = fp;
      final sid = bindSessionId?.trim();
      if (sid != null && sid.isNotEmpty) {
        unawaited(next.bindSession(sid));
      }
    } else {
      _client = null;
      _proofFp = null;
    }
  }

  Future<void> dispose() async {
    _syncGen++;
    await _client?.stop();
    _client = null;
    _proofFp = null;
  }
}

typedef HostKindIsHttp = bool;
