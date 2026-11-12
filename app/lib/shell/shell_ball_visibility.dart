/// Visibility rules for the LocalHostShell **settings ball** (设置球).
///
/// ## Product role
///
/// The ball is the **native escape hatch** of [LocalHostShell]: the chat surface
/// is either the Host WebView or the boot / error brand screen, so shell-level
/// controls must not depend on Host health.
///
/// From the ball the person reaches:
/// - phone control (无障碍 / Root / 自检)
/// - app settings (引擎 · 保活 · 外观 · 关于 · 更新)
/// - Host conversation settings **when** the WebView is ready
/// - engine status **when** Host is down (code 1, stopped, still booting)
///
/// ## When it shows
///
/// | Surface | Ball |
/// |---|---|
/// | Boot / installing / starting / error / stopped | on |
/// | Host running (WebView loading or ready) | on |
/// | Soft keyboard open (≥ [shellBallKeyboardHidePx]) | **off** |
///
/// Hiding only for the keyboard avoids covering the input bar. It must **not**
/// wait for WebView `onPageFinished` — that used to drop the ball on Host
/// failure and during long loads, leaving only 「重试」.
library;

/// Logical px: keyboard height at or above this hides the ball while typing.
const shellBallKeyboardHidePx = 48.0;

/// Whether the IME height should hide the settings ball.
bool shellBallKeyboardOpen(double keyboardHeight) =>
    keyboardHeight >= shellBallKeyboardHidePx;

/// Whether the settings ball belongs on screen for the current shell surface.
///
/// [hostSurfaceReady] is reserved for future gates; today the only suppress
/// signal is the soft keyboard. Boot / error / running all pass `true` for
/// host-independent reachability.
bool shellBallVisible({
  required bool keyboardOpen,
  bool hostSurfaceReady = true,
}) {
  if (keyboardOpen) return false;
  return hostSurfaceReady;
}
