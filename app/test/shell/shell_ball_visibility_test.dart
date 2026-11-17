import 'package:flutter_test/flutter_test.dart';
import 'package:xrk_app/shell/shell_ball_visibility.dart';
import 'package:xrk_app/shell/shell_quick_panel.dart';

void main() {
  group('shellBallVisible', () {
    test('shows on boot / error / running when keyboard is closed', () {
      expect(shellBallVisible(keyboardOpen: false), isTrue);
      expect(shellBallVisible(keyboardOpen: false, hostSurfaceReady: true), isTrue);
    });

    test('hides only while the soft keyboard is open', () {
      expect(shellBallVisible(keyboardOpen: true), isFalse);
      expect(shellBallKeyboardOpen(shellBallKeyboardHidePx), isTrue);
      expect(shellBallKeyboardOpen(shellBallKeyboardHidePx - 1), isFalse);
    });
  });

  group('shellQuickHostSettingsAction', () {
    test('Host ready → Host settings; Host down → hidden', () {
      expect(shellQuickHostSettingsAction(hostReady: true), ShellQuickAction.hostSettings);
      expect(shellQuickHostSettingsAction(hostReady: false), isNull);
    });
  });

  group('ShellQuickAction ordering', () {
    test('refresh is first so the panel can pin it above other tiles', () {
      expect(ShellQuickAction.values.first, ShellQuickAction.refresh);
      expect(ShellQuickAction.values[1], ShellQuickAction.leaveSafeMode);
    });
  });
}
