// Shell wiring smoke: session detail, chat subagent rows, sharing, empty chat.
// Native DS Bot drawer row removed — guest Web owns bot surfaces.
//
//   flutter test --update-goldens test/integration

import 'package:xrk_app/runtime/runtime_state.dart';
import 'package:xrk_app/ui/share/share_panel.dart';
import 'package:xrk_app/state/artifacts.dart';
import 'package:xrk_app/state/chat_state.dart';
import 'package:xrk_app/state/session_detail_state.dart';
import 'package:xrk_app/state/sessions_state.dart';
import 'package:xrk_app/state/workspace_state.dart';
import 'package:xrk_app/state/workspaces_state.dart';
import 'package:xrk_app/ui/chat/chat_screen.dart';
import 'package:xrk_app/ui/chat/composer.dart';
import 'package:xrk_app/ui/chat/empty_state.dart' show chatClock;
import 'package:xrk_app/ui/chat/widgets/artifact_card.dart';
import 'package:xrk_app/ui/chat/widgets/notice_row.dart';
import 'package:xrk_app/ui/chat/widgets/read_only_bar.dart';
import 'package:xrk_app/ui/chat/widgets/tool_row.dart';
import 'package:xrk_app/ui/common/segmented_pill.dart';
import 'package:xrk_app/ui/features/all_features_page.dart';
import 'package:xrk_app/ui/session/session_detail_page.dart';
import 'package:xrk_app/ui/theme/app_icons.dart';
import 'package:xrk_client/xrk_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../agents/support.dart';
import '../chat/support/harness.dart' show ChatHarness, loadTestFonts, pumpFrames, testApp, usePhoneView;
import '../chat/support/run_info_fixture.dart';
import '../chat/support/sample_chat.dart';
import '../shell/golden_harness.dart'
    show FakeCurrentSession, FakeRuntime, FakeSessions, goldenBoth, runningStatus, sampleSessions;

// ── Session detail fakes ──────────────────────────────────────────────────────

class _Panels extends SessionPanelsController {
  _Panels(super.sessionId);

  @override
  SessionPanels build() => SessionPanels.empty;
}

// ── Chat fixtures ─────────────────────────────────────────────────────────────

ChatState _parentChat() => ChatState(
  loading: false,
  title: '修复登录重复提交',
  items: [
    user(1, '把登录的重复提交修好'),
    tool('call-1', 'subagent', {
      'description': '审查改动',
      'prompt': '审查 lib/auth 下的改动',
    }, result: 'started subagent $reviewerId'),
    assistant(3, '审查交给子代理了。'),
  ],
);

ChatState _oneShotChat() => ChatState(
  loading: false,
  title: '查 CI 日志',
  items: [user(1, '查一下 CI 上失败的那一步，结果写进最终回答。'), assistant(2, '失败在 `flutter test`：一个登录页的金图没更新。')],
);

List<Override> _chatOverrides(String? session) => [
  ...ChatHarness(session: session, states: {parentId: _parentChat(), brokenId: _oneShotChat()}).overrides,
  ...agentsOverrides(sampleAgentSessions()),
  workspaceSourceProvider.overrideWith((ref, id) => null),
  workspaceRootProvider.overrideWith((ref, id) => null),
];

Future<ProviderContainer> _pumpChat(WidgetTester tester, String? session, {List<Override> extra = const []}) async {
  usePhoneView(tester);
  await tester.pumpWidget(testApp(const ChatScreen(), overrides: [..._chatOverrides(session), ...extra]));
  await pumpFrames(tester, 6);
  return ProviderScope.containerOf(tester.element(find.byType(ChatScreen)));
}

NoticeChatItem _lapsed(String route) => NoticeChatItem(
  seq: 9,
  kind: 'error',
  text: 'error',
  failure: LlmFailure(
    message:
        'llm-pi-ai: OAuth refresh failed for $route: invalid_grant (refresh '
        'token revoked)',
    code: 'UNKNOWN',
  ),
);

void main() {
  setUpAll(loadTestFonts);

  group('wording and parsing', () {
    test('a lapsed subscription is recognised by provider', () {
      expect(lapsedSubscription(_lapsed('openai-codex').failure), Subscription.chatgpt);
      expect(lapsedSubscription(_lapsed('anthropic').failure), Subscription.claude);
      expect(
        lapsedSubscription(
          const LlmFailure(
            message:
                'OAuth refresh returned a token that expires too soon for '
                'anthropic',
            code: 'UNKNOWN',
          ),
        ),
        Subscription.claude,
      );
      expect(
        lapsedSubscription(
          const LlmFailure(
            message:
                'llm-pi-ai: no credential for provider route "openai-codex"; '
                'its profile resolves …',
            code: 'MISSING_CREDENTIAL',
          ),
        ),
        Subscription.chatgpt,
      );
      // Other providers' OAuth and ordinary failures are not a sign-in.
      expect(lapsedSubscription(_lapsed('github-copilot').failure), isNull);
      expect(lapsedSubscription(const LlmFailure(message: 'HTTP 429 Too Many Requests', code: 'RATE_LIMIT')), isNull);
      expect(lapsedSubscription(null), isNull);
    });

    test('subagent tool calls name the child they talk to', () {
      expect(subagentIdOf(tool('c1', 'subagent', {'description': 'x'}, result: 'started subagent child-7')), 'child-7');
      expect(subagentIdOf(tool('c2', 'send_message', {'agent_id': 'child-8', 'message': 'hi'})), 'child-8');
      // Still streaming / no answer yet, and other tools.
      expect(subagentIdOf(tool('c3', 'subagent', {'description': 'x'}, status: ToolStatus.running)), isNull);
      expect(subagentIdOf(tool('c4', 'bash', {'command': 'ls'})), isNull);
    });
  });

  group('session detail', () {
    testWidgets('six tabs: the last one keeps the same inset as the first', (tester) async {
      usePhoneView(tester);
      await tester.pumpWidget(
        testApp(
          const SessionDetailPage(sessionId: parentId, initialTab: SessionTab.subagents),
          overrides: [..._chatOverrides(parentId), sessionPanelsProvider.overrideWith2(_Panels.new)],
        ),
      );
      await pumpFrames(tester, 6);
      final tabs = find.byType(GlassSegments);
      final track = tester.getRect(tabs);
      final thumb = tester.getRect(find.descendant(of: tabs, matching: find.byType(Positioned)).first);
      expect(find.descendant(of: tabs, matching: find.text('子代理')), findsOneWidget);
      expect(track.right - thumb.right, moreOrLessEquals(SegmentedPill.inset));
      expect(thumb.top - track.top, moreOrLessEquals(SegmentedPill.inset));
      // The label sits in the middle of its thumb, with room on both sides.
      final label = tester.getRect(find.descendant(of: tabs, matching: find.text('子代理')));
      expect(label.left - thumb.left, moreOrLessEquals(thumb.right - label.right, epsilon: 0.5));
      expect(label.left - thumb.left, greaterThanOrEqualTo(6));
    });
  });

  group('chat', () {
    testWidgets('a subagent tool row opens that child', (tester) async {
      final container = await _pumpChat(tester, parentId);
      final row = find.text('审查改动');
      expect(row, findsWidgets);
      expect(find.byIcon(AppIcons.disclosure), findsWidgets);
      await tester.tap(row.first);
      await pumpFrames(tester, 6);
      expect(container.read(currentSessionProvider), reviewerId);
    });

    testWidgets('a one-shot child shows the read-only bar, same size as the composer', (tester) async {
      await _pumpChat(tester, brokenId);
      expect(find.byType(Composer), findsNothing);
      expect(find.text('一次性子代理，只能查看'), findsOneWidget);
      final bar = tester.getRect(find.byType(ReadOnlyBar));
      expect(bar.height, ReadOnlyBar.height);

      // The composer of a continuable conversation sits in the same place.
      await tester.pumpWidget(const SizedBox());
      await _pumpChat(tester, parentId);
      final composer = tester.getRect(find.byType(Composer));
      expect(composer.top, moreOrLessEquals(bar.top, epsilon: 0.5));
      expect(composer.bottom, moreOrLessEquals(bar.bottom, epsilon: 0.5));
    });

    testWidgets('the empty chat names the workspace it starts in', (tester) async {
      await _pumpChat(
        tester,
        null,
        extra: [
          selectedWorkspaceProvider.overrideWithValue(
            const Workspace(workspaceId: 'w1', path: '/root/workspace/dsh-app', title: 'dsh-app', sessionIds: []),
          ),
        ],
      );
      expect(find.text('在「dsh-app」中'), findsOneWidget);
      final chip = find.ancestor(of: find.text('在「dsh-app」中'), matching: find.byType(InkWell));
      // Centred under the greeting.
      final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getCenter(chip.first).dx, moreOrLessEquals(width / 2, epsilon: 0.5));
    });

    testWidgets('a lapsed sign-in says so and offers 重新登录', (tester) async {
      usePhoneView(tester);
      await tester.pumpWidget(
        testApp(
          Scaffold(
            body: Center(child: NoticeRow(item: _lapsed('openai-codex'))),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('ChatGPT 登录已失效'), findsOneWidget);
      expect(find.text('重新登录'), findsOneWidget);
      // The key sits in the row's 24 lead line, vertically centred on it.
      final key = tester.getRect(find.widgetWithText(TextButton, '重新登录'));
      final glyph = tester.getRect(find.byIcon(AppIcons.noApiKey));
      expect(key.center.dy, moreOrLessEquals(glyph.center.dy, epsilon: 0.5));
    });
  });

  group('sharing', () {
    testWidgets('a delivered file has one 分享 (the share panel), none when it can\'t be read', (tester) async {
      usePhoneView(tester);
      const artifact = Artifact(path: '/root/workspace/report.md', origin: ArtifactOrigin.linked, turn: 1);
      final shown = <ArtifactAction?>[];
      Future<void> open(BuildContext context, {required bool canFetch}) async =>
          shown.add(await showArtifactMenu(context, artifact: artifact, canFetch: canFetch));
      await tester.pumpWidget(
        testApp(
          Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(onPressed: () => open(context, canFetch: true), child: const Text('fetch')),
                  TextButton(onPressed: () => open(context, canFetch: false), child: const Text('path only')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('fetch'));
      await tester.pumpAndSettle();
      expect(find.text('分享'), findsOneWidget);
      expect(find.text('分享图片'), findsNothing);
      await tester.tap(find.text('分享'));
      await tester.pumpAndSettle();
      expect(shown.last, ArtifactAction.share);
      await tester.tap(find.text('path only'));
      await tester.pumpAndSettle();
      expect(find.text('分享'), findsNothing);
    });
  });

  group('goldens', () {
    for (final brightness in Brightness.values) {
      final mode = brightness.name;

      testWidgets('all features, every group ($mode)', (tester) async {
        // Tall enough for every group at once.
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 3000);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          testApp(const AllFeaturesPage(), brightness: brightness, overrides: _chatOverrides(parentId)),
        );
        await pumpFrames(tester, 8);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/all_features_full_$mode.png'));
      });

      testWidgets('one-shot child, read-only ($mode)', (tester) async {
        usePhoneView(tester);
        await tester.pumpWidget(
          testApp(const ChatScreen(), brightness: brightness, overrides: _chatOverrides(brokenId)),
        );
        await pumpFrames(tester, 6);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_read_only_$mode.png'));
      });

      testWidgets('new chat in a workspace ($mode)', (tester) async {
        // The greeting follows the clock: the afternoon, as in the chat
        // goldens.
        chatClock = () => DateTime(2026, 10, 23, 15, 20);
        addTearDown(() => chatClock = DateTime.now);
        usePhoneView(tester);
        await tester.pumpWidget(
          testApp(
            const ChatScreen(),
            brightness: brightness,
            overrides: [
              ..._chatOverrides(null),
              selectedWorkspaceProvider.overrideWithValue(
                const Workspace(workspaceId: 'w1', path: '/root/workspace/dsh-app', title: 'dsh-app', sessionIds: []),
              ),
            ],
          ),
        );
        await pumpFrames(tester, 8);
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/chat_empty_workspace_$mode.png'));
      });

      testWidgets('lapsed sign-in row ($mode)', (tester) async {
        usePhoneView(tester);
        await tester.pumpWidget(
          testApp(
            Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    NoticeRow(item: _lapsed('openai-codex')),
                    NoticeRow(item: _lapsed('anthropic')),
                  ],
                ),
              ),
            ),
            brightness: brightness,
          ),
        );
        await tester.pump();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/notice_lapsed_$mode.png'));
      });
    }
  });
}

