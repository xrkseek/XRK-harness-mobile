import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../launch/launch_state.dart';
import '../../runtime/runtime_bridge.dart';
import '../../runtime/runtime_state.dart';
import '../../share_code/guest_fs.dart';
import '../../state/engine_control.dart';
import '../../state/hosts_state.dart';
import '../../state/notify_state.dart';
import '../../state/onboarding_state.dart';
import '../../state/settings_state.dart';
import '../../ui_config/ui_skill.dart';
import '../onboarding/onboarding_flow.dart';
import '../onboarding/setup_progress.dart';
import '../theme/theme.dart';
import '../web/mode_home.dart';
import 'usage_upgrade_notice.dart';

/// Where a launch should start, given what is installed and configured.
///
/// XRK local-only: no Remote host, no DeepSeek connect page. Models are
/// configured in xrkh's Web settings after the Host is up.
///
/// - First run [OnboardingPrefs.setupStep] not over → back to that page
///   (appearance is treated as access). Waiting page only while the runtime
///   is not there.
/// - Runtime mid-install with no saved page → the unpack halo.
/// - [OnboardingPrefs.localDeclined] (legacy remote / uninstall) → home.
/// - Runtime outdated → setup, which upgrades it.
/// - First install missing → welcome, then access beside the unpack.
/// - Runtime ready → home (`null`); xrkh owns model onboarding.
OnboardingStep? initialOnboardingStep({
  required RuntimeStatus status,
  required bool hasApiKey,
  required OnboardingPrefs prefs,
  bool hasCustomProvider = false,
}) {
  final installedCurrent = status.installedVersion != null && status.installedVersion == status.bundledVersion;
  final needsRuntime = switch (status.phase) {
    RuntimePhase.notInstalled || RuntimePhase.installing => true,
    RuntimePhase.error => !installedCurrent,
    _ => false,
  };
  if (prefs.setupStep case final resume?
      when !prefs.localDeclined && (installedCurrent || status.installedVersion == null)) {
    return switch (resume) {
      SetupStep.appearance || SetupStep.access => OnboardingStep.access,
      _ => needsRuntime ? OnboardingStep.finishing : null,
    };
  }
  if (needsRuntime) {
    if (status.phase == RuntimePhase.installing) return OnboardingStep.runtime;
    if (prefs.localDeclined) return null;
    if (!runtimeStepAsks(status)) return OnboardingStep.runtime;
    return prefs.welcomeSeen ? OnboardingStep.access : OnboardingStep.welcome;
  }
  return null;
}

/// Whether the setup step asks 本机 or 远程主机 first: nothing to upgrade and
/// no install underway.
bool runtimeStepAsks(RuntimeStatus status) =>
    status.installedVersion == null && status.phase != RuntimePhase.installing;

/// App root: waits for settings and the native runtime to report in, then shows
/// onboarding or the home shell, and auto-starts the local engine once per launch
/// (设置 › 引擎 › 打开 App 时自动启动).
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key, this.home});

  /// Stands in for [ModeHome] (tests).
  @visibleForTesting
  final Widget? home;

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  bool _decided = false;

  bool _launchReady = false;
  OnboardingStep? _step;
  bool _autoStartDone = false;

  /// First run on this phone, setting up while the runtime unpacks
  /// (docs/design/onboarding-parallel-setup.md).
  bool _beside = false;

  /// The engine was asked to start for it, once.
  bool _besideEngine = false;

  ProviderContainer get _container => ProviderScope.containerOf(context, listen: false);

  void _goTo(OnboardingStep? step) {
    if (!mounted) return;
    setState(() => _step = step);
  }

  void _afterRuntime() {
    _autoStartDone = true;
    unawaited(EngineControl.ensureStarted(_container));
    _goTo(null);
  }

  // ── Set up beside the unpack ──

  OnboardingPrefsController get _prefs => ref.read(onboardingPrefsProvider.notifier);

  /// The unpack, through the one entry (a second request is the first one).
  void _startUnpack() {
    // Time left is estimated from the first progress report on.
    ref.read(installEtaProvider);
    unawaited(ref.read(runtimeInstallProvider.notifier).install());
    // Android 13 asks about notifications once the channels exist: now, as the
    // unpack (and its notification) starts, not over a later step.
    unawaited(ref.read(notifyChannelProvider).status().then<void>((_) {}, onError: (_) {}));
  }

  /// Start the local engine as soon as the runtime is ready (beside unpack).
  void _startEngineBeside() {
    if (_besideEngine) return;
    _besideEngine = true;
    _autoStartDone = true;
    unawaited(EngineControl.ensureStarted(_container));
  }

  /// Unpack in the background; first-run permission walk runs beside it.
  void _chooseLocal() {
    _beside = true;
    unawaited(_prefs.setSetupStep(SetupStep.access));
    _startUnpack();
    _goTo(OnboardingStep.access);
  }

  void _afterAppearance() {
    unawaited(_prefs.setSetupStep(SetupStep.access));
    _goTo(OnboardingStep.access);
  }

  void _afterAccess() {
    _finishBeside();
  }

  /// Everything set: home if the runtime is there, else wait for it.
  void _finishBeside() {
    if (ref.read(setupRuntimeProvider) != SetupRuntime.ready) {
      unawaited(_prefs.setSetupStep(SetupStep.finishing));
      _goTo(OnboardingStep.finishing);
      return;
    }
    _startEngineBeside();
    _leaveBeside();
    _goTo(null);
  }

  /// The unpack the waiting page showed is done.
  void _afterFinishing() {
    _startEngineBeside();
    _leaveBeside();
    _goTo(null);
  }

  void _leaveBeside() {
    _beside = false;
    unawaited(_prefs.setSetupStep(null));
  }

  void _maybeAutoStart() {
    if (_autoStartDone) return;
    _autoStartDone = true;
    final settings = ref.read(settingsProvider);
    if (!settings.autoStartLocal) return;
    final status = ref.read(localRuntimeProvider).status;
    // After repeated crashes with automatic safe mode off, the failure card
    // waits for the user instead of starting again.
    if (status.phase == RuntimePhase.installed && EngineControl.shouldAutoStart(status)) {
      unawaited(ref.read(localRuntimeProvider.notifier).start());
    }
  }

  /// Back to first run's set-up-beside-the-unpack after the app went away:
  /// an unpack that died with the process starts again (from scratch, as
  /// Android always does); one that is done gets the engine going.
  void _resumeBeside(SetupStep? saved, RuntimeStatus status) {
    if (saved == null) return;
    _beside = switch (_step) {
      OnboardingStep.appearance || OnboardingStep.access || OnboardingStep.finishing => true,
      _ => false,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // First run is over (finished while away, or a remote host instead).
      if (!_beside) return unawaited(_prefs.setSetupStep(null));
      if (saved == SetupStep.access && ref.read(onboardingPrefsProvider).setupStep != SetupStep.access) {
        unawaited(_prefs.setSetupStep(SetupStep.access));
      }
      switch (setupRuntimeOf(status)) {
        case SetupRuntime.absent:
          _startUnpack();
        case SetupRuntime.ready when _step != OnboardingStep.finishing:
          _startEngineBeside();
        case _:
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final runtime = ref.watch(localRuntimeProvider.select((s) => (status: s.status, loaded: s.loaded)));
    final prefs = ref.watch(onboardingPrefsProvider);
    // The last host comes back while the splash shows, so a phone without
    // the runtime doesn't open on 本机 for a frame before its remote host.
    ref.read(activeHostProvider);

    // "重置运行环境" sends the user back through setup; 「卸载运行环境」
    // (localDeclined) stays home.
    ref.listen(localRuntimeProvider.select((s) => s.status.phase), (prev, next) {
      if (_decided &&
          _step == null &&
          next == RuntimePhase.notInstalled &&
          prev != RuntimePhase.notInstalled &&
          !ref.read(onboardingPrefsProvider).localDeclined) {
        _goTo(OnboardingStep.runtime);
      }
    });
    // Setting up beside the unpack: the engine starts the moment the runtime
    // is there (the waiting page goes on by itself and starts it then).
    ref.listen(setupRuntimeProvider, (prev, next) {
      if (_beside && next == SetupRuntime.ready && prev != SetupRuntime.ready && _step != OnboardingStep.finishing) {
        _startEngineBeside();
      }
    });
    // Each start of the on-device engine writes the bundled skills (xrk-ui,
    // xrk-plugin) into its skills folder, while they are still the app's.
    ref.listen(uiSkillAutoInstallProvider, (_, _) {});
    // The rootfs came or went: files read straight from it look again.
    ref.listen(localRuntimeProvider.select((s) => s.status.installedVersion), (prev, next) {
      if (prev != next) ref.invalidate(guestFsProvider);
    });
    final Widget child;
    if (!settings.loaded || !runtime.loaded || !prefs.loaded) {
      child = const _Splash();
    } else {
      if (!_decided) {
        _decided = true;
        _step = initialOnboardingStep(
          status: runtime.status,
          hasApiKey: settings.hasApiKey,
          hasCustomProvider: settings.customProviderIds.isNotEmpty,
          prefs: prefs,
        );
        if (_step == OnboardingStep.access && prefs.setupStep != SetupStep.access) {
          _beside = true;
        }
        _resumeBeside(prefs.setupStep ?? (_step == OnboardingStep.access ? SetupStep.access : null), runtime.status);
      }
      if (_step case final step?) {
        child = OnboardingFlow(
          step: step,
          chooseRuntime: false,
          beside: _beside,
          onLocal: null,
          onAppearanceDone: _afterAppearance,
          onAccessDone: _afterAccess,
          onFinished: _afterFinishing,
          onRemote: null,
          onWelcomeDone: () {
            unawaited(ref.read(onboardingPrefsProvider.notifier).markWelcomeSeen());
            _chooseLocal();
          },
          onRuntimeDone: _afterRuntime,
        );
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _maybeAutoStart();
        });
        // The native shell or the web page, by 界面 (ui_mode_state.dart); an
        // install from before usage statistics is told about them there, once.
        child = UsageUpgradeNotice(child: widget.home ?? const ModeHome());
      }
    }
    if (child is! _Splash && !_launchReady) {
      // 启动画面: the first page is up. A warm start's launch screen goes now; a cold start of
      // this phone's engine finishes its motion first (or goes when the engine is up).
      _launchReady = true;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => LaunchController.active.value?.ready(waitsForEngine: ref.read(activeHostProvider).isLocal),
      );
    }
    return AnimatedSwitcher(
      duration: AppMotion.of(context, AppMotion.page),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      child: KeyedSubtree(
        key: ValueKey(child is _Splash ? 'splash' : (_step == null ? 'home' : 'onboarding')),
        child: child,
      ),
    );
  }
}

/// Shown until settings and runtime status arrive. Same black as the launch window.
class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF0B0B0C),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: ColoredBox(color: Color(0xFF0B0B0C)),
    );
  }
}
