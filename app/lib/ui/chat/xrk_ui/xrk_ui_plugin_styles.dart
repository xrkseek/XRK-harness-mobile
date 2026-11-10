// Rendering for the bounded view-v2 style vocabulary. V1 never enters here.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../theme/app_icons.dart';
import '../../theme/theme.dart';
import 'xrk_ui_blocks.dart';
import 'xrk_ui_model.dart';
import 'xrk_ui_plugin_figures.dart';
import 'xrk_ui_plugin_row.dart';
import 'xrk_ui_plugin_tones.dart';
import 'xrk_ui_widgets.dart';

Color _color(XrkUiColorPair pair, BuildContext context) =>
    Color(0xFF000000 | pair.at(Theme.of(context).brightness == Brightness.dark));

FontWeight _weight(XrkUiTextWeight value) => switch (value) {
  XrkUiTextWeight.regular => FontWeight.w400,
  XrkUiTextWeight.medium => FontWeight.w500,
  XrkUiTextWeight.semibold => FontWeight.w600,
  XrkUiTextWeight.bold => FontWeight.w700,
};

TextAlign _textAlign(XrkUiStyleAlign value) => switch (value) {
  XrkUiStyleAlign.start => TextAlign.start,
  XrkUiStyleAlign.center => TextAlign.center,
  XrkUiStyleAlign.end => TextAlign.end,
};

/// Preferred usable width shared by columns and nested padding. A parent
/// that is already narrower keeps its full width instead of losing more to
/// decoration. The value is a layout preference, not a tight size constraint.
double xrkUiPluginContentMinWidth(BuildContext context) =>
    136 * (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 2.0);

/// The narrowest content a padded box keeps before its padding gives way:
/// two 48 dp targets side by side, scaled with the text.
double xrkUiPluginPaddedMinWidth(BuildContext context) =>
    96 * (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 2.0);

/// Apply equal padding on all four sides without repeatedly consuming the
/// space needed by a nested control. A card or grid cell keeps its full inset
/// while its content stays at least [xrkUiPluginPaddedMinWidth] wide, so text
/// never touches a visible edge on a phone; only deeper than that does the
/// padding shrink. No overflow, scaling or clipping is used to claim a larger
/// touch target than the width actually available.
EdgeInsets xrkUiPluginAdaptivePadding(
  BuildContext context, {
  required double requested,
  required double availableWidth,
}) => EdgeInsets.all(math.min(requested, math.max(0, (availableWidth - xrkUiPluginPaddedMinWidth(context)) / 2)));

/// The ownership label and border are outside the author's tree. Even an
/// inline bitmap cannot paint over them, open an overlay or hide attribution.
class XrkUiPluginStyles extends StatelessWidget {
  const XrkUiPluginStyles({
    super.key,
    required this.view,
    required this.child,
    this.compact = false,
    this.boundary = true,
  });

  final XrkUiView view;
  final Widget child;
  final bool compact;

  /// The ownership label and border. Off only for a model reply drawn in
  /// another plugin's format (`XrkUiView.dialect`): that is the model
  /// speaking, inside the reply's own card, not a plugin's surface.
  final bool boundary;

  static XrkUiView? viewOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_StyleScope>()?.view;
  static XrkUiPluginStyle? styleOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StyleScope>()?.style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = _color(XrkUiPluginPalette.surface, context);
    final foreground = _color(XrkUiPluginPalette.ink, context);
    final muted = _color(XrkUiPluginPalette.muted, context);
    final rootStyle = view.styles[view.root.path];
    final accent = rootStyle == null ? theme.colorScheme.primary : _color(rootStyle.accent, context);
    final onAccent = Color(0xFF000000 | xrkUiReadableColor(0xFFFFFF, accent.toARGB32() & 0xFFFFFF));
    final colors = theme.colorScheme.copyWith(
      surface: background,
      onSurface: foreground,
      onSurfaceVariant: muted,
      primary: accent,
      onPrimary: onAccent,
    );
    if (!boundary) {
      return Theme(
        data: theme.copyWith(colorScheme: colors),
        child: _StyleScope(view: view, style: rootStyle, child: child),
      );
    }
    if (compact) {
      return ColoredBox(
        key: const ValueKey('plugin-v2-boundary'),
        color: background,
        child: Row(
          children: [
            Icon(
              AppIcons.plugin,
              key: const ValueKey('plugin-v2-attribution'),
              size: 14,
              color: muted,
              semanticLabel: context.l10n.plugViewV2Content,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRect(
                child: Theme(
                  data: theme.copyWith(colorScheme: colors),
                  child: child,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: context.l10n.plugViewV2Content,
      child: DecoratedBox(
        key: const ValueKey('plugin-v2-boundary'),
        decoration: ShapeDecoration(
          color: background,
          shape: Squircle.border(AppShape.md, side: BorderSide(color: muted.withValues(alpha: 0.35))),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Row(
                  key: const ValueKey('plugin-v2-attribution'),
                  children: [
                    Icon(AppIcons.plugin, size: 14, color: muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.l10n.plugViewV2Content,
                        style: theme.textTheme.labelSmall?.copyWith(color: muted),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ClipRect(
                child: Theme(
                  data: theme.copyWith(colorScheme: colors),
                  child: _StyleScope(view: view, style: rootStyle, child: child),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleScope extends InheritedWidget {
  const _StyleScope({required this.view, required this.style, required super.child});
  final XrkUiView view;
  final XrkUiPluginStyle? style;
  @override
  bool updateShouldNotify(_StyleScope old) => view != old.view || style != old.style;
}

/// A style is associated with the parsed node path; v1 node classes and
/// constructors do not carry v2 fields and keep their old rendering code.
class XrkUiStyledNode extends StatelessWidget {
  const XrkUiStyledNode({super.key, required this.node, required this.depth, required this.fallback});
  final XrkUiNode node;
  final int depth;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final view = XrkUiPluginStyles.viewOf(context);
    final style = view?.styles[node.path];
    if (view == null || style == null) return fallback;
    final content = switch (node) {
      final XrkUiLayout layout => _StyledLayout(node: layout, style: style, depth: depth),
      final XrkUiText text => XrkUiStyledText(text: text.text, style: style),
      final XrkUiMetric metric => _StyledMetric(node: metric, style: style),
      final XrkUiCallout callout => XrkUiStyledText(text: callout.text, style: style),
      _ => fallback,
    };
    final theme = Theme.of(context);
    final background = _color(style.background, context);
    Color readable(Color candidate) =>
        Color(0xFF000000 | xrkUiReadableColor(candidate.toARGB32() & 0xFFFFFF, background.toARGB32() & 0xFFFFFF));
    final foreground = readable(_color(XrkUiPluginPalette.ink, context));
    final muted = _color(style.muted, context);
    final accent = _color(style.accent, context);
    final onAccent = Color(0xFF000000 | xrkUiReadableColor(0xFFFFFF, accent.toARGB32() & 0xFFFFFF));
    final error = readable(theme.colorScheme.error);
    final onError = Color(0xFF000000 | xrkUiReadableColor(0xFFFFFF, error.toARGB32() & 0xFFFFFF));
    final semantics = XrkColors.of(context);
    final adjusted = semantics.copyWith(
      textTertiary: muted,
      textDisabled: muted,
      success: readable(semantics.success),
      warning: readable(semantics.warning),
      danger: readable(semantics.danger),
      info: readable(semantics.info),
    );
    return _StyleScope(
      view: view,
      style: style,
      child: Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            surface: background,
            onSurface: foreground,
            onSurfaceVariant: muted,
            primary: accent,
            onPrimary: onAccent,
            secondary: accent,
            onSecondary: onAccent,
            secondaryContainer: background,
            onSecondaryContainer: accent,
            tertiary: accent,
            onTertiary: onAccent,
            tertiaryContainer: background,
            onTertiaryContainer: accent,
            error: error,
            onError: onError,
            errorContainer: background,
            onErrorContainer: error,
            outline: muted,
            outlineVariant: muted,
            primaryContainer: background,
            onPrimaryContainer: accent,
          ),
          textTheme: theme.textTheme.apply(bodyColor: foreground, displayColor: foreground),
          extensions: [
            for (final extension in theme.extensions.values)
              if (extension is! XrkColors) extension,
            adjusted,
          ],
        ),
        child: content,
      ),
    );
  }
}

TextStyle _textStyle(BuildContext context, XrkUiPluginStyle style) {
  final base = style.size == XrkUiTextSize.mono
      ? AppType.mono(size: style.size.pixels, color: _color(style.foreground, context))
      : Theme.of(context).textTheme.bodyMedium!
            .copyWith(fontSize: style.size.pixels, color: _color(style.foreground, context), height: 1.5);
  return base.copyWith(
    fontWeight: _weight(style.weight),
    fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
    decoration: TextDecoration.combine([
      if (style.underline) TextDecoration.underline,
      if (style.strike) TextDecoration.lineThrough,
    ]),
  );
}

class XrkUiStyledText extends StatelessWidget {
  const XrkUiStyledText({super.key, required this.text, required this.style});
  final String text;
  final XrkUiPluginStyle style;

  @override
  Widget build(BuildContext context) {
    final base = _textStyle(context, style);
    final code = AppType.mono(
      size: style.size.pixels,
      color: base.color,
    ).copyWith(fontWeight: base.fontWeight, fontStyle: base.fontStyle, decoration: base.decoration);
    final spans = style.spans.isEmpty
        ? XrkUiPlainText.spans(text, base, code)
        : <InlineSpan>[
            for (final span in style.spans)
              TextSpan(
                text: span.text,
                style: (span.mono ? code : base).copyWith(
                  color: _color(span.color, context),
                  fontWeight: _weight(span.weight),
                  backgroundColor: span.background == null ? null : _color(span.background!, context),
                ),
              ),
          ];
    return SizedBox(
      width: double.infinity,
      child: Text.rich(
        TextSpan(style: base, children: spans),
        textAlign: _textAlign(style.align),
        maxLines: style.maxLines,
        overflow: style.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
      ),
    );
  }
}

class _StyledMetric extends StatelessWidget {
  const _StyledMetric({required this.node, required this.style});
  final XrkUiMetric node;
  final XrkUiPluginStyle style;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        node.label,
        textAlign: _textAlign(style.align),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _color(style.muted, context)),
      ),
      const SizedBox(height: 4),
      XrkUiStyledText(text: node.value, style: style),
      if (node.trend case final points?) ...[
        const SizedBox(height: 6),
        XrkUiTrendLine(points: points, color: xrkUiToneColor(context, node.tone) ?? _color(style.accent, context)),
      ],
      if (node.caption case final caption?) ...[
        const SizedBox(height: 4),
        Text(
          caption,
          textAlign: _textAlign(style.align),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _color(style.muted, context)),
        ),
      ],
    ],
  );
}

class _StyledLayout extends StatelessWidget {
  const _StyledLayout({required this.node, required this.style, required this.depth});
  final XrkUiLayout node;
  final XrkUiPluginStyle style;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final child in node.children)
        if (!XrkUiPluginScope.hides(context, child)) child,
    ];
    Widget child(XrkUiNode n) => XrkUiNodeView(node: n, depth: depth + 1);
    Widget gap() => style.dividers
        ? Padding(
            padding: EdgeInsets.symmetric(vertical: style.gap / 2),
            child: Divider(height: 1, thickness: 1, color: _color(style.accent, context)),
          )
        : SizedBox(height: style.gap);
    final Widget content;
    if (!node.row) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) gap(),
            Align(
              alignment: switch (style.align) {
                XrkUiStyleAlign.start => AlignmentDirectional.centerStart,
                XrkUiStyleAlign.center => AlignmentDirectional.center,
                XrkUiStyleAlign.end => AlignmentDirectional.centerEnd,
              },
              child: child(children[i]),
            ),
          ],
        ],
      );
    } else {
      content = LayoutBuilder(
        builder: (context, box) {
          if (children.isEmpty) return const SizedBox.shrink();
          final maxColumns = style.columns.isEmpty
              ? math.min(children.length, 3)
              : math.min(children.length, style.columns.length);
          var count = maxColumns;
          while (count > 1) {
            final weights = style.columns.isEmpty ? List.filled(count, 1) : style.columns.take(count).toList();
            final sum = weights.fold(0, (a, b) => a + b);
            final available = box.maxWidth - style.gap * (count - 1);
            if (weights.every((w) => available * w / sum >= xrkUiPluginContentMinWidth(context))) break;
            count--;
          }
          final weights = style.columns.isEmpty ? List.filled(count, 1) : style.columns.take(count).toList();
          final view = XrkUiPluginStyles.viewOf(context);
          // A visible container (card, tint or own background) is drawn at the
          // row's full height; other cells keep the row's vertical alignment.
          bool card(XrkUiNode n) {
            if (n is! XrkUiLayout) return false;
            final s = view?.styles[n.path];
            return s != null && (s.card != XrkUiCardStyle.plain || s.background != style.background);
          }

          Widget oneRow(int offset) {
            final row = XrkUiEqualRow(
              key: ValueKey('plugin-v2-row:${node.path}:$offset'),
              gap: style.gap,
              flex: weights,
              align: switch (style.align) {
                XrkUiStyleAlign.start => CrossAxisAlignment.start,
                XrkUiStyleAlign.center => CrossAxisAlignment.center,
                XrkUiStyleAlign.end => CrossAxisAlignment.end,
              },
              stretch: [for (var i = 0; i < count; i++) offset + i < children.length && card(children[offset + i])],
              children: [
                for (var i = 0; i < count; i++)
                  offset + i < children.length ? child(children[offset + i]) : const SizedBox.shrink(),
              ],
            );
            // The same structure with and without lines, so a wrap from two
            // columns to one never rebuilds a cell that stayed in place.
            if (!style.dividers) return row;
            final available = box.maxWidth - style.gap * (count - 1);
            final sum = weights.fold(0, (a, b) => a + b);
            var used = 0;
            final lines = <Widget>[];
            for (var i = 1; i < count && offset + i < children.length; i++) {
              used += weights[i - 1];
              lines.add(
                PositionedDirectional(
                  key: ValueKey('plugin-v2-divider:${node.path}:$offset:$i'),
                  start: available * used / sum + style.gap * (i - 0.5) - 0.5,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: ColoredBox(color: _color(style.accent, context)),
                ),
              );
            }
            // Dividers use the row's actual height, never an intrinsic pass.
            return Stack(children: [row, ...lines]);
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var offset = 0; offset < children.length; offset += count) ...[
                if (offset > 0) gap(),
                oneRow(offset),
              ],
            ],
          );
        },
      );
    }
    return DecoratedBox(
      key: ValueKey('plugin-v2-layout:${node.path}'),
      decoration: ShapeDecoration(
        color: _color(style.background, context),
        shape: Squircle.border(
          AppShape.md,
          side: style.card == XrkUiCardStyle.outlined
              ? BorderSide(color: _color(style.accent, context))
              : BorderSide.none,
        ),
      ),
      // In an equal-height row the card fills the row; its content keeps its
      // natural height at the top and sees the same constraints either way.
      child: XrkUiCellFill(
        child: LayoutBuilder(
          builder: (context, box) => Padding(
            key: ValueKey('plugin-v2-padding:${node.path}'),
            padding: xrkUiPluginAdaptivePadding(context, requested: style.padding, availableWidth: box.maxWidth),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Plugin-only action treatment: app corners, an accent outline, equal
/// padding and a minimum 48 dp target; never the system grant button style.
/// A [primary] action (the confirm side of `confirm`) adds a tonal accent
/// fill under the same outline — still not a solid fill with inverse text.
///
/// Existing list and option rows use the same state feedback through
/// [xrkUiPluginInkWell], without changing their v1 widget tree.
class XrkUiV2ActionButton extends StatefulWidget {
  const XrkUiV2ActionButton({
    super.key,
    required this.label,
    this.icon,
    this.busy = false,
    this.enabled = true,
    this.primary = false,
    required this.onTap,
  });
  final String label;
  final IconData? icon;
  final bool busy;
  final bool enabled;
  final bool primary;
  final VoidCallback onTap;

  @override
  State<XrkUiV2ActionButton> createState() => _XrkUiV2ActionButtonState();
}

class _XrkUiV2ActionButtonState extends State<XrkUiV2ActionButton> {
  bool _focused = false;
  bool _highlighted = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tones = XrkUiPluginTones.of(context);
    final style = XrkUiPluginStyles.styleOf(context);
    final accent = style == null ? Theme.of(context).colorScheme.primary : _color(style.accent, context);
    final foreground = widget.primary ? tones.onTint : accent;
    final shape = Squircle.border(
      AppShape.md,
      side: BorderSide(
        color: widget.primary ? tones.accentLine : accent,
        width: _focused || _highlighted || _hovered ? 2 : 1,
      ),
    );
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: Material(
        color: widget.primary ? tones.tint : Colors.transparent,
        shape: shape,
        child: InkWell(
          customBorder: shape,
          // State overlays would composite a different background underneath
          // text that may be exactly at the contrast floor. Use the outline
          // for pointer/keyboard feedback and retain the checked background.
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          onFocusChange: (value) => setState(() => _focused = value),
          onHighlightChanged: (value) => setState(() => _highlighted = value),
          onHover: (value) => setState(() => _hovered = value),
          onTap: widget.enabled ? widget.onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              key: ValueKey('plugin-v2-button-padding:${widget.label}'),
              padding: const EdgeInsets.all(12),
              child: Center(
                child: widget.busy
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                      )
                    : ExcludeSemantics(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.icon != null) ...[
                              Icon(widget.icon, size: 18, color: foreground),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                widget.label,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.labelLarge
                                    ?.copyWith(color: foreground, fontSize: 15),
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
    );
  }
}

/// Retains the legacy InkWell verbatim for v1. In v2, a focus/press outline
/// replaces translucent ink, keeping secondary text on its checked surface.
Widget xrkUiPluginInkWell(
  BuildContext context, {
  ShapeBorder? customBorder,
  VoidCallback? onTap,
  required Widget child,
}) => XrkUiPluginStyles.viewOf(context) == null
    ? InkWell(customBorder: customBorder, onTap: onTap, child: child)
    : _PluginInk(customBorder: customBorder, onTap: onTap, child: child);

class _PluginInk extends StatefulWidget {
  const _PluginInk({required this.customBorder, required this.onTap, required this.child});
  final ShapeBorder? customBorder;
  final VoidCallback? onTap;
  final Widget child;
  @override
  State<_PluginInk> createState() => _PluginInkState();
}

class _PluginInkState extends State<_PluginInk> {
  bool _focused = false;
  bool _highlighted = false;
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final shape = switch (widget.customBorder) {
      final OutlinedBorder border => border,
      _ => Squircle.border(AppShape.sm),
    };
    return InkWell(
      customBorder: shape,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      splashFactory: NoSplash.splashFactory,
      onFocusChange: (value) => setState(() => _focused = value),
      onHighlightChanged: (value) => setState(() => _highlighted = value),
      onHover: (value) => setState(() => _hovered = value),
      onTap: widget.onTap,
      child: DecoratedBox(
        key: const ValueKey('plugin-v2-ink-feedback'),
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: shape.copyWith(
            side: _focused || _highlighted || _hovered
                ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Equal heights within one row, even when a label wraps under large text.
/// Narrow hosts use a vertical group, preserving each actual target width.
class XrkUiV2ActionRow extends StatelessWidget {
  const XrkUiV2ActionRow({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (children.length > 1 &&
          box.maxWidth < children.length * xrkUiPluginContentMinWidth(context) + (children.length - 1) * 12) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
          ],
        );
      }
      return XrkUiEqualRow(
        gap: 12,
        flex: List.filled(children.length, 1),
        stretch: List.filled(children.length, true),
        children: children,
      );
    },
  );
}
