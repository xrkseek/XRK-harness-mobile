import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xrk_app/remote/relay/xrk_remote_backend.dart';
import 'package:xrk_app/remote/relay/relay_backend.dart';
import 'package:xrk_app/remote/relay/webrtc_peer.dart';
import 'package:xrk_app/remote/link_status.dart';
import 'package:xrk_app/state/hosts_state.dart';

import 'support/fake_relay.dart';

import 'package:xrk_app/remote/secret_store.dart';

void main() {
  for (final legacy in <bool?>[null, false, true]) {
    test('automatic transport is enabled immediately, including legacy preference $legacy', () async {
      SharedPreferences.setMockInitialValues({'remote_direct_p2p': ?legacy});
      final c = ProviderContainer(overrides: [secretStoreProvider.overrideWithValue(MemorySecretStore())]);
      addTearDown(c.dispose);
      final backend = c.read(relayBackendProvider) as XrkRemoteRelayBackend;
      expect(backend.peerConnector, flutterPeerConnector);
      expect(
        backend.account.peerConnector,
        flutterPeerConnector,
        reason: 'first connect does not wait for preferences',
      );
      await pumpEventQueue();
      expect((await SharedPreferences.getInstance()).containsKey('remote_direct_p2p'), isFalse);
      expect(identical(c.read(relayBackendProvider), backend), isTrue);
    });
  }
  test('a connected Remote link reports the actual selected path', () async {
    final relay = FakeRelayBackend(user: sampleRelayUser)..path = RelayPath.p2p;
    final link = RelayHostLink(backend: relay, hostId: 'mac', resolveHost: () async => sampleRelayHosts.first);
    addTearDown(link.close);
    await link.open();
    expect(link.status.isConnected, isTrue);
    expect(link.status.path, RelayPath.p2p);
  });
}
