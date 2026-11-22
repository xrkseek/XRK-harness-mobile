import 'package:xrk_app/shell/shell_host_download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('session.export URLs are recognized', () {
    expect(
      isHostSessionExportUrl('http://127.0.0.1:8787/api/session.export?sessionId=s1'),
      isTrue,
    );
    expect(
      isHostSessionExportUrl('http://127.0.0.1:8787/api/face/session.export?sessionId=s1'),
      isTrue,
    );
    expect(isHostSessionExportUrl('http://127.0.0.1:8787/api/session.list'), isFalse);
  });

  test('workspace file download URLs are recognized', () {
    expect(
      isHostWorkspaceFileDownloadUrl('http://127.0.0.1:8787/sidebar/file?path=/a.md&download=1'),
      isTrue,
    );
    expect(
      isHostWorkspaceFileDownloadUrl('http://127.0.0.1:8787/sidebar/file?path=/a.md'),
      isFalse,
    );
  });

  test('session-log vs workspace file copy routing', () {
    expect(
      isHostSessionExportDownload(
        url: 'http://h/api/session.export?sessionId=s1',
        filename: 'xrk-session-s1.zip',
      ),
      isTrue,
    );
    expect(
      isHostSessionExportDownload(
        url: 'http://h/sidebar/file?path=/a.pptx&download=1',
        filename: '随机演示.pptx',
      ),
      isFalse,
    );
    expect(
      isHostSessionExportDownload(url: '', filename: 'xrk-session-sess_x.zip'),
      isTrue,
    );
  });

  test('blob/data and download routes are shell-intercepted', () {
    expect(isObjectDownloadUrl('blob:http://host/uuid'), isTrue);
    expect(isObjectDownloadUrl('data:text/plain,hi'), isTrue);
    expect(isHostShellDownloadNavigation('blob:http://103.236.89.174:8787/abc'), isTrue);
    expect(
      isHostShellDownloadNavigation('http://h/sidebar/file?path=x&download=1'),
      isTrue,
    );
  });

  test('filename prefers suggested, else sessionId', () {
    expect(hostDownloadFilename('http://x/api/session.export?sessionId=a/b', 'keep.zip'), 'keep.zip');
    expect(
      hostDownloadFilename('http://x/api/session.export?sessionId=ses_01/x', null),
      'xrk-session-ses_01_x.zip',
    );
  });

  test('absolute URLs pass through', () {
    final uri = resolveHostDownloadUri(
      'http://127.0.0.1:8787/api/session.export?sessionId=s1',
      pageUrl: 'http://127.0.0.1:8787/?token=x',
    );
    expect(uri.toString(), 'http://127.0.0.1:8787/api/session.export?sessionId=s1');
  });

  test('relative URLs resolve against the WebView page', () {
    final uri = resolveHostDownloadUri(
      '/api/session.export?sessionId=s1',
      pageUrl: 'http://127.0.0.1:8787/chat?x=1',
    );
    expect(uri.scheme, 'http');
    expect(uri.host, '127.0.0.1');
    expect(uri.port, 8787);
    expect(uri.path, '/api/session.export');
    expect(uri.queryParameters['sessionId'], 's1');
  });

  test('relative URLs without a page base fail clearly', () {
    expect(
      () => resolveHostDownloadUri('/api/session.export?sessionId=s1'),
      throwsA(isA<StateError>()),
    );
  });
}
