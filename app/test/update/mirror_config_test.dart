// Product default: GitHub Releases for xrkseek/XRK-harness-mobile, with public
// accelerators ordered by timezone (proxy-first in CN/SEA). Optional self-hosted
// copy via XRK_UPDATE_MIRROR / XRK_UPDATE_MIRROR. Never go.dshtui.com by default.

import 'dart:convert';

import 'package:xrk_app/update/checker.dart';
import 'package:xrk_app/update/release.dart';
import 'package:xrk_app/update/update_config.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _api = 'https://api.github.com/repos/xrkseek/XRK-harness-mobile/releases/latest';
const _apk = 'xrk-harness-0.9.0-arm64.apk';
const _githubApk = 'https://github.com/xrkseek/XRK-harness-mobile/releases/download/v0.9.0/$_apk';
const _manifest = 'https://github.com/xrkseek/XRK-harness-mobile/releases/latest/download/update.json';
const _mirror = 'https://dl.example.com';
const _mirrorFeed = '$_mirror/update.json';
const _mirrorApk = '$_mirror/download/0.9.0/$_apk';
const _utc = Duration.zero;
const _cn = Duration(hours: 8);

void main() {
  group('defaults (UTC = GitHub first)', () {
    final sources = buildUpdateSources(timezoneOffset: _utc);

    test('GitHub and accelerators, API last; no self-hosted feed; nothing on go.dshtui.com', () {
      expect(sources.channel, isNull);
      expect(sources.feed, isNull);
      expect(sources.mirrors.map((m) => m.id), ['github', 'ghfast', 'gh-proxy']);
      final endpoints = sources.metadataEndpoints();
      expect(endpoints.map((e) => e.id), [
        'manifest:github',
        'manifest:ghfast',
        'manifest:gh-proxy',
        'api',
      ]);
      expect(endpoints.map((e) => e.url.toString()).take(2), [_manifest, 'https://ghfast.top/$_manifest']);
      expect(endpoints.every((e) => e.headers.isEmpty), isTrue);
      final urls = sources.downloadUrls([Uri.parse(_githubApk)]);
      expect(urls.map((u) => u.url.toString()), [
        _githubApk,
        'https://ghfast.top/$_githubApk',
        'https://gh-proxy.com/$_githubApk',
      ]);
      expect(urls.first.label, 'GitHub');
      expect(urls.every((u) => u.headers.isEmpty), isTrue);
      expect([for (final e in endpoints) e.url.host], isNot(contains('go.dshtui.com')));
      expect([for (final e in endpoints) e.url.host], isNot(contains('dl.dshtui.com')));
    });

    test('the shipped configuration (no token in tests) matches with the same timezone', () {
      final shipped = defaultUpdateSources(timezoneOffset: _utc);
      expect(shipped.channel, isNull);
      expect(shipped.feed, isNull);
      expect(shipped.metadataEndpoints().map((e) => e.id), sources.metadataEndpoints().map((e) => e.id));
      expect(shipped.mirrors.map((m) => m.id), sources.mirrors.map((m) => m.id));
    });

    test('CN timezone prefers public proxies before raw GitHub', () {
      final cn = buildUpdateSources(timezoneOffset: _cn);
      expect(cn.mirrors.map((m) => m.id), ['ghfast', 'gh-proxy', 'github']);
      expect(preferGithubProxyByTimezone(_cn), isTrue);
      expect(preferGithubProxyByTimezone(_utc), isFalse);
      final urls = cn.downloadUrls([Uri.parse(_githubApk)]);
      expect(urls.first.url.toString(), 'https://ghfast.top/$_githubApk');
      expect(urls.last.url.toString(), _githubApk);
    });

    test('the API is not moved ahead by having answered last time; the others are', () {
      expect(sources.metadataEndpoints(preferred: 'api').map((e) => e.id).first, 'manifest:github');
      expect(sources.metadataEndpoints(preferred: 'api').last.id, 'api');
      expect(sources.metadataEndpoints(preferred: 'manifest:gh-proxy').map((e) => e.id), [
        'manifest:gh-proxy',
        'manifest:github',
        'manifest:ghfast',
        'api',
      ]);
    });

    test('GitHub update.json answers first when available', () async {
      final http = FakeHttp({_manifest: (_, _) => textResponse(fixture('update.json'))});
      final result = await UpdateChecker(http: http, sources: sources).check();
      expect(http.urls, [_manifest]);
      expect((result as CheckFound).endpoint.id, 'manifest:github');
    });

    test('accelerators then API when GitHub manifest is down', () async {
      var http = FakeHttp({
        'https://ghfast.top/$_manifest': (_, _) => textResponse('Forbidden', status: 403),
        'https://gh-proxy.com/$_manifest': (_, _) => textResponse(fixture('update.json')),
      });
      var result = await UpdateChecker(http: http, sources: sources).check();
      expect((result as CheckFound).endpoint.id, 'manifest:gh-proxy');
      expect(http.urls, isNot(contains(_api)));

      http = FakeHttp({_api: (_, _) => textResponse(fixture('github_release.json'))});
      result = await UpdateChecker(http: http, sources: sources).check();
      expect(http.urls, [
        _manifest,
        'https://ghfast.top/$_manifest',
        'https://gh-proxy.com/$_manifest',
        _api,
      ]);
      expect((result as CheckFound).endpoint.id, 'api');
    });
  });

  group('another copy of the release files (DSH_UPDATE_MIRROR)', () {
    final sources = buildUpdateSources(mirror: '$_mirror/', timezoneOffset: _utc);

    test('its update.json comes first, then GitHub; downloads try it first', () {
      expect(sources.feed.toString(), _mirrorFeed);
      expect(sources.mirrors.map((m) => m.id), ['self', 'github', 'ghfast', 'gh-proxy']);
      final urls = sources.downloadUrls([Uri.parse(_githubApk)]);
      expect(urls.map((u) => u.url.toString()), [
        _mirrorApk,
        _githubApk,
        'https://ghfast.top/$_githubApk',
        'https://gh-proxy.com/$_githubApk',
      ]);
      expect(urls.first.label, 'dl.example.com');
    });

    test('a manifest from the mirror: its URL first, no duplicate', () {
      final urls = sources.downloadUrls([Uri.parse(_mirrorApk), Uri.parse(_githubApk)]);
      expect(urls.map((u) => u.url.toString()), [
        _mirrorApk,
        _githubApk,
        'https://ghfast.top/$_githubApk',
        'https://gh-proxy.com/$_githubApk',
      ]);
    });

    test('whatever worked last still moves to the front', () {
      final urls = sources.downloadUrls([Uri.parse(_githubApk)], preferredMirror: 'github');
      expect(urls.first.url.toString(), _githubApk);
      expect(urls[1].url.toString(), _mirrorApk);
    });

    test('checksums go through the mirror too', () {
      final sums = githubReleaseAsset('v0.9.0', checksumsName);
      expect(sources.downloadUrls([sums]).first.url.toString(), '$_mirror/download/0.9.0/SHA256SUMS');
    });

    test('the mirror answers: its APK URL, nothing else asked', () async {
      final manifest = jsonEncode({
        'schema': 1,
        'version': '0.9.0+10251518',
        'tag': 'v0.9.0',
        'assets': {
          'arm64': {'name': _apk, 'size': 185254217, 'sha256': '1c' * 32, 'url': _mirrorApk},
        },
      });
      final http = FakeHttp({_mirrorFeed: (_, _) => textResponse(manifest)});
      final result = await UpdateChecker(http: http, sources: sources).check();
      expect(http.urls, [_mirrorFeed]);
      final found = result as CheckFound;
      expect(found.endpoint.id, 'feed');
      expect(found.release.apks[ApkFlavor.arm64]!.url.toString(), _mirrorApk);
    });

    test('the mirror is down or answers with an error page: GitHub answers', () async {
      var http = FakeHttp({_manifest: (_, _) => textResponse(fixture('update.json'))});
      var result = await UpdateChecker(http: http, sources: sources).check();
      expect(http.urls, [_mirrorFeed, _manifest]);
      expect((result as CheckFound).endpoint.id, 'manifest:github');

      http = FakeHttp({
        _mirrorFeed: (_, _) => textResponse('<html>502</html>', status: 502),
        _manifest: (_, _) => textResponse(fixture('update.json')),
      });
      result = await UpdateChecker(http: http, sources: sources).check();
      expect((result as CheckFound).endpoint.id, 'manifest:github');
    });
  });

  group('the mirror only maps tagged release files', () {
    final mirror = UpdateMirror.selfHosted(_mirror);

    test('tag → version directory', () {
      expect(
        mirror.rewrite(githubReleaseAsset('v1.3.0-beta.1', 'xrk-harness-1.3.0-beta.1-x64.apk')).toString(),
        '$_mirror/download/1.3.0-beta.1/xrk-harness-1.3.0-beta.1-x64.apk',
      );
    });

    test('nothing else', () {
      expect(mirror.rewrite(githubLatestAsset(updateManifestName)), isNull);
      expect(mirror.rewrite(githubReleaseAsset('0.9.0', _apk)), isNull);
      expect(mirror.rewrite(Uri.parse('https://github.com/someone/else/releases/download/v1.0.0/a.apk')), isNull);
      expect(mirror.rewrite(Uri.parse(_mirrorApk)), isNull);
    });
  });

  group('overrides', () {
    test('another feed; downloads still try the optional copy first when set', () {
      final sources = buildUpdateSources(
        mirror: 'https://dl.example.com',
        feed: 'https://update.example.com/dsh/update.json',
        timezoneOffset: _utc,
      );
      expect(sources.feed.toString(), 'https://update.example.com/dsh/update.json');
      expect(sources.metadataEndpoints().first.id, 'feed');
      expect(sources.mirrors.first.id, 'self');
      expect(buildUpdateSources(feed: '', timezoneOffset: _utc).feed, isNull);
      expect(buildUpdateSources(mirror: _mirror, feed: '', timezoneOffset: _utc).feed, isNull);
    });

    test('no copy at all: GitHub only, the API still last', () {
      final sources = buildUpdateSources(mirror: '', timezoneOffset: _utc);
      expect(sources.feed, isNull);
      expect(sources.mirrors.map((m) => m.id), ['github', 'ghfast', 'gh-proxy']);
      expect(sources.metadataEndpoints().map((e) => e.id), [
        'manifest:github',
        'manifest:ghfast',
        'manifest:gh-proxy',
        'api',
      ]);
    });

    test('accelerators replaced or dropped', () {
      expect(
        buildUpdateSources(accelerators: 'https://a.example/', timezoneOffset: _utc).mirrors.map((m) => m.id),
        ['github', 'custom0'],
      );
      expect(buildUpdateSources(accelerators: '', timezoneOffset: _utc).mirrors.map((m) => m.id), ['github']);
    });
  });
}
