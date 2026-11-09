import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens Host Settings to [sectionId] (e.g. `phone`, `general`).
/// Returns true when the WebView bridge accepted the open.
typedef HostSettingsOpener = Future<bool> Function({String sectionId});

class HostSettingsOpenerController extends Notifier<HostSettingsOpener?> {
  @override
  HostSettingsOpener? build() => null;

  void bind(HostSettingsOpener? opener) => state = opener;
}

/// Bound by [LocalHostShell] while the thin Host WebView is live.
/// `sectionId: phone` → native [PhoneControlScreen]; other sections → native
/// [SettingsScreen]. Host's own settings panel is opened from the shell ball.
final hostSettingsOpenerProvider =
    NotifierProvider<HostSettingsOpenerController, HostSettingsOpener?>(HostSettingsOpenerController.new);

/// Opens native 手机操控 when the thin shell is mounted.
Future<bool> openHostPhoneSettings(WidgetRef ref) async {
  final open = ref.read(hostSettingsOpenerProvider);
  if (open == null) return false;
  return open(sectionId: 'phone');
}
