import 'package:flutter_test/flutter_test.dart';
import 'package:xrk_app/remote/bridge/phone_bridge_client.dart';
import 'package:xrk_app/remote/http/http_host_link.dart';

void main() {
  test('operatorProofFingerprint changes when PIN cookies remint', () {
    const a = HttpHostSession(
      deviceToken: '',
      sessionToken: '',
      wanPinCookie: 'old-digest',
    );
    const b = HttpHostSession(
      deviceToken: '',
      sessionToken: '',
      wanPinCookie: 'new-digest',
    );
    expect(operatorProofFingerprint(a), isNot(operatorProofFingerprint(b)));
    expect(operatorProofFingerprint(a), operatorProofFingerprint(a));
  });

  test('hasOperatorProof accepts PIN-only Face', () {
    const pinOnly = HttpHostSession(
      deviceToken: '',
      sessionToken: '',
      wanPinCookie: 'digest',
    );
    expect(pinOnly.hasOperatorProof, isTrue);
    expect(pinOnly.isReady, isFalse);
  });
}
