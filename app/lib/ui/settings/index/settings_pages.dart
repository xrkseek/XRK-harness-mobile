// The page behind each [SettingsPageId], and what a settings link
// (`xrkharness://open/<id>`) opens: a page by one of its link ids, or the page a
// row is on.

import 'package:flutter/material.dart';

import '../../engine/engine_screen.dart';
import '../../phone/app_rules_page.dart';
import '../../phone/dnd_mode_page.dart';
import '../../phone/phone_settings_gateway.dart';
import '../../phone/phone_unlock_page.dart';
import '../about_page.dart';
import '../appearance/appearance_page.dart';
import '../background_guide_page.dart';
import '../diagnostics_page.dart';
import '../notification_settings.dart';
import '../performance_page.dart';
import '../settings_screen.dart';
import '../system_access_page.dart';
import 'spot_anchor.dart';
import 'spots.dart';

export 'spots.dart';

/// Phone-shell pages only. Web-owned [SettingsPageId]s (models / plugins /
/// account / engine YAML / …) fall through to the hub — those live in the
/// in-guest Web Settings UI.
Widget settingsPage(SettingsPageId id, {String? sessionId}) {
  if (!SettingsIndex.isShellPage(id) && id != SettingsPageId.hub) {
    return const SettingsScreen();
  }
  return switch (id) {
    SettingsPageId.hub => const SettingsScreen(),
    SettingsPageId.appearance => const AppearancePage(),
    SettingsPageId.performance => const PerformancePage(),
    SettingsPageId.notifications => const NotificationSettingsPage(),
    SettingsPageId.phone => const PhoneSettingsGateway(),
    SettingsPageId.phoneAppRules => const PhoneAppRulesPage(),
    SettingsPageId.phoneDnd => const PhoneDndPage(),
    SettingsPageId.phoneUnlocks => const PhoneUnlockPage(),
    SettingsPageId.engine => const EngineScreen(),
    SettingsPageId.background => const BackgroundGuidePage(),
    SettingsPageId.systemAccess => const SystemAccessPage(),
    SettingsPageId.diagnostics => const DiagnosticsPage(),
    SettingsPageId.about => const AboutPage(),
    // Retired / Web-owned — hub.
    _ => const SettingsScreen(),
  };
}

/// What a settings link id opens: a page (by any of its link ids), or the
/// page a row is on. Null for ids the index doesn't know.
Widget? settingsPageForLink(String id, {String? sessionId}) {
  if (SettingsIndex.pageForLink(id) case final page?) {
    return settingsPage(page.id, sessionId: sessionId);
  }
  if (SettingsIndex.spotForLink(id) case final spot?) {
    return spotPage(spot, sessionId: sessionId);
  }
  return null;
}

/// Where [spot] leads: the page it opens, or the page it is on with the row
/// brought into view and lit.
Widget spotPage(SettingSpot spot, {String? sessionId}) => spot.isEntry
    ? settingsPage(spot.opens!, sessionId: sessionId)
    : SpotFocus(
        target: spot.id,
        child: settingsPage(spot.page, sessionId: sessionId),
      );

/// Pushes [spotPage] straight over the current page, without the pages in
/// between: back returns here.
Future<void> openSpot(BuildContext context, SettingSpot spot, {String? sessionId}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => spotPage(spot, sessionId: sessionId)));
