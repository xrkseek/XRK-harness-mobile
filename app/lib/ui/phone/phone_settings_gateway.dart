import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'phone_control_screen.dart';

/// Settings deep-link / search entry for 手机操控 → native screen
/// (multi-brand restricted-settings guide, unlocks, app rules).
class PhoneSettingsGateway extends ConsumerStatefulWidget {
  const PhoneSettingsGateway({super.key});

  @override
  ConsumerState<PhoneSettingsGateway> createState() => _PhoneSettingsGatewayState();
}

class _PhoneSettingsGatewayState extends ConsumerState<PhoneSettingsGateway> {
  var _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_route()));
  }

  Future<void> _route() async {
    if (_started || !mounted) return;
    _started = true;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const PhoneControlScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
