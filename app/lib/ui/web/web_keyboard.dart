import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The keyboard height a page is laid out for.
///
/// Flutter reports the keyboard's height on every frame of its slide. Laying
/// a web page out again on each of them (and, for a WebView that shrinks,
/// resizing the platform view and its texture) is what made opening and
/// closing the keyboard stutter. The page moves once per slide instead, as in
/// a browser: right away when the slide's end is known — a keyboard opening
/// to the height it had last time in a window this wide, or one closing —
/// else once the reports stop ([settle], [rest] after the last one). The
/// heights outlive the app's process ([restore]), so a cold start's first
/// keyboard is known up front too.
///
/// Shared by [WebViewPage] and the thin [LocalHostShell] Host WebView — one
/// algorithm, no parallel debounce hacks.
class WebKeyboard {
  /// Quiet time after which the keyboard counts as at rest.
  static const rest = Duration(milliseconds: 100);

  /// The last height an open keyboard came to rest at, per window width
  /// (shared by every page: it is the phone's keyboard).
  static final _open = <int, double>{};

  /// Where [_open] is kept between runs.
  static const prefsKey = 'web.keyboard';

  static Future<void>? _restored;

  /// Reads the heights of earlier runs, once per run; heights seen since win.
  static Future<void> restore() => _restored ??= () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final json = jsonDecode(prefs.getString(prefsKey) ?? '{}');
          if (json is! Map) return;
          for (final MapEntry(:key, :value) in json.entries) {
            final width = int.tryParse('$key');
            if (width != null && value is num && value > 0) {
              _open.putIfAbsent(width, value.toDouble);
            }
          }
        } catch (_) {
          // No storage (tests, a broken store): learnt again this run.
        }
      }();

  static Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefsKey,
        jsonEncode({for (final e in _open.entries) '${e.key}': e.value}),
      );
    } catch (_) {}
  }

  /// Forgets every height; with [restore], the next [restore] reads the
  /// stored ones again.
  @visibleForTesting
  static void forgetHeights({bool restore = false}) {
    _open.clear();
    _restored = restore ? null : Future<void>.value();
  }

  /// What the page is laid out for.
  double get height => _height;
  double _height = 0;

  /// The height last seen at rest.
  double _rest = 0;

  /// The keyboard reports [raw] in a window [width] wide. True when [height]
  /// changed.
  bool report(double raw, double width) {
    final before = _height;
    if (raw == _rest) {
      _height = raw;
    } else if (raw > _rest) {
      // Opening (or growing): where it ends is known from last time.
      final known = _rest == 0 ? _open[width.round()] : null;
      if (known != null) _height = known;
    } else {
      // Closing: the page goes back down at once, under the keyboard.
      _height = 0;
    }
    return _height != before;
  }

  /// The reports stopped at [raw]. True when [height] changed.
  ///
  /// Closing already snapped [_height] to 0 in [report]. A mid-close quiet
  /// period must not resurrect a partial IME height (that parked the Host
  /// composer mid-screen after the model picker stole focus).
  ///
  /// Only treat as mid-close when we already had a rest height ([_rest] > 0)
  /// and [raw] is still below it. A cold first open has [_rest] == 0 — that
  /// must settle normally. The old `raw < infinity` fallback swallowed every
  /// first open and left `#root` / chrome laid out as if the keyboard were
  /// closed (composer under the IME).
  bool settle(double raw, double width) {
    final before = _height;
    if (_height == 0 && _rest > 0 && raw > 0 && raw < _rest) {
      // Mid-close noise after we already floored the layout — stay closed.
      return false;
    }
    _rest = _height = raw;
    if (raw > 0 && _open[width.round()] != raw) {
      _open[width.round()] = raw;
      unawaited(_save());
    }
    return _height != before;
  }
}
