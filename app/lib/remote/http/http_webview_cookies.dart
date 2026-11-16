import 'package:webview_flutter/webview_flutter.dart';

import 'http_host_config.dart';
import 'http_host_link.dart';

/// Cookies harvested from Face WebView after PIN / pair / renew.
///
/// PIN-only Face sets `dsh_ma_lan` / `dsh_ma_wan` (and maybe `xrk_operator_ui`)
/// but **not** `dsh_ma_device`. Bridge ticket accepts PIN proof + App clientDeviceId.
class BridgeWebCookies {
  const BridgeWebCookies({
    this.deviceToken = '',
    this.sessionToken = '',
    this.csrfToken,
    this.lanPinCookie = '',
    this.wanPinCookie = '',
  });

  final String deviceToken;
  final String sessionToken;
  final String? csrfToken;
  final String lanPinCookie;
  final String wanPinCookie;

  bool get hasPairedSession => deviceToken.isNotEmpty && sessionToken.isNotEmpty;

  /// Enough to prove Face gate (pair session or LAN/WAN PIN).
  bool get hasOperatorProof =>
      hasPairedSession ||
      sessionToken.isNotEmpty ||
      lanPinCookie.isNotEmpty ||
      wanPinCookie.isNotEmpty;

  HttpHostSession get asSession => HttpHostSession(
        deviceToken: deviceToken,
        sessionToken: sessionToken,
        csrfToken: csrfToken,
        lanPinCookie: lanPinCookie,
        wanPinCookie: wanPinCookie,
      );
}

/// Read mobile-access cookies the Face WebView obtained after PIN / renew.
Future<BridgeWebCookies?> readBridgeCookiesFromWebView(HttpHostConfig config) async {
  final manager = WebViewCookieManager();
  final uri = Uri.parse(config.origin);
  var cookies = await manager.getCookies(domain: uri);
  if (cookies.isEmpty && uri.hasAuthority) {
    cookies = await manager.getCookies(
      domain: Uri(scheme: uri.scheme, host: uri.host, port: uri.hasPort ? uri.port : null),
    );
  }
  var device = '';
  var session = '';
  String? csrf;
  var lan = '';
  var wan = '';
  for (final c in cookies) {
    if (c.name == HttpHostLink.deviceCookie) device = c.value;
    if (c.name == HttpHostLink.sessionCookie) session = c.value;
    if (c.name == HttpHostLink.csrfCookie) csrf = c.value;
    if (c.name == HttpHostLink.lanPinCookie) lan = c.value;
    if (c.name == HttpHostLink.wanPinCookie) wan = c.value;
  }
  final out = BridgeWebCookies(
    deviceToken: device,
    sessionToken: session,
    csrfToken: csrf,
    lanPinCookie: lan,
    wanPinCookie: wan,
  );
  if (!out.hasOperatorProof) return null;
  return out;
}

/// Read paired device/session cookies (legacy helper).
Future<HttpHostSession?> readHttpHostCookiesFromWebView(HttpHostConfig config) async {
  final bridge = await readBridgeCookiesFromWebView(config);
  return bridge?.asSession;
}

/// Push mobile-access session cookies into the shared WebView cookie jar.
Future<void> injectHttpHostCookies(HttpHostConfig config, HttpHostSession session) async {
  final manager = WebViewCookieManager();
  final host = Uri.parse(config.origin).host;
  Future<void> put(String name, String value, {required String path}) {
    return manager.setCookie(
      WebViewCookie(name: name, value: value, domain: host, path: path),
    );
  }

  if (session.deviceToken.isNotEmpty) {
    await put(HttpHostLink.deviceCookie, session.deviceToken, path: '/mobile-access/auth/renew');
  }
  if (session.sessionToken.isNotEmpty) {
    await put(HttpHostLink.sessionCookie, session.sessionToken, path: '/');
  }
  final csrf = session.csrfToken;
  if (csrf != null && csrf.isNotEmpty) {
    await put(HttpHostLink.csrfCookie, csrf, path: '/');
  }
  if (session.lanPinCookie.isNotEmpty) {
    await put(HttpHostLink.lanPinCookie, session.lanPinCookie, path: '/');
  }
  if (session.wanPinCookie.isNotEmpty) {
    await put(HttpHostLink.wanPinCookie, session.wanPinCookie, path: '/');
  }
  await put(HttpHostLink.operatorUiCookie, '1', path: '/');
}
