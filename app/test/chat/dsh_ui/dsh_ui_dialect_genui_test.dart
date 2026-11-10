// The genui dialect of the ```dsh-ui fence (docs/design/plugin-ui-v3.md
// §3.2): `@changfenhuang/dsh-genui` writes its own JSON under the same fence.
// Its blocks become a read-only plugin view, never 「格式有误 + 让它重发」.

import 'dart:convert';

import 'package:xrk_app/l10n/l10n.dart';
import 'package:xrk_app/ui/chat/xrk_ui/xrk_ui.dart';
import 'package:xrk_app/ui/chat/xrk_ui/xrk_ui_dialect_card.dart';
import 'package:xrk_app/ui/chat/xrk_ui/xrk_ui_dialect_genui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

String j(Object json) => jsonEncode(json);

/// A status report the way genui's SKILL.md teaches it.
final report = j({
  'title': '本周构建',
  'items': [
    {
      'type': 'grid',
      'cols': 3,
      'items': [
        {'type': 'stat', 'label': '通过', 'value': '26', 'delta': '+4'},
        {'type': 'stat', 'label': '失败', 'value': '2', 'delta': '-1'},
        {'type': 'stat', 'label': '耗时', 'value': '6.2 分'},
      ],
    },
    {
      'type': 'table',
      'columns': ['任务', '状态', '耗时'],
      'types': ['text', 'badge', 'num'],
      'rows': [
        ['lint', '通过', 42],
        ['test', '失败', 318],
      ],
    },
    {
      'type': 'steps',
      'current': 1,
      'steps': [
        {'title': '拉代码'},
        {'title': '跑测试', 'desc': '第 2 个分片失败'},
        {'title': '发布'},
      ],
    },
    {'type': 'callout', 'tone': 'warning', 'title': '注意', 'content': '`test` 的 [日志](https://ci.example/1) 里有 ==超时=='},
    {'type': 'echart', 'preset': 'bar', 'data': []},
    {'type': 'button', 'label': '重跑', 'action': 'rerun'},
    {'type': 'submit', 'label': '提交', 'action': 'grade'},
  ],
});

void main() {
  group('detection', () {
    test('genui roots: an items envelope, a bare genui component, a root list', () {
      expect(isGenuiDialect(jsonDecode(report)), isTrue);
      expect(isGenuiDialect({'type': 'stat', 'label': 'a', 'value': '1'}), isTrue);
      expect(
        isGenuiDialect([
          {'type': 'keyvalue', 'pairs': []},
        ]),
        isTrue,
      );
      expect(isGenuiDialect({'type': 'text', 'content': '你好'}), isTrue);
      expect(isGenuiDialect({'type': 'steps', 'steps': []}), isTrue);
    });

    test("the app's own format is never taken for genui", () {
      expect(
        isGenuiDialect({
          'type': 'stack',
          'children': [
            {'type': 'metric', 'label': 'a', 'value': 1},
          ],
        }),
        isFalse,
      );
      expect(isGenuiDialect({'type': 'text', 'text': '你好'}), isFalse);
      expect(
        isGenuiDialect([
          {'type': 'metric', 'label': 'a', 'value': 1},
        ]),
        isFalse,
      );
      expect(
        isGenuiDialect({
          'type': 'steps',
          'items': ['a'],
        }),
        isFalse,
      );
      expect(isGenuiDialect('nope'), isFalse);
    });
  });

  group('mapping', () {
    test('a status report becomes a read-only plugin view, marked genui', () {
      final parsed = parseXrkUiUncached(report);
      expect(parsed, isA<XrkUiParsed>());
      final view = (parsed as XrkUiParsed).view;
      expect(view.dialect, 'genui');
      expect(view.version, 2);
      expect(view.title, '本周构建');
      expect(view.interactive, isFalse, reason: 'nothing in a genui block answers the model from the app');

      final metrics = view.nodes.whereType<XrkUiMetric>().toList();
      expect([for (final m in metrics) m.label], ['通过', '失败', '耗时']);
      expect([for (final m in metrics) m.tone], [XrkUiTone.good, XrkUiTone.bad, null]);
      expect(metrics.first.caption, '+4');

      final table = view.nodes.whereType<XrkUiTable>().single;
      expect([for (final c in table.columns) c.label], ['任务', '状态', '耗时']);

      final steps = view.nodes.whereType<XrkUiSteps>().single;
      expect(
        [for (final s in steps.items) s.status],
        [XrkUiStepStatus.done, XrkUiStepStatus.current, XrkUiStepStatus.todo],
      );
      expect(steps.items[1].detail, '第 2 个分片失败');

      // A callout is a tinted panel: the title in the tone's colour, then the words.
      final texts = [for (final n in view.nodes.whereType<XrkUiText>()) n.text];
      expect(
        texts,
        containsAllInOrder(['注意', '`test` 的 日志 里有 超时']),
        reason: 'links keep their words, highlights their text',
      );
      final panel = view.nodes.whereType<XrkUiLayout>().firstWhere(
        (l) => l.children.whereType<XrkUiText>().any((t) => t.text == '注意'),
      );
      expect(view.styles[panel.path]?.card, XrkUiCardStyle.tinted);
    });

    test('parts without a native counterpart read 「… · 在网页版查看」; a run of them folds into one', () {
      final view = (parseXrkUiUncached(report) as XrkUiParsed).view;
      final tags = [
        for (final n in view.nodes)
          if (n is XrkUiControlDisplay && n.kind == 'tag') n.text,
      ];
      expect(tags, [
        appL10n.viewUiDialectWebOnly(appL10n.viewUiDialectKindChart),
        appL10n.viewUiDialectWebOnly(appL10n.viewUiDialectKindInteractive),
      ]);
      expect(view.nodes.whereType<XrkUiPlaceholder>(), isEmpty, reason: 'no grey 「这部分无法显示」 rows');
      expect([for (final i in view.issues) i.path], containsAll(['spec.items[4]', 'spec.items[5]', 'spec.items[6]']));
    });

    test('genui chart data become categories and aligned series', () {
      final view = (parseXrkUiUncached(
        j({
          'items': [
            {
              'type': 'chart',
              'kind': 'bars',
              'horizontal': true,
              'series': [
                {
                  'label': '今年',
                  'data': [
                    {'label': 'Q1', 'value': 30},
                    {'label': 'Q2', 'value': 45},
                  ],
                },
                {
                  'label': '去年',
                  'data': [
                    {'label': 'Q2', 'value': 20},
                  ],
                },
              ],
            },
          ],
        }),
      ) as XrkUiParsed).view;
      final chart = view.nodes.whereType<XrkUiChart>().single;
      expect(chart.kind, XrkUiChartKind.hbar);
      expect(chart.categories, ['Q1', 'Q2']);
      expect([for (final s in chart.series) s.name], ['今年', '去年']);
      expect(chart.series[1].values, [null, 20]);
    });

    test('keyvalue, list aliases, timeline, tabs and code map to their native components', () {
      final view = (parseXrkUiUncached(
        j({
          'items': [
            {
              'type': 'keyvalue',
              'pairs': [
                {'key': '版本', 'value': '0.2.1'},
              ],
            },
            {
              'type': 'list',
              'items': [
                '纯文字',
                {'label': '标题', 'description': '说明'},
              ],
            },
            {
              'type': 'timeline',
              'items': [
                {'title': '发布', 'time': '10-30', 'desc': '公测'},
              ],
            },
            {
              'type': 'tabs',
              'tabs': [
                {
                  'label': '概览',
                  'items': [
                    {'type': 'text', 'content': '内容'},
                  ],
                },
              ],
            },
            {'type': 'code', 'lang': 'ts', 'code': 'const a = 1'},
            {
              'type': 'json',
              'value': {'ok': true},
            },
          ],
        }),
      ) as XrkUiParsed).view;
      final kv = view.nodes.whereType<XrkUiKeyValue>().single;
      expect(kv.items.single.label, '版本');
      final list = view.nodes.whereType<XrkUiList>().single;
      expect([for (final i in list.items) (i.title, i.subtitle)], [('纯文字', null), ('标题', '说明')]);
      final containers = view.nodes.whereType<XrkUiControlContainer>().toList();
      expect([for (final c in containers) c.kind], ['timeline', 'tabs']);
      expect(containers.first.sections.single.label, '10-30 · 发布');
      final code = [
        for (final n in view.nodes)
          if (n is XrkUiControlDisplay && n.kind == 'codeBlock') (n.language, n.text),
      ];
      expect(code.first, ('ts', 'const a = 1'));
      expect(code.last.$1, 'json');
    });

    test('only inline images show; a host or web address reads 「图片 · 在网页版查看」', () {
      const pixel =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      final view = (parseXrkUiUncached(
        j({
          'items': [
            {'type': 'image', 'src': pixel, 'alt': '点'},
            {'type': 'image', 'src': '/mmx-files/a.png'},
            {'type': 'image', 'src': 'https://example.com/a.png'},
          ],
        }),
      ) as XrkUiParsed).view;
      expect(view.nodes.whereType<XrkUiImage>(), hasLength(1));
      final tags = [
        for (final n in view.nodes)
          if (n is XrkUiControlDisplay && n.kind == 'tag') n.text,
      ];
      expect(tags, [appL10n.viewUiDialectWebOnly(appL10n.viewUiDialectKindImage)]);
    });

    test('stat spark → metric trend (last 30), progress ring → ring, image-group → gallery', () {
      const pixel =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      final view = (parseXrkUiUncached(
        j({
          'items': [
            {
              'type': 'stat',
              'label': '余额',
              'value': '¥12',
              'spark': [for (var i = 0; i < 40; i++) i],
            },
            {
              'type': 'stat',
              'label': '坏的',
              'value': '1',
              'spark': [1, 'x'],
            },
            {'type': 'progress', 'variant': 'ring', 'value': 40, 'label': '额度'},
            {
              'type': 'image-group',
              'items': [
                {'src': pixel, 'alt': '一', 'caption': '第一张'},
                {'src': 'https://example.com/b.png', 'alt': '外链'},
                {'src': pixel, 'alt': '二'},
              ],
            },
          ],
        }),
      ) as XrkUiParsed).view;
      final metrics = view.nodes.whereType<XrkUiMetric>().toList();
      expect(metrics.first.trend, [for (var i = 10; i < 40; i++) i.toDouble()]);
      expect(metrics.last.trend, isNull, reason: 'a spark that is not all numbers is left out, not noted');
      expect(view.nodes.whereType<XrkUiProgress>().single.ring, isTrue);
      final gallery = view.nodes.whereType<XrkUiGallery>().single;
      expect(gallery.items.map((i) => i.image.alt), ['一', '二'], reason: 'only inline pictures');
      expect(gallery.items.first.caption, '第一张');
      expect(gallery.items.every((i) => i.action == null), isTrue);
    });

    test('a block with nothing to show stays a quiet fallback, marked genui (no resend)', () {
      final parsed = parseXrkUiUncached(
        j({
          'items': [
            {'type': 'arrow', 'dir': 'down'},
            {'type': 'icon', 'name': 'Nodes'},
          ],
        }),
      );
      expect(parsed, isA<XrkUiInvalid>());
      expect((parsed as XrkUiInvalid).dialect, 'genui');
    });

    test('a genui block may use the panel budget; the app format keeps its 16 KiB limit', () {
      final rows = [
        for (var i = 0; i < 50; i++) ['任务 $i', '这一行的说明写得比较长，用来把整块撑过十六 KiB。' * 6, '$i'],
      ];
      final big = j({
        'items': [
          {
            'type': 'table',
            'columns': ['任务', '说明', '序号'],
            'rows': rows,
          },
          {
            'type': 'list',
            'items': [for (var i = 0; i < 50; i++) '第 $i 条：这一条也写得很长很长，帮整块越过模型卡的上限'],
          },
        ],
      });
      expect(utf8.encode(big).length, greaterThan(XrkUiLimits.hardBytes));
      expect(parseXrkUiUncached(big), isA<XrkUiParsed>());

      final own = j({
        'type': 'stack',
        'children': [
          for (var i = 0; i < 120; i++) {'type': 'text', 'text': '这一段写得很长很长很长很长很长很长很长很长很长。' * 2 + '$i'},
        ],
      });
      expect(utf8.encode(own).length, greaterThan(XrkUiLimits.hardBytes));
      expect(parseXrkUiUncached(own), isA<XrkUiInvalid>());
      expect((parseXrkUiUncached(own) as XrkUiInvalid).dialect, isNull);
    });

    test('the mapped tree never carries an action', () {
      final mapping = genuiToPluginView(jsonDecode(report));
      final text = jsonEncode(mapping.view);
      expect(text.contains('"action"'), isFalse);
      expect(text.contains('"onChange"'), isFalse);
      expect(text.contains('"bind"'), isFalse);
    });

    test('mapping is total on hostile input', () {
      for (final input in <Object?>[
        null,
        42,
        'x',
        <Object?>[],
        {'items': 'nope'},
        {
          'items': [null, 1, 'a', <Object?>[], {}],
        },
        {
          'items': [
            {'type': 'table', 'columns': 'x', 'rows': 3},
            {'type': 'chart', 'data': 'x'},
            {
              'type': 'grid',
              'cols': 'x',
              'items': [
                {'type': 'stat'},
              ],
            },
            {'type': 'card'},
            {'type': 'tabs', 'tabs': 'x'},
            {
              'type': 'steps',
              'current': 'x',
              'steps': [1, null],
            },
          ],
        },
      ]) {
        expect(() => genuiToPluginView(input), returnsNormally, reason: '$input');
      }
    });
  });

  group('block', () {
    setUpAll(loadTestFonts);

    testWidgets('a genui block draws the read-only card, no resend', (tester) async {
      usePhoneView(tester);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: SingleChildScrollView(
              child: XrkUiScope(
                sessionId: 's1',
                messageId: 'a1',
                state: XrkUiState.live,
                onReply: (_) async => true,
                onAskResend: (_) async => true,
                child: XrkUiBlock(source: report),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(XrkUiDialectCard), findsOneWidget);
      expect(find.text('拉代码'), findsOneWidget);
      expect(find.text(appL10n.viewUiResend), findsNothing);
      expect(find.text(appL10n.viewUiInvalid), findsNothing);
      expect(
        find.byKey(const ValueKey('plugin-v2-attribution')),
        findsNothing,
        reason: 'model output, not a plugin surface',
      );
    });

    testWidgets('an unmappable genui block falls back without offering a resend', (tester) async {
      usePhoneView(tester);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: XrkUiScope(
              sessionId: 's1',
              messageId: 'a1',
              state: XrkUiState.live,
              onReply: (_) async => true,
              onAskResend: (_) async => true,
              child: XrkUiBlock(
                source: j({
                  'items': [
                    {'type': 'arrow'},
                  ],
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(appL10n.viewUiDialectInvalid), findsOneWidget);
      expect(find.text(appL10n.viewUiResend), findsNothing);
    });
  });
}
