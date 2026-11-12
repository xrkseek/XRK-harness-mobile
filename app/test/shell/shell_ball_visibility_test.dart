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

  group('shellQuickThirdAction', () {
    test('Host ready → conversation settings; Host down → engine status', () {
      expect(shellQuickThirdAction(hostReady: true), ShellQuickAction.hostSettings);
      expect(shellQuickThirdAction(hostReady: false), ShellQuickAction.engineStatus);
    });
  });
}
