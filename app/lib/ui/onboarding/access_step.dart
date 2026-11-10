// First run beside the runtime unpack: which capabilities to enable, then
// each permission one at a time, then a short summary.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../state/access_state.dart';
import '../access/access_pick_page.dart';
import '../access/access_summary_page.dart';
import '../access/access_walk.dart';
import 'onboarding_scaffold.dart';

/// Pick capabilities → turn each permission on → summary. Skip on the first
/// page continues with nothing changed. Picks are kept until the step is over,
/// so a launch after the app was killed in system settings resumes the walk.
class AccessStepPage extends ConsumerStatefulWidget {
  const AccessStepPage({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  ConsumerState<AccessStepPage> createState() => _AccessStepPageState();
}

class _AccessStepPageState extends ConsumerState<AccessStepPage> {
  bool _summary = false;
  bool _walkedOnce = false;
  bool _finishing = false;

  Future<void> _walked() async {
    if (_walkedOnce) return;
    _walkedOnce = true;
    await ref.read(accessReadingsProvider.notifier).refresh();
    if (mounted) setState(() => _summary = true);
  }

  /// 继续: what was picked goes on as the summary is left, so an item turned
  /// on from it counts ([AccessSetupController.finish]). If that fails (the
  /// readings could not be taken) the step is not over and nothing is lost:
  /// it says so with 重试 (over 继续 while it shows), and 继续 works again.
  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    try {
      await ref.read(accessSetupProvider.notifier).finish();
    } catch (_) {
      _finishing = false;
      if (mounted) {
        final l10n = context.l10n;
        ScaffoldMessenger.maybeOf(context)
          ?..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(l10n.accessFinishFailed),
              // Goes by itself: 继续 underneath does the same.
              persist: false,
              duration: const Duration(seconds: 6),
              action: SnackBarAction(label: l10n.commonRetry, onPressed: () => unawaited(_finish())),
            ),
          );
      }
      return;
    }
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final setup = ref.watch(accessSetupProvider);
    final readings = ref.watch(accessReadingsProvider).value;
    final features = setup.features;
    final Widget page;
    if (setup.loaded && features == null) {
      // The pick needs nothing from the phone (mobile data, if known, shows when read).
      page = AccessPickPage(
        key: const ValueKey('pick'),
        onPicked: (picked, phoneMode) =>
            unawaited(ref.read(accessSetupProvider.notifier).choose(picked, phoneMode: phoneMode)),
        onSkip: widget.onDone,
      );
    } else if (features == null || readings == null) {
      page = const OnboardingScaffold(key: ValueKey('loading'), children: [SizedBox.shrink()]);
    } else {
      final items = accessWalk(features, readings.vendor);
      page = _summary
          ? AccessSummaryPage(
              key: const ValueKey('summary'),
              items: items,
              onDone: () => unawaited(_finish()),
            )
          : AccessWalk(
              key: const ValueKey('walk'),
              items: items,
              vendor: readings.vendor,
              skipped: setup.skipped,
              onSkip: (item) => unawaited(ref.read(accessSetupProvider.notifier).skip(item)),
              onDone: () => unawaited(_walked()),
            );
    }
    return OnboardingSwitcher(child: page);
  }
}
