// A ```dsh-ui block written in another plugin's format (genui), drawn as a
// read-only plugin view (docs/design/plugin-ui-v3.md §3.2). Nothing in it can
// be tapped: what has no native counterpart already reads
// 「… · 在网页版查看」.
//
// The card is the view's own opaque surface (the colour every v2 contrast
// check is made against), at the size of the app's dsh-ui cards: radius 20,
// 16 all round. A glass card around it would show the surface as a second
// box inside the first.

import 'package:flutter/material.dart';

import '../../theme/theme.dart';
import '../media/media_viewer.dart' show openGalleryPictures;
import 'xrk_ui_blocks.dart';
import 'xrk_ui_model.dart';
import 'xrk_ui_plugin_styles.dart';
import 'xrk_ui_style.dart';
import 'xrk_ui_widgets.dart';

class XrkUiDialectCard extends StatelessWidget {
  const XrkUiDialectCard({super.key, required this.view, this.animate = false});

  final XrkUiView view;

  /// Charts grow once, right after the reply finished streaming.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final surface = Color(0xFF000000 | XrkUiPluginPalette.surface.at(dark));
    final ink = Color(0xFF000000 | XrkUiPluginPalette.ink.at(dark));
    final edge = Color(0xFF000000 | XrkUiPluginPalette.muted.at(dark)).withValues(alpha: 0.18);
    return DecoratedBox(
      key: const ValueKey('dsh-ui-dialect-card'),
      decoration: ShapeDecoration(
        color: surface,
        shape: Squircle.border(AppShape.lg, side: BorderSide(color: edge)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(XrkUiMetrics.cardPadding),
        child: XrkUiPluginScope(
          animate: animate,
          child: XrkUiPictureViewer(
            open: openGalleryPictures,
            child: XrkUiPluginStyles(
              view: view,
              boundary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (view.title case final title?) ...[
                    Semantics(
                      header: true,
                      child: Text(title, style: theme.textTheme.titleMedium?.copyWith(color: ink)),
                    ),
                    const SizedBox(height: 12),
                  ],
                  XrkUiNodeView(node: view.root),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
