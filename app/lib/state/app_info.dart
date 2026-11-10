import '../l10n/l10n.dart';

/// Build-time app metadata.
///
/// There is no package_info plugin in the dependency set, so the version is a
/// constant kept in sync with `pubspec.yaml` (`version: 0.7.16+1`). Release builds can
/// override it: `flutter build apk --dart-define=XRK_APP_VERSION=1.2.0+7`
/// (falls back to legacy `XRK_APP_VERSION` if only that is set).
abstract final class AppInfo {
  static const version = String.fromEnvironment(
    'XRK_APP_VERSION',
    defaultValue: String.fromEnvironment('XRK_APP_VERSION', defaultValue: '0.7.16+1'),
  );

  /// "1.0.0 (1)" for display.
  static String get displayVersion {
    final parts = version.split('+');
    return parts.length == 2 ? '${parts[0]} (${parts[1]})' : version;
  }

  /// The app's name as the phone shows it: launcher, Recents, notifications, system
  /// settings, the licence page. Matches `android:label` in AndroidManifest.xml.
  static const name = 'XRK Harness';

  /// The in-app wordmark: the drawer's lockup, the welcome page and the brand mark's
  /// spoken label.
  static const wordmark = 'XRK';

  /// Product identity line on About / licence: official XRK Harness.
  static String get disclaimer => appL10n.stateAppDisclaimer;

  /// The line under the brand mark (welcome page, About).
  static String get slogan => appL10n.appSlogan;

  /// Public product repo (About author row + Star + update feed).
  static const author = 'xrkseek';
  static const authorGithubHandle = 'xrkseek/XRK-harness-mobile';
  static const authorGithubUrl = 'https://github.com/xrkseek/XRK-harness-mobile';

  static const deepseekPlatform = 'https://platform.deepseek.com/api_keys';
  static const remoteConsole = 'https://dsh.r2049.cn/app';

  /// XRK Remote's upstream, credited under the XRK Remote card as its GitHub
  /// handle and name.
  static const remoteProject = 'liguobao/xrk-remote';
  static const remoteProjectUrl = 'https://github.com/$remoteProject';
}
