// `accent: "app"` (docs/design/plugin-ui-v3.md §4.3): a v2 view takes the
// person's palette, still corrected to ≥ 4.5:1 on every painted background,
// and parses again when the palette changes.

import 'package:xrk_app/ui/chat/xrk_ui/xrk_ui_model.dart';
import 'package:xrk_app/ui/plugins/view/plugin_view.dart';
import 'package:xrk_app/ui/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

int _rgb(Color c) => c.toARGB32() & 0xFFFFFF;

/// A small status card that leans on the accent: a tinted panel, accent
/// text, a highlighted span.
Map<String, Object?> _view() => {
  'v': 2,
  'accent': 'app',
  'type': 'stack',
  'title': '本周',
  'children': [
    {
      'type': 'stack',
      'style': {'card': 'tinted', 'gap': 'S'},
      'children': [
        {
          'type': 'text',
          'text': '完成 7 / 10',
          'style': {'size': 'title', 'weight': 'bold', 'color': 'accent'},
        },
        {
          'type': 'text',
          'text': '还剩 3 项',
          'spans': [
            {'text': '还剩 '},
            {'text': '3', 'mono': true, 'background': 'accent'},
            {'text': ' 项'},
          ],
        },
      ],
    },
    {'type': 'progress', 'value': 70, 'label': '进度'},
  ],
};

void main() {
  tearDown(() => XrkUiAppAccent.set(XrkUiAppAccent.fallback));

  test("the default is the app's default palette, 雾蓝", () {
    expect(XrkUiAppAccent.fallback, _rgb(AppAccent.mist.seed));
    final view = (parsePluginView(_view()) as XrkUiParsed).view;
    expect(view.styles[view.root.path]!.accent.light, _rgb(AppAccent.mist.seed), reason: 'already ≥ 4.5:1 on the light surface');
  });

  test('a palette change re-parses the same view object with the new accent', () {
    final json = _view();
    final before = (parsePluginView(json) as XrkUiParsed).view;
    XrkUiAppAccent.set(_rgb(AppAccent.amber.seed));
    final after = (parsePluginView(json) as XrkUiParsed).view;
    expect(identical(before, after), isFalse);
    expect(after.styles[after.root.path]!.accent.light, isNot(before.styles[before.root.path]!.accent.light));
  });

  test('the same colour twice is no change (the cache stays)', () {
    final json = _view();
    final first = (parsePluginView(json) as XrkUiParsed).view;
    XrkUiAppAccent.set(XrkUiAppAccent.fallback);
    expect(identical((parsePluginView(json) as XrkUiParsed).view, first), isTrue);
  });

  test('every preset stays readable: accent ≥ 4.5:1 on the light and the dark surface', () {
    for (final preset in AppAccent.presets) {
      XrkUiAppAccent.set(_rgb(preset.seed));
      final view = (parsePluginView(_view()) as XrkUiParsed).view;
      final accent = view.styles[view.root.path]!.accent;
      for (final dark in [false, true]) {
        final ratio = xrkUiContrast(accent.at(dark), XrkUiPluginPalette.surface.at(dark));
        expect(ratio, greaterThanOrEqualTo(4.5), reason: '${preset.id} dark=$dark');
      }
    }
  });

  test('"app" is an accent, not a colour: elsewhere it is a note', () {
    final view =
        (parsePluginView({
                  'v': 2,
                  'type': 'text',
                  'text': 'x',
                  'style': {'color': 'app'},
                })
                as XrkUiParsed)
            .view;
    expect(view.issues.map((i) => i.path), contains('view.style.color'));
  });

  group('golden', () {
    setUpAll(loadTestFonts);
    for (final brightness in Brightness.values) {
      testWidgets('follows 黛青 (${brightness.name})', (tester) async {
        XrkUiAppAccent.set(_rgb(AppAccent.daiqing.seed));
        usePhoneView(tester);
        tester.view.physicalSize = const Size(780, 760);
        await tester.pumpWidget(
          testApp(
            Scaffold(
              body: AppBackdrop(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 56, 16, 24),
                  children: [PluginFrame(pluginName: '进度', icon: 'chart', child: PluginView(view: _view()))],
                ),
              ),
            ),
            brightness: brightness,
          ),
        );
        await pumpFrames(tester);
        await expectLater(find.byType(Scaffold), matchesGoldenFile('goldens/plugin_view_app_accent_${brightness.name}.png'));
      });
    }
  });
}
