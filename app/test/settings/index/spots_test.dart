// The settings index holds together on its own: unique ids, every page
// reachable from the hub, every searchable entry with synonyms in both
// languages, link ids that don't collide.

import 'package:xrk_app/l10n/l10n.dart';
import 'package:xrk_app/links/page_links.dart';
import 'package:xrk_app/ui/features/feature_catalog.dart';
import 'package:xrk_app/ui/settings/index/settings_pages.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final zh = lookupL10n(const Locale('zh'));
  final en = lookupL10n(const Locale('en'));

  test('ids are unique', () {
    final ids = [for (final s in SettingsIndex.spots) s.id];
    expect(ids.toSet().length, ids.length);
    for (final id in ids) {
      expect(id, matches(RegExp(r'^(page:[a-zA-Z]+|[a-z0-9-]+)$')), reason: id);
    }
  });

  test('every page is registered once and walks back to the hub', () {
    expect(SettingsIndex.pages.keys.toSet(), SettingsPageId.values.toSet());
    expect(SettingsIndex.page(SettingsPageId.hub).parent, isNull);
    for (final id in SettingsPageId.values) {
      final chain = SettingsIndex.chain(id);
      expect(chain.first, SettingsPageId.hub, reason: '$id');
      expect(chain.last, id);
      expect(chain.toSet().length, chain.length, reason: 'a loop above $id');
    }
  });

  test('a page group is only set where the hub shows the row', () {
    for (final page in SettingsIndex.pages.values) {
      if (page.group != null) expect(page.parent, SettingsPageId.hub, reason: '${page.id}');
    }
    for (final spot in SettingsIndex.rows) {
      if (spot.group != null) expect(spot.page, SettingsPageId.hub, reason: spot.id);
    }
  });

  test('an entry carries its page\'s name (one home, one name)', () {
    for (final page in SettingsIndex.pages.values.where((p) => p.parent != null)) {
      final entry = SettingsIndex.entry(page.id);
      expect(entry.page, page.parent);
      expect(entry.opens, page.id);
      for (final l10n in [zh, en]) {
        expect(entry.title(l10n), page.title(l10n));
      }
    }
  });

  test('every searchable entry has synonyms in Chinese and English', () {
    for (final spot in SettingsIndex.spots) {
      if (spot.opens == SettingsPageId.hub) continue;
      expect(spot.keywords, isNotNull, reason: spot.id);
      for (final l10n in [zh, en]) {
        final words = spot.keywords!(l10n).split(',').map((w) => w.trim()).toList();
        expect(words.where((w) => w.isNotEmpty), isNotEmpty, reason: spot.id);
        expect(words.every((w) => w.isNotEmpty), isTrue, reason: '${spot.id}: an empty synonym');
        expect(spot.title(l10n).trim(), isNotEmpty, reason: spot.id);
      }
    }
  });

  test('link ids are unique and don\'t collide with 全部功能\'s', () {
    final ids = [for (final p in SettingsIndex.pages.values) ...p.links, for (final s in SettingsIndex.rows) ?s.link];
    expect(ids.toSet().length, ids.length);
    expect(ids.toSet().intersection(catalogPageLinks), isEmpty);
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[a-z0-9-]+$')), reason: id);
      expect(pageLinkId(Uri.parse('xrkharness://open/$id')), id);
    }
  });

  test('全部功能\'s 设置 cards are shell settings pages, by the same names', () {
    final section = featureSections.singleWhere((s) => s.id == settingsFeatureSection);
    expect(featureSections.last, section, reason: 'the last group');
    expect([for (final i in section.items) i.id], ['phone', 'appearance', 'notifications', 'engine']);
    for (final item in section.items) {
      final page = SettingsIndex.pageForLink(item.id);
      expect(page, isNotNull, reason: item.id);
      expect(SettingsIndex.isShellPage(page!.id), isTrue, reason: item.id);
      for (final l10n in [zh, en]) {
        expect(item.titleIn(l10n), page.title(l10n), reason: item.id);
      }
      // Phone keeps a Host-web-aware gateway; other cards match settingsPage.
      if (item.id == 'phone') {
        expect(item.native, isNotNull);
        continue;
      }
      expect(item.native!(null).runtimeType, settingsPage(page.id).runtimeType, reason: item.id);
    }
  });

  test('the way there reads like the guide; a result path names the hub group', () {
    expect(SettingsIndex.trail(Spots.phoneConfirm, zh), ['设置', '手机操控', '确认方式']);
    expect(SettingsIndex.trail(SettingsIndex.entry(SettingsPageId.phone), zh), ['设置', '手机操控']);
    expect(SettingsIndex.trail(Spots.phoneConfirm, en), ['Settings', 'Phone control', 'Confirmation']);
    // A page shows the pages down to itself; a row the page it is on.
    expect(SettingsIndex.path(SettingsIndex.entry(SettingsPageId.phone), zh), ['设置', '能力', '手机操控']);
    expect(SettingsIndex.path(Spots.phoneConfirm, zh), ['设置', '能力', '手机操控']);
    expect(SettingsIndex.path(SettingsIndex.entry(SettingsPageId.permission), zh), ['设置', 'AI', '权限']);
    expect(SettingsIndex.path(Spots.phoneFiles, en), ['Settings', 'AI', 'Permissions']);
    expect(SettingsIndex.path(Spots.chatTextSize, zh), ['设置', zh.hubSettingsAppearance]);
  });

  test('phone search index keeps shell hub pages and drops Host / orphan rows', () {
    final ids = {for (final s in SettingsIndex.spots) s.id};
    expect(ids.contains('page:phone'), isTrue);
    expect(ids.contains('page:appearance'), isTrue);
    expect(ids.contains('page:interface'), isTrue);
    expect(ids.contains('page:background'), isTrue);
    expect(ids.contains('language'), isTrue);
    expect(SettingsIndex.isShellPage(SettingsPageId.interface), isTrue);
    // Host-owned pages must stay shell:false and out of search.
    expect(SettingsIndex.isShellPage(SettingsPageId.models), isFalse);
    expect(SettingsIndex.isShellPage(SettingsPageId.plugins), isFalse);
    expect(SettingsIndex.isShellPage(SettingsPageId.account), isFalse);
    expect(ids.contains('page:models'), isFalse);
    expect(ids.contains('page:plugins'), isFalse);
    expect(ids.contains('page:account'), isFalse);
    // Orphans kept on Spots for compile, never indexed.
    expect(ids.contains('community'), isFalse);
    expect(ids.contains('fold-turns'), isFalse);
    expect(ids.contains('chat-text-size'), isFalse);
    expect(SettingsIndex.rows.map((s) => s.id), isNot(contains('community')));
    expect(SettingsIndex.rows.map((s) => s.id), isNot(contains('fold-turns')));
  });
}
