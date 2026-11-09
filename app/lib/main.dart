import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'launch/launch_state.dart';
import 'shell/local_host_shell.dart';
import 'state/locale_state.dart';
import 'ui/shell/root_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([AppLanguageController.load(), LaunchController.begin()]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: PlatformDispatcher.instance.platformBrightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarIconBrightness: PlatformDispatcher.instance.platformBrightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    ),
  );
  runApp(
    const ProviderScope(
      child: DshApp(home: RootGate(home: LocalHostShell())),
    ),
  );
}
