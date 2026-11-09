import 'package:flutter/material.dart';

import 'access_step.dart';
import 'appearance_step.dart';
import 'onboarding_scaffold.dart';
import 'runtime_setup_page.dart';
import 'welcome_page.dart';

/// First-run pages for XRK Harness Mobile.
///
/// Models / providers are configured later in the in-device xrkh Web settings —
/// there is no DeepSeek (or any provider) login in this flow.
///
/// First install: [welcome] → [access] (permissions) beside the runtime unpack,
/// then [finishing] if the unpack is still running. Upgrades / resets go
/// [runtime] only. [appearance] remains for older resumes that saved that step
/// (the gate maps it to access).
enum OnboardingStep { welcome, runtime, appearance, access, finishing }

/// Moves between the first-run pages. The step itself is owned by the root
/// gate, which also decides where a returning user resumes.
///
/// The welcome and finishing pages stand alone; the steps between show a thin
/// step bar at the top ([OnboardingProgress]) and, beside an unpack, its
/// capsule at the bottom.
class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({
    super.key,
    required this.step,
    required this.onWelcomeDone,
    required this.onRuntimeDone,
    this.chooseRuntime = false,
    this.onRemote,
    this.onLocal,
    this.onAppearanceDone,
    this.onAccessDone,
    this.onFinished,
    this.beside = false,
  });

  final OnboardingStep step;
  final VoidCallback onWelcomeDone;
  final VoidCallback onRuntimeDone;

  /// The runtime step asks first: this phone or a remote host
  /// ([RuntimeSetupPage.choose]); false installs (resume, upgrade, reset).
  final bool chooseRuntime;

  /// Picked 「远程主机」 (or gave up on a failed install for one).
  final VoidCallback? onRemote;

  /// Picked 「本机」: the caller starts the unpack and moves on to
  /// [OnboardingStep.access]. Null: the runtime page installs itself.
  final VoidCallback? onLocal;

  final VoidCallback? onAppearanceDone;

  /// Past the permission walk (picked and walked, or skipped).
  final VoidCallback? onAccessDone;

  /// The unpack [OnboardingStep.finishing] waited for is done.
  final VoidCallback? onFinished;

  /// The steps run beside an unpack (first run on this phone).
  final bool beside;

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  late DateTime _since = DateTime.now();

  @override
  void didUpdateWidget(OnboardingFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) _since = DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final Widget page = switch (step) {
      OnboardingStep.welcome => WelcomePage(onStart: widget.onWelcomeDone),
      OnboardingStep.runtime => RuntimeSetupPage(
        onDone: widget.onRuntimeDone,
        choose: widget.chooseRuntime,
        onRemote: widget.onRemote,
        onLocal: widget.onLocal,
      ),
      OnboardingStep.appearance => AppearanceStepPage(onDone: widget.onAppearanceDone ?? () {}),
      OnboardingStep.access => AccessStepPage(onDone: widget.onAccessDone ?? () {}),
      OnboardingStep.finishing => RuntimeSetupPage(
        onDone: widget.onFinished ?? widget.onRuntimeDone,
        waiting: true,
        onRemote: widget.onRemote,
      ),
    };
    final steps = widget.beside
        ? const [OnboardingStep.access]
        : const [OnboardingStep.runtime];
    final index = steps.indexOf(step);
    return OnboardingSwitcher(
      child: KeyedSubtree(
        key: ValueKey(step),
        child: index < 0
            ? page
            : OnboardingProgress(
                step: index + 1,
                steps: steps.length,
                since: _since,
                runtime: widget.beside && step != OnboardingStep.runtime,
                onRemote: widget.onRemote,
                child: page,
              ),
      ),
    );
  }
}
