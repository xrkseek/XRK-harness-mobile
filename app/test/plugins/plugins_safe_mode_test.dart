import 'package:xrk_app/state/plugins_state.dart';
import 'package:xrk_app/ui/plugins/plugins_screen.dart';
import 'package:xrk_client/xrk_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat/support/harness.dart';
import 'support/fake_plugin_host.dart';

void main() {
  late FakePluginCarrier carrier;
  late XrkClient client;

  setUp(() {
    carrier = FakePluginCarrier();
    client = XrkClient.withCarrier(carrier);
    carrier.handlers['pluginManager/listBundles'] = (_) => sampleBundles;
  });

  tearDown(() => client.close());

  test('a local engine in safe mode never installs', () {
    final host = PluginHost.of(fakeHost(client), safeMode: true);
    expect(host.canInstall, isFalse);
    expect(PluginHost.of(fakeHost(client)).canInstall, isTrue);
  });

  testWidgets('the page says why installing is off in safe mode', (tester) async {
    usePhoneView(tester);
    await tester.pumpWidget(
      testApp(const PluginsScreen(), overrides: pluginOverrides(fakeHost(client), safeMode: true)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('安全模式下不能安装或卸载插件'), findsOneWidget);
  });
}
