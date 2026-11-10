// Which entries the plugin settings page offers, on what a real Host lists
// (docs/design/plugin-config.md §7). The fixtures come from one r13 runtime
// (XRK 0.2.1-rc.4 + xrk-bridge 0.4.0) launched like the App launches it —
// its own overlay, voice, sign-in, message search and phone control —
// after the person switched on the official voice-input kit and installed a
// local plugin (`local-notes`):
//
//   fixtures/bridge_catalog_r13.json   GET /xrk-mobile/v1/plugin-config, as served
//   fixtures/plugin_bundles_r13.json   pluginManager/listBundles, same moment
//                                      (`meta.icon` data URLs cut to "<icon>",
//                                      the local plugin's source path shortened)
//
// 202 entries, 84 configurable: 79 of them XRK's own core rows, one the
// App's phone control, four the person's plugins. The old namespace
// blacklist let 58 core entries through, writable.

import 'dart:convert';
import 'dart:io';

import 'package:xrk_app/state/plugin_config/plugin_config_state.dart';
import 'package:xrk_app/ui/plugins/config/plugin_config_entries.dart';
import 'package:xrk_client/xrk_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_bridge.dart';

Object? _fixture(String name) => jsonDecode(File('test/plugin_config/fixtures/$name').readAsStringSync());

/// The list as the client parses it.
List<PluginConfigEntrySummary> _listed() => [
  for (final e in (_fixture('bridge_catalog_r13.json')! as Map)['entries'] as List)
    ?PluginConfigEntrySummary.fromJson(e),
];

List<Map<String, Object?>> _rawBundles() => (_fixture('plugin_bundles_r13.json')! as List).cast<Map<String, Object?>>();

List<PluginBundle> _bundles([List<Map<String, Object?>>? raw]) => [
  for (final b in raw ?? _rawBundles()) PluginBundle.fromJson(b),
];

/// The page's state on that Host: the bridge's list (forms read one at a
/// time), scoped by [bundles].
PluginConfigState _state(List<PluginBundle>? bundles, {List<PluginConfigEntrySummary>? listed}) => PluginConfigState(
  forms: const {},
  lazy: true,
  complete: true,
  entries: {
    for (final e in listed ?? _listed())
      e.entryId: PluginConfigEntry(
        e.entryId,
        package: e.package,
        label: e.label,
        state: e.state,
        configurable: e.configurable,
        reason: e.reason,
      ),
  },
  scope: PluginConfigScope.of(bundles),
);

/// What the old blacklist kept out (curated + internal namespaces).
const _sensitive = [
  'webserver',
  'connection',
  'credentials',
  'sandbox-policy',
  'fs-sandbox',
  'approval',
  'system-prompt',
];

/// The person's plugins on that Host with something to set, in the Host's order.
const _plugins = ['speech-to-text', 'speech-to-text-sensevoice', 'api-speech-to-text', 'local-notes'];

Set<String> _rowsOf(String bundle) => {
  for (final b in _bundles())
    if (b.name == bundle)
      for (final r in b.rows) r.rowId,
};

void main() {
  test('the recorded Host: every entry listed, the sensitive ones configurable', () {
    final listed = _listed();
    expect(listed, hasLength(202));
    expect(listed.where((e) => e.configurable), hasLength(84));
    final byId = {for (final e in listed) e.entryId: e};
    for (final id in _sensitive) {
      expect(byId[id]?.configurable, isTrue, reason: '$id would take a write');
      expect(byId[id]?.package, startsWith('@deepseek-ai/'));
    }
    // What the list carries: nothing that says core or plugin.
    final keys = {for (final e in (_fixture('bridge_catalog_r13.json')! as Map)['entries'] as List) ...(e as Map).keys};
    expect(keys, {'entryId', 'package', 'label', 'state', 'configurable', 'reason'});
  });

  test('设置 › 引擎参数 › 插件 offers the voice-input kit and the local plugin, nothing else', () {
    final state = _state(_bundles());
    expect(pluginConfigEntries(state), _plugins);
    for (final id in _sensitive) {
      expect(state.isPlugin(id), isFalse, reason: id);
      expect(hasPluginConfig(state, id), isFalse, reason: id);
    }
  });

  test('every other configurable entry stays out: 79 core rows and the App\'s phone control', () {
    final state = _state(_bundles());
    final hidden = [
      for (final e in _listed())
        if (e.configurable && !_plugins.contains(e.entryId)) e.entryId,
    ];
    expect(hidden, hasLength(80));
    final core = {..._rowsOf('@xrkseek/harness-cli-base'), ..._rowsOf('@xrkseek/harness-cli-web-app')};
    expect(hidden.where(core.contains), hasLength(79));
    expect(hidden.where((id) => !core.contains(id)).toList(), [
      'dsh-app-phone',
    ], reason: 'inserted by the App\'s --patch');
    for (final id in hidden) {
      expect(state.isPlugin(id), isFalse, reason: id);
      expect(hasPluginConfig(state, id), isFalse, reason: id);
    }
    // Nor the App's other rows, loaded by path.
    for (final id in ['xrk-bridge', 'dsh-app-auth']) {
      expect(state.isPlugin(id), isFalse, reason: id);
    }
  });

  test('a plugin row without settings gets no page; a plugin\'s other rows are its own', () {
    final state = _state(_bundles());
    expect(state.isPlugin('ui-voice-input'), isTrue);
    expect(state.entries['ui-voice-input']!.configurable, isFalse);
    expect(hasPluginConfig(state, 'ui-voice-input'), isFalse);
  });

  test('a market plugin is a plugin like a local one', () {
    final raw = _rawBundles();
    final local = raw.firstWhere((b) => b['name'] == 'xrk-mobile-fixture-local-notes');
    final market = {
      ...local,
      'name': 'dsh-hooks',
      'version': '0.14.4',
      'source': 'dsh-hooks@0.14.4',
      'rows': [
        {'rowId': 'hooks', 'moduleName': 'dsh-hooks', 'entryId': 'include:hooks'},
      ],
    };
    final listed = [
      ..._listed(),
      const PluginConfigEntrySummary(entryId: 'hooks', package: 'dsh-hooks', configurable: true),
    ];
    final state = _state(_bundles([...raw, market]), listed: listed);
    expect(pluginConfigEntries(state), [..._plugins, 'hooks']);
  });

  group('denied by default', () {
    test('no plugin list yet (or none at all): nothing', () {
      expect(pluginConfigEntries(_state(null)), isEmpty);
      expect(pluginConfigEntries(_state(const [])), isEmpty);
    });

    test('an entry no chosen bundle declares: not offered', () {
      final listed = [
        ..._listed(),
        const PluginConfigEntrySummary(entryId: 'mystery', package: 'mystery-plugin', configurable: true),
        const PluginConfigEntrySummary(entryId: 'by-path', configurable: true),
      ];
      final state = _state(_bundles(), listed: listed);
      expect(state.isPlugin('mystery'), isFalse);
      expect(state.isPlugin('by-path'), isFalse);
      expect(pluginConfigEntries(state), _plugins);
    });

    test('bundles the person did not choose, or that did not load, bring nothing', () {
      final raw = _rawBundles();
      Map<String, Object?> voice(Map<String, Object?> change) => {
        ...raw.firstWhere((b) => b['name'] == '@xrkseek/harness-cli-experimental-voice-input-bundle'),
        ...change,
      };
      final others = raw.where((b) => b['name'] != '@xrkseek/harness-cli-experimental-voice-input-bundle').toList();
      expect(
        pluginConfigEntries(
          _state(
            _bundles([
              ...others,
              voice({'enabled': false}),
            ]),
          ),
        ),
        ['local-notes'],
      );
      expect(
        pluginConfigEntries(
          _state(
            _bundles([
              ...others,
              voice({
                'error': {'code': 'incompatible-version'},
              }),
            ]),
          ),
        ),
        ['local-notes'],
      );
      expect(
        pluginConfigEntries(
          _state(
            _bundles([
              ...others,
              voice({'optional': false, 'official': false}),
            ]),
          ),
        ),
        ['local-notes'],
        reason: 'shipped but not optional: the installation\'s own layer',
      );
    });

    test('installation layers and alternatives repeating core ids are not plugins', () {
      final state = _state(_bundles());
      final bundles = {for (final b in _bundles()) b.name: b};
      for (final name in ['@xrkseek/harness-cli-base', '@xrkseek/harness-cli-web-app', '@xrkseek/harness-cli-sdk-minimal']) {
        expect(PluginConfigScope.owns(bundles[name]!), isFalse, reason: name);
      }
      // dsh-sdk-minimal (not selected) declares rows under core ids.
      expect(_rowsOf('@xrkseek/harness-cli-sdk-minimal'), containsAll(['llm-deepseek', 'sandbox']));
      expect(state.isPlugin('llm-deepseek'), isFalse);
      expect(state.isPlugin('sandbox'), isFalse);
    });

    test('a chosen bundle claiming a core id under another module does not make it a plugin', () {
      final raw = _rawBundles();
      final local = raw.firstWhere((b) => b['name'] == 'xrk-mobile-fixture-local-notes');
      final claim = {
        ...local,
        'rows': [
          ...(local['rows']! as List),
          {'rowId': 'webserver', 'moduleName': 'xrk-mobile-fixture-local-notes'},
        ],
      };
      final state = _state(_bundles([...raw.where((b) => b != local), claim]));
      expect(state.entries['webserver']!.package, '@xrkseek/harness-cli-host-webserver');
      expect(state.isPlugin('webserver'), isFalse);
      expect(pluginConfigEntries(state), _plugins);
    });

    test('a chosen bundle re-declaring a core row, same id and same package: still not a plugin (CR-a17797b)', () {
      // The review's observation, asserted the right way round: the core
      // (dsh-web-app) declares `webserver` too: the id is not the chosen bundle's alone.
      final raw = _rawBundles();
      final local = raw.firstWhere((b) => b['name'] == 'xrk-mobile-fixture-local-notes');
      final claim = {
        ...local,
        'rows': [
          ...(local['rows']! as List),
          {'rowId': 'webserver', 'moduleName': '@xrkseek/harness-cli-host-webserver', 'entryId': 'include:webserver'},
        ],
      };
      final state = _state(_bundles([...raw.where((b) => b != local), claim]));
      expect({..._rowsOf('@xrkseek/harness-cli-base'), ..._rowsOf('@xrkseek/harness-cli-web-app')}, contains('webserver'));
      expect(state.entries['webserver']!.package, '@xrkseek/harness-cli-host-webserver');
      expect(state.isPlugin('webserver'), isFalse);
      expect(hasPluginConfig(state, 'webserver'), isFalse);
      expect(pluginConfigEntries(state), _plugins);
    });

    test('one id inserted by two chosen bundles: neither', () {
      final raw = _rawBundles();
      final local = raw.firstWhere((b) => b['name'] == 'xrk-mobile-fixture-local-notes');
      final twin = {...local, 'name': 'another-notes', 'source': 'another-notes@1.0.0'};
      expect(
        pluginConfigEntries(_state(_bundles([...raw, twin]))),
        _plugins.where((id) => id != 'local-notes').toList(),
      );
    });
  });

  test('the write layer: every core entry of the recorded list is refused before a request', () async {
    final host = await FakeBridgeHost.start();
    addTearDown(host.close);
    host.listed = (_fixture('bridge_catalog_r13.json')! as Map)['entries'] as List<Object?>;
    final client = await XrkClient.connect(baseUri: host.baseUri, token: FakeBridgeHost.token, startMux: false);
    addTearDown(client.close);
    final scope = PluginConfigScope.of(_bundles());
    final api = BridgePluginConfigApi(client, _NoFallback(), scope: () => scope);
    final catalog = (await api.describe())!;
    expect(catalog.entries, hasLength(202));
    final core = [
      for (final e in _listed())
        if (e.configurable && !_plugins.contains(e.entryId)) e.entryId,
    ];
    for (final id in core) {
      await expectLater(
        api.apply(id, const [
          SettingsOp.set(['enabled'], false),
        ], revision: 'r1').drain<void>(),
        throwsA(isA<PluginConfigFailure>().having((f) => f.kind, 'kind', PluginConfigFailureKind.rejected)),
        reason: id,
      );
      await expectLater(api.read(id), throwsA(isA<PluginConfigFailure>()), reason: id);
    }
    expect(host.writes(), isEmpty);
    expect(host.requests.where((r) => r.$2.startsWith('$xrkGoPluginConfigPath/')), isEmpty);
    // A plugin of the same list goes out (404 here: the fake serves no form).
    await expectLater(api.read('local-notes'), completion(isNull));
    expect(host.requests.where((r) => r.$2 == xrkGoPluginConfigEntryPath('local-notes')), hasLength(1));
  });
}

/// The bridge answers here; the fallback is never asked.
class _NoFallback implements PluginConfigApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError('fallback asked: ${invocation.memberName}');
}
