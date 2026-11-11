// Portions derived from DS Bot (https://github.com/Fei2411/DeepSeek-Bot), Apache-2.0, Copyright 2026 Fei2411 and the DS Bot contributors. See THIRD_PARTY_NOTICES.md.
// Modified: `views.js` normalisation, checks and summary translated to Dart;
// lenient instead of strict (unknown properties ignored, a broken child becomes
// a placeholder, limits truncate); a smaller catalog plus `compare` and
// `steps`; phone-sized limits; Chinese messages.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../l10n/l10n.dart';
import '../../../plugins/native/native_icons.dart' show nativeIcon;
import 'xrk_ui_bind.dart';
import 'xrk_ui_dialect_genui.dart';
import 'xrk_ui_plugin_formula.dart';

part 'xrk_ui_plugin_model.dart';
part 'xrk_ui_plugin_styles_model.dart';
part 'xrk_ui_plugin_controls_model.dart';

/// 模型卡的上限。超了就截断并标注，只有源文本超过 [hardBytes] 才整块降级。
abstract final class XrkUiLimits {
  /// 给模型的说明里写的大小。超过它照样画，只是说明里不鼓励。
  static const softBytes = 4096;

  /// 超过这个字节数不解析，直接降级成代码块。
  static const hardBytes = 16384;
  static const nodes = 40;
  static const depth = 6;
  static const children = 16;
  static const series = 6;
  static const points = 60;
  static const compareItems = 4;
  static const compareRows = 8;
  static const options = 8;
  static const steps = 12;
  static const text = 2000;
  static const label = 200;
  static const title = 80;
}

/// 一处问题：在哪（`view.children[2].type`）+ 怎么了。给「让它重发」用，
/// 模型照着路径就能改。
final class XrkUiIssue {
  const XrkUiIssue(this.path, this.message);

  final String path;
  final String message;

  @override
  String toString() => appL10n.viewLabeledValue(path, message);

  @override
  bool operator ==(Object other) => other is XrkUiIssue && other.path == path && other.message == message;

  @override
  int get hashCode => Object.hash(path, message);
}

// ───────────────────────── 节点 ─────────────────────────

/// 视图里的一个组件。[path] 是它在 JSON 里的位置，[truncation] 是超限截断的
/// 说明（「已截断：只显示前 60 个点」），没截断时为 null。
sealed class XrkUiNode {
  const XrkUiNode({required this.path, this.truncation});

  final String path;
  final String? truncation;
}

/// `stack`（竖排）/ `row`（横排，窄屏自动换行）。
final class XrkUiLayout extends XrkUiNode {
  const XrkUiLayout({required super.path, required this.row, required this.children, super.truncation});

  final bool row;
  final List<XrkUiNode> children;
}

/// `text`：一段 Markdown。
final class XrkUiText extends XrkUiNode {
  const XrkUiText({
    required super.path,
    required this.text,
    this.muted = false,
    this.restricted = false,
    super.truncation,
  });

  final String text;
  final bool muted;

  /// 插件视图：只认段落、换行、粗体、行内代码（链接只显示文字，图片只显示
  /// 替代文字），不走完整 Markdown。
  final bool restricted;
}

/// 语义色调。模型卡的 metric 只认 good / warn / bad；插件视图另有 info、muted。
enum XrkUiTone { good, warn, bad, info, muted }

/// `metric`：一个关键数字。[value] 已经是要显示的文字。
final class XrkUiMetric extends XrkUiNode {
  const XrkUiMetric({
    required super.path,
    required this.label,
    required this.value,
    this.tone,
    this.caption,
    this.trend,
  });

  final String label;
  final String value;
  final XrkUiTone? tone;
  final String? caption;

  /// v2 `trend`: 2–30 points under the value (null keeps a gap); null when
  /// the view has none.
  final List<double?>? trend;
}

enum XrkUiChartKind { bar, hbar, line, donut }

/// 图表的一组数据。[values] 与类别一一对应；缺的或不是有限数的位置是 null。
final class XrkUiSeries {
  const XrkUiSeries({this.name, required this.values});

  final String? name;
  final List<double?> values;
}

/// `chart`：柱状 / 横向柱状 / 折线 / 环形。
final class XrkUiChart extends XrkUiNode {
  const XrkUiChart({
    required super.path,
    required this.kind,
    required this.categories,
    required this.series,
    this.unit,
    this.caption,
    super.truncation,
  });

  final XrkUiChartKind kind;
  final List<String> categories;
  final List<XrkUiSeries> series;
  final String? unit;
  final String? caption;
}

final class XrkUiCompareItem {
  const XrkUiCompareItem({required this.title, this.badge, required this.rows});

  final String title;
  final String? badge;

  /// `[名称, 值]`。
  final List<(String, String)> rows;
}

/// `compare`：2–4 张竖排的对比卡。
final class XrkUiCompare extends XrkUiNode {
  const XrkUiCompare({required super.path, required this.items, super.truncation});

  final List<XrkUiCompareItem> items;
}

enum XrkUiStepStatus { done, current, todo, failed }

final class XrkUiStep {
  const XrkUiStep({required this.label, required this.status, this.detail});

  final String label;
  final XrkUiStepStatus status;
  final String? detail;
}

/// `steps`：步骤与进度。
final class XrkUiSteps extends XrkUiNode {
  const XrkUiSteps({required super.path, required this.items, super.truncation});

  final List<XrkUiStep> items;
}

enum XrkUiCalloutTone { info, good, warn, bad }

/// `callout`：提示与风险。
final class XrkUiCallout extends XrkUiNode {
  const XrkUiCallout({
    required super.path,
    required this.text,
    this.tone = XrkUiCalloutTone.info,
    this.restricted = false,
    super.truncation,
  });

  final String text;
  final XrkUiCalloutTone tone;

  /// 插件视图：受限文字（同 [XrkUiText.restricted]）。
  final bool restricted;
}

final class XrkUiOption {
  const XrkUiOption({required this.label, this.description, this.value});

  final String label;
  final String? description;

  /// 插件视图：点按时回传的值；null 时用 [label]。
  final String? value;

  String get key => value ?? label;
}

/// `options`：看完再选（回答组件）。
final class XrkUiOptions extends XrkUiNode {
  const XrkUiOptions({
    required super.path,
    required this.id,
    required this.options,
    this.multi = false,
    this.freetext = false,
    this.freetextHint,
    this.selected = const [],
    super.truncation,
  });

  /// 模型卡：回复里认卡用的 id；插件视图：invoke 的动作 id（不合规时为空，
  /// 选项只读）。
  final String id;
  final List<XrkUiOption> options;
  final bool multi;

  /// 用户还能在选项之外自己填一句（`freetext: true`，或直接给一个提示词）。
  final bool freetext;

  /// 输入框的提示词；null 用 App 的「其他（自己填）」。
  final String? freetextHint;

  /// 插件视图：当前选中项的 [XrkUiOption.key]（由插件维护）。
  final List<String> selected;

  List<String> get labels => [for (final o in options) o.label];
}

/// `confirm`：确认后继续（回答组件）。
final class XrkUiConfirm extends XrkUiNode {
  const XrkUiConfirm({required super.path, required this.id, this.confirmLabel, this.cancelLabel});

  static String get defaultConfirm => appL10n.commonConfirm;
  static String get defaultCancel => appL10n.commonCancel;

  final String id;

  /// 模型写的按钮字；null 时按钮显示 [defaultConfirm]。
  final String? confirmLabel;
  final String? cancelLabel;

  String get confirmText => confirmLabel ?? defaultConfirm;
  String get cancelText => cancelLabel ?? defaultCancel;
}

/// 画不出来的子节点：一行灰色占位，其余照画。
final class XrkUiPlaceholder extends XrkUiNode {
  const XrkUiPlaceholder({required super.path, required this.issue, this.type});

  /// 模型写的 type（认识但缺属性时有值）。
  final String? type;
  final XrkUiIssue issue;
}

/// 解析好的一张视图。
final class XrkUiView {
  const XrkUiView({
    required this.root,
    this.title,
    this.issues = const [],
    this.bytes = 0,
    this.version = 1,
    this.styles = const {},
    this.dialect,
  });

  /// The fence came in another plugin's format and was mapped onto a
  /// read-only plugin view (`genui`); null for the app's own format.
  final String? dialect;

  /// This view, marked as mapped from [name]'s format.
  XrkUiView asDialect(String name, {List<XrkUiIssue> notes = const []}) => XrkUiView(
    root: root,
    title: title,
    issues: List.unmodifiable([...issues, ...notes]),
    bytes: bytes,
    version: version,
    styles: styles,
    dialect: name,
  );

  /// Only an explicit plugin-view v2 enables author styles. Model cards and
  /// old plugin views retain the exact v1 rendering path.
  final int version;
  final Map<String, XrkUiPluginStyle> styles;

  final XrkUiNode root;
  final String? title;

  /// 宽松模式放过去的问题（忽略的属性不算）：占位、截断、修过的 JSON。
  final List<XrkUiIssue> issues;

  /// 源文本的 UTF-8 字节数。
  final int bytes;

  /// 深度优先遍历所有节点（含根）。
  Iterable<XrkUiNode> get nodes sync* {
    Iterable<XrkUiNode> walk(XrkUiNode node) sync* {
      yield node;
      if (node is XrkUiLayout) {
        for (final child in node.children) {
          yield* walk(child);
        }
      } else if (node is XrkUiControlContainer) {
        for (final child in node.children) {
          yield* walk(child);
        }
      }
    }

    yield* walk(root);
  }

  /// 回答组件（`options` / `confirm`），按出现顺序。
  List<XrkUiNode> get answerNodes => [
    for (final node in nodes)
      if (node is XrkUiOptions || node is XrkUiConfirm) node,
  ];

  bool get interactive => answerNodes.isNotEmpty;

  /// 有没有被截断的地方。
  bool get truncated => nodes.any((n) => n.truncation != null);
}

// ───────────────────────── 解析结果 ─────────────────────────

sealed class XrkUiParse {
  const XrkUiParse();
}

final class XrkUiParsed extends XrkUiParse {
  const XrkUiParsed(this.view);

  final XrkUiView view;
}

/// 整块画不了（JSON 坏了、根节点不认识、太大）：降级成代码块。
final class XrkUiInvalid extends XrkUiParse {
  const XrkUiInvalid(this.error, {this.dialect});

  final XrkUiIssue error;

  /// Set for another plugin's format (`genui`): nothing to resend, the
  /// block is fine where it came from.
  final String? dialect;

  /// 「让它重发」发出的文字（由用户点了才发）。
  String get resendText => xrkUiResendText(error);
}

/// 「让它重发」的消息正文。
String xrkUiResendText(XrkUiIssue error) => appL10n.viewUiResendMessage(error);

// ───────────────────────── 入口 ─────────────────────────

/// 解析围栏里的源文本，按文本缓存（列表每 32ms 重建一次，同一段不重复解析）。
XrkUiParse parseXrkUi(String source) => _cache.get(source);

/// 不走缓存的解析（测试、一次性用途）。
XrkUiParse parseXrkUiUncached(String source) {
  final bytes = utf8.encode(source).length;
  if (bytes > XrkUiLimits.hardBytes) {
    // Only a genui block may use the larger panel budget (§3.2 of
    // plugin-ui-v3.md); anything else is too big exactly as before.
    if (bytes <= XrkUiProfile.panel.bytes) {
      Object? big;
      try {
        big = jsonDecode(source.trim());
      } on FormatException {
        big = null;
      }
      if (isGenuiDialect(big)) return _parseGenui(big);
    }
    return XrkUiInvalid(XrkUiIssue('view', appL10n.viewUiBytesLimit(bytes, XrkUiLimits.hardBytes)));
  }
  final text = source.trim();
  if (text.isEmpty) {
    return XrkUiInvalid(XrkUiIssue('view', appL10n.viewUiEmptyCode));
  }
  Object? json;
  final repairs = <XrkUiIssue>[];
  try {
    json = jsonDecode(text);
  } on FormatException catch (e) {
    // 宽松：模型偶尔带注释或尾逗号。修过还不行，才算格式有误。
    final relaxed = _relaxJson(text);
    Object? retry = _notJson;
    if (relaxed != text) {
      try {
        retry = jsonDecode(relaxed);
      } on FormatException {
        // 报原文的错：那才是模型写的位置。
      }
    }
    if (identical(retry, _notJson)) {
      final message = e.offset == null
          ? appL10n.viewUiInvalidJson(e.message)
          : appL10n.viewUiInvalidJsonOffset(e.message, e.offset!);
      return XrkUiInvalid(XrkUiIssue('view', message));
    }
    json = retry;
    repairs.add(XrkUiIssue('view', appL10n.viewUiJsonRepaired));
  }
  // 一万层的 `[[[…]]]` 不会是视图：先量嵌套，免得后面递归太深。
  final size = measureXrkUiJson(json, maxBytes: XrkUiLimits.hardBytes * 2, maxDepth: XrkUiProfile.jsonNesting);
  if (size.tooDeep) {
    return XrkUiInvalid(XrkUiIssue('view', appL10n.plugViewTooDeep(XrkUiProfile.jsonNesting)));
  }
  if (isGenuiDialect(json)) return _parseGenui(json);
  return xrkUiFromJson(json, bytes: bytes, issues: repairs);
}

/// A genui block (docs/design/plugin-ui-v3.md §3.2): mapped to a read-only
/// plugin view under the panel budget. Never offers a resend.
XrkUiParse _parseGenui(Object? json) {
  final mapping = genuiToPluginView(json);
  final notes = [for (final path in mapping.notes) XrkUiIssue(path, appL10n.viewUiDialectNote)];
  final view = mapping.view;
  if (view == null) {
    return XrkUiInvalid(XrkUiIssue('view', appL10n.viewUiDialectInvalid), dialect: 'genui');
  }
  return switch (parseXrkUiPluginUncached(view)) {
    XrkUiParsed(view: final parsed) => XrkUiParsed(parsed.asDialect('genui', notes: notes)),
    XrkUiInvalid(:final error) => XrkUiInvalid(error, dialect: 'genui'),
  };
}

const _notJson = Object();

/// 从已解码的 JSON 建视图：先 [normalizeXrkUi]，再宽松校验。
XrkUiParse xrkUiFromJson(
  Object? json, {
  int bytes = 0,
  List<XrkUiIssue> issues = const [],
  XrkUiProfile profile = XrkUiProfile.model,
}) {
  var value = profile.plugin ? json : normalizeXrkUi(json);
  // 模型偶尔直接给一个组件数组：当作竖排。
  if (value is List) {
    value = <String, Object?>{'type': 'stack', 'children': value};
  }
  if (value is! Map<String, Object?>) {
    return XrkUiInvalid(XrkUiIssue('view', appL10n.viewUiExpectedObject));
  }
  final ctx = _Ctx(profile)..issues.addAll(issues);
  if (profile.plugin) _initPluginStyles(value, ctx);
  final root = _node(value, 'view', 1, ctx);
  if (root is XrkUiPlaceholder) return XrkUiInvalid(root.issue);
  if (root is XrkUiLayout && root.children.isNotEmpty && root.children.every((c) => c is XrkUiPlaceholder)) {
    return XrkUiInvalid((root.children.first as XrkUiPlaceholder).issue);
  }
  if (root is XrkUiControlContainer && root.children.isNotEmpty && root.children.every((c) => c is XrkUiPlaceholder)) {
    return XrkUiInvalid((root.children.first as XrkUiPlaceholder).issue);
  }
  final rawTitle = value['title'];
  final title = rawTitle is XrkUiMissing ? null : _clip(_string(rawTitle)?.trim(), XrkUiLimits.title);
  return XrkUiParsed(
    XrkUiView(
      root: root,
      title: title == null || title.isEmpty ? null : title,
      issues: List.unmodifiable(ctx.issues),
      bytes: bytes,
      version: ctx.version,
      styles: Map.unmodifiable(ctx.styles),
    ),
  );
}

/// 规范化（照 DS Bot `normalizeView`）：有的供应商把嵌套数组编成
/// `{"item": [...]}`（还可能套好几层），把数字编成字符串。数组解包；数值字段
/// 和图表的 `values` 接受数字字符串。返回新对象，不改输入。
Object? normalizeXrkUi(Object? value) {
  if (value is List) return [for (final item in value) normalizeXrkUi(item)];
  if (value is! Map) return value;
  if (value.length == 1 && value.containsKey('item')) {
    final inner = normalizeXrkUi(value['item']);
    if (inner is List) return inner;
  }
  final out = <String, Object?>{};
  for (final entry in value.entries) {
    out['${entry.key}'] = normalizeXrkUi(entry.value);
  }
  for (final field in _numericFields) {
    if (out.containsKey(field)) out[field] = _numeric(out[field]);
  }
  final values = out['values'];
  if (values is List) out['values'] = [for (final v in values) _numeric(v)];
  return out;
}

const _numericFields = ['value', 'percent', 'min', 'max', 'step', 'height'];

Object? _numeric(Object? value) {
  if (value is! String || value.trim().isEmpty) return value;
  final parsed = num.tryParse(value.trim());
  return parsed == null || parsed.isNaN ? value : parsed;
}

// ───────────────────────── 校验 ─────────────────────────

const _types = ['stack', 'row', 'text', 'metric', 'chart', 'compare', 'steps', 'callout', 'options', 'confirm'];

class _Ctx {
  _Ctx([this.p = XrkUiProfile.model]);

  final XrkUiProfile p;
  int nodes = 0;
  int version = 1;
  int accent = XrkUiPluginPalette.defaultAccent;
  int richSpans = 0;
  XrkUiColorPair styleBackground = XrkUiPluginPalette.surface;
  final styles = <String, XrkUiPluginStyle>{};
  final contrastNotes = <String>{};
  int inputFields = 0;
  bool inForm = false;
  final inputBindings = <String>{};

  /// 插件视图里已经有一个实心主色按钮了（之后的按普通画）。
  bool primaryUsed = false;
  final issues = <XrkUiIssue>[];

  XrkUiPlaceholder broken(String path, String message, {String? type}) {
    final issue = XrkUiIssue(path, message);
    issues.add(issue);
    return XrkUiPlaceholder(path: path, issue: issue, type: type);
  }

  void note(String path, String message) => issues.add(XrkUiIssue(path, message));
}

XrkUiNode _node(Object? raw, String path, int depth, _Ctx ctx) {
  // 占位也算一个节点：上限管的是画出来的东西。
  ctx.nodes += 1;
  if (raw is! Map<String, Object?>) {
    return ctx.broken(path, appL10n.viewUiExpectedObject);
  }
  if (depth > ctx.p.depth) {
    return ctx.broken(path, appL10n.viewUiDepthLimit(depth, ctx.p.depth));
  }
  final type = raw['type'];
  final types = ctx.p.plugin ? (ctx.version >= 2 ? xrkUiPluginComponents : _pluginTypes) : _types;
  if (type is! String || !types.contains(type)) {
    final shown = type == null || type is XrkUiMissing || type is Map
        ? appL10n.viewUiMissingType
        : appL10n.viewUiUnknownComponent(_show(type));
    return ctx.broken('$path.type', appL10n.viewUiAvailableTypes(shown, types.join(', ')));
  }
  if (ctx.version == 2 && _pluginReservedRoles.contains(raw['role'])) {
    return ctx.broken('$path.role', appL10n.plugViewStyleReserved, type: type);
  }
  final previousBackground = ctx.styleBackground;
  if (ctx.version == 2) {
    final style = _readPluginStyle(raw, path, ctx);
    ctx.styles[path] = style;
    ctx.styleBackground = style.background;
  }
  try {
    if (ctx.p.plugin) {
      if (_pluginNode(type, raw, path, depth, ctx) case final node?) return node;
    }
    return switch (type) {
      'stack' || 'row' => _layout(raw, path, depth, ctx, row: type == 'row'),
      'text' => _text(raw, path, ctx),
      'metric' => _metric(raw, path, ctx),
      'chart' => _chart(raw, path, ctx),
      'compare' => _compare(raw, path, ctx),
      'steps' => _steps(raw, path, ctx),
      'callout' => _callout(raw, path, ctx),
      'options' => _options(raw, path, ctx),
      _ => _confirm(raw, path, ctx),
    };
  } finally {
    ctx.styleBackground = previousBackground;
  }
}

XrkUiNode _layout(Map<String, Object?> raw, String path, int depth, _Ctx ctx, {required bool row}) {
  final children = raw['children'];
  if (ctx.p.plugin && _isEmpty(children)) {
    return XrkUiEmpty(path: path, type: row ? 'row' : 'stack');
  }
  if (children is! List || children.isEmpty) {
    return ctx.broken('$path.children', appL10n.viewUiExpectedChildren(ctx.p.children), type: row ? 'row' : 'stack');
  }
  final built = <XrkUiNode>[];
  var dropped = 0;
  for (var i = 0; i < children.length; i++) {
    if (i >= ctx.p.children || ctx.nodes >= ctx.p.nodes) {
      dropped = children.length - i;
      break;
    }
    built.add(_node(children[i], '$path.children[$i]', depth + 1, ctx));
  }
  String? truncation;
  if (dropped > 0) {
    truncation = appL10n.viewUiHiddenItems(dropped);
    ctx.note(
      '$path.children',
      ctx.nodes >= ctx.p.nodes
          ? appL10n.viewUiNodeLimit(ctx.p.nodes, dropped)
          : appL10n.viewUiChildLimit(ctx.p.children, dropped),
    );
  }
  return XrkUiLayout(path: path, row: row, children: List.unmodifiable(built), truncation: truncation);
}

XrkUiNode _text(Map<String, Object?> raw, String path, _Ctx ctx) {
  final text = _string(raw['text']);
  if (text == null) {
    return ctx.broken('$path.text', appL10n.viewUiExpectedString, type: 'text');
  }
  final max = ctx.p.text;
  final clipped = text.length > max;
  if (clipped) {
    ctx.note('$path.text', appL10n.viewUiTextLimit(text.length, max));
  }
  final tone = raw['tone'];
  return XrkUiText(
    path: path,
    text: clipped ? '${text.substring(0, max)}…' : text,
    muted: tone == 'muted' || (ctx.p.plugin && (tone == 'secondary')),
    restricted: ctx.p.plugin,
    truncation: clipped ? appL10n.viewUiTextTruncated : null,
  );
}

XrkUiNode _metric(Map<String, Object?> raw, String path, _Ctx ctx) {
  final label = _string(raw['label']);
  if (label == null) {
    return ctx.broken('$path.label', appL10n.viewUiExpectedString, type: 'metric');
  }
  final value = raw['value'];
  final String shown;
  if (value is num) {
    if (!value.isFinite) {
      return ctx.broken('$path.value', appL10n.viewUiExpectedFinite, type: 'metric');
    }
    shown = formatXrkUiValue(value.toDouble());
  } else if (value is String) {
    shown = value;
  } else if (value is bool) {
    shown = value ? appL10n.viewUiYes : appL10n.viewUiNo;
  } else if (value is XrkUiMissing) {
    shown = xrkUiMissingText;
  } else {
    return ctx.broken('$path.value', appL10n.viewUiExpectedStringNumber, type: 'metric');
  }
  return XrkUiMetric(
    path: path,
    label: _clip(label, XrkUiLimits.label)!,
    value: _clip(shown, XrkUiLimits.label)!,
    tone: ctx.p.plugin
        ? _pluginTone(raw['tone'], '$path.tone', ctx, muted: false)
        : _tone(raw['tone'], '$path.tone', ctx),
    caption: _clip(_string(raw['caption']), XrkUiLimits.label),
    trend: ctx.p.plugin && ctx.version >= 2 ? _metricTrend(raw['trend'], '$path.trend', ctx) : null,
  );
}

/// v2 `metric.trend`: 2–30 finite numbers or nulls; anything else is a note
/// and no line.
List<double?>? _metricTrend(Object? raw, String path, _Ctx ctx) {
  if (raw == null || raw is XrkUiMissing) return null;
  if (raw is! List || raw.length < 2 || raw.length > XrkUiControlLimits.trendPoints) {
    ctx.note(path, appL10n.plugViewBadTrend(XrkUiControlLimits.trendPoints));
    return null;
  }
  final points = <double?>[];
  for (final v in raw) {
    if (v == null || v is XrkUiMissing) {
      points.add(null);
    } else if (v is num && v.isFinite) {
      points.add(v.toDouble());
    } else {
      ctx.note(path, appL10n.plugViewBadTrend(XrkUiControlLimits.trendPoints));
      return null;
    }
  }
  if (points.whereType<double>().length < 2) {
    ctx.note(path, appL10n.plugViewBadTrend(XrkUiControlLimits.trendPoints));
    return null;
  }
  return List.unmodifiable(points);
}

XrkUiTone? _tone(Object? raw, String path, _Ctx ctx) {
  if (raw == null || raw is XrkUiMissing) return null;
  final tone = switch (raw) {
    'good' || 'success' || 'positive' => XrkUiTone.good,
    'warn' || 'warning' || 'caution' => XrkUiTone.warn,
    'bad' || 'danger' || 'error' || 'negative' => XrkUiTone.bad,
    _ => null,
  };
  if (tone == null) {
    ctx.note(path, appL10n.viewUiUnknownTone(_show(raw)));
  }
  return tone;
}

XrkUiNode _chart(Map<String, Object?> raw, String path, _Ctx ctx) {
  final rawKind = raw['kind'];
  var kind = switch (rawKind) {
    null || XrkUiMissing() || 'bar' || 'column' || 'columns' => XrkUiChartKind.bar,
    'hbar' || 'barh' || 'horizontal' || 'horizontalBar' => XrkUiChartKind.hbar,
    'line' || 'area' || 'spline' => XrkUiChartKind.line,
    'donut' || 'pie' || 'doughnut' || 'ring' => XrkUiChartKind.donut,
    _ => null,
  };
  if (kind == null) {
    ctx.note('$path.kind', appL10n.viewUiUnknownChart(_show(rawKind)));
    kind = XrkUiChartKind.bar;
  }

  final rawCategories = raw['categories'];
  if (ctx.p.plugin && (_isEmpty(rawCategories) || _isEmpty(raw['series']))) {
    return XrkUiEmpty(path: path, type: 'chart');
  }
  if (rawCategories is! List || rawCategories.isEmpty) {
    return ctx.broken('$path.categories', appL10n.viewUiExpectedCategories, type: 'chart');
  }
  final notes = <String>[];
  var categories = [for (final c in rawCategories.take(XrkUiLimits.points + 1)) _clip(_string(c) ?? '', 40)!];
  if (categories.length > XrkUiLimits.points) {
    ctx.note('$path.categories', appL10n.viewUiCategoryLimit(rawCategories.length, XrkUiLimits.points));
    categories = categories.sublist(0, XrkUiLimits.points);
    notes.add(appL10n.viewUiFirstPoints(XrkUiLimits.points));
  }

  // 宽松：series 写成单个对象，或者 values 直接写在 chart 上。
  var rawSeries = raw['series'];
  if (rawSeries is Map) rawSeries = [rawSeries];
  // 宽松：series 直接写成一组数字。
  if (rawSeries is List && rawSeries.isNotEmpty && rawSeries.every((e) => e == null || e is num || e is String)) {
    rawSeries = [
      {'values': rawSeries},
    ];
  }
  if (rawSeries == null && raw['values'] is List) {
    rawSeries = [
      {'values': raw['values']},
    ];
  }
  if (rawSeries is! List || rawSeries.isEmpty) {
    return ctx.broken('$path.series', appL10n.viewUiExpectedSeries('{name?, values}'), type: 'chart');
  }
  final series = <XrkUiSeries>[];
  for (var i = 0; i < rawSeries.length; i++) {
    final item = rawSeries[i];
    final at = '$path.series[$i]';
    // 宽松：series 里的一项直接是数字数组。
    final Object? values = item is Map ? item['values'] : item;
    if (values is! List) {
      ctx.note('$at.values', appL10n.viewUiSkippedSeries);
      continue;
    }
    if (values.length != categories.length && values.length != rawCategories.length) {
      ctx.note('$at.values', appL10n.viewUiValuesCategories(values.length, rawCategories.length));
    }
    var bad = 0;
    final parsed = <double?>[
      for (var j = 0; j < categories.length; j++)
        if (j < values.length) _chartValue(values[j], () => bad++) else null,
    ];
    if (bad > 0) ctx.note('$at.values', appL10n.viewUiNonFiniteValues(bad));
    series.add(
      XrkUiSeries(name: item is Map ? _clip(_string(item['name']), 40) : null, values: List.unmodifiable(parsed)),
    );
  }
  if (series.isEmpty) {
    return ctx.broken('$path.series', appL10n.viewUiNoSeries, type: 'chart');
  }
  var kept = series;
  if (kind == XrkUiChartKind.donut && kept.length > 1) {
    ctx.note('$path.series', appL10n.viewUiDonutSeries(kept.length - 1));
    kept = kept.sublist(0, 1);
    notes.add(appL10n.viewUiFirstSeries);
  } else if (kept.length > XrkUiLimits.series) {
    ctx.note('$path.series', appL10n.viewUiSeriesLimit(kept.length, XrkUiLimits.series));
    kept = kept.sublist(0, XrkUiLimits.series);
    notes.add(appL10n.viewUiFirstSeriesCount(XrkUiLimits.series));
  }
  if (kept.every((s) => s.values.every((v) => v == null))) {
    if (ctx.p.plugin) return XrkUiEmpty(path: path, type: 'chart');
    return ctx.broken('$path.series', appL10n.viewUiNoFiniteValues, type: 'chart');
  }
  return XrkUiChart(
    path: path,
    kind: kind,
    categories: List.unmodifiable(categories),
    series: List.unmodifiable(kept),
    unit: _clip(_string(raw['unit'])?.trim(), 12),
    caption: _clip(_string(raw['caption']), XrkUiLimits.label),
    truncation: notes.isEmpty ? null : appL10n.viewUiTruncated(notes.join(appL10n.viewListSeparator)),
  );
}

/// 图表值：有限数；数字字符串里的千分位逗号和末尾的 % 也认。
double? _chartValue(Object? value, void Function() onBad) {
  if (value is XrkUiMissing) return null;
  if (value is num) {
    if (value.isFinite) return value.toDouble();
    onBad();
    return null;
  }
  if (value is String) {
    var s = value.trim().replaceAll(',', '').replaceAll('_', '');
    if (s.endsWith('%')) s = s.substring(0, s.length - 1).trim();
    final parsed = double.tryParse(s);
    if (parsed != null && parsed.isFinite) return parsed;
  }
  if (value != null) onBad();
  return null;
}

XrkUiNode _compare(Map<String, Object?> raw, String path, _Ctx ctx) {
  final rawItems = raw['items'];
  if (ctx.p.plugin && _isEmpty(rawItems)) {
    return XrkUiEmpty(path: path, type: 'compare');
  }
  if (rawItems is! List || rawItems.isEmpty) {
    return ctx.broken(
      '$path.items',
      appL10n.viewUiExpectedCompare(XrkUiLimits.compareItems, '{title, badge?, rows}'),
      type: 'compare',
    );
  }
  final notes = <String>[];
  final items = <XrkUiCompareItem>[];
  var rowsCut = false;
  for (var i = 0; i < rawItems.length; i++) {
    final item = rawItems[i];
    final at = '$path.items[$i]';
    if (items.length >= XrkUiLimits.compareItems) {
      ctx.note('$path.items', appL10n.viewUiItemLimit(rawItems.length, XrkUiLimits.compareItems));
      notes.add(appL10n.viewUiFirstItems(XrkUiLimits.compareItems));
      break;
    }
    if (item is! Map) {
      ctx.note(at, appL10n.viewUiSkippedCompare('{title, badge?, rows}'));
      continue;
    }
    final title = _string(item['title']);
    if (title == null || title.trim().isEmpty) {
      ctx.note('$at.title', appL10n.viewUiSkippedItemLabel);
      continue;
    }
    final rows = <(String, String)>[];
    final rawRows = item['rows'];
    final List<Object?> entries = switch (rawRows) {
      final List<Object?> list => list,
      // 宽松：rows 写成 {名称: 值}。
      final Map<String, Object?> map => [
        for (final e in map.entries) [e.key, e.value],
      ],
      _ => const [],
    };
    for (var r = 0; r < entries.length; r++) {
      if (rows.length >= XrkUiLimits.compareRows) {
        ctx.note('$at.rows', appL10n.viewUiRowLimit(entries.length, XrkUiLimits.compareRows));
        rowsCut = true;
        break;
      }
      final row = _pair(entries[r]);
      if (row == null) {
        ctx.note('$at.rows[$r]', appL10n.viewUiSkippedRow);
        continue;
      }
      rows.add(row);
    }
    items.add(
      XrkUiCompareItem(
        title: _clip(title.trim(), 40)!,
        badge: _clip(_string(item['badge'])?.trim(), 12),
        rows: List.unmodifiable(rows),
      ),
    );
  }
  if (items.isEmpty) {
    return ctx.broken('$path.items', appL10n.viewUiNoItems, type: 'compare');
  }
  if (rowsCut) notes.add(appL10n.viewUiFirstRows(XrkUiLimits.compareRows));
  return XrkUiCompare(
    path: path,
    items: List.unmodifiable(items),
    truncation: notes.isEmpty ? null : appL10n.viewUiTruncated(notes.join(appL10n.viewListSeparator)),
  );
}

(String, String)? _pair(Object? raw) {
  if (raw is List && raw.isNotEmpty) {
    final name = _string(raw[0]);
    if (name == null) return null;
    final value = raw.length > 1 ? _string(raw[1]) ?? '' : '';
    return (_clip(name, 40)!, _clip(value, 80)!);
  }
  if (raw is Map) {
    final name = _string(raw['label'] ?? raw['name']);
    if (name == null) return null;
    return (_clip(name, 40)!, _clip(_string(raw['value']) ?? '', 80)!);
  }
  return null;
}

XrkUiNode _steps(Map<String, Object?> raw, String path, _Ctx ctx) {
  final rawItems = raw['items'];
  if (ctx.p.plugin && _isEmpty(rawItems)) {
    return XrkUiEmpty(path: path, type: 'steps');
  }
  if (rawItems is! List || rawItems.isEmpty) {
    return ctx.broken('$path.items', appL10n.viewUiExpectedSteps('{label, status, detail?}'), type: 'steps');
  }
  final items = <XrkUiStep>[];
  String? truncation;
  for (var i = 0; i < rawItems.length; i++) {
    if (items.length >= XrkUiLimits.steps) {
      ctx.note('$path.items', appL10n.viewUiStepLimit(rawItems.length, XrkUiLimits.steps));
      truncation = appL10n.viewUiFirstSteps(XrkUiLimits.steps);
      break;
    }
    final item = rawItems[i];
    final at = '$path.items[$i]';
    if (item is String) {
      items.add(XrkUiStep(label: _clip(item, XrkUiLimits.label)!, status: XrkUiStepStatus.todo));
      continue;
    }
    if (item is! Map) {
      ctx.note(at, appL10n.viewUiSkippedStep('{label, status, detail?}'));
      continue;
    }
    final label = _string(item['label'] ?? item['title']);
    if (label == null) {
      ctx.note('$at.label', appL10n.viewUiSkippedStepLabel);
      continue;
    }
    final rawStatus = item['status'];
    var status = switch (rawStatus) {
      'done' || 'completed' || 'complete' || 'success' => XrkUiStepStatus.done,
      'current' || 'active' || 'doing' || 'in_progress' || 'running' => XrkUiStepStatus.current,
      null || XrkUiMissing() || 'todo' || 'pending' || 'waiting' => XrkUiStepStatus.todo,
      'failed' || 'error' || 'blocked' => XrkUiStepStatus.failed,
      _ => null,
    };
    if (status == null) {
      ctx.note('$at.status', appL10n.viewUiUnknownStatus(_show(rawStatus)));
      status = XrkUiStepStatus.todo;
    }
    items.add(
      XrkUiStep(
        label: _clip(label, XrkUiLimits.label)!,
        status: status,
        detail: _clip(_string(item['detail']), XrkUiLimits.label),
      ),
    );
  }
  if (items.isEmpty) {
    return ctx.broken('$path.items', appL10n.viewUiNoSteps, type: 'steps');
  }
  return XrkUiSteps(path: path, items: List.unmodifiable(items), truncation: truncation);
}

XrkUiNode _callout(Map<String, Object?> raw, String path, _Ctx ctx) {
  final text = _string(raw['text']);
  if (text == null) {
    return ctx.broken('$path.text', appL10n.viewUiExpectedString, type: 'callout');
  }
  final rawTone = raw['tone'];
  var tone = switch (rawTone) {
    null || XrkUiMissing() || 'info' || 'note' => XrkUiCalloutTone.info,
    'good' || 'success' || 'tip' => XrkUiCalloutTone.good,
    'warn' || 'warning' || 'caution' => XrkUiCalloutTone.warn,
    'bad' || 'danger' || 'error' => XrkUiCalloutTone.bad,
    _ => null,
  };
  if (tone == null) {
    ctx.note('$path.tone', appL10n.viewUiUnknownCalloutTone(_show(rawTone)));
    tone = XrkUiCalloutTone.info;
  }
  final max = ctx.p.text;
  final clipped = text.length > max;
  if (clipped) {
    ctx.note('$path.text', appL10n.viewUiTextLimit(text.length, max));
  }
  return XrkUiCallout(
    path: path,
    text: clipped ? '${text.substring(0, max)}…' : text,
    tone: tone,
    restricted: ctx.p.plugin,
    truncation: clipped ? appL10n.viewUiTextTruncated : null,
  );
}

XrkUiNode _options(Map<String, Object?> raw, String path, _Ctx ctx) {
  final rawOptions = raw['options'];
  if (ctx.p.plugin && _isEmpty(rawOptions)) {
    return XrkUiEmpty(path: path, type: 'options');
  }
  if (rawOptions is! List || rawOptions.isEmpty) {
    return ctx.broken(
      '$path.options',
      appL10n.viewUiExpectedOptions(XrkUiLimits.options, '{label, description?}'),
      type: 'options',
    );
  }
  final options = <XrkUiOption>[];
  final seen = <String>{};
  String? truncation;
  for (var i = 0; i < rawOptions.length; i++) {
    if (options.length >= XrkUiLimits.options) {
      ctx.note('$path.options', appL10n.viewUiOptionLimit(rawOptions.length, XrkUiLimits.options));
      truncation = appL10n.viewUiFirstOptions(XrkUiLimits.options);
      break;
    }
    final item = rawOptions[i];
    final at = '$path.options[$i]';
    final label = _string(item is Map ? item['label'] : item)?.trim();
    if (label == null || label.isEmpty) {
      ctx.note('$at.label', appL10n.viewUiSkippedItemLabel);
      continue;
    }
    // 插件视图：点按回传 value（缺省 label）。
    final rawValue = ctx.p.plugin && item is Map ? item['value'] : null;
    final value = rawValue is String && rawValue.isNotEmpty ? _clip(rawValue, XrkUiLimits.label) : null;
    // 回复只带 label（插件视图带 value）：同名的两项分不出来，后一项丢掉。
    if (!seen.add(value ?? label)) {
      ctx.note('$at.label', appL10n.viewUiDuplicateLabel(_show(label)));
      continue;
    }
    options.add(
      XrkUiOption(
        label: _clip(label, 80)!,
        description: item is Map ? _clip(_string(item['description'])?.trim(), XrkUiLimits.label) : null,
        value: value,
      ),
    );
  }
  if (options.isEmpty) {
    return ctx.broken('$path.options', appL10n.viewUiNoOptions, type: 'options');
  }
  final multi = raw['multi'];
  // `freetext: true` 开一个「自己填」；给字符串时同时当输入框提示词。
  final rawFreetext = raw['freetext'];
  final hint = rawFreetext is String ? _clip(rawFreetext.trim(), XrkUiLimits.label) : null;
  final freetext = rawFreetext == true || rawFreetext == 'true' || (hint != null && hint.isNotEmpty);
  return XrkUiOptions(
    path: path,
    id: ctx.p.plugin ? _pluginActionId(raw['id'], '$path.id', ctx) ?? '' : _string(raw['id']) ?? 'options',
    options: List.unmodifiable(options),
    multi: multi == true || multi == 'true',
    freetext: freetext,
    freetextHint: hint == null || hint.isEmpty ? null : hint,
    selected: ctx.p.plugin ? _selected(raw['selected']) : const [],
    truncation: truncation,
  );
}

XrkUiNode _confirm(Map<String, Object?> raw, String path, _Ctx ctx) {
  String? label(Object? v) {
    if (v is XrkUiMissing) return null;
    final s = _clip(_string(v)?.trim(), 12);
    return s == null || s.isEmpty ? null : s;
  }

  return XrkUiConfirm(
    path: path,
    id: ctx.p.plugin ? _pluginActionId(raw['id'], '$path.id', ctx) ?? '' : _string(raw['id']) ?? 'confirm',
    confirmLabel: label(raw['confirmLabel']),
    cancelLabel: label(raw['cancelLabel']),
  );
}

/// 文字型属性：字符串照用；数字、布尔转成文字（宽松）。
String? _string(Object? value) => switch (value) {
  final String s => s,
  XrkUiMissing() => xrkUiMissingText,
  final num n when n.isFinite => formatXrkUiValue(n.toDouble()),
  final bool b => '$b',
  _ => null,
};

/// 问题说明里引用的值：短 JSON；编不出来的（NaN、无穷大、取不到）照样
/// 给一个字，不抛错。
String _show(Object? value) => switch (value) {
  XrkUiMissing() => xrkUiMissingText,
  Map() => '{…}',
  List() => '[…]',
  final String s => jsonEncode(s.length <= 40 ? s : '${s.substring(0, 40)}…'),
  final num n => '$n',
  _ => '$value',
};

String? _clip(String? text, int max) {
  if (text == null || text.length <= max) return text;
  return '${text.substring(0, max)}…';
}

/// 模型写的数字显示成文字：整数不带 .0，一万以上加千分位，小数最多两位。
String formatXrkUiValue(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    final whole = value.round();
    return whole.abs() >= 10000 ? _group(whole.toString()) : '$whole';
  }
  final fixed = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  return value.abs() >= 10000 ? _group(fixed) : fixed;
}

String _group(String digits) {
  final negative = digits.startsWith('-');
  final body = negative ? digits.substring(1) : digits;
  final dot = body.indexOf('.');
  final whole = dot < 0 ? body : body.substring(0, dot);
  final frac = dot < 0 ? '' : body.substring(dot);
  final out = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
    out.write(whole[i]);
  }
  return '${negative ? '-' : ''}$out$frac';
}

// ───────────────────────── 宽松 JSON ─────────────────────────

/// 去掉 `//`、`/* */` 注释和 `}` / `]` 前的尾逗号（跳过字符串里的内容）。
/// 只在严格解析失败时用。
String _relaxJson(String text) {
  final out = StringBuffer();
  var i = 0;
  var inString = false;
  int? pendingComma;
  final buffer = <int>[];

  void flushComma() {
    if (pendingComma != null) {
      out.writeCharCode(pendingComma!);
      pendingComma = null;
    }
    for (final c in buffer) {
      out.writeCharCode(c);
    }
    buffer.clear();
  }

  while (i < text.length) {
    final c = text.codeUnitAt(i);
    if (inString) {
      out.writeCharCode(c);
      if (c == 0x5C && i + 1 < text.length) {
        out.writeCharCode(text.codeUnitAt(i + 1));
        i += 2;
        continue;
      }
      if (c == 0x22) inString = false;
      i++;
      continue;
    }
    if (c == 0x2F && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1);
      if (next == 0x2F) {
        while (i < text.length && text.codeUnitAt(i) != 0x0A) {
          i++;
        }
        continue;
      }
      if (next == 0x2A) {
        final end = text.indexOf('*/', i + 2);
        i = end < 0 ? text.length : end + 2;
        continue;
      }
    }
    if (c == 0x2C) {
      flushComma();
      pendingComma = c;
      i++;
      continue;
    }
    if (pendingComma != null && (c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09)) {
      buffer.add(c);
      i++;
      continue;
    }
    if (pendingComma != null && (c == 0x7D || c == 0x5D)) {
      pendingComma = null;
    }
    flushComma();
    if (c == 0x22) inString = true;
    out.writeCharCode(c);
    i++;
  }
  flushComma();
  return out.toString();
}

// ───────────────────────── 摘要 ─────────────────────────

const _summaryPart = 40;
const _summaryCount = 8;

/// 复制 / 导出时代替整块 JSON 的一行（照 DS Bot `viewSummary`）：容器本身
/// 不出字，每个组件一小段，最多 8 段，每段最多 40 个字。
///
/// `[视图] 近 6 个月支出：月均=¥4,180；最高=¥5,920；图表：5月=3,800 元, …`
String xrkUiSummary(XrkUiView view) {
  final parts = <String>[];
  void visit(XrkUiNode node) {
    if (parts.length >= _summaryCount) return;
    final line = _componentSummary(node);
    if (line != null) parts.add(_summaryClip(line));
    if (node is XrkUiLayout) {
      for (final child in node.children) {
        if (parts.length >= _summaryCount) return;
        visit(child);
      }
    } else if (node is XrkUiControlContainer) {
      for (final child in node.children) {
        if (parts.length >= _summaryCount) return;
        visit(child);
      }
    }
  }

  visit(view.root);
  final title = view.title;
  final body = parts.join(appL10n.viewSemicolonSeparator);
  if (title == null) return appL10n.viewUiSummaryBody(body);
  return body.isEmpty ? appL10n.viewUiSummaryBody(title) : appL10n.viewUiSummaryTitleBody(title, body);
}

/// 源文本 → 一行摘要；画不了时给一句通用的。
String xrkUiSummaryOf(String source) => switch (parseXrkUi(source)) {
  XrkUiParsed(:final view) => xrkUiSummary(view),
  XrkUiInvalid() => appL10n.viewUiSummaryInvalid,
};

String _summaryClip(String text) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= _summaryPart ? flat : flat.substring(0, _summaryPart);
}

String? _componentSummary(XrkUiNode node) {
  String withUnit(double? v, String? unit) {
    if (v == null) return '—';
    final n = formatXrkUiNumber(v);
    if (unit == null || unit.isEmpty) return n;
    return unit == '%' ? '$n%' : '$n $unit';
  }

  return switch (node) {
    XrkUiLayout() || XrkUiControlContainer() => null,
    XrkUiInput(:final label) => label,
    XrkUiControlDisplay(:final text) => text,
    XrkUiText(:final text) => appL10n.viewUiSummaryText(text.trim()),
    XrkUiMetric(:final label, :final value) => '$label=$value',
    XrkUiChart(:final categories, :final series, :final unit) => appL10n.viewUiSummaryChart(
      [for (var i = 0; i < categories.length; i++) '${categories[i]}=${withUnit(series.first.values[i], unit)}']
          .join(', '),
    ),
    XrkUiCompare(:final items) => appL10n.viewUiSummaryCompare(items.map((i) => i.title).join('/')),
    XrkUiSteps(:final items) => appL10n.viewUiSummarySteps(items.map((i) => i.label).join('/')),
    XrkUiCallout(:final text) => appL10n.viewUiSummaryCallout(text.trim()),
    XrkUiOptions(:final options) => appL10n.viewUiSummaryOptions(options.map((o) => o.label).join('/')),
    final XrkUiConfirm c => appL10n.viewUiSummaryConfirm(c.confirmText, c.cancelText),
    XrkUiPlaceholder() || XrkUiEmpty() || XrkUiActions() || XrkUiImage() => null,
    XrkUiEmptyState(:final title) => title,
    XrkUiGallery(:final items) => [for (final i in items) ?i.image.alt].join('/'),
    XrkUiList(:final items) => items.map((i) => i.title).join('/'),
    XrkUiKeyValue(:final items) => [
      for (final i in items) '${i.label}=${i.value}',
    ].join(appL10n.viewSemicolonSeparator),
    XrkUiProgress(:final label, :final shown) => label == null ? shown : '$label=$shown',
    XrkUiTable(:final columns) => columns.map((c) => c.label).join('/'),
  };
}

/// 图表里的数（刻度、提示、摘要）：≥100 不带小数，≥10 一位，其余两位，
/// 去掉末尾的 0，千分位分组（照 DS Bot `formatNumber`）。
String formatXrkUiNumber(double value) {
  if (!value.isFinite) return '—';
  final abs = value.abs();
  if (abs >= 1e15) return value.toStringAsExponential(1);
  final digits = abs >= 100 ? 0 : (abs >= 10 ? 1 : 2);
  var fixed = value.toStringAsFixed(digits);
  if (digits > 0) fixed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  if (fixed == '-0') fixed = '0';
  return _group(fixed);
}

/// 紧凑的刻度：一万以上用「万」，一亿以上用「亿」。
String formatXrkUiCompact(double value) {
  if (!value.isFinite) return '—';
  final abs = value.abs();
  if (abs >= 1e16) return value.toStringAsExponential(0);
  if (AppLocale.isEnglish) {
    if (abs >= 1e9) {
      return appL10n.viewUiHundredMillion(formatXrkUiNumber(value / 1e9));
    }
    if (abs >= 1e6) {
      return appL10n.viewUiMillion(formatXrkUiNumber(value / 1e6));
    }
    if (abs >= 1e3) {
      return appL10n.viewUiTenThousand(formatXrkUiNumber(value / 1e3));
    }
  } else {
    if (abs >= 1e8) {
      return appL10n.viewUiHundredMillion(formatXrkUiNumber(value / 1e8));
    }
    if (abs >= 1e4) {
      return appL10n.viewUiTenThousand(formatXrkUiNumber(value / 1e4));
    }
  }
  return formatXrkUiNumber(value);
}

// ───────────────────────── 复制 / 导出 ─────────────────────────

/// 把 Markdown 里的 ```` ```xrk-ui ```` / legacy ```` ```dsh-ui ```` 块换成一行摘要。
/// 没闭合的块（被中断）也换掉；忘了写围栏的裸 JSON 先补上围栏再换。
/// 其他代码块原样保留。
String xrkUiPlainText(String markdown) {
  final repaired = fenceBareXrkUiViews(markdown);
  if (!repaired.contains('xrk-ui') && !repaired.contains('dsh-ui')) return repaired;
  final lines = repaired.split('\n');
  final out = <String>[];
  var i = 0;
  final open = RegExp(r'^(\s{0,3})(`{3,}|~{3,})\s*(?:xrk-ui|dsh-ui)\s*$');
  final anyOpen = RegExp(r'^\s{0,3}(`{3,}|~{3,})');
  while (i < lines.length) {
    final line = lines[i];
    final match = open.firstMatch(line);
    if (match == null) {
      // 别的围栏：整块照抄，里面的 xrk-ui / dsh-ui 字样不当作开头。
      final other = anyOpen.firstMatch(line);
      out.add(line);
      i++;
      if (other != null) {
        final fence = other.group(1)!;
        while (i < lines.length) {
          out.add(lines[i]);
          if (_closes(lines[i], fence)) {
            i++;
            break;
          }
          i++;
        }
      }
      continue;
    }
    final fence = match.group(2)!;
    final body = <String>[];
    i++;
    while (i < lines.length && !_closes(lines[i], fence)) {
      body.add(lines[i]);
      i++;
    }
    if (i < lines.length) i++;
    out.add('${match.group(1)}${xrkUiSummaryOf(body.join('\n'))}');
  }
  return out.join('\n');
}

bool _closes(String line, String fence) {
  final t = line.trim();
  if (t.length < fence.length) return false;
  final ch = fence[0];
  return t.split('').every((c) => c == ch);
}

/// 模型偶尔不写围栏:把视图 JSON 直接当正文发出来。渲染前把这些裸 JSON 补成
/// ```` ```xrk-ui ```` 围栏,后面的围栏链路就能照常画成卡片。
///
/// 只认「单独成段、能完整解析成视图」的 JSON 对象:行内提到的 JSON、已有围栏
/// 里的内容、还没写完的流式半截都原样保留。
String fenceBareXrkUiViews(String markdown) {
  if (!markdown.contains('{')) return markdown;
  final lines = markdown.split('\n');
  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    final fence = _openingFence(lines[i]);
    if (fence != null) {
      // 别人的围栏:整块照抄,里面的裸 JSON 不补。
      out.add(lines[i]);
      i++;
      while (i < lines.length) {
        out.add(lines[i]);
        final closed = _closes(lines[i], fence);
        i++;
        if (closed) break;
      }
      continue;
    }
    if (lines[i].trimLeft().startsWith('{')) {
      final block = _jsonBlockAt(lines, i);
      if (block != null && parseXrkUi(block.source) is XrkUiParsed) {
        out.add('```xrk-ui');
        out.add(block.source);
        out.add('```');
        i = block.end;
        continue;
      }
    }
    out.add(lines[i]);
    i++;
  }
  return out.join('\n');
}

/// 这一行开了一个围栏时返回围栏标记(``` 或 ~~~),否则 null。
String? _openingFence(String line) {
  final match = RegExp(r'^\s{0,3}(`{3,}|~{3,})').firstMatch(line);
  return match?.group(1);
}

/// 没有可选标注,最多扫这么多:再长也不会是视图。
const _bareViewScanLimit = 64 * 1024;

/// 从 [start] 行起的整体 JSON 对象;跨行、能配平才返回(流式半截返回 null)。
/// 对象所在的最后一行后面不能有别的内容 —— 只认单独成段的 JSON。
({String source, int end})? _jsonBlockAt(List<String> lines, int start) {
  final buffer = StringBuffer();
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < lines.length; i++) {
    final line = i == start ? lines[i].trimLeft() : lines[i];
    var consumed = line.length;
    for (var j = 0; j < line.length; j++) {
      final unit = line.codeUnitAt(j);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (unit == 0x5C) {
          escaped = true;
        } else if (unit == 0x22) {
          inString = false;
        }
        continue;
      }
      if (unit == 0x22) {
        inString = true;
      } else if (unit == 0x7B) {
        depth++;
      } else if (unit == 0x7D) {
        depth--;
        if (depth == 0) {
          consumed = j + 1;
          break;
        }
      }
    }
    if (i > start) buffer.write('\n');
    buffer.write(line);
    if (depth == 0 && !inString) {
      // 对象在这行的第 consumed 个字符收尾;后面只能有空白。
      if (line.substring(consumed).trim().isNotEmpty) return null;
      final source = buffer.toString().substring(0, buffer.length - (line.length - consumed)).trimRight();
      return (source: source, end: i + 1);
    }
    if (buffer.length > _bareViewScanLimit) return null;
  }
  return null;
}

// ───────────────────────── 缓存 ─────────────────────────

final _cache = _ParseCache(48);

class _ParseCache {
  _ParseCache(this.capacity);

  final int capacity;
  // Map 字面量就是 LinkedHashMap：按插入顺序，最旧的在最前。
  final _entries = <String, XrkUiParse>{};
  String? _language;

  XrkUiParse get(String source) {
    final language = AppLocale.current.languageCode;
    if (_language != language) {
      _entries.clear();
      _language = language;
    }
    final hit = _entries.remove(source);
    if (hit != null) {
      _entries[source] = hit;
      return hit;
    }
    final parsed = parseXrkUiUncached(source);
    _entries[source] = parsed;
    if (_entries.length > capacity) _entries.remove(_entries.keys.first);
    return parsed;
  }
}
