import 'package:flutter_test/flutter_test.dart';
import 'package:xrk_app/runtime/runtime_bridge.dart';

/// Mirrors [LocalHostShell] auto-boot gates: never start from [RuntimePhase.error]
/// unless the user forced a retry (native SafePolicy already auto-restarts).
bool shouldAutoStartFromPhase(
  RuntimePhase phase, {
  required bool force,
  required bool userStopped,
  required bool autoStartLocal,
  required bool engineAllows,
}) {
  if (force) {
    return phase == RuntimePhase.installed ||
        phase == RuntimePhase.notInstalled ||
        phase == RuntimePhase.error;
  }
  if (userStopped) return false;
  if (!autoStartLocal) return false;
  if (!engineAllows) return false;
  if (phase == RuntimePhase.error) return false;
  return phase == RuntimePhase.installed || phase == RuntimePhase.notInstalled;
}

bool shouldHandlePhaseListen(RuntimePhase? prev, RuntimePhase next, {required bool userStopped}) {
  if (next == RuntimePhase.installed &&
      (prev == RuntimePhase.running || prev == RuntimePhase.stopping)) {
    return false; // mark userStopped; do not boot
  }
  if (next == RuntimePhase.error) return false;
  if (next == RuntimePhase.installed && !userStopped) return true;
  return false;
}

void main() {
  test('error phase does not auto-start (breaks 启动失败 loop)', () {
    expect(
      shouldAutoStartFromPhase(
        RuntimePhase.error,
        force: false,
        userStopped: false,
        autoStartLocal: true,
        engineAllows: true,
      ),
      isFalse,
    );
    expect(
      shouldAutoStartFromPhase(
        RuntimePhase.error,
        force: true,
        userStopped: false,
        autoStartLocal: true,
        engineAllows: true,
      ),
      isTrue,
    );
  });

  test('installed still auto-starts; user stop and settings block', () {
    expect(
      shouldAutoStartFromPhase(
        RuntimePhase.installed,
        force: false,
        userStopped: false,
        autoStartLocal: true,
        engineAllows: true,
      ),
      isTrue,
    );
    expect(
      shouldAutoStartFromPhase(
        RuntimePhase.installed,
        force: false,
        userStopped: true,
        autoStartLocal: true,
        engineAllows: true,
      ),
      isFalse,
    );
    expect(
      shouldAutoStartFromPhase(
        RuntimePhase.installed,
        force: false,
        userStopped: false,
        autoStartLocal: false,
        engineAllows: true,
      ),
      isFalse,
    );
    expect(
      shouldAutoStartFromPhase(
        RuntimePhase.installed,
        force: false,
        userStopped: false,
        autoStartLocal: true,
        engineAllows: false,
      ),
      isFalse,
    );
  });

  test('phase listen ignores error and stop teardown', () {
    expect(shouldHandlePhaseListen(RuntimePhase.running, RuntimePhase.error, userStopped: false), isFalse);
    expect(shouldHandlePhaseListen(RuntimePhase.running, RuntimePhase.installed, userStopped: false), isFalse);
    expect(shouldHandlePhaseListen(RuntimePhase.starting, RuntimePhase.installed, userStopped: false), isTrue);
    expect(shouldHandlePhaseListen(RuntimePhase.starting, RuntimePhase.installed, userStopped: true), isFalse);
  });
}
