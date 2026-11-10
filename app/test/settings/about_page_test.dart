import 'dart:ui' show SemanticsAction;

import 'package:xrk_app/l10n/l10n.dart';
import 'package:xrk_app/state/app_info.dart';
import 'package:xrk_app/state/star_prompt.dart';
import 'package:xrk_app/state/update_state.dart';
import 'package:xrk_app/ui/settings/about_page.dart';
import 'package:xrk_app/ui/settings/settings_widgets.dart';
import 'package:xrk_app/ui/theme/theme.dart';
import 'package:xrk_app/update/version.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_fonts.dart';

class _FixedUpdate extends AppUpdateController {
  @override
  AppUpdateState build() => const AppUpdateState(current: AppVersion(1, 0, 2, build: 42));
}

class _StarStore implements StarPromptStore {
  final writes = <StarPromptRecord>[];

  @override
  Future<StarPromptRecord?> read() async => const StarPromptRecord();

  @override
  Future<void> write(StarPromptRecord record) async => writes.add(record);
}

const _githubKey = 'about-author-github';
const _githubUrl = 'https://github.com/xrkseek/XRK-harness-mobile';

void main() {
  late List<Uri> opened;
  late _StarStore store;
  late Future<bool> Function(Uri) opener;

  setUp(() {
    opened = [];
    store = _StarStore();
    opener = (uri) async {
      opened.add(uri);
      return true;
    };
  });

  tearDown(() => AppLocale.use(AppLocale.zhCN));

  Future<void> pump(
    WidgetTester tester, {
    Locale locale = AppLocale.zhCN,
    Brightness brightness = Brightness.light,
    double scale = 1,
  }) async {
    AppLocale.use(locale);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateProvider.overrideWith(_FixedUpdate.new),
          starLinkOpenerProvider.overrideWithValue((uri) => opener(uri)),
          starPromptStoreProvider.overrideWithValue(store),
          starPromptGateProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: withTestFonts(buildLightTheme()),
          darkTheme: withTestFonts(buildDarkTheme()),
          themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
          locale: locale,
          supportedLocales: AppLocale.supported,
          localizationsDelegates: L10n.localizationsDelegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const AboutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final row = find.byKey(ValueKey(key));
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  for (final locale in AppLocale.supported) {
    for (final brightness in Brightness.values) {
      testWidgets('source repo row fits 360dp at 1.3x in $locale $brightness', (tester) async {
        await pump(tester, locale: locale, brightness: brightness, scale: 1.3);
        final english = locale == AppLocale.en;
        expect(find.text(english ? 'Source repository' : '开源仓库'), findsOneWidget);
        expect(find.text(AppInfo.authorGithubHandle), findsOneWidget);
        expect(find.text('1.0.2 (42)'), findsOneWidget);
        expect(find.byKey(const ValueKey('settings-star')), findsOneWidget);
        expect(find.text(english ? 'GitHub profile' : 'GitHub 主页'), findsOneWidget);
        expect(find.text(english ? 'Bilibili profile' : 'B站主页'), findsNothing);
        expect(find.text(english ? 'X profile' : 'X 主页'), findsNothing);

        final row = find.byKey(const ValueKey(_githubKey));
        await tester.ensureVisible(row);
        await tester.pumpAndSettle();
        expect(tester.getSize(row).height, greaterThanOrEqualTo(64));
        expect(tester.widget<SettingsTile>(row).onTap, isNotNull);
        expect(tester.takeException(), isNull);

        final disclaimer = find.text(
          english ? 'Official XRK Harness · Local-first' : 'XRK Harness 官方产品 · 本地优先',
        );
        await tester.ensureVisible(disclaimer);
        await tester.pumpAndSettle();
        expect(disclaimer.hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('GitHub author row opens the product repository without finishing star', (tester) async {
    await pump(tester);
    await tap(tester, _githubKey);
    expect(opened.map((uri) => uri.toString()), [_githubUrl]);
    expect(store.writes, isEmpty);
  });

  testWidgets('the separate project star still opens the repository', (tester) async {
    await pump(tester);
    await tap(tester, 'settings-star');
    expect(opened.map((uri) => uri.toString()), [_githubUrl]);
    expect(store.writes.last.finished, isTrue);
  });

  testWidgets('no browser copies the GitHub URL and reports it', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    opener = (_) async => false;
    await pump(tester);
    await tap(tester, _githubKey);
    expect(clipboard, _githubUrl);
    expect(find.text('没能打开浏览器，网址已复制'), findsOneWidget);
    expect(store.writes, isEmpty);
  });

  testWidgets('browser and clipboard exceptions report failure without claiming a copy', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') throw PlatformException(code: 'no-clipboard');
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    opener = (_) async => throw PlatformException(code: 'no-browser');
    await pump(tester, locale: AppLocale.en);
    await tap(tester, _githubKey);
    expect(find.text(lookupL10n(AppLocale.en).stateBrowserOpenFailed), findsOneWidget);
    expect(find.text(lookupL10n(AppLocale.en).shellBrowserUrlCopied), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('GitHub row is announced as an actionable link', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pump(tester, locale: AppLocale.en);
      final row = find.byKey(const ValueKey(_githubKey));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final node = tester.getSemantics(row);
      expect(node.flagsCollection.isLink, isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    } finally {
      semantics.dispose();
    }
  });
}
