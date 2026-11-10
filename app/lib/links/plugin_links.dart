// Official-market plugin pages on the share host: `$shareHostOrigin/p/<name>`.
// Off when [shareHostOrigin] is empty.

import 'dart:async';

import 'package:xrk_client/xrk_client.dart' show MarketIndexException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../share_hosted/hosted_config.dart' show shareHostOrigin;
import '../state/plugins_state.dart';
import '../ui/plugins/plugin_detail_sheet.dart' show showMarketPluginSheet;
import 'app_links.dart';

final _packageName = RegExp(r'^(?:@[a-z0-9][a-z0-9._~-]*/)?[a-z0-9][a-z0-9._~-]*$');

/// The page of [name] in the official market, the package name encoded as
/// one path segment (`/p/%40scope%2Fname`). Empty host → empty string.
String marketPluginLink(String name) =>
    shareHostOrigin.isEmpty ? '' : '$shareHostOrigin/p/${Uri.encodeComponent(name)}';

/// The package a plugin link names — https or app-link scheme on the share
/// host; null when no share host or the URI is something else.
String? marketPluginLinkName(Uri uri) {
  if (shareHostOrigin.isEmpty) return null;
  final host = Uri.tryParse(shareHostOrigin)?.host;
  if (host == null || host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != appLinkScheme) return null;
  if (uri.host.toLowerCase() != host || uri.userInfo.isNotEmpty || uri.hasPort) {
    return null;
  }
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 2 || segments.length > 3 || segments.first != 'p') return null;
  final name = segments.skip(1).join('/');
  return _packageName.hasMatch(name) && name.length <= 214 ? name : null;
}

/// [name]'s market entry: the official market's, else dshfind's. Null when
/// neither lists it.
Future<MarketEntry?> findMarketEntry(ProviderContainer container, String name) async {
  try {
    if ((await container.read(officialMarketProvider.future)).byName[name] case final entry?) return entry;
  } on MarketFetchException {
    // dshfind may still list it.
  } on MarketIndexException {
    // Same.
  }
  return (await container.read(marketCatalogProvider.future)).byName[name];
}

/// Opens [uri]'s plugin in its detail sheet over the home route; a plugin
/// neither market lists, or a market that can't be read, gets a toast.
/// False when [uri] isn't a plugin link.
Future<bool> openMarketPluginLink(BuildContext context, Uri uri) async {
  final name = marketPluginLinkName(uri);
  if (name == null) return false;
  final l10n = context.l10n;
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    final entry = await findMarketEntry(container, name);
    if (!context.mounted) return true;
    if (entry == null) {
      messenger?.showSnackBar(SnackBar(content: Text(l10n.marketLinkNotFound(name))));
      return true;
    }
    unawaited(showMarketPluginSheet(context, entry));
  } on Object catch (error) {
    messenger?.showSnackBar(
      SnackBar(content: Text(error is MarketFetchException ? error.message : l10n.pluginsMarketInvalid)),
    );
  }
  return true;
}

/// Registers `<share host>/p` with [router]. No-op when share host is unset.
VoidCallback registerPluginLinks(LinkRouter router) {
  final host = Uri.tryParse(shareHostOrigin)?.host;
  if (host == null || host.isEmpty) return () {};
  return router.registerLinkHandler('$host/p', (uri) async {
    final context = router.context;
    if (context == null) return false;
    return openMarketPluginLink(context, uri);
  });
}
