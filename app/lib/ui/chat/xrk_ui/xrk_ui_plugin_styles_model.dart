// Bounded view-v2 styles. The interpreter owns both opaque backgrounds and
// text colours, so contrast diagnostics describe the colours actually drawn.
part of 'xrk_ui_model.dart';

/// Colour values are opaque 24-bit sRGB. Alpha is never author controlled.
final class XrkUiColorPair {
  const XrkUiColorPair(this.light, this.dark);

  final int light;
  final int dark;
  int at(bool darkMode) => darkMode ? dark : light;
}

abstract final class XrkUiPluginPalette {
  // The existing card palette's neutral anchors. V2 paints these explicitly;
  // it does not estimate the colour underneath a translucent parent card.
  static const surface = XrkUiColorPair(0xF8FAFE, 0x272A33);
  static const elevated = XrkUiColorPair(0xF0F3F9, 0x30343F);
  static const ink = XrkUiColorPair(0x20242B, 0xF1F4F9);
  static const muted = XrkUiColorPair(0x586372, 0xB5BDCA);
  static const defaultAccent = 0x3D6FD6;
  // Original category palette, corrected only when a v2 background is used.
  static const chart = [
    XrkUiColorPair(0x3D6FD6, 0x5B8EE6),
    XrkUiColorPair(0xDC6530, 0xD9692F),
    XrkUiColorPair(0x169470, 0x1F9E76),
    XrkUiColorPair(0xB88000, 0xB88510),
    XrkUiColorPair(0xD0628F, 0xD6649A),
    XrkUiColorPair(0x6B58D0, 0x8A7DE0),
  ];
  static const chartOther = XrkUiColorPair(0x9AA0AA, 0x6B707A);
  static const named = <String, int>{
    'red': 0xD04545,
    'orange': 0xCA6328,
    'amber': 0xAA7900,
    'green': 0x258051,
    'teal': 0x167F84,
    'blue': 0x3D6FD6,
    'indigo': 0x5B5CC7,
    'violet': 0x8554BB,
    'pink': 0xB94F83,
    'gray': 0x697382,
  };
}

/// The person's accent (设置 › 主题) for a view that asks for `accent: "app"`
/// (docs/design/plugin-ui-v3.md §4.3): the light seed of the palette; the
/// dark side is derived like any requested colour, by the contrast search.
/// The app sets it whenever the palette changes; the plugin-view parse cache
/// starts over when [revision] moves. The default is 雾蓝, the app's default.
abstract final class XrkUiAppAccent {
  static const fallback = 0x4B67B4;
  static int _rgb = fallback;
  static int _revision = 0;

  static int get rgb => _rgb;
  static int get revision => _revision;

  static void set(int rgb) {
    final value = rgb & 0xFFFFFF;
    if (value == _rgb) return;
    _rgb = value;
    _revision++;
  }
}

/// WCAG 2.2 relative luminance and ratio, without rounding the threshold.
double xrkUiContrast(int foreground, int background) {
  double luminance(int rgb) {
    double channel(int shift) {
      final c = ((rgb >> shift) & 255) / 255;
      return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0);
  }

  final a = luminance(foreground);
  final b = luminance(background);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

int _mixPluginColor(int from, int to, double amount) {
  int channel(int shift) => (((from >> shift) & 255) * (1 - amount) + ((to >> shift) & 255) * amount).round();
  return (channel(16) << 16) | (channel(8) << 8) | channel(0);
}

/// Search only two bounded, monotone sRGB segments. Every returned candidate
/// was tested after 8-bit quantisation; 4.499 never counts as 4.5.
int xrkUiReadableColor(int requested, int background, {double minimum = 4.5}) {
  if (xrkUiContrast(requested, background) >= minimum) return requested;
  var best = requested;
  var bestDistance = 2.0;
  for (final target in const [0x000000, 0xFFFFFF]) {
    if (xrkUiContrast(target, background) < minimum) continue;
    var low = 0.0;
    var high = 1.0;
    var passing = target;
    for (var step = 0; step < 16; step++) {
      final middle = (low + high) / 2;
      final candidate = _mixPluginColor(requested, target, middle);
      if (xrkUiContrast(candidate, background) >= minimum) {
        high = middle;
        passing = candidate;
      } else {
        low = middle;
      }
    }
    if (high < bestDistance) {
      bestDistance = high;
      best = passing;
    }
  }
  return best;
}

enum XrkUiTextSize {
  display(28),
  title(24),
  subtitle(20),
  body(16),
  caption(13),
  mono(14);

  const XrkUiTextSize(this.pixels);
  final double pixels;
}

enum XrkUiTextWeight {
  regular(400),
  medium(500),
  semibold(600),
  bold(700);

  const XrkUiTextWeight(this.value);
  final int value;
}

enum XrkUiStyleAlign { start, center, end }

enum XrkUiCardStyle { plain, surface, tinted, outlined }

final class XrkUiRichSpan {
  const XrkUiRichSpan({
    required this.text,
    required this.color,
    required this.weight,
    this.mono = false,
    this.background,
  });
  final String text;
  final XrkUiColorPair color;
  final XrkUiTextWeight weight;
  final bool mono;
  final XrkUiColorPair? background;
}

final class XrkUiPluginStyle {
  const XrkUiPluginStyle({
    required this.foreground,
    required this.background,
    required this.accent,
    required this.muted,
    this.size = XrkUiTextSize.body,
    this.weight = XrkUiTextWeight.regular,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.align = XrkUiStyleAlign.start,
    this.maxLines,
    this.card = XrkUiCardStyle.plain,
    this.padding = 0,
    this.gap = 12,
    this.columns = const [],
    this.dividers = false,
    this.spans = const [],
    this.chartColors = const [],
    this.chartOther,
  });

  final XrkUiColorPair foreground;
  final XrkUiColorPair background;
  final XrkUiColorPair accent;
  final XrkUiColorPair muted;
  final XrkUiTextSize size;
  final XrkUiTextWeight weight;
  final bool italic;
  final bool underline;
  final bool strike;
  final XrkUiStyleAlign align;
  final int? maxLines;
  final XrkUiCardStyle card;
  final double padding;
  final double gap;
  final List<int> columns;
  final bool dividers;
  final List<XrkUiRichSpan> spans;
  final List<XrkUiColorPair> chartColors;
  final XrkUiColorPair? chartOther;

  // Colours survive both enlargement and reduction of the system text size.
  // The stronger 4.5 floor also exceeds WCAG's 3.0 floor for large text.
  double get minimumContrast => _pluginMinimumContrast(size, weight);
}

double _pluginMinimumContrast(XrkUiTextSize size, XrkUiTextWeight weight) => 4.5;

const _pluginReservedStyleKeys = {
  'position',
  'left',
  'right',
  'top',
  'bottom',
  'width',
  'height',
  'radius',
  'borderRadius',
  'elevation',
  'shadow',
  'fontFamily',
  'fontSize',
  'lineHeight',
  'opacity',
  'gradient',
  'transform',
  'zIndex',
};
const _pluginReservedRoles = {'system', 'approval', 'authorization', 'dialog', 'permission'};

void _initPluginStyles(Map<String, Object?> raw, _Ctx ctx) {
  final version = raw['v'];
  ctx.version = version == 2 ? 2 : 1;
  if (version != null && version != 1 && version != 2) {
    ctx.note('view.v', appL10n.plugViewVersionFallback(_show(version)));
  }
  if (ctx.version == 1) return;
  ctx.accent = raw['accent'] == 'app'
      ? XrkUiAppAccent.rgb
      : _pluginColor(raw['accent'], 'view.accent', ctx, allowAccent: false) ?? XrkUiPluginPalette.defaultAccent;
}

String _pluginHex(int rgb) => '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

int? _pluginColor(Object? value, String path, _Ctx ctx, {bool allowAccent = true}) {
  if (value == null || value is XrkUiMissing) return null;
  if (value is String) {
    if (value.length > 16) {
      ctx.note(path, appL10n.plugViewStyleInvalid('red … gray / #RRGGBB${allowAccent ? ' / accent' : ''}'));
      return null;
    }
    if (allowAccent && value == 'accent') return ctx.accent;
    if (XrkUiPluginPalette.named[value] case final rgb?) return rgb;
    if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) return int.parse(value.substring(1), radix: 16);
  }
  ctx.note(path, appL10n.plugViewStyleInvalid('red … gray / #RRGGBB${allowAccent ? ' / accent' : ''}'));
  return null;
}

XrkUiColorPair _pluginReadablePair(
  XrkUiColorPair requested,
  XrkUiColorPair background,
  double minimum,
  String path,
  _Ctx ctx, {
  bool once = false,
}) {
  int resolve(int value, int base, String mode) {
    final corrected = xrkUiReadableColor(value, base, minimum: minimum);
    if (corrected != value && (!once || ctx.contrastNotes.add('$path:$value:$base:$minimum:$mode'))) {
      ctx.note(
        path,
        appL10n.plugViewContrastAdjusted(mode, _pluginHex(value), _pluginHex(corrected), formatXrkUiValue(minimum)),
      );
    }
    return corrected;
  }

  return XrkUiColorPair(
    resolve(requested.light, background.light, 'light'),
    resolve(requested.dark, background.dark, 'dark'),
  );
}

T _pluginStyleEnum<T extends Enum>(Object? raw, List<T> values, T fallback, String path, _Ctx ctx) {
  if (raw == null || raw is XrkUiMissing) return fallback;
  for (final value in values) {
    if (value.name == raw) return value;
  }
  ctx.note(path, appL10n.plugViewStyleInvalid(values.map((e) => e.name).join(' / ')));
  return fallback;
}

bool _pluginStyleFlag(Map raw, String key, String path, _Ctx ctx) {
  final value = raw[key];
  if (value == null || value is XrkUiMissing) return false;
  if (value is bool) return value;
  ctx.note('$path.$key', appL10n.plugViewStyleInvalid('true / false'));
  return false;
}

double _pluginSpacing(Object? value, double fallback, String path, _Ctx ctx) {
  if (value == null || value is XrkUiMissing) return fallback;
  final spacing = switch (value) {
    'S' => 8.0,
    'M' => 12.0,
    'L' => 16.0,
    _ => null,
  };
  if (spacing != null) return spacing;
  ctx.note(path, appL10n.plugViewStyleInvalid('S / M / L'));
  return fallback;
}

XrkUiColorPair _pluginTint(int rgb) => XrkUiColorPair(
  _mixPluginColor(XrkUiPluginPalette.surface.light, rgb, 0.10),
  _mixPluginColor(XrkUiPluginPalette.surface.dark, rgb, 0.16),
);

XrkUiPluginStyle _readPluginStyle(Map<String, Object?> raw, String path, _Ctx ctx) {
  final styleAt = '$path.style';
  final rawStyle = raw['style'];
  final style = rawStyle is Map ? rawStyle : const {};
  if (rawStyle != null && rawStyle is! XrkUiMissing && rawStyle is! Map) {
    ctx.note(styleAt, appL10n.plugViewStyleInvalid('{…}'));
  }
  for (final key in _pluginReservedStyleKeys) {
    if (style.containsKey(key)) ctx.note('$styleAt.$key', appL10n.plugViewStyleReserved);
  }
  const known = {
    'size',
    'weight',
    'italic',
    'underline',
    'strike',
    'align',
    'maxLines',
    'color',
    'card',
    'padding',
    'gap',
    'columns',
    'dividers',
    'background',
  };
  for (final key in style.keys.take(32)) {
    if (!known.contains(key) && !_pluginReservedStyleKeys.contains(key)) {
      ctx.note('$styleAt.$key', appL10n.plugViewStyleReserved);
    }
  }
  if (style.length > 32) ctx.note(styleAt, appL10n.plugViewStyleReserved);
  final type = raw['type'];
  final layout = type == 'stack' || type == 'row';
  final textNode = type == 'text' || type == 'metric' || type == 'callout';
  final defaults = type == 'metric' ? XrkUiTextSize.title : XrkUiTextSize.body;
  final size = _pluginStyleEnum(style['size'], XrkUiTextSize.values, defaults, '$styleAt.size', ctx);
  final weight = _pluginStyleEnum(
    style['weight'],
    XrkUiTextWeight.values,
    type == 'metric' ? XrkUiTextWeight.semibold : XrkUiTextWeight.regular,
    '$styleAt.weight',
    ctx,
  );
  var card = _pluginStyleEnum(style['card'], XrkUiCardStyle.values, XrkUiCardStyle.plain, '$styleAt.card', ctx);
  if (!layout && card != XrkUiCardStyle.plain) {
    ctx.note('$styleAt.card', appL10n.plugViewStyleContainerOnly);
    card = XrkUiCardStyle.plain;
  }
  final tint = _pluginColor(style['background'], '$styleAt.background', ctx);
  if (!layout && tint != null) ctx.note('$styleAt.background', appL10n.plugViewStyleContainerOnly);
  final background = layout
      ? tint != null
            ? _pluginTint(tint)
            : switch (card) {
                XrkUiCardStyle.surface => XrkUiPluginPalette.elevated,
                XrkUiCardStyle.tinted => _pluginTint(tint ?? ctx.accent),
                _ => ctx.styleBackground,
              }
      : ctx.styleBackground;
  final chosen = _pluginColor(style['color'], '$styleAt.color', ctx);
  final tone = switch (raw['tone']) {
    'good' || 'success' || 'positive' => XrkUiPluginPalette.named['green'],
    'warn' || 'warning' || 'caution' => XrkUiPluginPalette.named['amber'],
    'bad' || 'danger' || 'error' || 'negative' => XrkUiPluginPalette.named['red'],
    'info' || 'note' => XrkUiPluginPalette.named['blue'],
    _ => null,
  };
  final selected = chosen ?? tone;
  final requested = selected != null
      ? XrkUiColorPair(selected, selected)
      : raw['tone'] == 'muted' || raw['tone'] == 'secondary'
      ? XrkUiPluginPalette.muted
      : XrkUiPluginPalette.ink;
  final minimum = _pluginMinimumContrast(size, weight);
  final foreground = _pluginReadablePair(requested, background, minimum, '$styleAt.color', ctx);
  final accent = _pluginReadablePair(
    XrkUiColorPair(ctx.accent, ctx.accent),
    background,
    4.5,
    'view.accent',
    ctx,
    once: true,
  );
  final muted = _pluginReadablePair(XrkUiPluginPalette.muted, background, 4.5, '$styleAt.muted', ctx);
  int? maxLines;
  final lines = style['maxLines'];
  if (lines is int && lines >= 1 && lines <= 20) {
    maxLines = lines;
  } else if (lines != null && lines is! XrkUiMissing) {
    ctx.note('$styleAt.maxLines', appL10n.plugViewStyleInvalid('1–20'));
  }
  final columns = <int>[];
  final rawColumns = style['columns'];
  if (rawColumns is List &&
      rawColumns.isNotEmpty &&
      rawColumns.length <= 8 &&
      rawColumns.every((e) => e is int && e >= 1 && e <= 12)) {
    columns.addAll(rawColumns.cast<int>());
  } else if (rawColumns != null && rawColumns is! XrkUiMissing && rawColumns != 'equal') {
    ctx.note('$styleAt.columns', appL10n.plugViewStyleInvalid('equal / [1…12] × 1…8'));
  }
  if (!layout && const ['padding', 'gap', 'columns', 'dividers'].any(style.containsKey)) {
    ctx.note(styleAt, appL10n.plugViewStyleContainerOnly);
  }
  if (!textNode &&
      const ['size', 'weight', 'italic', 'underline', 'strike', 'maxLines', 'color'].any(style.containsKey)) {
    ctx.note(styleAt, appL10n.plugViewStyleTextOnly);
  }
  final spans = <XrkUiRichSpan>[];
  final rawSpans = raw['spans'];
  if (type == 'text' && rawSpans != null && rawSpans is! XrkUiMissing) {
    if (rawSpans is! List) {
      ctx.note('$path.spans', appL10n.plugViewStyleInvalid('[{text, …}]'));
    } else {
      var characters = 0;
      final totalLimit = ctx.p == XrkUiProfile.panel
          ? 256
          : ctx.p == XrkUiProfile.toolCard
          ? 64
          : 16;
      for (var i = 0; i < rawSpans.length; i++) {
        if (i >= 32 || ctx.richSpans >= totalLimit || characters >= ctx.p.text) {
          ctx.note('$path.spans', appL10n.plugViewRichLimit);
          break;
        }
        final span = rawSpans[i];
        final at = '$path.spans[$i]';
        if (span is! Map || _string(span['text']) == null) {
          ctx.note(at, appL10n.plugViewStyleInvalid('{text, …}'));
          continue;
        }
        for (final key in const ['link', 'url', 'href', 'action']) {
          if (span.containsKey(key)) ctx.note('$at.$key', appL10n.plugViewStyleReserved);
        }
        final original = _string(span['text'])!;
        final room = ctx.p.text - characters;
        final text = original.length <= room ? original : '${original.substring(0, room)}…';
        if (original.length > room) ctx.note('$path.spans', appL10n.plugViewRichLimit);
        characters += math.min(original.length, room);
        final spanWeight = _pluginStyleEnum(span['weight'], XrkUiTextWeight.values, weight, '$at.weight', ctx);
        final spanColor = _pluginColor(span['color'], '$at.color', ctx);
        final spanBackground = _pluginColor(span['background'], '$at.background', ctx);
        final highlight = spanBackground == null ? null : _pluginTint(spanBackground);
        final spanForeground = _pluginReadablePair(
          spanColor == null ? requested : XrkUiColorPair(spanColor, spanColor),
          highlight ?? background,
          _pluginMinimumContrast(size, spanWeight),
          '$at.color',
          ctx,
        );
        spans.add(
          XrkUiRichSpan(
            text: text,
            color: spanForeground,
            weight: spanWeight,
            mono: _pluginStyleFlag(span, 'mono', at, ctx),
            background: highlight,
          ),
        );
        ctx.richSpans++;
      }
    }
  }
  final chartColors = <XrkUiColorPair>[];
  XrkUiColorPair? chartOther;
  if (type == 'chart' || type == 'progress') {
    for (var i = 0; i < XrkUiPluginPalette.chart.length; i++) {
      chartColors.add(_pluginReadablePair(XrkUiPluginPalette.chart[i], background, 3, '$path.palette[$i]', ctx));
    }
    chartOther = _pluginReadablePair(XrkUiPluginPalette.chartOther, background, 3, '$path.palette.other', ctx);
  }
  return XrkUiPluginStyle(
    foreground: foreground,
    background: background,
    accent: accent,
    muted: muted,
    size: size,
    weight: weight,
    italic: _pluginStyleFlag(style, 'italic', styleAt, ctx),
    underline: _pluginStyleFlag(style, 'underline', styleAt, ctx),
    strike: _pluginStyleFlag(style, 'strike', styleAt, ctx),
    align: _pluginStyleEnum(style['align'], XrkUiStyleAlign.values, XrkUiStyleAlign.start, '$styleAt.align', ctx),
    maxLines: maxLines,
    card: card,
    padding: layout
        ? _pluginSpacing(style['padding'], card == XrkUiCardStyle.plain ? 0 : 12, '$styleAt.padding', ctx)
        : 0,
    gap: layout ? _pluginSpacing(style['gap'], path == 'view' ? 16 : 12, '$styleAt.gap', ctx) : 12,
    columns: List.unmodifiable(columns),
    dividers: layout && _pluginStyleFlag(style, 'dividers', styleAt, ctx),
    spans: List.unmodifiable(spans),
    chartColors: List.unmodifiable(chartColors),
    chartOther: chartOther,
  );
}
