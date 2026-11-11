// Every user-facing surface of the official XRK Web client (0.2.1-rc.2) and
// where it lives in the app: a native page, the official page inside the app
// (XRK Web with a deep link), or both. The parity table behind it is
// `docs/official-parity.md`.

import 'dart:async';

import 'package:xrk_client/xrk_client.dart' show PluginBundle;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n.dart';
import '../../plugins/native/native_icons.dart';
import '../../plugins/native/native_state.dart';
import '../../plugins/seams/seams.dart';
import '../../state/plugins_state.dart';
import '../common/feature_tile.dart';
import '../files/files_page.dart';
import '../engine/engine_screen.dart';
import '../phone/phone_control_screen.dart';
import '../plugins/seats/plugin_seat_page.dart';
import '../plugins/seats/seat_links.dart';
import '../session/session_artifacts.dart';
import '../session/session_detail_page.dart';
import '../shell/session_search_page.dart';
import '../settings/appearance/appearance_page.dart';
import '../settings/index/spots.dart';
import '../settings/notification_settings.dart';
import '../terminal/terminal_page.dart';
import '../theme/app_icons.dart';
import '../web/web_target.dart';
import 'feature_widgets.dart' show openSessionInChat;
import 'jobs_page.dart';
import 'session_export_page.dart';
import 'skills_page.dart';

/// Builds a native page; [sessionId] is the conversation open in the chat.
typedef FeaturePageBuilder = Widget Function(String? sessionId);

/// Does something other than pushing a page (a sheet, back to the chat).
typedef FeatureAction = FutureOr<void> Function(BuildContext context, WidgetRef ref, String? sessionId);

/// One entry of 全部功能.
class FeatureItem {
  const FeatureItem({
    required this.id,
    required this._title,
    required this._summary,
    required this.icon,
    this.tile,
    this.native,
    this.action,
    this.web,
    this.needsSession = false,
    this.webInSession = false,
  }) : _localizedTitle = null,
       _localizedSummary = null,
       assert(native != null || action != null || web != null);

  const FeatureItem.localized({
    required this.id,
    required String Function(L10n) title,
    required String Function(L10n) summary,
    required this.icon,
    this.tile,
    this.native,
    this.action,
    this.web,
    this.needsSession = false,
    this.webInSession = false,
  }) : _title = '',
       _summary = '',
       _localizedTitle = title,
       _localizedSummary = summary,
       assert(native != null || action != null || web != null);

  final String id;
  final String _title;
  final String _summary;
  final String Function(L10n)? _localizedTitle;
  final String Function(L10n)? _localizedSummary;

  // Resolve on read: the catalog and its provider keep the same objects
  // across language changes.
  String get title => _localizedTitle?.call(appL10n) ?? _title;
  String get summary => _localizedSummary?.call(appL10n) ?? _summary;

  /// [title] in [l10n]'s language (search matches both languages).
  String titleIn(L10n l10n) => _localizedTitle?.call(l10n) ?? _title;
  final IconData icon;

  /// The feature's own graphic ([FeatureTile]), for the nine headline features.
  final FeatureKind? tile;

  /// The app's own page, when there is one.
  final FeaturePageBuilder? native;

  /// The app's own way in when it isn't a page (a sheet, the composer).
  final FeatureAction? action;

  /// The official page inside the app.
  final DshWebTarget? web;

  /// Only makes sense for an open conversation (disabled without one).
  final bool needsSession;

  /// The web page belongs to the open conversation: open it there first.
  final bool webInSession;

  /// The app has its own page or flow for it.
  bool get hasNative => native != null || action != null;

  bool get webOnly => !hasNative;

  /// [web] aimed at [sessionId] when it belongs to a conversation.
  DshWebTarget? webFor(String? sessionId) => webInSession && sessionId != null ? web?.inSession(sessionId) : web;
}

class FeatureSection {
  const FeatureSection(String title, this.items, {this.note, this.id}) : _title = title, _localizedTitle = null;

  const FeatureSection.localized(String Function(L10n) title, this.items, {this.note, this.id})
    : _title = '',
      _localizedTitle = title;

  /// Names a section the page draws something more for ([settingsFeatureSection]).
  final String? id;

  final String _title;
  final String Function(L10n)? _localizedTitle;
  String get title => _localizedTitle?.call(appL10n) ?? _title;

  /// [title] in [l10n]'s language.
  String titleIn(L10n l10n) => _localizedTitle?.call(l10n) ?? _title;
  final List<FeatureItem> items;
  final String? note;
}

String _session(String? id) => id ?? '';

/// Back to the chat, where the composer does the rest (`@`, the mic).
void _backToChat(BuildContext context, WidgetRef ref, String? _) =>
    Navigator.of(context).popUntil((route) => route.isFirst);

/// The last section: shortcuts to settings pages (the same pages, by the same
/// names), followed by 全部设置.
const settingsFeatureSection = 'settings';

/// What 全部功能 holds: things to do now. Settings live in 设置; the last
/// group is a few shortcuts there (docs/design/settings-ia.md §4.6).
final featureSections = <FeatureSection>[
  FeatureSection.localized((l10n) => l10n.catalogCurrentChat, [
    FeatureItem.localized(
      id: 'session-detail',
      title: (l10n) => l10n.catalogChatDetails,
      summary: (l10n) => l10n.catalogChatDetailsSummary,
      icon: AppIcons.sessionDetails,
      needsSession: true,
      action: (context, ref, id) => SessionDetailPage.open(context, _session(id)),
    ),
    FeatureItem.localized(
      id: 'artifacts',
      title: (l10n) => l10n.catalogArtifacts,
      summary: (l10n) => l10n.catalogArtifactsSummary,
      icon: AppIcons.artifacts,
      needsSession: true,
      native: (id) => SessionArtifactsPage(sessionId: _session(id)),
    ),
    FeatureItem.localized(
      id: 'files',
      title: (l10n) => l10n.catalogFiles,
      summary: (l10n) => l10n.catalogFilesSummary,
      icon: AppIcons.files,
      tile: FeatureKind.files,
      needsSession: true,
      native: (id) => WorkspaceFilesPage(sessionId: _session(id)),
    ),
    FeatureItem.localized(
      id: 'terminal',
      title: (l10n) => l10n.catalogTerminal,
      summary: (l10n) => l10n.catalogTerminalSummary,
      icon: AppIcons.terminal,
      tile: FeatureKind.terminal,
      needsSession: true,
      native: (id) => TerminalPage(sessionId: _session(id)),
    ),
    FeatureItem.localized(
      id: 'export',
      title: (l10n) => l10n.catalogExport,
      summary: (l10n) => l10n.catalogExportSummary,
      icon: AppIcons.exportLog,
      needsSession: true,
      native: (id) => SessionExportPage(sessionId: _session(id)),
    ),
    FeatureItem.localized(
      id: 'jobs',
      title: (l10n) => l10n.catalogJobs,
      summary: (l10n) => l10n.catalogJobsSummary,
      icon: AppIcons.jobs,
      needsSession: true,
      native: (id) => JobsPage(sessionId: _session(id)),
    ),
    FeatureItem.localized(
      id: 'plan-goal',
      title: (l10n) => l10n.catalogPlanGoal,
      summary: (l10n) => l10n.catalogPlanGoalSummary,
      icon: AppIcons.goal,
      needsSession: true,
      action: (context, ref, id) => SessionDetailPage.open(context, _session(id), tab: SessionTab.progress),
    ),
    FeatureItem.localized(
      id: 'skills',
      title: (l10n) => l10n.catalogSkills,
      summary: (l10n) => l10n.catalogSkillsSummary,
      icon: AppIcons.skill,
      needsSession: true,
      native: (id) => SkillsPage(sessionId: _session(id)),
    ),
    FeatureItem.localized(
      id: 'subagents',
      title: (l10n) => l10n.catalogSubagents,
      summary: (l10n) => l10n.catalogSubagentsSummary,
      icon: AppIcons.subagents,
      tile: FeatureKind.subagents,
      needsSession: true,
      action: (context, ref, id) => SessionDetailPage.open(context, _session(id), tab: SessionTab.subagents),
    ),
    FeatureItem.localized(
      id: 'reference',
      title: (l10n) => l10n.catalogReference,
      summary: (l10n) => l10n.catalogReferenceSummary,
      icon: AppIcons.mention,
      action: _backToChat,
    ),
  ]),
  FeatureSection.localized((l10n) => l10n.catalogPlugins, [
  ]),
  FeatureSection.localized((l10n) => l10n.catalogToolsSection, [
    FeatureItem.localized(
      id: 'search',
      title: (l10n) => l10n.catalogSearch,
      summary: (l10n) => l10n.catalogSearchSummary,
      icon: AppIcons.search,
      action: (context, ref, _) async {
        final id = await showSessionSearch(context);
        if (id != null && context.mounted) {
          openSessionInChat(context, ref, id);
        }
      },
    ),
    FeatureItem.localized(
      id: 'web',
      title: (l10n) => l10n.commonWeb,
      summary: (l10n) => l10n.catalogWebSummary,
      icon: AppIcons.webApp,
      web: const DshWebTarget(),
    ),
  ]),
  // Phone-shell settings only (same homes as the Settings hub). Models /
  // permission / remote / plugins live in in-guest Web Settings — do not
  // surface native Host dead pages from 全部功能.
  FeatureSection.localized((l10n) => l10n.commonSettings, [
    FeatureItem.localized(
      id: 'phone',
      title: (l10n) => l10n.catalogPhoneControl,
      summary: (l10n) => l10n.catalogPhoneControlSummary,
      icon: AppIcons.phoneControl,
      tile: FeatureKind.phone,
      // Prefer Host Settings › phone (xrk-mobile-ui guest plugin). AllFeatures
      // + Settings hub route via hostSettingsOpener; native is unlock/a11y fallback.
      native: (_) => const PhoneControlScreen(),
      web: const DshWebTarget(settings: DshWebSettings.phone),
    ),
    FeatureItem.localized(
      id: 'appearance',
      title: (l10n) => SettingsIndex.page(SettingsPageId.appearance).title(l10n),
      summary: (l10n) => l10n.searchKwTheme,
      icon: AppIcons.theme,
      native: (_) => const AppearancePage(),
    ),
    FeatureItem.localized(
      id: 'notifications',
      title: (l10n) => SettingsIndex.page(SettingsPageId.notifications).title(l10n),
      summary: (l10n) => l10n.searchKwNotifications,
      icon: AppIcons.notifications,
      native: (_) => const NotificationSettingsPage(),
    ),
    FeatureItem.localized(
      id: 'engine',
      title: (l10n) => SettingsIndex.page(SettingsPageId.engine).title(l10n),
      summary: (l10n) => l10n.searchKwEngine,
      icon: AppIcons.engine,
      native: (_) => const EngineScreen(),
    ),
  ], id: settingsFeatureSection),
];

/// Plugin seat panels are guest-Web / plugin UI — not mirrored in 全部功能.
final featureSectionsProvider = Provider.autoDispose<List<FeatureSection>>((ref) => featureSections);
