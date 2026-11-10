import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/l10n.dart';
import '../terminal/terminal_palette.dart';
import '../theme/app_icons.dart';
import '../theme/theme.dart';
import '../common/brief_notice.dart';

final _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

/// Product shell log prefix (Kotlin runtime / installer). Legacy `[dsh-app]` still highlighted.
const kAppLogPrefix = '[xrkh-app]';
const kAppLogPrefixLegacy = '[dsh-app]';

/// Strips ANSI escape sequences (XRK and node colour their output).
String stripAnsi(String line) => line.replaceAll(_ansi, '');

bool _isAppLogLine(String line) =>
    line.startsWith(kAppLogPrefix) || line.startsWith(kAppLogPrefixLegacy);

/// Live log well: monospace 12/1.5 in the code-well material.
///
/// Lines are chronological (oldest → newest). When the list grows, the view
/// sticks to the newest line unless the user has scrolled up. Sparse logs sit
/// at the **top** of the well — a reversed ListView used to leave a huge blank
/// band above a handful of install lines.
///
/// [terminal] draws it as a bare dark terminal (dark palette in both themes,
/// no well of its own) for [TerminalCard].
class LogView extends StatefulWidget {
  const LogView({super.key, required this.lines, this.emptyText, this.terminal = false});

  final List<String> lines;
  final String? emptyText;
  final bool terminal;

  @override
  State<LogView> createState() => _LogViewState();
}

class _LogViewState extends State<LogView> {
  final _controller = ScrollController();
  int _lastLen = 0;
  bool _stickToEnd = true;

  @override
  void initState() {
    super.initState();
    _lastLen = widget.lines.length;
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStick());
  }

  @override
  void didUpdateWidget(covariant LogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != _lastLen) {
      _lastLen = widget.lines.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStick());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    // Within ~48px of the bottom → keep following new lines.
    _stickToEnd = pos.maxScrollExtent - pos.pixels <= 48;
  }

  void _maybeStick() {
    if (!_stickToEnd || !_controller.hasClients) return;
    final max = _controller.position.maxScrollExtent;
    if (max <= 0) return;
    _controller.jumpTo(max);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = widget.terminal ? TerminalCard.colorsOf(context) : XrkColors.of(context);
    final accent = widget.terminal ? TerminalPalette.of(context).accent : Theme.of(context).colorScheme.primary;
    final base = AppType.monoSmall(color: colors.codeWellFg);
    final body = widget.lines.isEmpty
        ? Center(
            child: Text(widget.emptyText ?? l10n.phoneLogEmpty, style: base.copyWith(color: colors.textTertiary)),
          )
        : SelectionArea(
            child: ListView.builder(
              controller: _controller,
              padding: widget.terminal ? const EdgeInsets.fromLTRB(16, 4, 16, 14) : const EdgeInsets.fromLTRB(14, 12, 14, 12),
              itemCount: widget.lines.length,
              itemBuilder: (context, index) {
                final line = stripAnsi(widget.lines[index]);
                final Color color;
                if (_isAppLogLine(line)) {
                  color = accent;
                } else if (_looksLikeError(line)) {
                  color = colors.danger;
                } else {
                  color = colors.codeWellFg;
                }
                return Text(line, style: base.copyWith(color: color));
              },
            ),
          );
    if (widget.terminal) return body;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.codeWellBg,
        shape: AppShape.outlined(colors.codeWellBorder, width: 0.5),
      ),
      child: ClipRSuperellipse(borderRadius: AppShape.radiusMd, child: body),
    );
  }

  static bool _looksLikeError(String line) {
    final lower = line.toLowerCase();
    return lower.contains('error') || lower.contains('fatal') || lower.contains('exception');
  }
}

/// A dark terminal card (dark in light mode too): a title row with a quiet
/// count and copy / share, then the live [LogView].
///
/// ```
/// ╭──────────────────────────────────────╮
/// │ 日志  14 行                  ⧉   ⇪ │
/// │ [gateway] listening on 127.0.0.1…   │
/// ╰──────────────────────────────────────╯
/// ```
class TerminalCard extends StatelessWidget {
  const TerminalCard({
    super.key,
    required this.title,
    required this.lines,
    this.height,
    this.emptyText,
    this.command,
    this.countLabel,
    this.shareSubject,
  });

  final String title;
  final List<String> lines;

  /// A command shown under the title row (`\$ npm run dev`).
  final String? command;

  /// Replaces 「N 行」 next to the title.
  final String? countLabel;
  final String? shareSubject;

  /// Fixed height; null fills the parent.
  final double? height;
  final String? emptyText;

  /// The dark semantic colours of the current palette: the card is dark in
  /// both themes, its neutrals follow the palette.
  static XrkColors colorsOf(BuildContext context) =>
      XrkColors.forAccent(Brightness.dark, XrkSurfaces.of(context).accent);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = colorsOf(context);
    final background = TerminalPalette.of(context).background;
    final theme = Theme.of(context);
    final muted = colors.textTertiary;
    Widget action(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        foregroundColor: colors.codeWellFg,
        disabledForegroundColor: colors.textDisabled,
        highlightColor: Colors.white.withValues(alpha: 0.08),
      ),
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
    );
    final card = DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: RoundedSuperellipseBorder(
          borderRadius: AppShape.radiusLg,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.06), width: 0.5),
        ),
      ),
      child: ClipRSuperellipse(
        borderRadius: AppShape.radiusLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 5, 0),
              child: Row(
                children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(color: colors.codeWellFg)),
                  const SizedBox(width: 8),
                  Text(
                    countLabel ?? l10n.phoneLogLineCount(lines.length),
                    style: AppType.tabular(theme.textTheme.labelSmall!.copyWith(color: muted)),
                  ),
                  const Spacer(),
                  action(
                    AppIcons.copy,
                    l10n.phoneLogCopyAll,
                    lines.isEmpty ? null : () => LogActions.copy(context, lines),
                  ),
                  action(
                    AppIcons.share,
                    l10n.commonShare,
                    lines.isEmpty
                        ? null
                        : () => LogActions.share(lines, subject: shareSubject ?? l10n.phoneLogShareTitle),
                  ),
                ],
              ),
            ),
            if (command case final command?)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SelectableText('\$ $command', maxLines: 3, style: AppType.monoSmall(color: colors.codeWellFg)),
              ),
            Expanded(
              // Lines scrolled up melt into the title row instead of being cut.
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0xFF000000)],
                  stops: [0, 0.12],
                ).createShader(rect),
                child: LogView(lines: lines, emptyText: emptyText, terminal: true),
              ),
            ),
          ],
        ),
      ),
    );
    return height == null ? card : SizedBox(height: height, child: card);
  }
}

/// Copy / share helpers shared by the engine screen and the setup screen.
abstract final class LogActions {
  static String joined(List<String> lines) => lines.map(stripAnsi).join('\n');

  static Future<void> copy(BuildContext context, List<String> lines) async {
    await Clipboard.setData(ClipboardData(text: joined(lines)));
    if (!context.mounted) return;
    showBriefNotice(context, context.l10n.phoneLogCopiedLines(lines.length));
  }

  static Future<void> share(List<String> lines, {String? subject}) async {
    if (lines.isEmpty) return;
    await SharePlus.instance.share(ShareParams(text: joined(lines), subject: subject ?? appL10n.phoneLogShareTitle));
  }
}
