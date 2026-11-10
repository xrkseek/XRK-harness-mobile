// The Flutter side of the plugin-view blocks
// (docs/design/native-plugins-views.md §2.2, §4): list, keyValue, progress,
// table, actions, image, the empty state, restricted text, and the options /
// confirm variants that invoke the plugin instead of sending a reply; and the
// v2 emptyState and gallery (docs/design/plugin-ui-v3.md §4.2).

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../plugins/native/native_icons.dart' show nativeIcon;
import '../../common/pressable.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';
import 'xrk_ui_model.dart';
import 'xrk_ui_plugin.dart';
import 'xrk_ui_plugin_figures.dart';
import 'xrk_ui_plugin_styles.dart';
import 'xrk_ui_style.dart';
import 'xrk_ui_widgets.dart';

/// 插件视图的上下文：点按交给谁、同源图片怎么取、要不要播生长动画。
/// 有它就按插件视图画（options / confirm 走 invoke）；[onAction] 为 null 时
/// 只读：`actions`、`confirm` 不显示，`options` 只读，`list` 行不可点。
class XrkUiPluginScope extends InheritedWidget {
  const XrkUiPluginScope({super.key, this.onAction, this.imageResolver, this.animate = false, required super.child});

  final PluginActionHandler? onAction;
  final PluginImageResolver? imageResolver;
  final bool animate;

  bool get interactive => onAction != null;

  static XrkUiPluginScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<XrkUiPluginScope>();

  /// 插件视图里不画的组件（容器据此跳过，不留空位）：空的按钮组（没有
  /// 按钮就什么都不画，不写「暂无数据」）；只读时的按钮组和确认；以及只
  /// 装着它们的容器。
  static bool hides(BuildContext context, XrkUiNode node) {
    final scope = maybeOf(context);
    if (scope == null) return false;
    final readOnly = !scope.interactive;
    bool hidden(XrkUiNode n) => switch (n) {
      XrkUiEmpty(type: 'actions') => true,
      XrkUiActions() || XrkUiConfirm() => readOnly,
      XrkUiLayout(:final children) => children.isNotEmpty && children.every(hidden),
      _ => false,
    };
    return hidden(node);
  }

  @override
  bool updateShouldNotify(XrkUiPluginScope old) =>
      old.onAction != onAction || old.imageResolver != imageResolver || old.animate != animate;
}

/// 发一次 invoke，并记住哪些元素在等结果（小环、防重复点）。
mixin _Invoking<T extends StatefulWidget> on State<T> {
  final _busy = <Object>{};

  bool busy(Object key) => _busy.contains(key);

  Future<bool> invoke(Object key, PluginAction action) async {
    final handler = XrkUiPluginScope.maybeOf(context)?.onAction;
    if (handler == null || _busy.contains(key)) return false;
    setState(() => _busy.add(key));
    var ok = false;
    try {
      ok = await handler(action);
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() => _busy.remove(key));
    return ok;
  }
}

/// 值的显示：像数字的（可带 ≤ 2 个字的前缀，如「¥」「+」）按数字排——等宽，
/// 单位小一号；其余（「deepseek-v4」「正常」）整段按 [number] 样式，不拆。
TextSpan xrkUiValueSpan(String text, {required TextStyle number, required TextStyle unit}) {
  if (_numberish.hasMatch(text)) {
    return xrkUiNumberSpan(text, number: number, unit: unit);
  }
  return TextSpan(text: text, style: number);
}

final _numberish = RegExp(r'^\s*[^\d\s]{0,2}\s*[-+−]?\d');

Color? xrkUiToneColor(BuildContext context, XrkUiTone? tone) {
  final dsh = XrkColors.of(context);
  return switch (tone) {
    XrkUiTone.good => dsh.success,
    XrkUiTone.warn => dsh.warning,
    XrkUiTone.bad => dsh.danger,
    XrkUiTone.info => dsh.info,
    XrkUiTone.muted => dsh.textTertiary,
    null => null,
  };
}

/// 一个小环（等 invoke 返回）。
class _Spinner extends StatelessWidget {
  const _Spinner({this.size = 16, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(strokeWidth: 2, color: color ?? Theme.of(context).colorScheme.primary),
  );
}

// ───────────────────────── 文字 ─────────────────────────

/// 插件视图的 `text`：段落、换行、`**粗体**`、`` `行内代码` ``。链接只显示
/// 文字，图片只显示替代文字；其余按原文。不经 Markdown，不会加载任何东西。
class XrkUiPlainText extends StatelessWidget {
  const XrkUiPlainText(this.text, {super.key, this.muted = false});

  final String text;
  final bool muted;

  static final _inline = RegExp(r'\*\*(.+?)\*\*|`([^`\n]+)`|!\[([^\]\n]*)\]\([^)\n]*\)|\[([^\]\n]+)\]\([^)\n]*\)');

  static List<InlineSpan> spans(String text, TextStyle style, TextStyle code) {
    final out = <InlineSpan>[];
    var at = 0;
    for (final m in _inline.allMatches(text)) {
      if (m.start > at) out.add(TextSpan(text: text.substring(at, m.start)));
      if (m.group(1) case final bold?) {
        out.add(
          TextSpan(
            text: bold,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        );
      } else if (m.group(2) case final c?) {
        out.add(TextSpan(text: c, style: code));
      } else {
        out.add(TextSpan(text: m.group(3) ?? m.group(4)));
      }
      at = m.end;
    }
    if (at < text.length) out.add(TextSpan(text: text.substring(at)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = muted
        ? AppType.chatBody(context, scale: 0.9, color: theme.colorScheme.onSurfaceVariant)
        : AppType.chatBody(context, color: theme.colorScheme.onSurface);
    final code = AppType.mono(
      size: (style.fontSize ?? 16) * 0.88,
      color: style.color,
      height: style.height ?? 1.55,
    ).copyWith(backgroundColor: context.xrkUiWell);
    final paragraphs = text
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Text.rich(TextSpan(style: style, children: spans(paragraphs[i], style, code))),
        ],
      ],
    );
  }
}

// ───────────────────────── 空 / 占位 ─────────────────────────

/// 数组取不到或为空：浅底井里一行「暂无数据」。
class XrkUiEmptyBlock extends StatelessWidget {
  const XrkUiEmptyBlock({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(color: context.xrkUiWell, shape: Squircle.border(XrkUiMetrics.wellRadius)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
        child: Text(
          context.l10n.plugViewEmpty,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: XrkColors.of(context).textTertiary),
        ),
      ),
    );
  }
}

// ───────────────────────── list ─────────────────────────

class XrkUiListBlock extends StatefulWidget {
  const XrkUiListBlock({super.key, required this.node});

  final XrkUiList node;

  /// 单行 / 两行的行高（页面设计 §4）。
  static const rowHeight = 52.0;
  static const twoLineHeight = 64.0;

  @override
  State<XrkUiListBlock> createState() => _XrkUiListBlockState();
}

class _XrkUiListBlockState extends State<XrkUiListBlock> with _Invoking {
  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final interactive = XrkUiPluginScope.maybeOf(context)?.interactive ?? false;
    final withIcons = node.items.any((i) => i.icon != null);
    return DecoratedBox(
      decoration: ShapeDecoration(color: context.xrkUiWell, shape: Squircle.border(XrkUiMetrics.wellRadius)),
      child: Squircle.clip(
        radius: XrkUiMetrics.wellRadius,
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < node.items.length; i++) _row(context, i, node.items[i], withIcons, interactive),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, int index, XrkUiListItem item, bool withIcons, bool interactive) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = XrkColors.of(context);
    final tone = xrkUiToneColor(context, item.tone);
    final action = interactive ? item.action : null;
    final waiting = busy(index);
    final subtitle = item.subtitle;
    final twoLines = subtitle != null && subtitle.isNotEmpty;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: twoLines ? XrkUiListBlock.twoLineHeight : XrkUiListBlock.rowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (withIcons) ...[
              SizedBox.square(
                dimension: 20,
                child: item.icon == null
                    ? null
                    : Icon(
                        nativeIcon(item.icon!) ?? AppIcons.running,
                        size: 20,
                        color: tone ?? colors.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurface),
                  ),
                  if (twoLines)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
                      ),
                    ),
                ],
              ),
            ),
            if (item.trailing case final trailing? when trailing.isNotEmpty) ...[
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text.rich(
                  xrkUiValueSpan(
                    trailing,
                    number: theme.textTheme.bodyMedium!.copyWith(color: tone ?? colors.onSurfaceVariant),
                    unit: theme.textTheme.bodySmall!.copyWith(color: tone ?? dsh.textTertiary),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(width: 8),
              SizedBox.square(
                dimension: 16,
                child: waiting
                    ? const _Spinner(size: 14)
                    : Icon(AppIcons.disclosure, size: 16, color: dsh.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null) {
      return MergeSemantics(child: row);
    }
    return Semantics(
      button: true,
      child: xrkUiPluginInkWell(
        context,
        onTap: waiting
            ? null
            : () => invoke(
                index,
                PluginAction(
                  id: action.id,
                  args: action.args,
                  source: PluginActionSource.row,
                  path: '${widget.node.path}.items[$index]',
                ),
              ),
        child: row,
      ),
    );
  }
}

// ───────────────────────── keyValue ─────────────────────────

class XrkUiKeyValueBlock extends StatelessWidget {
  const XrkUiKeyValueBlock({super.key, required this.node});

  final XrkUiKeyValue node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = XrkColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < node.items.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    node.items[i].label,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text.rich(
                    xrkUiValueSpan(
                      node.items[i].value,
                      number: theme.textTheme.bodyMedium!.copyWith(
                        color: xrkUiToneColor(context, node.items[i].tone) ?? colors.onSurface,
                      ),
                      unit: theme.textTheme.bodySmall!.copyWith(
                        color: xrkUiToneColor(context, node.items[i].tone) ?? dsh.textTertiary,
                      ),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ───────────────────────── progress ─────────────────────────

class XrkUiProgressBlock extends StatelessWidget {
  const XrkUiProgressBlock({super.key, required this.node});

  final XrkUiProgress node;

  static const barHeight = 6.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final styled = XrkUiPluginStyles.viewOf(context) != null;
    final fill = xrkUiToneColor(context, node.tone) ?? XrkUiPalette.of(context).first;
    final track = styled ? colors.surface : colors.onSurface.withValues(alpha: dark ? 0.12 : 0.08);
    final fraction = node.fraction ?? 0;
    if (node.ring) {
      // Opaque: the ring's track sits on the view's verified background.
      final ringTrack = Color.alphaBlend(colors.onSurface.withValues(alpha: dark ? 0.16 : 0.10), colors.surface);
      return Center(
        child: XrkUiRing(fraction: node.fraction, shown: node.shown, color: fill, track: ringTrack, label: node.label),
      );
    }
    return Semantics(
      label: node.label,
      value: node.shown,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    node.label ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurface),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  node.shown,
                  maxLines: 1,
                  style: AppType.tabular(theme.textTheme.bodySmall!.copyWith(color: colors.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: barHeight,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  color: track,
                  shape: StadiumBorder(side: styled ? BorderSide(color: colors.outline) : BorderSide.none),
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AnimatedFractionallySizedBox(
                    duration: AppMotion.of(context, AppMotion.standard),
                    curve: AppMotion.std,
                    widthFactor: fraction,
                    heightFactor: 1,
                    child: fraction <= 0
                        ? null
                        : DecoratedBox(
                            decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── table ─────────────────────────

/// 表格：表头一条细线，行间不画线；数字列右对齐、等宽数字；放不下时
/// 横向滑动。首列贴左缘、末列贴右缘，列间 24。
class XrkUiTableBlock extends StatelessWidget {
  const XrkUiTableBlock({super.key, required this.node});

  final XrkUiTable node;

  static const maxColumn = 200.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = XrkColors.of(context);
    final head = theme.textTheme.bodySmall!.copyWith(color: dsh.textTertiary, fontWeight: FontWeight.w500);
    final body = theme.textTheme.bodyMedium!.copyWith(color: colors.onSurface);
    final last = node.columns.length - 1;

    Widget cell(int c, String text, TextStyle style, {required bool header}) {
      final end = node.columns[c].align == XrkUiAlign.end;
      return Padding(
        padding: EdgeInsetsDirectional.fromSTEB(c == 0 ? 0 : 12, header ? 0 : 8, c == last ? 0 : 12, 8),
        child: Text(
          text,
          textAlign: end ? TextAlign.end : TextAlign.start,
          style: end && !header ? AppType.tabular(style) : style,
        ),
      );
    }

    final widths = <int, TableColumnWidth>{
      for (var c = 0; c <= last; c++)
        c: const MinColumnWidth(IntrinsicColumnWidth(flex: 1), FixedColumnWidth(maxColumn)),
    };
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: box.maxWidth),
          child: Table(
            columnWidths: widths,
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: colors.outlineVariant, width: 0.5)),
                ),
                children: [for (var c = 0; c <= last; c++) cell(c, node.columns[c].label, head, header: true)],
              ),
              for (final row in node.rows)
                TableRow(children: [for (var c = 0; c <= last; c++) cell(c, row[c], body, header: false)]),
            ],
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── actions ─────────────────────────

/// 按钮组：1–2 个并排等宽，3–4 个竖排。主按钮实心主色，其余浅底。
class XrkUiActionsBlock extends StatefulWidget {
  const XrkUiActionsBlock({super.key, required this.node});

  final XrkUiActions node;

  static const height = 44.0;

  @override
  State<XrkUiActionsBlock> createState() => _XrkUiActionsBlockState();
}

class _XrkUiActionsBlockState extends State<XrkUiActionsBlock> with _Invoking {
  @override
  Widget build(BuildContext context) {
    final items = widget.node.items;
    final interactive = XrkUiPluginScope.maybeOf(context)?.interactive ?? false;
    Widget button(int i) {
      final item = items[i];
      return XrkUiActionButton(
        label: item.label,
        icon: item.icon == null ? null : nativeIcon(item.icon!) ?? AppIcons.running,
        primary: item.primary,
        busy: busy(i),
        enabled: interactive && !busy(i),
        onTap: () => invoke(
          i,
          PluginAction(
            id: item.action.id,
            args: item.action.args,
            source: PluginActionSource.button,
            path: '${widget.node.path}.items[$i]',
          ),
        ),
      );
    }

    if (items.length <= 2) {
      if (XrkUiPluginStyles.viewOf(context) != null) {
        return XrkUiV2ActionRow(children: [for (var i = 0; i < items.length; i++) button(i)]);
      }
      return Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: button(i))],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[if (i > 0) const SizedBox(height: 8), button(i)],
      ],
    );
  }
}

/// 一个胶囊按钮（高 44）：主按钮实心主色，其余浅底。
class XrkUiActionButton extends StatelessWidget {
  const XrkUiActionButton({
    super.key,
    required this.label,
    this.icon,
    this.primary = false,
    this.busy = false,
    this.enabled = true,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool primary;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (XrkUiPluginStyles.viewOf(context) != null) {
      return XrkUiV2ActionButton(label: label, icon: icon, busy: busy, enabled: enabled, onTap: onTap);
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dsh = XrkColors.of(context);
    final Color fill;
    final Color fg;
    if (primary) {
      fill = enabled || busy ? colors.primary : colors.primary.withValues(alpha: 0.4);
      fg = colors.onPrimary;
    } else {
      fill = context.xrkUiWell;
      fg = enabled || busy ? colors.onSurface : dsh.textTertiary;
    }
    return Semantics(
      button: true,
      enabled: enabled,
      child: Pressable(
        enabled: enabled,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: enabled ? onTap : null,
              child: SizedBox(
                height: XrkUiActionsBlock.height,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: busy
                        ? _Spinner(size: 18, color: fg)
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 6)],
                              Flexible(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelLarge?.copyWith(color: fg),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── image ─────────────────────────

/// 把插件资源（`asset:icons/a.png`）换成带凭据的 [ImageProvider]（聊天页或
/// 面板上方放一个）。
class PluginImages extends InheritedWidget {
  const PluginImages({super.key, required this.resolver, required super.child});

  final PluginImageResolver resolver;

  static PluginImages? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PluginImages>();

  @override
  bool updateShouldNotify(PluginImages old) => old.resolver != resolver;
}

class XrkUiImageBlock extends StatelessWidget {
  const XrkUiImageBlock({super.key, required this.node});

  final XrkUiImage node;

  /// 图片最高多少（再高就按高度缩，居中）。
  static const maxHeight = 320.0;

  ImageProvider? _provider(BuildContext context, double width) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final target = (width * dpr).round().clamp(1, 2048);
    final ImageProvider? base = switch (node.source) {
      XrkUiDataImage(:final bytes) => MemoryImage(bytes),
      final XrkUiAssetImage asset =>
        (XrkUiPluginScope.maybeOf(context)?.imageResolver ?? PluginImages.maybeOf(context)?.resolver)?.call(asset.src),
      null => null,
    };
    if (base == null) return null;
    return ResizeImage(base, width: target, policy: ResizeImagePolicy.fit);
  }

  double? get _ratio => switch (node.source) {
    _ when node.aspect != null => node.aspect,
    XrkUiDataImage(:final width, :final height) => (width / height).clamp(0.25, 4.0),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dsh = XrkColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final ratio = _ratio ?? 16 / 9;
            var width = box.maxWidth;
            var height = width / ratio;
            if (height > maxHeight) {
              height = maxHeight;
              width = height * ratio;
            }
            final provider = _provider(context, width);
            if (provider == null) {
              // 永远取不到（地址不合规、没有解析器）：一行占位，不占一张图的地方。
              return _Unavailable(width: box.maxWidth, height: 48);
            }
            final unavailable = _Unavailable(width: width, height: height);
            final Widget image = Image(
              image: provider,
              width: width,
              height: height,
              fit: node.aspect != null ? BoxFit.cover : BoxFit.contain,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) =>
                  frame == null && !sync ? _Unavailable(width: width, height: height, quiet: true) : child,
              errorBuilder: (context, error, stack) => unavailable,
            );
            return Center(
              child: Semantics(
                image: true,
                label: node.alt,
                child: Squircle.clip(radius: XrkUiMetrics.wellRadius, child: image),
              ),
            );
          },
        ),
        if (node.caption case final caption?) ...[
          const SizedBox(height: 8),
          Text(caption, style: theme.textTheme.bodySmall?.copyWith(color: dsh.textTertiary)),
        ],
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.width, required this.height, this.quiet = false});

  final double width;
  final double height;

  /// 加载中：只有浅底，没有字。
  final bool quiet;

  @override
  Widget build(BuildContext context) {
    final dsh = XrkColors.of(context);
    return Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(color: context.xrkUiWell, shape: Squircle.border(XrkUiMetrics.wellRadius)),
      alignment: Alignment.center,
      child: quiet
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.imageBroken, size: 16, color: dsh.textTertiary),
                const SizedBox(width: 8),
                Text(
                  context.l10n.plugViewImageUnavailable,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: dsh.textTertiary),
                ),
              ],
            ),
    );
  }
}

// ───────────────────────── options / confirm（插件） ─────────────────────────

/// 插件视图的选项：点按 invoke（单选 `{value}`、多选 `{values}`），先按
/// 选中画，失败退回；之后以插件推来的 `selected` 为准。只读时打勾、不可点。
class XrkUiPluginOptions extends StatefulWidget {
  const XrkUiPluginOptions({super.key, required this.node});

  final XrkUiOptions node;

  @override
  State<XrkUiPluginOptions> createState() => _XrkUiPluginOptionsState();
}

class _XrkUiPluginOptionsState extends State<XrkUiPluginOptions> with _Invoking {
  /// 点下后、插件更新 `selected` 之前的选中项。
  Set<String>? _local;

  @override
  void didUpdateWidget(XrkUiPluginOptions old) {
    super.didUpdateWidget(old);
    if (old.node != widget.node) _local = null;
  }

  Set<String> get _selected => _local ?? widget.node.selected.toSet();

  Future<void> _tap(XrkUiOption option) async {
    final node = widget.node;
    final before = _local;
    final Set<String> next;
    if (node.multi) {
      next = {..._selected};
      if (!next.remove(option.key)) next.add(option.key);
    } else {
      next = {option.key};
    }
    setState(() => _local = next);
    final ok = await invoke(
      option.key,
      PluginAction(
        id: node.id,
        args: node.multi
            ? {
                'values': [
                  for (final o in node.options)
                    if (next.contains(o.key)) o.key,
                ],
              }
            : {'value': option.key},
        source: PluginActionSource.option,
        path: node.path,
      ),
    );
    if (!ok && mounted) setState(() => _local = before);
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final interactive = (XrkUiPluginScope.maybeOf(context)?.interactive ?? false) && node.id.isNotEmpty;
    final selected = _selected;
    final waiting = node.options.any((o) => busy(o.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < node.options.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          XrkUiOptionRow(
            option: node.options[i],
            multi: node.multi,
            selected: selected.contains(node.options[i].key),
            answered: false,
            settled: false,
            busy: busy(node.options[i].key),
            enabled: interactive && !waiting,
            onTap: () => _tap(node.options[i]),
          ),
        ],
      ],
    );
  }
}

/// 插件视图的确认：一对按钮，点按 invoke `{confirmed}`。只读时不显示。
class XrkUiPluginConfirm extends StatefulWidget {
  const XrkUiPluginConfirm({super.key, required this.node});

  final XrkUiConfirm node;

  @override
  State<XrkUiPluginConfirm> createState() => _XrkUiPluginConfirmState();
}

class _XrkUiPluginConfirmState extends State<XrkUiPluginConfirm> with _Invoking {
  void _send(bool confirmed) => invoke(
    confirmed,
    PluginAction(
      id: widget.node.id,
      args: {'confirmed': confirmed},
      source: PluginActionSource.confirm,
      path: widget.node.path,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final interactive = (XrkUiPluginScope.maybeOf(context)?.interactive ?? false) && node.id.isNotEmpty;
    final waiting = busy(true) || busy(false);
    if (XrkUiPluginStyles.viewOf(context) != null) {
      return XrkUiV2ActionRow(
        children: [
          XrkUiV2ActionButton(
            label: node.cancelText,
            busy: busy(false),
            enabled: interactive && !waiting,
            onTap: () => _send(false),
          ),
          XrkUiV2ActionButton(
            label: node.confirmText,
            primary: true,
            busy: busy(true),
            enabled: interactive && !waiting,
            onTap: () => _send(true),
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: XrkUiConfirmButton(
            label: node.cancelText,
            primary: false,
            chosen: false,
            settled: false,
            busy: busy(false),
            enabled: interactive && !waiting,
            onTap: () => _send(false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: XrkUiConfirmButton(
            label: node.confirmText,
            primary: true,
            chosen: false,
            settled: false,
            busy: busy(true),
            enabled: interactive && !waiting,
            onTap: () => _send(true),
          ),
        ),
      ],
    );
  }
}

// ───────────────────────── 状态条 ─────────────────────────

/// 状态条预算：一行。text 的文字、metric 的「名称 值」、progress 的标签和
/// 百分比，用「 · 」连起来；别的组件跳过。
class XrkUiStripLine extends StatelessWidget {
  const XrkUiStripLine({super.key, required this.view});

  final XrkUiView view;

  static String textOf(XrkUiView view) {
    final parts = <String>[];
    for (final node in view.nodes) {
      final part = switch (node) {
        XrkUiText(:final text) => text.replaceAll(RegExp(r'\*\*|`'), '').replaceAll(RegExp(r'\s+'), ' ').trim(),
        XrkUiMetric(:final label, :final value) => '$label $value',
        XrkUiProgress(:final label, :final shown) => label == null ? shown : '$label $shown',
        _ => null,
      };
      if (part != null && part.isNotEmpty) parts.add(part);
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      textOf(view),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: AppType.tabular(theme.textTheme.bodySmall!.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    );
  }
}

// ───────────────────────── emptyState / gallery（v2） ─────────────────────────

/// The plugin a view belongs to, for the picture viewer's label
/// (`PluginFrame` puts it there).
class XrkUiSourceName extends InheritedWidget {
  const XrkUiSourceName({super.key, required this.name, required super.child});

  final String name;

  static String? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<XrkUiSourceName>()?.name;

  @override
  bool updateShouldNotify(XrkUiSourceName old) => old.name != name;
}

/// The measured geometry (`plugin_view_figures_test.dart`).
abstract final class XrkUiGalleryMetrics {
  static const gap = 8.0;
  static const radius = 8.0;

  /// A cell never gets narrower: fewer columns instead.
  static const minCell = 72.0;

  /// Content this wide or wider takes three columns when none were asked for.
  static const threeFrom = 320.0;
  static const captionGap = 4.0;

  static const emptyBadge = 48.0;
  static const emptyIcon = 24.0;
  static const emptyMaxWidth = 280.0;
  static const emptyPadding = 24.0;

  /// Badge → title and the last line → button (`EmptyView`'s compact size).
  static const emptyGap = 14.0;

  /// The button is as wide as its words, never narrower than this.
  static const emptyButtonMinWidth = 120.0;
}

/// `emptyState`: the app's compact empty look (`EmptyView`) — a round badge in
/// the view's accent, the title, a line, one plugin button as wide as its
/// words — centred.
class XrkUiEmptyStateBlock extends StatelessWidget {
  const XrkUiEmptyStateBlock({super.key, required this.node});

  final XrkUiEmptyState node;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    // Opaque, so the icon's contrast is against what is painted.
    final badge = Color.alphaBlend(colors.primary.withValues(alpha: dark ? 0.16 : 0.10), colors.surface);
    final actions = node.actions;
    return Center(
      key: const ValueKey('dsh-ui-empty-state'),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: XrkUiGalleryMetrics.emptyMaxWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: XrkUiGalleryMetrics.emptyPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                key: const ValueKey('dsh-ui-empty-badge'),
                width: XrkUiGalleryMetrics.emptyBadge,
                height: XrkUiGalleryMetrics.emptyBadge,
                decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Icon(
                  (node.icon == null ? null : nativeIcon(node.icon)) ?? AppIcons.empty,
                  size: XrkUiGalleryMetrics.emptyIcon,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: XrkUiGalleryMetrics.emptyGap),
              Text(
                node.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(color: colors.onSurface),
              ),
              if (node.message case final message?) ...[
                const SizedBox(height: 4),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
              if (actions != null && !XrkUiPluginScope.hides(context, actions)) ...[
                const SizedBox(height: XrkUiGalleryMetrics.emptyGap),
                _EmptyStateButton(node: actions),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyStateButton extends StatefulWidget {
  const _EmptyStateButton({required this.node});

  final XrkUiActions node;

  @override
  State<_EmptyStateButton> createState() => _EmptyStateButtonState();
}

class _EmptyStateButtonState extends State<_EmptyStateButton> with _Invoking {
  @override
  Widget build(BuildContext context) {
    final item = widget.node.items.single;
    final interactive = XrkUiPluginScope.maybeOf(context)?.interactive ?? false;
    return ConstrainedBox(
      key: const ValueKey('dsh-ui-empty-button'),
      constraints: const BoxConstraints(minWidth: XrkUiGalleryMetrics.emptyButtonMinWidth),
      child: IntrinsicWidth(
        child: XrkUiActionButton(
          label: item.label,
          icon: item.icon == null ? null : nativeIcon(item.icon!) ?? AppIcons.running,
          busy: busy(0),
          enabled: interactive && !busy(0),
          onTap: () => unawaited(
            invoke(
              0,
              PluginAction(
                id: item.action.id,
                args: item.action.args,
                source: PluginActionSource.button,
                // The emptyState's own `action`.
                path: widget.node.path,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How many columns a gallery gets at [width]: the asked number, else 3 from
/// [XrkUiGalleryMetrics.threeFrom] and 2 below; fewer while a cell would be
/// under [XrkUiGalleryMetrics.minCell].
int xrkUiGalleryColumns(double width, int? asked) {
  var columns = asked ?? (width >= XrkUiGalleryMetrics.threeFrom ? 3 : 2);
  while (columns > 1 && (width - XrkUiGalleryMetrics.gap * (columns - 1)) / columns < XrkUiGalleryMetrics.minCell) {
    columns--;
  }
  return columns;
}

/// `gallery`: equal cells, 8 apart, rows as high as their tallest caption. A
/// cell with an action invokes it; any other tap — and a long press on any
/// cell — opens the app's picture viewer on the whole set.
class XrkUiGalleryBlock extends StatefulWidget {
  const XrkUiGalleryBlock({super.key, required this.node});

  final XrkUiGallery node;

  @override
  State<XrkUiGalleryBlock> createState() => _XrkUiGalleryBlockState();
}

class _XrkUiGalleryBlockState extends State<XrkUiGalleryBlock> with _Invoking {
  ImageProvider? _full(BuildContext context, XrkUiImage image) => switch (image.source) {
    XrkUiDataImage(:final bytes) => MemoryImage(bytes),
    final XrkUiAssetImage asset =>
      (XrkUiPluginScope.maybeOf(context)?.imageResolver ?? PluginImages.maybeOf(context)?.resolver)?.call(asset.src),
    null => null,
  };

  void _view(BuildContext context, int index) {
    final pictures = <ViewerPicture>[];
    var at = 0;
    for (var i = 0; i < widget.node.items.length; i++) {
      final item = widget.node.items[i];
      final provider = _full(context, item.image);
      if (provider == null) continue;
      if (i == index) at = pictures.length;
      final source = item.image.source;
      pictures.add(
        ViewerPicture(
          image: provider,
          name: item.image.alt ?? item.caption ?? context.l10n.plugViewGalleryPicture(i + 1),
          label: item.image.alt,
          bytes: source is XrkUiDataImage ? () async => source.bytes : () => xrkUiImageBytes(provider),
        ),
      );
    }
    if (pictures.isEmpty) return;
    XrkUiPictureViewer.maybeOf(context)?.call(context, pictures, at, XrkUiSourceName.maybeOf(context));
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final scope = XrkUiPluginScope.maybeOf(context);
    final interactive = scope?.interactive ?? false;
    final canView = XrkUiPictureViewer.maybeOf(context) != null;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final columns = xrkUiGalleryColumns(width, node.columns);
        final cell = (width - XrkUiGalleryMetrics.gap * (columns - 1)) / columns;
        final rows = <Widget>[];
        for (var start = 0; start < node.items.length; start += columns) {
          final end = (start + columns).clamp(0, node.items.length);
          final captioned = [for (var i = start; i < end; i++) node.items[i].caption != null].any((c) => c);
          if (rows.isNotEmpty) rows.add(const SizedBox(height: XrkUiGalleryMetrics.gap));
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: XrkUiGalleryMetrics.gap),
                  SizedBox(
                    width: cell,
                    child: start + c < end
                        ? _cell(context, start + c, cell, captioned, interactive, canView)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          );
        }
        return Column(
          key: const ValueKey('dsh-ui-gallery'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: rows,
        );
      },
    );
  }

  Widget _cell(BuildContext context, int index, double width, bool captioned, bool interactive, bool canView) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final item = widget.node.items[index];
    final height = width / widget.node.aspect;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final full = _full(context, item.image);
    final provider = full == null
        ? null
        : ResizeImage(full, width: (width * dpr).round().clamp(1, 1024), policy: ResizeImagePolicy.fit);
    final action = interactive ? item.action : null;
    final waiting = busy(index);
    // An opaque tile a shade off the view's surface, so a missing or loading
    // picture still holds its cell (the view's own well is the surface itself).
    final well = Color.alphaBlend(
      colors.onSurface.withValues(alpha: theme.brightness == Brightness.dark ? 0.08 : 0.05),
      colors.surface,
    );
    final placeholder = Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(color: well, shape: Squircle.border(XrkUiGalleryMetrics.radius)),
      alignment: Alignment.center,
      child: Icon(AppIcons.imageBroken, size: 20, color: colors.onSurfaceVariant),
    );
    Widget picture = provider == null
        ? placeholder
        : Squircle.clip(
            radius: XrkUiGalleryMetrics.radius,
            child: Image(
              image: provider,
              width: width,
              height: height,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, sync) => frame == null && !sync
                  ? Container(
                      width: width,
                      height: height,
                      decoration: ShapeDecoration(color: well, shape: Squircle.border(XrkUiGalleryMetrics.radius)),
                    )
                  : child,
              errorBuilder: (context, error, stack) => placeholder,
            ),
          );
    if (waiting) {
      picture = Stack(alignment: Alignment.center, children: [picture, const _Spinner(size: 20)]);
    }
    final VoidCallback? onTap = action != null
        ? () => unawaited(
            invoke(
              index,
              PluginAction(
                id: action.id,
                args: action.args,
                source: PluginActionSource.row,
                path: '${widget.node.path}.items[$index]',
              ),
            ),
          )
        : (canView && full != null ? () => _view(context, index) : null);
    final caption = item.caption;
    final alt = item.image.alt;
    final tap = waiting ? null : onTap;
    final longPress = canView && full != null ? () => _view(context, index) : null;
    // One node per cell: the picture's words, the caption as its value, and
    // the cell's own taps (the inner ones are left out, not doubled).
    return Semantics(
      key: ValueKey('dsh-ui-gallery-cell-$index'),
      container: true,
      excludeSemantics: true,
      image: true,
      button: tap != null,
      label: alt ?? caption,
      value: alt != null && caption != null && caption != alt ? caption : null,
      onTap: tap,
      onLongPress: longPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Pressable(onTap: tap, onLongPress: longPress, child: picture),
          if (captioned) ...[
            const SizedBox(height: XrkUiGalleryMetrics.captionGap),
            Text(
              caption ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// A picture of a plugin's gallery, for the app's viewer
/// (`MediaViewerPage.pictures`): already in memory or the plugin's own asset,
/// never a workspace file.
@immutable
class ViewerPicture {
  const ViewerPicture({required this.image, required this.name, this.label, this.bytes});

  final ImageProvider image;

  /// The title when it is the only one, and the file name when saved.
  final String name;

  /// What a screen reader says.
  final String? label;

  /// For 保存 and 分享; null leaves both out.
  final Future<Uint8List> Function()? bytes;
}

typedef XrkUiOpenPictures = void Function(
  BuildContext context,
  List<ViewerPicture> pictures,
  int index,
  String? source,
);

/// Who opens a gallery's pictures full screen; none (a preview, a test) and a
/// tap does nothing.
class XrkUiPictureViewer extends InheritedWidget {
  const XrkUiPictureViewer({super.key, required this.open, required super.child});

  final XrkUiOpenPictures open;

  static XrkUiOpenPictures? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<XrkUiPictureViewer>()?.open;

  @override
  bool updateShouldNotify(XrkUiPictureViewer old) => old.open != open;
}

/// The bytes behind [provider], as PNG: saving or sharing a plugin's own
/// (asset) picture, whose original bytes the app never holds.
Future<Uint8List> xrkUiImageBytes(ImageProvider provider) async {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  final image = await completer.future;
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('no bytes');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
