// The ＋ panel (settings-ia §4.4, media-generation §4.2): tiles equal and 8
// apart, 16 from the sides, the 本对话 card lined up with them; 权限 goes
// through `/permission`, 计划模式 through `/plan` and `/plan off`, 确认方式
// through `setPolicies`; and the permission pill on the composer's edge.

import 'package:xrk_app/l10n/l10n.dart';
import 'package:xrk_app/state/chat_state.dart';
import 'package:xrk_app/state/risk_notice_store.dart';
import 'package:xrk_app/state/session_modes.dart';
import 'package:xrk_app/ui/chat/chat_screen.dart';
import 'package:xrk_app/ui/chat/composer.dart';
import 'package:xrk_app/ui/chat/widgets/permission_pill.dart';
import 'package:xrk_app/ui/chat/widgets/plus_panel.dart';
import 'package:xrk_app/ui/common/list_page_row.dart';
import 'package:xrk_app/ui/theme/app_icons.dart';
import 'package:xrk_app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../phone/support.dart';
import 'support/harness.dart';

class _NoRiskStore implements RiskNoticeStore {
  @override
  Future<bool> silenced(String id) async => false;

  @override
  Future<void> silence(String id) async {}
}

List<Override> _extra({SessionModes modes = const SessionModes(preset: 'workspace-write')}) => [
  riskNoticeStoreProvider.overrideWithValue(_NoRiskStore()),
  sessionModesProvider.overrideWith((ref, id) => modes),
];

/// A page with one key that opens the panel.
Future<ChatHarness> _openPanel(
  WidgetTester tester, {
  double width = 390,
  double scale = 1,
  bool generate = false,
  bool files = true,
  String? session = 's1',
  Brightness brightness = Brightness.light,
  SessionModes modes = const SessionModes(preset: 'workspace-write'),
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(width * 2, 844 * 2);
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 32);
  tester.view.viewPadding = const FakeViewPadding(top: 48, bottom: 32);
  addTearDown(tester.view.reset);
  final harness = ChatHarness(newChatCatalogs: true, session: session);
  await tester.pumpWidget(
    testApp(
      MediaQuery.withClampedTextScaling(
        minScaleFactor: scale,
        maxScaleFactor: scale,
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: Colors.transparent,
            body: AppBackdrop(
              child: Center(
                child: TextButton(
                  onPressed: () => showPlusPanel(context, files: files, generate: generate, sessionId: session),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
      brightness: brightness,
      overrides: [
        ...harness.overrides,
        ..._extra(modes: modes),
      ],
    ),
  );
  await tester.tap(find.text('打开'));
  await pumpFrames(tester);
  return harness;
}

List<Rect> _tiles(WidgetTester tester) => [
  for (final e in find.byType(PlusTile).evaluate()) tester.getRect(find.byWidget(e.widget)),
];

Rect _card(WidgetTester tester, {int index = 0}) =>
    tester.getRect(find.descendant(of: find.byType(ListPageCard), matching: find.byType(GlassSurface)).at(index));

void main() {
  group('geometry', () {
    for (final width in [320.0, 390.0]) {
      for (final generate in [false, true]) {
        for (final scale in [1.0, 1.3]) {
          testWidgets('${generate ? 4 : 3} tiles at ${width.round()} (×$scale): equal, 8 apart, 16 in; card lined up', (
            tester,
          ) async {
            await _openPanel(tester, width: width, generate: generate, scale: scale);
            final tiles = _tiles(tester);
            expect(tiles, hasLength(generate ? 4 : 3));
            expect(tiles.first.left, moreOrLessEquals(PlusPanelMetrics.side, epsilon: 0.01));
            expect(width - tiles.last.right, moreOrLessEquals(PlusPanelMetrics.side, epsilon: 0.01));
            for (var i = 1; i < tiles.length; i++) {
              expect(tiles[i].width, moreOrLessEquals(tiles.first.width, epsilon: 0.01));
              expect(tiles[i].left - tiles[i - 1].right, moreOrLessEquals(PlusPanelMetrics.gap, epsilon: 0.01));
              expect(tiles[i].top, tiles.first.top);
            }
            if (width == 320 && generate) expect(tiles.first.width, moreOrLessEquals(66, epsilon: 0.01));
            // The coloured squares sit centred in their tiles: mirrored.
            final squares = [
              for (final e in find.byType(PlusTile).evaluate())
                tester.getRect(find.descendant(of: find.byWidget(e.widget), matching: find.byType(Container)).first),
            ];
            expect(
              squares.first.left - tiles.first.left,
              moreOrLessEquals(tiles.last.right - squares.last.right, epsilon: 0.01),
            );
            final card = _card(tester);
            expect(card.left, moreOrLessEquals(tiles.first.left, epsilon: 0.01));
            expect(card.right, moreOrLessEquals(tiles.last.right, epsilon: 0.01));
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    testWidgets('a new chat has tiles only', (tester) async {
      await _openPanel(tester, session: null);
      expect(find.text('本对话'), findsNothing);
      expect(find.byType(ListPageCard), findsNothing);
    });

    testWidgets('生成 closes the panel with its choice', (tester) async {
      PlusChoice? picked;
      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(780, 1688);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => picked = await showPlusPanel(context, generate: true),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await pumpFrames(tester);
      await tester.tap(find.text('生成'));
      await pumpFrames(tester);
      expect(picked, isA<GenerateChoice>());
    });
  });

  group('本对话', () {
    testWidgets('计划模式 runs /plan, then /plan off', (tester) async {
      final harness = await _openPanel(tester);
      final toggle = find.descendant(
        of: find.ancestor(of: find.text('计划模式'), matching: find.byType(ListPageRow)),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await pumpFrames(tester);
      expect(tester.widget<Switch>(toggle).value, isTrue);
      await tester.tap(toggle);
      await pumpFrames(tester);
      expect(harness.controllers['s1']!.commandLines, ['/plan', '/plan off']);
    });

    testWidgets('a plan mode already on reads on', (tester) async {
      await _openPanel(tester, modes: const SessionModes(preset: 'workspace-write', plan: true));
      final toggle = find.descendant(
        of: find.ancestor(of: find.text('计划模式'), matching: find.byType(ListPageRow)),
        matching: find.byType(Switch),
      );
      expect(tester.widget<Switch>(toggle).value, isTrue);
    });
  });

  group('手机操控', () {
    testWidgets('hidden while phone control is off', (tester) async {
      FakePhoneNative(status: phoneStatus(enabled: false)).install();
      await _openPanel(tester);
      expect(find.text('确认方式'), findsNothing);
    });

    testWidgets('确认方式 picks a mode through setPolicies', (tester) async {
      final native = FakePhoneNative(status: phoneStatus(enabled: true))..install();
      await _openPanel(tester);
      await tester.pumpAndSettle();
      expect(find.text('确认方式'), findsOneWidget);
      expect(find.text('每次都询问'), findsOneWidget);
      // The two cards line up with each other.
      expect(_card(tester, index: 1).left, _card(tester).left);
      expect(_card(tester, index: 1).right, _card(tester).right);
      await tester.tap(find.text('确认方式'));
      await pumpFrames(tester);
      await tester.tap(find.text('本任务免确认'));
      await pumpFrames(tester);
      final call = native.callsOf('setPolicies').single;
      expect((call.arguments as Map)['confirmMode'], 'task');
    });
  });

  group('auto-approve pill', () {
    testWidgets('自动允许中 shows while this client allows everything', (tester) async {
      usePhoneView(tester);
      final harness = ChatHarness(
        newChatCatalogs: true,
        session: 's1',
        states: {'s1': const ChatState(loading: false, autoApprove: true)},
      );
      await tester.pumpWidget(
        testApp(
          const ChatScreen(),
          overrides: [
            ...harness.overrides,
            ..._extra(modes: const SessionModes(preset: 'danger-full-access')),
          ],
        ),
      );
      await pumpFrames(tester);
      expect(find.byType(AutoApprovePill), findsOneWidget);
      expect(find.byType(PermissionPill), findsNothing);
    });
  });

  goldens();
}

/// Goldens, run last in [main].
void goldens() {
  group('goldens', () {
    for (final brightness in Brightness.values) {
      final suffix = brightness.name;
      testWidgets('panel with 生成, 本对话 and 手机操控 ($suffix)', (tester) async {
        FakePhoneNative(status: phoneStatus(enabled: true)).install();
        await _openPanel(tester, generate: true, brightness: brightness);
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/plus_panel_$suffix.png'));
      });

      testWidgets('panel at 320 ×1.3 ($suffix)', (tester) async {
        FakePhoneNative(status: phoneStatus(enabled: false)).install();
        await _openPanel(tester, generate: true, width: 320, scale: 1.3, brightness: brightness);
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/plus_panel_320_$suffix.png'));
      });
    }
  });
}
