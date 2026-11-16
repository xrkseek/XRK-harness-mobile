import 'package:flutter/foundation.dart';

/// Host-side phone-bridge phase mirrored for App UI.
enum RemoteBridgePhase {
  /// Not on HTTP Host.
  idle,

  /// HTTP Host selected but Face PIN / cookies not ready yet.
  needPin,

  /// Trying ticket/register.
  connecting,

  /// On Host 待批准.
  pending,

  /// Whitelisted; waiting for 操控 + 无障碍 (or poll not started).
  allowed,

  /// Polling; phone_* can run.
  online,

  /// Last announce/ticket failed.
  error,
}

@immutable
class RemoteBridgeSnapshot {
  const RemoteBridgeSnapshot({
    required this.phase,
    this.deviceKey,
    this.message,
    this.pollEnabled = false,
  });

  final RemoteBridgePhase phase;
  final String? deviceKey;
  final String? message;
  final bool pollEnabled;

  static const idle = RemoteBridgeSnapshot(phase: RemoteBridgePhase.idle);

  String get titleZh => switch (phase) {
        RemoteBridgePhase.idle => '远程桥未连接',
        RemoteBridgePhase.needPin => '先打开 Face（PIN）',
        RemoteBridgePhase.connecting => '正在报到 / 上线…',
        RemoteBridgePhase.pending => '等待 Host 批准',
        RemoteBridgePhase.allowed => '已批准 · 待上线',
        RemoteBridgePhase.online => '远程桥在线',
        RemoteBridgePhase.error => '远程桥失败',
      };

  String get bodyZh => switch (phase) {
        RemoteBridgePhase.idle =>
          '本机 Host 直接用下方「手机操控」即可。远程 HTTP Host 需要 PIN 打开 Face 后才会报到。',
        RemoteBridgePhase.needPin =>
          '已选远程主机，但还没拿到 Face 登录态。回到对话页输入当前 PIN，打开 Face 后再点「重新报到」。',
        RemoteBridgePhase.connecting =>
          message?.isNotEmpty == true
              ? message!
              : '正在向 Host 报到（ticket / register）… Host 刚重启会自动换票。',
        RemoteBridgePhase.pending =>
          '请在远程 Face → 设置 → 远程手机桥 点「允许」。允许后回到这里开「手机操控」+ 无障碍即可上线。',
        RemoteBridgePhase.allowed =>
          'Host 已允许本机。打开下方「启用手机操控」并开启无障碍后，会立刻进入在线、可跑 phone_*。',
        RemoteBridgePhase.online =>
          'Host 可对本机下发 phone_*。保持 App 前台或开启保活；切会话会自动绑定当前对话。',
        RemoteBridgePhase.error => message ?? '无法报到 Host，请检查网络与 PIN（Host 重启会换 PIN）。',
      };

  bool get okTone => phase == RemoteBridgePhase.online || phase == RemoteBridgePhase.allowed;
  bool get warnTone =>
      phase == RemoteBridgePhase.pending ||
      phase == RemoteBridgePhase.connecting ||
      phase == RemoteBridgePhase.needPin;
  bool get dangerTone => phase == RemoteBridgePhase.error;
}

/// Process-wide mirror updated by [PhoneBridgeController] for Settings UI.
final ValueNotifier<RemoteBridgeSnapshot> remoteBridgeStatus =
    ValueNotifier(RemoteBridgeSnapshot.idle);

/// Bump to ask [LocalHostShell] to re-harvest Face cookies and sync the bridge.
final ValueNotifier<int> remoteBridgeResyncTick = ValueNotifier(0);

void requestRemoteBridgeResync() {
  remoteBridgeResyncTick.value++;
}
