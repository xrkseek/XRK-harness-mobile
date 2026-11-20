import 'package:flutter_test/flutter_test.dart';
import 'package:xrk_app/ui/web/web_view_page.dart';

void main() {
  test('WebComposeResult parses bridge reason for clipboard fallback', () {
    final missed = WebComposeResult.parse('{"text":false,"files":0,"reason":"no_composer"}');
    expect(missed.text, isFalse);
    expect(missed.files, 0);
    expect(missed.reason, 'no_composer');

    final ok = WebComposeResult.parse('{"text":true,"files":2}');
    expect(ok.text, isTrue);
    expect(ok.files, 2);
    expect(ok.reason, isNull);
  });
}
