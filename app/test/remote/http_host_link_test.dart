import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xrk_app/remote/http/http_host_config.dart';
import 'package:xrk_app/remote/http/http_host_link.dart';
import 'package:xrk_app/remote/link_status.dart';
import 'package:xrk_app/remote/secret_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemorySecretStore secrets;

  setUp(() {
    secrets = MemorySecretStore();
  });

  HttpHostConfig config() => const HttpHostConfig(
        id: 'http-test',
        name: '测试机',
        origin: 'http://example.test:8787',
      );

  test('probe → native-pair → connected', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/mobile-access/health')) {
        return http.Response(jsonEncode({'ok': true, 'service': 'xrk-mobile-access'}), 200);
      }
      if (request.url.path.endsWith('/mobile-access/auth/native-pair')) {
        expect(jsonDecode(request.body)['token'], 'pair-token');
        return http.Response(
          jsonEncode({
            'deviceToken': 'dev',
            'sessionToken': 'sess',
            'csrfToken': 'csrf',
          }),
          201,
        );
      }
      return http.Response('nope', 404);
    });

    final link = HttpHostLink(
      config: config(),
      secrets: secrets,
      pairingToken: 'pair-token',
      httpClient: client,
      retryFirstOpen: false,
    );
    addTearDown(link.close);

    final phases = <HostLinkPhase>[];
    final sub = link.statuses.listen((s) => phases.add(s.phase));
    addTearDown(sub.cancel);

    final session = await link.open();
    expect(session.deviceToken, 'dev');
    expect(session.sessionToken, 'sess');
    expect(link.status.phase, HostLinkPhase.connected);
    expect(await secrets.read(HttpHostSecrets.deviceTokenKey('http-test')), 'dev');
    expect(phases, contains(HostLinkPhase.connecting));
    expect(phases, contains(HostLinkPhase.connected));
  });

  test('health failure is retryable failed without pairing', () async {
    final client = MockClient((request) async {
      throw const SocketException('unreachable');
    });
    final link = HttpHostLink(
      config: config(),
      secrets: secrets,
      httpClient: client,
      retryFirstOpen: false,
    );
    addTearDown(link.close);

    await expectLater(link.open(), throwsA(isA<HostLinkError>()));
    expect(link.status.phase, HostLinkPhase.failed);
    expect(link.status.error?.kind, HostLinkErrorKind.unreachable);
    expect(link.status.error?.retryable, isTrue);
  });

  test('missing pairing without secrets still connects for Face PIN', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/mobile-access/health')) {
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      return http.Response('nope', 404);
    });
    final link = HttpHostLink(
      config: config(),
      secrets: secrets,
      httpClient: client,
      retryFirstOpen: false,
    );
    addTearDown(link.close);

    final session = await link.open();
    expect(session.isReady, isFalse);
    expect(link.status.phase, HostLinkPhase.connected);
  });

  test('TLS-only FRP HTTP 501 upgrades bare host:port to https', () async {
    final client = MockClient((request) async {
      if (request.url.scheme == 'http') {
        return http.Response(
          'Not Implemented',
          501,
          headers: {'server': 'SakuraFrp'},
        );
      }
      if (request.url.path.endsWith('/mobile-access/health')) {
        return http.Response(jsonEncode({'ok': true}), 200);
      }
      return http.Response('nope', 404);
    });
    final link = HttpHostLink(
      config: const HttpHostConfig(
        id: 'frp-https',
        name: '穿透',
        origin: 'http://tunnel.example:12345',
      ),
      secrets: secrets,
      httpClient: client,
      retryFirstOpen: false,
    );
    addTearDown(link.close);

    await link.open();
    expect(link.config.origin, 'https://tunnel.example:12345');
    expect(link.status.phase, HostLinkPhase.connected);
  });
}
