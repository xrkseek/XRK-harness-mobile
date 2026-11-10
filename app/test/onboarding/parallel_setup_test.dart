// First run on this phone sets up while the runtime unpacks: welcome then
// the access walk beside the unpack; no Remote / DeepSeek connect.

import 'package:xrk_app/runtime/runtime_bridge.dart';
import 'package:xrk_app/runtime/runtime_state.dart';
import 'package:xrk_app/state/onboarding_state.dart';
import 'package:xrk_app/ui/onboarding/access_step.dart';
import 'package:xrk_app/ui/onboarding/onboarding_flow.dart';
import 'package:xrk_app/ui/onboarding/runtime_setup_page.dart';
import 'package:xrk_app/ui/onboarding/setup_progress.dart';
import 'package:xrk_app/ui/shell/root_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_optional_support.dart';
import 'parallel_setup_support.dart';

const _capsule = ValueKey('setup-capsule');
const _seen = OnboardingPrefs(loaded: true, welcomeSeen: true);

Finder _capsuleText(String text) => find.descendant(of: find.byKey(_capsule), matching: find.text(text));

Future<void> skipAccess(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, '跳过'));
  await frames(tester);
}

void main() {
  setUp(useSavedHost);

  group('where a launch resumes', () {
    const fresh = OnboardingPrefs(loaded: true, welcomeSeen: true);
    OnboardingStep? at(SetupStep step, RuntimeStatus status, {bool key = false, bool skipped = false}) =>
        initialOnboardingStep(
          status: status,
          hasApiKey: key,
          prefs: fresh.copyWith(setupStep: step, keySkipped: skipped),
        );

    test('back on the page it was on, whatever the unpack did meanwhile', () {
      for (final status in [missingStatus, installingStatus, failedStatus, stoppedStatus]) {
        expect(at(SetupStep.appearance, status), OnboardingStep.access, reason: '${status.phase}');
        expect(at(SetupStep.access, status), OnboardingStep.access, reason: '${status.phase}');
        expect(
          at(SetupStep.connect, status),
          status.phase == RuntimePhase.installed || status.phase == RuntimePhase.running
              ? isNull
              : OnboardingStep.finishing,
          reason: '${status.phase}',
        );
      }
    });

    test('connected already: the waiting page while the runtime is missing, else home', () {
      expect(at(SetupStep.connect, installingStatus, key: true), OnboardingStep.finishing);
      expect(at(SetupStep.connect, missingStatus, skipped: true), OnboardingStep.finishing);
      expect(at(SetupStep.connect, stoppedStatus, key: true), isNull);
      expect(at(SetupStep.finishing, installingStatus), OnboardingStep.finishing);
      expect(at(SetupStep.finishing, missingStatus), OnboardingStep.finishing);
      expect(at(SetupStep.finishing, stoppedStatus), isNull);
    });

    test('an upgrade or a remote host instead goes the old way', () {
      final upgrade = RuntimeStatus(phase: RuntimePhase.notInstalled, bundledVersion: bundled, installedVersion: 'r4');
      expect(at(SetupStep.appearance, upgrade), OnboardingStep.runtime);
      expect(
        initialOnboardingStep(
          status: missingStatus,
          hasApiKey: false,
          prefs: fresh.copyWith(setupStep: SetupStep.appearance, localDeclined: true),
        ),
        isNull,
      );
    });

    test('without a saved page nothing changes', () {
      expect(initialOnboardingStep(status: missingStatus, hasApiKey: false, prefs: fresh), OnboardingStep.access);
      expect(initialOnboardingStep(status: installingStatus, hasApiKey: false, prefs: fresh), OnboardingStep.runtime);
      expect(initialOnboardingStep(status: stoppedStatus, hasApiKey: false, prefs: fresh), isNull);
    });

    test('the setup runtime reads the native phase', () {
      expect(setupRuntimeOf(missingStatus), SetupRuntime.absent);
      expect(setupRuntimeOf(missingStatus, launchFailed: true), SetupRuntime.failed);
      expect(setupRuntimeOf(installingStatus), SetupRuntime.unpacking);
      expect(setupRuntimeOf(stoppedStatus), SetupRuntime.ready);
      expect(setupRuntimeOf(failedStatus), SetupRuntime.failed);
      expect(
        setupRuntimeOf(
          const RuntimeStatus(phase: RuntimePhase.error, bundledVersion: bundled, installedVersion: bundled),
        ),
        SetupRuntime.ready,
      );
    });
  });

  group('本机: set up while it unpacks', () {
    testWidgets('starts the unpack once, then 权限 with the unpack in a capsule', (tester) async {
      final rig = await pumpGate(tester);
      expect(find.byType(AccessStepPage), findsOneWidget);
      expect(rig.runtime.calls, ['install']);
      expect(find.byKey(_capsule), findsOneWidget);
      expect(rig.prefs.setupStep, SetupStep.access);
      expect(rig.prefs.localDeclined, isFalse);

      rig.runtime.unpack(0.42);
      await frames(tester, 3);
      expect(_capsuleText('运行环境 42%'), findsOneWidget);
    });

    testWidgets('skip access while unpacking waits, then home with the engine', (tester) async {
      final rig = await pumpGate(tester);
      rig.runtime.unpack(0.6);
      await skipAccess(tester);

      expect(find.byType(RuntimeSetupPage), findsOneWidget);
      expect(find.text('完成后自动进入'), findsOneWidget);
      expect(rig.prefs.setupStep, SetupStep.finishing);
      expect(find.byKey(_capsule), findsNothing);
      expect(rig.runtime.calls, ['install']);

      rig.runtime.finish();
      await frames(tester, 20);
      expect(find.text('home'), findsOneWidget);
      expect(rig.runtime.calls, ['install', 'start']);
      expect(rig.prefs.setupStep, isNull);
    });

    testWidgets('done while on 权限: the capsule says so, engine starts; skip goes home', (tester) async {
      final rig = await pumpGate(tester);
      rig.runtime.unpack(0.9);
      await frames(tester, 2);
      rig.runtime.finish();
      await frames(tester, 3);
      expect(_capsuleText('运行环境已就绪'), findsOneWidget);
      expect(rig.runtime.calls, ['install', 'start']);

      await skipAccess(tester);
      expect(find.text('home'), findsOneWidget);
      expect(rig.prefs.setupStep, isNull);
      expect(rig.runtime.calls, ['install', 'start']);
    });
  });

  group('a failed unpack', () {
    testWidgets('the capsule turns red; retry through the one entry', (tester) async {
      final rig = await pumpGate(tester);
      rig.runtime.fail();
      await frames(tester, 3);
      expect(_capsuleText('安装未完成'), findsOneWidget);
      expect(find.byType(AccessStepPage), findsOneWidget);

      await tester.tap(find.byKey(_capsule));
      await frames(tester, 6);
      final sheet = find.byKey(const ValueKey('setup-status-sheet'));
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text('安装未完成')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, '重试'));
      await tester.pump();
      expect(rig.runtime.calls, ['install', 'install']);
    });

    testWidgets('on the waiting page: retry and logs', (tester) async {
      final rig = await pumpGate(
        tester,
        runtime: unpackingState(0.7),
        prefs: _seen.copyWith(setupStep: SetupStep.finishing, keySkipped: true),
      );
      expect(find.text('完成后自动进入'), findsOneWidget);
      rig.runtime.fail();
      await frames(tester, 3);
      expect(find.text('安装未完成'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '查看日志'), findsOneWidget);
    });
  });

  group('coming back after the app went away', () {
    testWidgets('unpack died with the app: same page, unpacking again', (tester) async {
      final rig = await pumpGate(tester, prefs: _seen.copyWith(setupStep: SetupStep.access));
      expect(find.byType(AccessStepPage), findsOneWidget);
      expect(rig.runtime.calls, ['install']);
      expect(find.byKey(_capsule), findsOneWidget);
    });

    testWidgets('still unpacking: same page, same unpack', (tester) async {
      final rig = await pumpGate(
        tester,
        runtime: unpackingState(0.3),
        prefs: _seen.copyWith(setupStep: SetupStep.access),
      );
      expect(find.byType(AccessStepPage), findsOneWidget);
      expect(_capsuleText('运行环境 30%'), findsOneWidget);
      expect(rig.runtime.calls, isEmpty);
    });

    testWidgets('waiting page, unpack died: one unpack, though page and gate both ask', (tester) async {
      final rig = await pumpGate(tester, prefs: _seen.copyWith(setupStep: SetupStep.finishing, keySkipped: true));
      expect(find.text('完成后自动进入'), findsOneWidget);
      expect(rig.runtime.calls, ['install']);
    });

    testWidgets('done while away on 权限: engine starting', (tester) async {
      final rig = await pumpGate(
        tester,
        runtime: const LocalRuntimeState(loaded: true, status: stoppedStatus),
        prefs: _seen.copyWith(setupStep: SetupStep.access),
      );
      expect(find.byType(AccessStepPage), findsOneWidget);
      expect(rig.runtime.calls, ['start']);
    });

    testWidgets('done while away on waiting page: home', (tester) async {
      final rig = await pumpGate(
        tester,
        runtime: const LocalRuntimeState(loaded: true, status: stoppedStatus),
        prefs: _seen.copyWith(setupStep: SetupStep.finishing, keySkipped: true),
      );
      expect(find.text('home'), findsOneWidget);
      expect(rig.prefs.setupStep, isNull);
    });
  });

  group('the other ways are as they were', () {
    testWidgets('an upgrade unpacks on its own page, then home', (tester) async {
      final rig = await pumpGate(
        tester,
        runtime: const LocalRuntimeState(
          loaded: true,
          status: RuntimeStatus(phase: RuntimePhase.notInstalled, bundledVersion: bundled, installedVersion: 'r4'),
        ),
      );
      expect(find.text('正在更新运行环境'), findsOneWidget);
      expect(find.byKey(_capsule), findsNothing);
      expect(rig.runtime.calls, ['install']);
      rig.runtime.finish();
      await frames(tester, 20);
      expect(find.text('home'), findsOneWidget);
      expect(rig.prefs.setupStep, isNull);
    });

    testWidgets('installed: home, no DeepSeek connect', (tester) async {
      await pumpGate(tester, runtime: const LocalRuntimeState(loaded: true, status: stoppedStatus));
      expect(find.text('home'), findsOneWidget);
    });
  });

  tearDown(() => SharedPreferences.setMockInitialValues({}));
}
