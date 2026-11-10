import 'package:xrk_app/ui/chat/xrk_ui/xrk_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sample_chat.dart';

void main() {
  group('reply text', () {
    test('a choice is the marker, the title and the visible labels', () {
      final reply = XrkUiReply.choice(['方案 A'], title: '选一个方案');
      expect(reply.text, '[dsh-ui reply] 选一个方案\n选择：方案 A');
      expect(reply.chipLabel, '已选择：方案 A');
      expect(XrkUiReply.choice(['A', 'C']).text, '[dsh-ui reply]\n选择：A、C');
    });

    test('line breaks in labels and titles are flattened', () {
      final reply = XrkUiReply.choice(['第一\n第二 '], title: ' 两行\n标题 ');
      expect(reply.text, '[dsh-ui reply] 两行 标题\n选择：第一 第二');
      expect(parseXrkUiReply(reply.text), reply);
    });

    test('a free-text answer rides on its own line', () {
      final both = XrkUiReply.choice(['方案 A'], title: '选一个方案', freetext: '先算一次成本');
      expect(both.text, '[dsh-ui reply] 选一个方案\n选择：方案 A\n其他：先算一次成本');
      expect(parseXrkUiReply(both.text), both);
      expect(both.chipLabel, '已选择：方案 A · 已填写：先算一次成本');

      final only = XrkUiReply.choice(const [], freetext: '都不要，先别动');
      expect(only.text, '[dsh-ui reply]\n其他：都不要，先别动');
      expect(parseXrkUiReply(only.text), only);
      expect(only.chipLabel, '已填写：都不要，先别动');
    });

    test('confirm and cancel skip the default words', () {
      expect(XrkUiReply.confirm(true, label: '开始').text, '[dsh-ui reply]\n确认：开始');
      expect(XrkUiReply.confirm(true, label: '确认').text, '[dsh-ui reply]\n确认');
      expect(XrkUiReply.confirm(false, label: '取消').text, '[dsh-ui reply]\n取消');
      expect(XrkUiReply.confirm(false, label: '再想想').text, '[dsh-ui reply]\n取消：再想想');
      expect(XrkUiReply.confirm(true).chipLabel, '已确认');
      expect(XrkUiReply.confirm(true, label: '开始').chipLabel, '已确认：开始');
      expect(XrkUiReply.confirm(false).chipLabel, '已取消');
    });
  });

  group('parsing a reply', () {
    test('round-trips what we send', () {
      for (final reply in [
        XrkUiReply.choice(['方案 A'], title: '选一个方案'),
        XrkUiReply.choice(['A', 'B']),
        XrkUiReply.confirm(true, label: '开始', title: '部署'),
        XrkUiReply.confirm(false),
      ]) {
        expect(parseXrkUiReply(reply.text), reply, reason: reply.text);
      }
    });

    test('takes half-width colons, blank lines and stray spaces', () {
      final reply = parseXrkUiReply('  [dsh-ui reply]  标题 \n\n选择: A ');
      expect(reply, const XrkUiReply(kind: XrkUiReplyKind.choice, title: '标题', value: 'A'));
    });

    test('an unknown body is still a reply', () {
      final reply = parseXrkUiReply('[dsh-ui reply] X\n数值：首付=30%');
      expect(reply!.kind, XrkUiReplyKind.other);
      expect(reply.chipLabel, '数值：首付=30%');
      expect(parseXrkUiReply('[dsh-ui reply]')!.chipLabel, '已回复');
    });

    test('ordinary messages are not replies', () {
      expect(parseXrkUiReply('选择：方案 A'), isNull);
      expect(parseXrkUiReply('好的 [dsh-ui reply]'), isNull);
      expect(xrkUiReplyChip('你好'), isNull);
      expect(xrkUiReplyChip('[dsh-ui reply] 计划\n确认'), '已确认');
    });

    test('labels that contain the separator are matched whole', () {
      final reply = XrkUiReply.choice(['红、绿', '蓝']);
      expect(reply.selectedIn(['红、绿', '蓝', '黄']), ['红、绿', '蓝']);
      expect(reply.choices, ['红', '绿', '蓝']);
    });
  });

  group('state from the message order (§3.5)', () {
    final view = assistant(2, '看完再选');
    const reply = '[dsh-ui reply] 选一个方案\n选择：方案 A';

    test('the last reply of a finished turn can be answered', () {
      final state = xrkUiStateFor(items: [user(1, '帮我比较'), view], messageId: view.id, running: false);
      expect(state, XrkUiState.live);
      expect(state.canAnswer, isTrue);
    });

    test('a running turn disables it', () {
      expect(xrkUiStateFor(items: [user(1, 'q'), view], messageId: view.id, running: true), XrkUiState.running);
      final streaming = assistant(2, '看完再选', streaming: true);
      expect(xrkUiStateFor(items: [streaming], messageId: streaming.id, running: false), XrkUiState.running);
    });

    test('a reply after it answers it; anything else expires it', () {
      final answered = xrkUiStateFor(
        items: [view, user(3, reply), assistant(4, '好的')],
        messageId: view.id,
        running: true,
      );
      expect(answered.interaction, XrkUiInteraction.answered);
      expect(answered.reply!.value, '方案 A');
      expect(xrkUiStateFor(items: [view, user(3, '换个思路')], messageId: view.id, running: false), XrkUiState.expired);
      // Only the first user message after the view counts.
      expect(
        xrkUiStateFor(items: [view, user(3, '等等'), user(5, reply)], messageId: view.id, running: false),
        XrkUiState.expired,
      );
    });

    test('the model talking on (after a tool call) expires it', () {
      expect(
        xrkUiStateFor(
          items: [
            view,
            tool('t1', 'bash', {'command': 'ls'}),
            assistant(4, '我先看一下'),
          ],
          messageId: view.id,
          running: false,
        ),
        XrkUiState.expired,
      );
      // An empty assistant step does not.
      expect(xrkUiStateFor(items: [view, assistant(4, '  ')], messageId: view.id, running: false), XrkUiState.live);
    });

    test('a prompt sent but not yet echoed already counts', () {
      final state = xrkUiStateFor(items: [view], messageId: view.id, running: false, pending: [reply]);
      expect(state.interaction, XrkUiInteraction.answered);
      expect(xrkUiStateFor(items: [view], messageId: view.id, running: false, pending: ['别的']), XrkUiState.expired);
    });

    test('an unknown message is read-only', () {
      expect(xrkUiStateFor(items: [view], messageId: 'a404', running: false), XrkUiState.expired);
    });
  });

  group('which view a reply answers', () {
    XrkUiView parse(String json) => (parseXrkUiUncached(json) as XrkUiParsed).view;

    final titled = parse(
      '{"type":"stack","title":"选一个方案","children":['
      '{"type":"options","id":"plan","options":[{"label":"方案 A"},{"label":"方案 B"}]}]}',
    );

    test('titles must agree when both have one', () {
      final ok = xrkUiAnswerFor(titled, XrkUiReply.choice(['方案 B'], title: '选一个方案'));
      expect(ok!.selected, ['方案 B']);
      expect(xrkUiAnswerFor(titled, XrkUiReply.choice(['方案 B'], title: '别的卡')), isNull);
      expect(xrkUiAnswerFor(titled, XrkUiReply.choice(['方案 B'])), isNotNull);
    });

    test('a confirm reply needs a confirm', () {
      expect(xrkUiAnswerFor(titled, XrkUiReply.confirm(true)), isNull);
      final confirm = parse('{"type":"confirm","confirmLabel":"开始"}');
      expect(xrkUiAnswerFor(confirm, XrkUiReply.confirm(true, label: '开始'))!.confirmed, isTrue);
    });

    test('free text only counts on a card that allows it', () {
      final free = parse(
        '{"type":"stack","children":['
        '{"type":"options","id":"plan","freetext":true,"options":[{"label":"方案 A"}]}]}',
      );
      final typed = xrkUiAnswerFor(free, XrkUiReply.choice(const [], freetext: '再算一次'));
      expect(typed!.selected, isEmpty);
      expect(typed.freetext, '再算一次');
      // 选项和「其他」可以一起答。
      final both = xrkUiAnswerFor(free, XrkUiReply.choice(['方案 A'], freetext: '先别动'));
      expect(both!.selected, ['方案 A']);
      expect(both.freetext, '先别动');
      // 没开 freetext 的卡不认这句。
      expect(xrkUiAnswerFor(titled, XrkUiReply.choice(const [], freetext: '再算一次')), isNull);
    });
  });
}
