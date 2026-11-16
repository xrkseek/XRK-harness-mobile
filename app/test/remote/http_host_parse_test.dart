import 'package:flutter_test/flutter_test.dart';
import 'package:xrk_app/remote/http/http_host_config.dart';
import 'package:xrk_app/remote/http/http_host_parse.dart';

void main() {
  group('normalizeHttpOrigin', () {
    test('adds scheme and strips path', () {
      expect(normalizeHttpOrigin('103.236.89.174:8787'), 'http://103.236.89.174:8787');
      expect(normalizeHttpOrigin('http://host:8787/mobile-access/pair'), 'http://host:8787');
      expect(normalizeHttpOrigin('https://example.com/'), 'https://example.com');
    });

    test('rejects empty / bad schemes', () {
      expect(normalizeHttpOrigin(''), null);
      expect(normalizeHttpOrigin('ftp://x'), null);
    });
  });

  group('parseHttpHostInput', () {
    test('parses typed IP and pair URL', () {
      final ip = parseHttpHostInput('103.236.89.174:8787');
      expect(ip?.origin, 'http://103.236.89.174:8787');
      expect(ip?.suggestedName, '103.236.89.174:8787');

      final pair = parseHttpHostInput(
        'http://10.0.0.2:8787/mobile-access/pair#instance=abc&token=tok.en',
      );
      expect(pair?.origin, 'http://10.0.0.2:8787');
      expect(pair?.hasPairing, isTrue);
      expect(pair?.pairingInstanceId, 'abc');
      expect(pair?.pairingToken, 'tok.en');
    });

    test('marks wan-pin pages', () {
      final pin = parseHttpHostInput('http://host:8787/mobile-access/wan-pin?return=/');
      expect(pin?.needsPinPage, isTrue);
      expect(pin?.origin, 'http://host:8787');
    });

    test('dsh1 alone needs fallback origin', () {
      expect(parseHttpHostInput('dsh1.inst.token.value'), isNull);
      final withOrigin = parseHttpHostPairing('dsh1.inst.token.value', fallbackOrigin: '10.0.0.1:8787');
      expect(withOrigin?.origin, 'http://10.0.0.1:8787');
      expect(withOrigin?.pairingInstanceId, 'inst');
      expect(withOrigin?.pairingToken, 'token.value');
    });
  });

  group('sameHttpOrigin', () {
    test('compares normalized origins', () {
      expect(sameHttpOrigin('http://A:8787/', 'a:8787'), isTrue);
      expect(sameHttpOrigin('http://a:8787', 'http://b:8787'), isFalse);
    });
  });
}
