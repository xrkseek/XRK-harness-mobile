// The plugin seats on the app's pages (docs/design/plugin-seams.md §3) over a
// fake inventory — the plugin detail's config row, a plugin's own page (island
// or the way to XRK Web), the 对话详情 插件 tab, 全部功能's plugin panels, and
// the settings hub rows. Goldens (light + dark) and behaviour. Without
// third-party occupants the pages' own goldens (test/plugins, test/session, …)
// are unaffected.
// Regenerate with `flutter test --update-goldens test/plugins/seats`.

import 'package:xrk_app/plugins/seams/seams.dart';
import 'package:xrk_app/runtime/runtime_state.dart';
import 'package:xrk_app/state/plugins_state.dart';
import 'package:xrk_app/state/settings_state.dart';
import 'package:xrk_app/ui/chat/empty_state.dart' show chatClock;
import 'package:xrk_app/ui/chat/widgets/live_clock.dart' show runClock;
import 'package:xrk_app/ui/features/all_features_page.dart';
import 'package:xrk_app/ui/features/feature_catalog.dart';
import 'package:xrk_app/ui/plugins/plugin_detail_sheet.dart';
import 'package:xrk_app/ui/plugins/plugins_screen.dart';
import 'package:xrk_app/ui/plugins/seats/plugin_seat_page.dart';
import 'package:xrk_app/ui/plugins/seats/session_plugins_tab.dart';
import 'package:xrk_app/ui/session/session_detail_page.dart';
import 'package:xrk_app/ui/settings/settings_screen.dart';
import 'package:xrk_app/ui/web/web_target.dart';
import 'package:xrk_client/xrk_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../chat/support/harness.dart' as chat;
import '../../chat/support/run_info_fixture.dart';
import '../../shell/golden_harness.dart';
import '../support/fake_plugin_host.dart';
import 'support.dart';

/// Pumps [home] on the phone surface with the seats and [extra] overrides.
Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Brightness brightness = Brightness.light,
  List<Override> seats = const [],
  List<Override> extra = const [],
}) async {
  await tester.runAsync(loadGoldenFonts);
  usePhoneSurface(tester);
  await tester.pumpWidget(goldenApp(home: home, brightness: brightness, overrides: [...extra, ...seats]));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Scrolls [finder] to the middle of the page.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await _settle(tester);
}

/// The installed list on a fake local host.
List<Override> _pluginHost() {
  final carrier = FakePluginCarrier();
  final client = XrkClient.withCarrier(carrier);
  carrier.handlers['pluginManager/listBundles'] = (_) => const <Object?>[];
  addTearDown(client.close);
  // seatOverrides selects the host.
  return pluginOverrides(fakeHost(client), selectHost: false);
}

/// 插件 › 已安装 › 岛屿探针.
Future<void> _openProbeSheet(WidgetTester tester) async {
  await tester.tap(find.text('岛屿探针').first);
  await _settle(tester);
}

final _hub = [
  localRuntimeProvider.overrideWith(() => FakeRuntime(const LocalRuntimeState(loaded: true, status: runningStatus))),
  settingsProvider.overrideWith(() => FakeSettings(const AppSettings(loaded: true))),
];

/// 对话详情 over the timed sample session (test/chat/support).
Future<void> _pumpDetail(
  WidgetTester tester, {
  required List<Override> seats,
  Brightness brightness = Brightness.light,
  SessionTab tab = SessionTab.trajectory,
}) async {
  chat.usePhoneView(tester);
  chat.mockClipboard(tester);
  final harness = chat.ChatHarness(session: 's1', states: {'s1': runInfoState()});
  await tester.pumpWidget(
    chat.testApp(
      SessionDetailPage(sessionId: 's1', initialTab: tab),
      brightness: brightness,
      overrides: [...harness.overrides, ...seats],
    ),
  );
  await chat.pumpFrames(tester, 6);
}

/// The inventory behind a seat, switchable mid-test.
class _Inventory extends Notifier<SeatInventory?> {
  _Inventory(this.initial);
  final SeatInventory? initial;

  @override
  SeatInventory? build() => initial;

  void set(SeatInventory? next) => state = next;
}

final _inventoryProvider = NotifierProvider<_Inventory, SeatInventory?>(() => _Inventory(null));

void main() {
  setUpAll(() async {
    await chat.loadTestFonts();
    chatClock = () => DateTime(2026, 10, 23, 15, 20);
  });
  setUp(() {
    openedWeb.clear();
    // 对话详情's running time, fixed.
    runClock = () => runInfoTestDispatched.add(const Duration(milliseconds: 12300));
  });
  tearDown(() => runClock = DateTime.now);

  group('goldens', () {
    for (final brightness in Brightness.values) {
      final mode = brightness == Brightness.dark ? 'dark' : 'light';
      Future<void> match(String name, [Finder? at]) =>
          expectLater(at ?? find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_$mode.png'));

      testWidgets('plugin detail: config only in XRK Web ($mode)', (tester) async {
        await _pump(
          tester,
          const PluginsScreen(),
          brightness: brightness,
          extra: _pluginHost(),
          seats: seatOverrides(
            inventory: seatInventory(tier: ClientInventoryTier.boot),
            budget: const NoIslandBudget(),
          ),
        );
        await _openProbeSheet(tester);
        await match('seat_bundle_web');
      });

      testWidgets('a plugin page with its island ($mode)', (tester) async {
        await _pump(
          tester,
          const PluginSeatPage(
            title: '岛屿探针',
            request: SeatRequest(
              slot: Slots.settingsSection,
              placement: SeatPlacement.page,
              package: probe,
              cell: 'k4-probe',
            ),
          ),
          brightness: brightness,
          seats: seatOverrides(inventory: seatInventory(occupancy: fullOccupancy)),
        );
        await match('seat_island_page');
      });

      testWidgets('a plugin page that only opens in XRK Web ($mode)', (tester) async {
        await _pump(
          tester,
          const PluginSeatPage(
            title: '桌宠面板',
            request: SeatRequest(slot: Slots.main, placement: SeatPlacement.page, package: pet, cell: 'pet-panel'),
          ),
          brightness: brightness,
          seats: seatOverrides(inventory: seatInventory(occupancy: fullOccupancy)),
        );
        await match('seat_web_page');
      });

      testWidgets('settings hub: the plugins\' sections under 插件 ($mode)', (tester) async {
        await _pump(
          tester,
          const SettingsScreen(),
          brightness: brightness,
          extra: _hub,
          seats: seatOverrides(inventory: seatInventory(occupancy: fullOccupancy)),
        );
        await _reveal(tester, find.text('桌宠提醒'));
        await match('seat_settings');
      });

      testWidgets('全部功能: plugin panels in 插件 ($mode)', (tester) async {
        await _pump(
          tester,
          const AllFeaturesPage(),
          brightness: brightness,
          seats: seatOverrides(inventory: seatInventory(occupancy: fullOccupancy)),
        );
        await _reveal(tester, find.text('探针面板'));
        await match('seat_all_features');
      });

      testWidgets('对话详情: the 插件 tab ($mode)', (tester) async {
        await _pumpDetail(
          tester,
          brightness: brightness,
          tab: SessionTab.plugins,
          seats: seatOverrides(inventory: seatInventory(occupancy: fullOccupancy)),
        );
        await match('seat_session_plugins', find.byType(SessionDetailPage));
      });
    }
  });

  group('plugin detail', () {

    testWidgets('a panel with an island opens its page; the other opens XRK Web', (tester) async {
      await _pump(
        tester,
        const AllFeaturesPage(),
        seats: [
          ...seatOverrides(inventory: seatInventory(occupancy: fullOccupancy)),
          dshWebOpenerProvider.overrideWithValue((context, ref, target) => openedWeb.add(target)),
        ],
      );
      await _reveal(tester, find.text('桌宠面板'));
      await tester.tap(find.text('桌宠面板'));
      expect(openedWeb.single, const DshWebTarget(sidebar: true));
      await tester.tap(find.text('探针面板'));
      await _settle(tester);
      expect(find.byType(PluginSeatPage), findsOneWidget);
      expect(find.byType(FakeIsland), findsOneWidget);
    });
  });

  group('settings hub', () {
    testWidgets('a section with an island opens its page; one without, XRK Web', (tester) async {
      await _pump(
        tester,
        const SettingsScreen(),
        extra: _hub,
        seats: seatOverrides(inventory: seatInventory(occupancy: fullOccupancy)),
      );
      await _reveal(tester, find.text('桌宠提醒'));
      await tester.tap(find.text('桌宠提醒'));
      expect(openedWeb.single, const DshWebTarget(settings: DshWebSettings.general));
      await tester.tap(find.text('岛屿探针'));
      await _settle(tester);
      expect(find.byType(PluginSeatPage), findsOneWidget);
      expect(find.byType(FakeIsland), findsOneWidget);
    });

    testWidgets('no rows without plugin sections', (tester) async {
      await _pump(
        tester,
        const SettingsScreen(),
        extra: _hub,
        seats: seatOverrides(inventory: seatInventory()),
      );
      await _reveal(tester, find.text('插件'));
      expect(find.text('插件'), findsOneWidget); // the 插件 row itself
      expect(find.text('岛屿探针'), findsNothing);
    });
  });
}
