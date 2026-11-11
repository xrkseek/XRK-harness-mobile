import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../runtime/runtime_state.dart';
import '../../state/update_state.dart';
import '../common/overview_card.dart';
import '../common/search_capsule.dart';
import '../engine/engine_screen.dart';
import '../engine/engine_status.dart';
import '../shell/brand_mark.dart';
import '../shell/page_frame.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import '../update/update_tiles.dart' show UpdateBadge;
import '../features/permission_page.dart';
import 'about_page.dart';
import 'appearance/appearance_page.dart';
import 'background_guide_page.dart';
import 'diagnostics_page.dart';
import 'language_tile.dart';
import 'notification_settings.dart';
import 'search/settings_search_page.dart';
import 'settings_widgets.dart';
import 'system_access_page.dart';
import 'index/spots.dart';

/// One hue per group on the hub: rows of a group share it.
abstract final class SettingsHues {
  static const ai = 2;
  static const abilities = 3;
  static const appearance = 1;
  static const general = 5;
  static const engine = 6;
  static const hosts = 6;
  static const help = 7;
}

/// Thin phone-shell settings hub for [LocalHostShell].
///
/// Models / plugins / account / Host YAML live in the in-guest Web Settings
/// (ball → 对话设置). This screen only lists shell-owned pages.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = XrkColors.of(context);
    final runtime = ref.watch(localRuntimeProvider);
    final engine = EngineStatusView.of(runtime);
    final exempt = ref.watch(batteryExemptProvider).value;
    final update = ref.watch(appUpdateProvider);
    final newVersion = update.hasUpdate && !update.isSkipped;

    return AppPage.list(
      title: l10n.commonSettings,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SearchCapsuleButton(
            key: const ValueKey('settings-search'),
            hint: l10n.searchSettingsHint,
            onTap: () => Navigator.of(context).push(SettingsSearchPage.route()),
          ),
        ),
        SpotAnchor(
          spot: SettingsIndex.entry(SettingsPageId.engine),
          child: OverviewCard(
            leading: OverviewGlyph(AppIcons.engine, tint: SettingsHues.engine),
            title: Text(l10n.hubSettingsEngine),
            subtitle: Text(
              [
                engine.label,
                if (runtime.status.engineVersionAlias case final v?) 'v$v',
              ].join(' · '),
            ),
            onTap: () => _push(context, const EngineScreen()),
            footer: OverviewFooter(tone: engine.tone, text: engine.label),
            onFooterTap: () => _push(context, const EngineScreen()),
          ),
        ),
        // App-owned AI surface: permission + phone files. Models / Host YAML
        // stay on the Host. 「个性化 / 可视化回复」was DSH leftover — removed.
        SettingsSection(
          title: l10n.hubGroupAi,
          children: [
            SettingsTile(
              icon: AppIcons.permissions,
              tint: SettingsHues.ai,
              spot: SettingsIndex.entry(SettingsPageId.permission),
              onTap: () => _push(context, const PermissionPage()),
            ),
          ],
        ),
        // 手机操控只从悬浮球进；深链 / 搜索仍可打开 PhoneControlScreen。
        SettingsSection(
          title: l10n.hubSettingsAppearance,
          children: [
            // 性能并进「主题」页，设置首页不再单开一行。
            const AppearanceEntryTile(tint: SettingsHues.appearance),
          ],
        ),
        SettingsSection(
          title: l10n.hubGroupGeneral,
          children: [
            const LanguageSettingsTile(tint: SettingsHues.general),
            const NotificationSettingsTile(tint: SettingsHues.general),
            SettingsTile(
              icon: AppIcons.keepAlive,
              tint: SettingsHues.general,
              spot: SettingsIndex.entry(SettingsPageId.background),
              value: exempt == null
                  ? null
                  : Text(
                      exempt ? l10n.hubValueAllowed : l10n.hubValueNeedsSetup,
                      style: exempt == false ? TextStyle(color: colors.warning) : null,
                    ),
              onTap: () => _push(context, const BackgroundGuidePage()),
            ),
            SettingsTile(
              icon: AppIcons.systemAccess,
              tint: SettingsHues.general,
              spot: SettingsIndex.entry(SettingsPageId.systemAccess),
              onTap: () => _push(context, const SystemAccessPage()),
            ),
          ],
        ),
        SettingsSection(
          title: l10n.hubGroupHelp,
          children: [
            SettingsTile(
              icon: AppIcons.diagnostics,
              tint: SettingsHues.help,
              spot: SettingsIndex.entry(SettingsPageId.diagnostics),
              onTap: () => _push(context, const DiagnosticsPage()),
            ),
            SettingsTile(
              icon: AppIcons.info,
              tint: SettingsHues.help,
              spot: SettingsIndex.entry(SettingsPageId.about),
              value: newVersion
                  ? UpdateBadge(l10n.hubAboutNewVersion)
                  : Text(update.current.name, style: AppType.tabular(Theme.of(context).textTheme.bodyMedium!)),
              onTap: () => _push(context, const AboutPage()),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(child: BrandMark(size: 18, color: colors.textDisabled)),
        ),
      ],
    );
  }
}
