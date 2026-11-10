// Retired dual-home page (原生 / 网页). Product home is LocalHostShell only;
// Host UI preferences live in the in-guest Web Settings. Kept as a redirect so
// old deep links / tests that still construct [InterfacePage] do not crash.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_screen.dart';

class InterfacePage extends ConsumerWidget {
  const InterfacePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => const SettingsScreen();
}
