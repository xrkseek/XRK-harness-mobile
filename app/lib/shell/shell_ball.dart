import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Draggable / collapsible settings ball for [LocalHostShell].
///
/// Product role and visibility: see `shell_ball_visibility.dart`.
/// Tap opens the shell quick panel (caller supplies [onTap]).
class ShellBall extends StatefulWidget {
  const ShellBall({
    super.key,
    required this.safeBottom,
    required this.safeTop,
    required this.onTap,
  });

  final double safeBottom;
  final double safeTop;
  final VoidCallback onTap;

  static const prefsDx = 'shell.ball.dx';
  static const prefsDy = 'shell.ball.dy';
  static const prefsCollapsed = 'shell.ball.collapsed';
  static const size = 48.0;
  static const collapsed = 28.0;

  @override
  State<ShellBall> createState() => _ShellBallState();
}

class _ShellBallState extends State<ShellBall> {
  double? _dx;
  double? _dy;
  var _collapsed = false;
  var _loaded = false;
  Offset? _dragOrigin;
  Offset? _startPos;

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _dx = p.getDouble(ShellBall.prefsDx);
        _dy = p.getDouble(ShellBall.prefsDy);
        _collapsed = p.getBool(ShellBall.prefsCollapsed) ?? false;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (_dx != null) await p.setDouble(ShellBall.prefsDx, _dx!);
      if (_dy != null) await p.setDouble(ShellBall.prefsDy, _dy!);
      await p.setBool(ShellBall.prefsCollapsed, _collapsed);
    } catch (_) {}
  }

  void _clamp(Size size) {
    final w = _collapsed ? ShellBall.collapsed : ShellBall.size;
    final h = _collapsed ? ShellBall.collapsed * 2.2 : ShellBall.size;
    final maxX = (size.width - w).clamp(0.0, size.width);
    final maxY = (size.height - h - widget.safeBottom).clamp(0.0, size.height);
    final minY = widget.safeTop + 8;
    _dx = (_dx ?? (size.width - w - 14)).clamp(0.0, maxX);
    _dy = (_dy ?? (size.height - h - widget.safeBottom - 18)).clamp(minY, maxY);
  }

  void _snapToEdge(Size size) {
    final w = _collapsed ? ShellBall.collapsed : ShellBall.size;
    final mid = size.width / 2;
    _dx = ((_dx ?? 0) + w / 2) < mid ? 0.0 : size.width - w;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final size = MediaQuery.sizeOf(context);
    _clamp(size);
    final w = _collapsed ? ShellBall.collapsed : ShellBall.size;
    final h = _collapsed ? ShellBall.collapsed * 2.2 : ShellBall.size;
    return Positioned(
      left: _dx,
      top: _dy,
      child: Semantics(
        button: true,
        label: '壳快捷入口',
        child: GestureDetector(
          onPanStart: (d) {
            _dragOrigin = d.globalPosition;
            _startPos = Offset(_dx!, _dy!);
          },
          onPanUpdate: (d) {
            if (_dragOrigin == null || _startPos == null) return;
            setState(() {
              _dx = _startPos!.dx + (d.globalPosition.dx - _dragOrigin!.dx);
              _dy = _startPos!.dy + (d.globalPosition.dy - _dragOrigin!.dy);
              _clamp(size);
            });
          },
          onPanEnd: (_) {
            setState(() {
              if (_collapsed) {
                _snapToEdge(size);
              }
            });
            unawaited(_persist());
            _dragOrigin = null;
            _startPos = null;
          },
          onTap: () {
            if (_collapsed) {
              setState(() => _collapsed = false);
              unawaited(_persist());
              return;
            }
            widget.onTap();
          },
          onLongPress: () {
            setState(() {
              _collapsed = !_collapsed;
              if (_collapsed) _snapToEdge(size);
              _clamp(size);
            });
            unawaited(_persist());
          },
          child: RepaintBoundary(
            child: Material(
              color: const Color(0xE6161618),
              elevation: 0,
              shape: _collapsed
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFF3A3A3E)),
                    )
                  : const CircleBorder(side: BorderSide(color: Color(0xFF3A3A3E))),
              child: SizedBox(
                width: w,
                height: h,
                child: Icon(
                  _collapsed
                      ? ((_dx ?? 0) < size.width / 2 ? Icons.chevron_right : Icons.chevron_left)
                      : Icons.apps,
                  color: const Color(0xFFE8E8E6),
                  size: _collapsed ? 18 : 22,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
