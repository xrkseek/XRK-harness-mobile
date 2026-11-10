// View v2 inputs and structured content. This is data, never executable code.
part of 'xrk_ui_model.dart';

const xrkUiPluginInputTypes = [
  'textField',
  'number',
  'stepper',
  'toggle',
  'slider',
  'select',
  'segmented',
  'chips',
  'date',
  'time',
  'rating',
];
const _pluginControlTypes = [
  ...xrkUiPluginInputTypes,
  'form',
  'tabs',
  'collapsible',
  'accordion',
  'carousel',
  'timeline',
  'grid',
  'badge',
  'tag',
  'avatar',
  'codeBlock',
  'divider',
  'spacer',
  'emptyState',
  'gallery',
];

abstract final class XrkUiControlLimits {
  static const fields = 32;
  static const options = 24;
  static const sections = 8;
  static const timeline = 24;
  static const textLength = 2000;
  static const textLines = 8;
  static const columns = 4;
  static const codeLength = 8000;
  static const valueBytes = 4096;

  /// `gallery`: pictures in a panel / in a tool card.
  static const gallery = 24;
  static const galleryCard = 8;

  /// `metric.trend`: points.
  static const trendPoints = 30;
  static const patterns = ['email', 'integer', 'decimal', 'alphanumeric', 'slug'];
}

/// Writable paths are deliberately narrower than read bindings. No array
/// allocation, empty segments, prototype names or access to another model.
List<String>? xrkUiInputPath(Object? raw) {
  if (raw is! String || raw.length > 256 || !raw.startsWith('data.')) {
    return null;
  }
  final parts = raw.substring(5).split('.');
  if (parts.isEmpty || parts.length > xrkUiBindingSegments) return null;
  final key = RegExp(r'^[A-Za-z_][A-Za-z0-9_-]{0,63}$');
  if (parts.any((p) => !key.hasMatch(p) || const ['__proto__', 'prototype', 'constructor'].contains(p))) {
    return null;
  }
  return List.unmodifiable(parts);
}

/// Adds a value read for each writable binding before the ordinary resolver.
/// Only template nodes are walked; bound data is never interpreted as a view.
Object? xrkUiInputBindings(Object? value, {int depth = 0}) {
  if (depth > XrkUiProfile.jsonNesting) return xrkUiMissing;
  if (value is List) {
    return [for (final item in value) xrkUiInputBindings(item, depth: depth + 1)];
  }
  if (value is! Map || xrkUiBindingPath(value) != null) return value;
  final out = <String, Object?>{
    for (final entry in value.entries) '${entry.key}': xrkUiInputBindings(entry.value, depth: depth + 1),
  };
  if (xrkUiPluginInputTypes.contains(out['type']) && xrkUiInputPath(out['bind']) != null) {
    out['value'] = <String, Object?>{r'$': out['bind']};
  }
  return out;
}

final class XrkUiInputChoice {
  const XrkUiInputChoice(this.label, this.value);
  final String label;
  final String value;
}

/// One input. The local controller owns drafts; [value] is the current model
/// value after bindings, with a safe fallback if the host has not sent it yet.
final class XrkUiInput extends XrkUiNode {
  const XrkUiInput({
    required super.path,
    required this.kind,
    required this.label,
    required this.bind,
    required this.value,
    this.readOnly = false,
    this.placeholder,
    this.maxLength = 256,
    this.minLength = 0,
    this.lines = 1,
    this.required = false,
    this.min = 0,
    this.max = 100,
    this.step = 1,
    this.range = false,
    this.multi = false,
    this.options = const [],
    this.pattern,
    this.onChange,
    this.minDate,
    this.maxDate,
    super.truncation,
  });
  final String kind;
  final String label;
  final String? bind;
  final Object? value;
  final bool readOnly;
  final String? placeholder;
  final int maxLength;
  final int minLength;
  final int lines;
  final bool required;
  final double min;
  final double max;
  final double step;
  final bool range;
  final bool multi;
  final List<XrkUiInputChoice> options;
  final String? pattern;
  final XrkUiAction? onChange;
  final DateTime? minDate;
  final DateTime? maxDate;

  bool get numeric => const ['number', 'stepper', 'slider', 'rating'].contains(kind);

  String? validate(Object? current) {
    final empty =
        current == null ||
        current is XrkUiMissing ||
        (current is String && current.trim().isEmpty) ||
        (current is List && current.isEmpty);
    if (empty) return required ? appL10n.plugInputRequired : null;
    if (kind == 'textField' && current is! String) {
      return appL10n.plugInputInvalidValue;
    }
    if (kind == 'chips' && multi && current is! List) {
      return appL10n.plugInputInvalidValue;
    }
    if (numeric) {
      final numbers = range && current is List ? current : [current];
      if (range && (numbers.length != 2 || current is! List)) {
        return appL10n.plugInputInvalidValue;
      }
      final values = <double>[];
      for (final item in numbers) {
        final n = item is num
            ? item.toDouble()
            : item is String
            ? double.tryParse(item)
            : null;
        if (n == null || !n.isFinite) return appL10n.plugInputNumber;
        if (kind == 'rating' && n != n.truncateToDouble()) return appL10n.plugInputInvalidValue;
        if (n < min || n > max) {
          return appL10n.plugInputBounds(formatXrkUiNumber(min), formatXrkUiNumber(max));
        }
        values.add(n);
      }
      if (range && values[0] > values[1]) return appL10n.plugInputInvalidValue;
    }
    if (current is String) {
      final length = current.runes.length;
      if (length < minLength || length > maxLength) {
        return appL10n.plugInputLength(minLength, maxLength);
      }
      if (pattern != null && !xrkUiInputMatches(pattern!, current)) {
        return appL10n.plugInputPattern;
      }
    }
    if (const ['select', 'segmented', 'chips'].contains(kind)) {
      final selected = multi && current is List ? current : [current];
      if (selected.any((v) => !options.any((o) => o.value == v))) {
        return appL10n.plugInputInvalidValue;
      }
    }
    if (kind == 'toggle' && current is! bool) {
      return appL10n.plugInputInvalidValue;
    }
    if (kind == 'date') {
      final date = xrkUiInputDate(current);
      if (date == null || (minDate != null && date.isBefore(minDate!)) || (maxDate != null && date.isAfter(maxDate!))) {
        return appL10n.plugInputDate;
      }
    }
    if (kind == 'time' && xrkUiInputTime(current) == null) {
      return appL10n.plugInputTime;
    }
    return null;
  }

  Object? submitted(Object? current) {
    if (numeric && current is String) {
      return current.trim().isEmpty ? null : double.tryParse(current);
    }
    return current;
  }
}

DateTime? xrkUiInputDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return null;
  }
  final y = int.parse(value.substring(0, 4));
  final m = int.parse(value.substring(5, 7));
  final d = int.parse(value.substring(8));
  if (y < 1900 || y > 2100) return null;
  final parsed = DateTime(y, m, d);
  return parsed.year == y && parsed.month == m && parsed.day == d ? parsed : null;
}

(int, int)? xrkUiInputTime(Object? value) {
  if (value is! String || !RegExp(r'^\d{2}:\d{2}$').hasMatch(value)) {
    return null;
  }
  final h = int.parse(value.substring(0, 2));
  final m = int.parse(value.substring(3));
  return h < 24 && m < 60 ? (h, m) : null;
}

/// Named, bounded patterns only: plugins cannot provide a regular expression.
bool xrkUiInputMatches(String pattern, String text) {
  if (text.length > XrkUiControlLimits.textLength * 2) return false;
  return switch (pattern) {
    'email' => RegExp(r'^[^\s@]+@[^\s@.]+(?:\.[^\s@.]+)+$').hasMatch(text),
    'integer' => RegExp(r'^[+-]?[0-9]+$').hasMatch(text),
    'decimal' => RegExp(r'^[+-]?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)$').hasMatch(text),
    'alphanumeric' => RegExp(r'^[A-Za-z0-9]+$').hasMatch(text),
    'slug' => RegExp(r'^[a-z0-9]+(?:-[a-z0-9]+)*$').hasMatch(text),
    _ => false,
  };
}

final class XrkUiControlSection {
  const XrkUiControlSection(this.label, this.children);
  final String label;
  final List<XrkUiNode> children;
}

final class XrkUiControlContainer extends XrkUiNode {
  const XrkUiControlContainer({
    required super.path,
    required this.kind,
    required this.sections,
    this.label,
    this.submit,
    this.submitLabel,
    this.columns = 2,
    this.expanded = false,
    super.truncation,
  });
  final String kind;
  final List<XrkUiControlSection> sections;
  final String? label;
  final XrkUiAction? submit;
  final String? submitLabel;
  final int columns;
  final bool expanded;
  Iterable<XrkUiNode> get children => sections.expand((s) => s.children);

  Iterable<XrkUiInput> get inputs sync* {
    Iterable<XrkUiInput> walk(XrkUiNode node) sync* {
      if (node is XrkUiInput) yield node;
      final Iterable<XrkUiNode> nested = switch (node) {
        XrkUiLayout(:final children) => children,
        XrkUiControlContainer(:final children) => children,
        _ => const [],
      };
      for (final child in nested) {
        yield* walk(child);
      }
    }

    for (final child in children) {
      yield* walk(child);
    }
  }
}

/// `emptyState` (v2): an icon, a title, one line, at most one button.
final class XrkUiEmptyState extends XrkUiNode {
  const XrkUiEmptyState({required super.path, required this.title, this.icon, this.message, this.actions});

  final String title;

  /// A plugin icon name; null draws the generic glyph.
  final String? icon;
  final String? message;

  /// The one button, as a one-item `actions` (it hides like one when the
  /// view can't be tapped).
  final XrkUiActions? actions;
}

/// One picture of a `gallery`.
final class XrkUiGalleryItem {
  const XrkUiGalleryItem({required this.image, this.caption, this.action});

  /// Source and alt text, checked like an `image`.
  final XrkUiImage image;
  final String? caption;

  /// A tap goes to the plugin; without one it opens the viewer.
  final XrkUiAction? action;
}

/// `gallery` (v2): equal cells in 2–4 columns; a tap opens the app's viewer
/// for the whole set (or invokes the cell's action).
final class XrkUiGallery extends XrkUiNode {
  const XrkUiGallery({required super.path, required this.items, this.columns, this.aspect = 1, super.truncation});

  final List<XrkUiGalleryItem> items;

  /// Asked for (2–4); null lets the width decide.
  final int? columns;

  /// Width / height of every cell (0.5–2).
  final double aspect;
}

XrkUiNode _emptyState(Map<String, Object?> raw, String path, _Ctx ctx) {
  final title = _string(raw['title'])?.trim();
  if (title == null || title.isEmpty) {
    return ctx.broken('$path.title', appL10n.viewUiExpectedString, type: 'emptyState');
  }
  if (title.length > 40) ctx.note('$path.title', appL10n.viewUiTextLimit(title.length, 40));
  final rawMessage = _string(raw['message'])?.trim();
  if (rawMessage != null && rawMessage.length > 120) {
    ctx.note('$path.message', appL10n.viewUiTextLimit(rawMessage.length, 120));
  }
  XrkUiActions? actions;
  final rawAction = raw['action'];
  if (rawAction is Map<String, Object?>) {
    final label = _string(rawAction['label'])?.trim();
    final action = _pluginAction(rawAction['action'], '$path.action.action', ctx);
    if (label == null || label.isEmpty) {
      ctx.note('$path.action.label', appL10n.viewUiSkippedItemLabel);
    } else if (action != null) {
      actions = XrkUiActions(
        path: '$path.action',
        items: [
          XrkUiButton(
            label: _clip(label, 12)!,
            action: action,
            icon: _icon(rawAction['icon'], '$path.action.icon', ctx),
          ),
        ],
      );
    } else if (rawAction['action'] == null) {
      ctx.note('$path.action.action', appL10n.plugViewBadAction('{id, args?}'));
    }
  } else if (rawAction != null && rawAction is! XrkUiMissing) {
    ctx.note('$path.action', appL10n.plugViewBadAction('{label, action}'));
  }
  return XrkUiEmptyState(
    path: path,
    title: _clip(title, 40)!,
    icon: _icon(raw['icon'], '$path.icon', ctx),
    message: rawMessage == null || rawMessage.isEmpty ? null : _clip(rawMessage, 120),
    actions: actions,
  );
}

XrkUiNode _gallery(Map<String, Object?> raw, String path, _Ctx ctx) {
  const shape = '{src, alt?, caption?, action?}';
  final rawItems = raw['items'];
  if (_isEmpty(rawItems)) return XrkUiEmpty(path: path, type: 'gallery');
  if (rawItems is! List) {
    return ctx.broken('$path.items', appL10n.plugViewExpectedItems(shape), type: 'gallery');
  }
  final max = ctx.p == XrkUiProfile.toolCard ? XrkUiControlLimits.galleryCard : XrkUiControlLimits.gallery;
  final items = <XrkUiGalleryItem>[];
  String? truncation;
  for (var i = 0; i < rawItems.length; i++) {
    if (items.length >= max) {
      truncation = appL10n.viewUiHiddenItems(rawItems.length - i);
      ctx.note('$path.items', appL10n.viewUiItemLimit(rawItems.length, max));
      break;
    }
    final item = rawItems[i];
    final at = '$path.items[$i]';
    if (item is! Map<String, Object?>) {
      ctx.note(at, appL10n.plugViewSkippedItem(shape));
      continue;
    }
    final image = _image({'src': item['src'], 'alt': item['alt']}, at, ctx) as XrkUiImage;
    items.add(
      XrkUiGalleryItem(
        image: image,
        caption: _optionalText(item['caption'], 40),
        action: _pluginAction(item['action'], '$at.action', ctx),
      ),
    );
  }
  if (items.isEmpty) return ctx.broken('$path.items', appL10n.viewUiNoItems, type: 'gallery');
  final rawColumns = raw['columns'];
  int? columns;
  if (rawColumns is int && rawColumns >= 2 && rawColumns <= 4) {
    columns = rawColumns;
  } else if (rawColumns != null && rawColumns is! XrkUiMissing) {
    ctx.note('$path.columns', appL10n.plugViewStyleInvalid('2–4'));
  }
  final rawAspect = raw['aspect'];
  var aspect = 1.0;
  if (rawAspect is num && rawAspect.isFinite && rawAspect >= 0.5 && rawAspect <= 2) {
    aspect = rawAspect.toDouble();
  } else if (rawAspect != null && rawAspect is! XrkUiMissing) {
    ctx.note('$path.aspect', appL10n.plugViewStyleInvalid('0.5–2'));
  }
  return XrkUiGallery(
    path: path,
    items: List.unmodifiable(items),
    columns: columns,
    aspect: aspect,
    truncation: truncation,
  );
}

final class XrkUiControlDisplay extends XrkUiNode {
  const XrkUiControlDisplay({
    required super.path,
    required this.kind,
    this.text,
    this.language,
    this.image,
    this.tone,
    this.size = 'M',
    super.truncation,
  });
  final String kind;
  final String? text;
  final String? language;
  final XrkUiImage? image;
  final XrkUiTone? tone;
  final String size;
}

XrkUiNode? _pluginControlNode(String type, Map<String, Object?> raw, String path, int depth, _Ctx ctx) {
  if (!_pluginControlTypes.contains(type)) return null;
  if (ctx.version < 2 || ctx.p == XrkUiProfile.strip) {
    return ctx.broken('$path.type', appL10n.plugInputUnavailable, type: type);
  }
  if (xrkUiPluginInputTypes.contains(type)) {
    return _pluginInput(type, raw, path, ctx);
  }
  if (const ['form', 'tabs', 'collapsible', 'accordion', 'carousel', 'timeline', 'grid'].contains(type)) {
    return _pluginControlContainer(type, raw, path, depth, ctx);
  }
  if (type == 'avatar') {
    final image = _image(raw, path, ctx) as XrkUiImage;
    return XrkUiControlDisplay(
      path: path,
      kind: type,
      image: XrkUiImage(path: path, source: image.source, alt: image.alt, aspect: 1),
    );
  }
  if (type == 'emptyState') return _emptyState(raw, path, ctx);
  if (type == 'gallery') return _gallery(raw, path, ctx);
  if (type == 'divider' || type == 'spacer') {
    final size = raw['size'] ?? 'M';
    if (!const ['S', 'M', 'L'].contains(size)) {
      ctx.note('$path.size', appL10n.plugInputInvalidValue);
    }
    return XrkUiControlDisplay(
      path: path,
      kind: type,
      size: const ['S', 'M', 'L'].contains(size) ? size as String : 'M',
    );
  }
  final key = type == 'codeBlock' ? 'code' : 'text';
  final text = raw[key];
  if (text is! String) {
    return ctx.broken('$path.$key', appL10n.viewUiExpectedString, type: type);
  }
  final max = type == 'codeBlock' ? XrkUiControlLimits.codeLength : XrkUiLimits.label;
  final clipped = text.length > max;
  if (clipped) {
    ctx.note('$path.$key', appL10n.viewUiTextLimit(text.length, max));
  }
  return XrkUiControlDisplay(
    path: path,
    kind: type,
    text: _clip(text, max),
    language: type == 'codeBlock' ? _optionalText(raw['language'], 32) : null,
    tone: _pluginTone(raw['tone'], '$path.tone', ctx),
    truncation: clipped ? appL10n.viewUiTextTruncated : null,
  );
}

XrkUiNode _pluginInput(String kind, Map<String, Object?> raw, String path, _Ctx ctx) {
  if (++ctx.inputFields > XrkUiControlLimits.fields) {
    return ctx.broken(path, appL10n.viewUiItemLimit(ctx.inputFields, XrkUiControlLimits.fields), type: kind);
  }
  if (raw['obscureText'] == true ||
      raw['password'] == true ||
      raw['inputType'] == 'password' ||
      raw['keyboardType'] == 'password') {
    return ctx.broken(path, appL10n.plugInputNoPassword, type: kind);
  }
  final label = raw['label'];
  if (label is! String || label.trim().isEmpty) {
    return ctx.broken('$path.label', appL10n.viewUiExpectedString, type: kind);
  }
  final binding = raw['bind'];
  if (binding != null && xrkUiInputPath(binding) == null) {
    return ctx.broken('$path.bind', appL10n.plugInputBadBinding, type: kind);
  }
  final bind = binding as String?;
  if (bind != null && ctx.inputBindings.any((b) => b == bind || b.startsWith('$bind.') || bind.startsWith('$b.'))) {
    return ctx.broken('$path.bind', appL10n.plugInputDuplicateBinding, type: kind);
  }
  if (bind != null) ctx.inputBindings.add(bind);
  int bounded(String key, int fallback, int min, int max) {
    final n = raw[key];
    if (n == null) return fallback;
    if (n is int && n >= min && n <= max) return n;
    ctx.note('$path.$key', appL10n.plugInputInvalidValue);
    return n is num && n.isFinite ? n.toInt().clamp(min, max) : fallback;
  }

  final maxLength = bounded('maxLength', 256, 1, XrkUiControlLimits.textLength);
  final minLength = bounded('minLength', 0, 0, maxLength);
  final lines = bounded('maxLines', raw['multiline'] == true ? 4 : 1, 1, XrkUiControlLimits.textLines);
  double number(String key, double fallback) {
    final n = raw[key];
    if (n == null) return fallback;
    if (n is num && n.isFinite && n.abs() <= 1e12) return n.toDouble();
    ctx.note('$path.$key', appL10n.viewUiExpectedFinite);
    return fallback;
  }

  final numeric = const ['number', 'stepper', 'slider', 'rating'].contains(kind);
  var min = number('min', kind == 'number' || kind == 'stepper' ? -1e9 : 0);
  var max = number(
    'max',
    kind == 'number' || kind == 'stepper'
        ? 1e9
        : kind == 'rating'
        ? 5
        : 100,
  );
  if (kind == 'rating') {
    max = max.clamp(1, 10).floorToDouble();
    if (min != 0) ctx.note('$path.min', appL10n.plugInputInvalidValue);
    min = 0;
  }
  if (max <= min && numeric) {
    return ctx.broken('$path.max', appL10n.plugInputInvalidValue, type: kind);
  }
  final step = number('step', 1);
  if (numeric && step < 1e-9) {
    return ctx.broken('$path.step', appL10n.plugInputInvalidValue, type: kind);
  }
  if (kind == 'slider') {
    final divisions = (max - min) / step;
    if (divisions < 1 || divisions > 1000 || (divisions - divisions.roundToDouble()).abs() > 1e-7) {
      return ctx.broken('$path.step', appL10n.plugInputInvalidValue, type: kind);
    }
  }
  final choices = <XrkUiInputChoice>[];
  if (const ['select', 'segmented', 'chips'].contains(kind)) {
    final items = raw['options'];
    if (items is! List) {
      return ctx.broken('$path.options', appL10n.viewUiNoOptions, type: kind);
    }
    final seen = <String>{};
    for (final (i, item) in items.indexed) {
      if (i >= XrkUiControlLimits.options) {
        ctx.note('$path.options', appL10n.viewUiItemLimit(items.length, XrkUiControlLimits.options));
        break;
      }
      final label = item is String
          ? item
          : item is Map
          ? item['label']
          : null;
      final value = item is String
          ? item
          : item is Map
          ? item['value'] ?? label
          : null;
      if (label is! String ||
          label.isEmpty ||
          value is! String ||
          value.isEmpty ||
          value.length > 200 ||
          !seen.add(value)) {
        ctx.note('$path.options[$i]', appL10n.plugInputInvalidValue);
        continue;
      }
      choices.add(XrkUiInputChoice(_clip(label, 80)!, value));
    }
  }
  final rawPattern = raw['pattern'];
  if (rawPattern != null && !XrkUiControlLimits.patterns.contains(rawPattern)) {
    return ctx.broken('$path.pattern', appL10n.plugInputNamedPattern, type: kind);
  }
  final minDate = raw['minDate'] == null ? null : xrkUiInputDate(raw['minDate']);
  final maxDate = raw['maxDate'] == null ? null : xrkUiInputDate(raw['maxDate']);
  if ((raw['minDate'] != null && minDate == null) ||
      (raw['maxDate'] != null && maxDate == null) ||
      (minDate != null && maxDate != null && minDate.isAfter(maxDate))) {
    return ctx.broken(path, appL10n.plugInputDate, type: kind);
  }
  final multi = kind == 'chips' && raw['multi'] == true;
  final range = kind == 'slider' && raw['range'] == true;
  var value = raw['value'];
  if (value is XrkUiMissing || value == null) {
    value = kind == 'toggle'
        ? false
        : multi
        ? <String>[]
        : range
        ? [min, max]
        : numeric && kind != 'number'
        ? 0.clamp(min, max)
        : '';
  }
  if (value is String && value.length > XrkUiControlLimits.textLength * 2) {
    ctx.note('$path.value', appL10n.viewUiTextLimit(value.length, XrkUiControlLimits.textLength));
    value = String.fromCharCodes(value.runes.take(XrkUiControlLimits.textLength));
  }
  if (value is List) {
    value = List<Object?>.unmodifiable(value.take(range ? 3 : XrkUiControlLimits.options));
  }
  if (value is Map || (value is num && !value.isFinite)) {
    ctx.note('$path.value', appL10n.plugInputInvalidValue);
    value = null;
  }
  return XrkUiInput(
    path: path,
    kind: kind,
    label: _clip(label, 200)!,
    bind: bind,
    value: value,
    readOnly: raw['readOnly'] == true || bind == null || ctx.p != XrkUiProfile.panel,
    placeholder: _optionalText(raw['placeholder'], 200),
    maxLength: maxLength,
    minLength: minLength,
    lines: lines,
    required: raw['required'] == true,
    min: min,
    max: max,
    step: step,
    multi: multi,
    range: range,
    options: List.unmodifiable(choices),
    pattern: rawPattern as String?,
    onChange: _pluginAction(raw['onChange'], '$path.onChange', ctx),
    minDate: minDate,
    maxDate: maxDate,
  );
}

XrkUiNode _pluginControlContainer(String kind, Map<String, Object?> raw, String path, int depth, _Ctx ctx) {
  if (kind == 'form' && ctx.inForm) {
    return ctx.broken(path, appL10n.plugInputNestedForm, type: kind);
  }
  final wasInForm = ctx.inForm;
  if (kind == 'form') ctx.inForm = true;
  final sections = <XrkUiControlSection>[];
  String? truncation;
  List<XrkUiNode> children(Object? value, String at, int childDepth) {
    if (value is! List) {
      return [ctx.broken(at, appL10n.viewUiExpectedChildren(ctx.p.children))];
    }
    final out = <XrkUiNode>[];
    for (final (i, item) in value.indexed) {
      if (i >= ctx.p.children || ctx.nodes >= ctx.p.nodes) {
        truncation = appL10n.viewUiHiddenItems(value.length - i);
        ctx.note(at, appL10n.viewUiNodeLimit(ctx.p.nodes, value.length - i));
        break;
      }
      out.add(_node(item, '$at[$i]', childDepth, ctx));
    }
    return List.unmodifiable(out);
  }

  if (const ['tabs', 'accordion', 'carousel', 'timeline'].contains(kind)) {
    final items = raw['items'];
    if (items is! List) {
      ctx.inForm = wasInForm;
      return ctx.broken('$path.items', appL10n.viewUiNoItems, type: kind);
    }
    final max = kind == 'timeline' ? XrkUiControlLimits.timeline : XrkUiControlLimits.sections;
    for (final (i, item) in items.indexed) {
      if (i >= max || ctx.nodes >= ctx.p.nodes) {
        truncation = appL10n.viewUiHiddenItems(items.length - i);
        ctx.note('$path.items', appL10n.viewUiItemLimit(items.length, max));
        break;
      }
      if (item is! Map || item['label'] is! String || (item['label'] as String).isEmpty) {
        ctx.note('$path.items[$i].label', appL10n.viewUiExpectedString);
        continue;
      }
      // A section header is a visible component and counts against the budget.
      ctx.nodes++;
      sections.add(
        XrkUiControlSection(
          _clip(item['label'] as String, 200)!,
          children(item['children'] ?? const [], '$path.items[$i].children', depth + 1),
        ),
      );
    }
  } else {
    sections.add(XrkUiControlSection('', children(raw['children'], '$path.children', depth + 1)));
  }
  ctx.inForm = wasInForm;
  final submit = kind == 'form' ? _pluginAction(raw['submit'], '$path.submit', ctx) : null;
  if (kind == 'form' && submit == null) {
    return ctx.broken('$path.submit', appL10n.plugInputSubmitMissing, type: kind);
  }
  final columns = raw['columns'];
  if (columns != null && (columns is! int || columns < 1 || columns > XrkUiControlLimits.columns)) {
    ctx.note('$path.columns', appL10n.plugInputInvalidValue);
  }
  return XrkUiControlContainer(
    path: path,
    kind: kind,
    sections: List.unmodifiable(sections),
    label: _optionalText(raw['label'], 200),
    submit: submit,
    submitLabel: _optionalText(raw['submitLabel'], 80),
    columns: columns is int ? columns.clamp(1, XrkUiControlLimits.columns) : 2,
    expanded: raw['expanded'] == true,
    truncation: truncation,
  );
}
