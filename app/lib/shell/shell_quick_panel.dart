import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// Destinations offered by the settings-ball quick panel.
///
/// [hostSettings] requires a live Host WebView. [engineStatus] is the
/// fallback when Host is down so the person can still open logs / start / stop.
enum ShellQuickAction {
  phoneControl,
  appSettings,
  hostSettings,
  engineStatus,
}

/// Which third tile the panel should offer for the current Host surface.
ShellQuickAction shellQuickThirdAction({required bool hostReady}) =>
    hostReady ? ShellQuickAction.hostSettings : ShellQuickAction.engineStatus;

/// Bottom sheet opened by the settings ball. Returns null if dismissed.
Future<ShellQuickAction?> showShellQuickPanel(
  BuildContext context, {
  required bool hostReady,
}) {
  final l10n = context.l10n;
  final third = shellQuickThirdAction(hostReady: hostReady);
  return showModalBottomSheet<ShellQuickAction>(
    context: context,
    backgroundColor: const Color(0xFF161618),
    // Material 3 draws its own drag handle; we paint one — keep a single bar.
    showDragHandle: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final bottom = MediaQuery.paddingOf(ctx).bottom;
      Widget tile({
        required IconData icon,
        required String title,
        required String subtitle,
        required ShellQuickAction value,
      }) {
        return ListTile(
          leading: Icon(icon, color: const Color(0xFFE8E8E6)),
          title: Text(title, style: const TextStyle(color: Color(0xFFE8E8E6), fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFFB8B8B4), fontSize: 12)),
          onTap: () => Navigator.pop(ctx, value),
        );
      }

      return SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottom > 0 ? 0 : 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3A3A3E),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.shellQuickPanel,
                    style: const TextStyle(color: Color(0xFFE8E8E6), fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              tile(
                icon: Icons.accessibility_new,
                title: l10n.phoneControlTitle,
                subtitle: '开关 · 无障碍 · Root · 自检',
                value: ShellQuickAction.phoneControl,
              ),
              tile(
                icon: Icons.settings_outlined,
                title: l10n.commonSettings,
                subtitle: '引擎 · 保活 · 外观 · 关于 · 更新',
                value: ShellQuickAction.appSettings,
              ),
              switch (third) {
                ShellQuickAction.hostSettings => tile(
                    icon: Icons.tune_outlined,
                    title: '对话设置',
                    subtitle: '模型 · 权限 · 插件 · Host 面板',
                    value: ShellQuickAction.hostSettings,
                  ),
                ShellQuickAction.engineStatus => tile(
                    icon: Icons.memory_outlined,
                    title: '引擎状态',
                    subtitle: '日志 · 启停 · 诊断（Host 未就绪）',
                    value: ShellQuickAction.engineStatus,
                  ),
                _ => const SizedBox.shrink(),
              },
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}
