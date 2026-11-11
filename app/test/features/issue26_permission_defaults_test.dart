import 'package:xrk_app/state/connection_state.dart';
import 'package:xrk_app/state/features_state.dart';
import 'package:xrk_app/state/hosts_state.dart';
import 'package:xrk_app/state/settings_state.dart';
import 'package:xrk_app/ui/features/permission_page.dart';
import 'package:xrk_client/xrk_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat/support/harness.dart';
import '../plugins/support/fake_plugin_host.dart';

class _Settings extends SettingsController {
  @override
  AppSettings build() => const AppSettings(loaded: true);
}

/// Face `permission` namespace schemastery envelope (Host FACE_PERMISSION_SCHEMA).
Map<String, Object?> _permissionSchema() => {
  'uid': 8,
  'refs': {
    '1': {'type': 'const', 'meta': {'description': 'Read only'}, 'value': 'read-only'},
    '2': {'type': 'const', 'meta': {'description': 'Workspace write'}, 'value': 'workspace-write'},
    '3': {'type': 'const', 'meta': {'description': 'Full access'}, 'value': 'danger-full-access'},
    '4': {'type': 'const', 'meta': {'description': 'Auto review'}, 'value': 'auto'},
    '5': {'type': 'union', 'list': [1, 2, 3, 4]},
    '6': {'type': 'string'},
    '7': {'type': 'array', 'inner': 6},
    '8': {
      'type': 'object',
      'dict': {'defaultPreset': 5, 'extraWritableRoots': 7},
    },
  },
};

Map<String, Object?> _describe(String stored) => {
  'writable': true,
  'namespaces': [
    {
      'ns': 'permission',
      'value': {'defaultPreset': stored},
      'revision': 7,
      'schema': _permissionSchema(),
    },
  ],
};

void main() {
  late FakePluginCarrier carrier;
  late XrkClient client;
  var stored = 'workspace-write';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    carrier = FakePluginCarrier();
    client = XrkClient.withCarrier(carrier);
    stored = 'workspace-write';
    carrier.handlers['settings.describe'] = (_) => _describe(stored);
    carrier.handlers['session/projections'] = (_) => {
      'kind': 'sequenced',
      'asOfSeq': 1,
      'values': {
        'permissions': {'currentValue': 'workspace-write'},
      },
    };
    carrier.handlers['commands/execute'] = (_) => {
      'commandId': 'permission-1',
      'result': {'kind': 'success', 'text': 'preset auto'},
    };
  });
  tearDown(() => client.close());

  Future<void> pump(WidgetTester tester, {String? sessionId}) async {
    usePhoneView(tester);
    await tester.pumpWidget(
      testApp(
        PermissionPage(sessionId: sessionId),
        overrides: [
          activeConnectionProvider.overrideWithValue(AsyncData(fakeHost(client, kind: HostKind.ssh))),
          settingsProvider.overrideWith(_Settings.new),
        ],
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Auto stays selectable for the current chat but is absent from defaults', (tester) async {
    await pump(tester, sessionId: 's1');
    expect(find.text('自动审查'), findsOneWidget);
    await tester.tap(find.text('自动审查'));
    await tester.pumpAndSettle();
    expect(find.text('开启自动审查？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '开启自动审查'));
    await tester.pumpAndSettle();
    expect(carrier.argsOf('commands/execute').single['line'], '/permission auto');
    expect(carrier.argsOf('settings.mutate'), isEmpty);
  });

  test('permissionPresets reads Face settings.describe schema', () async {
    final catalog = await client.permissionPresets();
    expect(catalog.defaultPreset, 'workspace-write');
    expect(catalog.options.map((o) => o.value), ['read-only', 'workspace-write', 'danger-full-access', 'auto']);
    expect(catalog.defaultOptions.map((o) => o.value), ['read-only', 'workspace-write', 'danger-full-access']);
  });

  test('describe failures surface as permissionState errors', () async {
    carrier.handlers['settings.describe'] = (_) => throw const XrkRemoteException('offline', 'unreachable');
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [activeConnectionProvider.overrideWithValue(AsyncData(fakeHost(client, kind: HostKind.ssh)))],
    );
    addTearDown(container.dispose);
    final sub = container.listen(permissionStateProvider(null), (_, _) {});
    addTearDown(sub.close);
    await expectLater(container.read(permissionStateProvider(null).future), throwsA(isA<XrkRemoteException>()));
  });
}
