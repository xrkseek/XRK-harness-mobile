import 'dart:async';

/// Hook for shared test setup. Keep product defaults (no third-party hosts).
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
