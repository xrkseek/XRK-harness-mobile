import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme/accent.dart';

/// Where the shell accent comes from.
enum AccentSource {
  /// One of the six presets ([AppearanceSettings.presetId]).
  preset,

  /// User-picked hue ([AppearanceSettings.customColor]), contrast-guarded.
  custom,
}

/// Accent half of appearance. Theme mode stays in `settings_state.dart`.
class AppearanceSettings {
  const AppearanceSettings({
    this.source = AccentSource.preset,
    this.presetId = 'mist',
    this.customColor = defaultCustom,
    this.loaded = false,
  });

  final AccentSource source;

  /// Last preset; restored when leaving custom.
  final String presetId;

  /// Custom ARGB before contrast guard.
  final int customColor;
  final bool loaded;

  /// Default custom: muted moss green (hue 140°).
  static const defaultCustom = 0xFF5F7A55;

  AppearanceSettings copyWith({AccentSource? source, String? presetId, int? customColor, bool? loaded}) =>
      AppearanceSettings(
        source: source ?? this.source,
        presetId: presetId ?? this.presetId,
        customColor: customColor ?? this.customColor,
        loaded: loaded ?? this.loaded,
      );
}

class AppearanceController extends Notifier<AppearanceSettings> {
  static const _sourceKey = 'appearance.accent_source';
  static const _presetKey = 'appearance.preset';
  static const _customKey = 'appearance.custom_color';

  /// Seed ARGB for native notification chrome (`DynamicColorPlugin` ThemeAccent).
  static const notifyColorKey = 'appearance.notify_color';

  late Future<void> _loaded;

  @override
  AppearanceSettings build() {
    _loaded = _load();
    return const AppearanceSettings();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Retired `wallpaper` source maps back to preset.
      final raw = prefs.getString(_sourceKey);
      final source = raw == 'custom' ? AccentSource.custom : AccentSource.preset;
      state = AppearanceSettings(
        source: source,
        presetId: AppAccent.preset(prefs.getString(_presetKey)).id,
        customColor: prefs.getInt(_customKey) ?? AppearanceSettings.defaultCustom,
        loaded: true,
      );
    } catch (_) {
      state = state.copyWith(loaded: true);
    }
  }

  Future<void> _save(AppearanceSettings next, Future<void> Function(SharedPreferences prefs) write) async {
    await _loaded;
    state = next.copyWith(loaded: true);
    try {
      await write(await SharedPreferences.getInstance());
    } catch (_) {
      // Kept for this run only.
    }
  }

  Future<void> selectPreset(String id) => _save(state.copyWith(source: AccentSource.preset, presetId: id), (p) async {
    await p.setString(_sourceKey, AccentSource.preset.name);
    await p.setString(_presetKey, id);
  });

  Future<void> selectCustom([int? color]) =>
      _save(state.copyWith(source: AccentSource.custom, customColor: color), (p) async {
        await p.setString(_sourceKey, AccentSource.custom.name);
        if (color != null) await p.setInt(_customKey, color);
      });
}

final appearanceProvider = NotifierProvider<AppearanceController, AppearanceSettings>(AppearanceController.new);

/// Active accent (preset or custom).
final accentProvider = Provider<AppAccent>((ref) {
  final s = ref.watch(appearanceProvider);
  final preset = AppAccent.preset(s.presetId);
  final accent = switch (s.source) {
    AccentSource.preset => preset,
    AccentSource.custom => AppAccent.derive(Color(s.customColor)),
  };
  if (s.loaded) unawaited(_publishNotifyColor(accent));
  return accent;
});

int? _published;

Future<void> _publishNotifyColor(AppAccent accent) async {
  final argb = accent.seed.toARGB32();
  if (_published == argb) return;
  _published = argb;
  try {
    await (await SharedPreferences.getInstance()).setInt(AppearanceController.notifyColorKey, argb);
  } catch (_) {
    // Tests: no backend.
  }
}
