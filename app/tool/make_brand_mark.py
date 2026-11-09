#!/usr/bin/env python3
"""Generates lib/ui/shell/brand_glyph.g.dart from the XRK petal mark.

Run from app/:

    python3 tool/make_brand_mark.py

Masters: the same path data as apps/web BrandMark / logo-mark.svg (and the
Android launcher vectors). Pure Python, no dependencies.
"""
from __future__ import annotations

import os
import re
import sys

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(APP, 'lib', 'ui', 'shell', 'brand_glyph.g.dart')

NUM = re.compile(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')

# Same geometry as packages/client/ui-primitives BrandMark / apps/web/public/logo-mark.svg.
PETALS = (
    'M86.406 81.629c2.27 1.72 4.44 3.51 6.59 5.37.82.69 1.63 1.38 2.46 2.09 '
    '25.71 22.47 43.77 54.11 61.54 82.91.61.98 1.22 1.96 1.84 2.96q2.94 4.74 '
    '5.85 9.48c.61.99 1.23 1.98 1.86 3 .57.93 1.13 1.85 1.72 2.81.25.41.25.41 '
    '1.53 2.49 1.18 2.21 1.97 3.77 2.2 6.26-.88 2.21-.88 2.21-2.33 4.67-.54.93'
    '-1.08 1.87-1.64 2.84-.61 1.03-1.21 2.06-1.84 3.12-1.3 2.26-2.61 4.52-3.9 '
    '6.79-.35.61-.69 1.21-1.05 1.83-3.83 6.73-7.4 13.59-10.98 20.46-6.04 11.56'
    '-12.24 23-18.88 34.23-.63 1.06-1.25 2.13-1.9 3.22-11.79 19.69-25.82 39.96'
    '-48.48 47.51-10.71 1.78-20.46.42-29.65-5.33-9.83-7.21-15.67-17.18-17.85'
    '-29.07-1.59-12.52 1.65-24.74 8.5-35.27 28.51-36.57 84.36-48.92 128-56-1'
    '-.19-2-.38-3.03-.57-90.61-17.27-90.61-17.27-121.97-35.43-.6-.35-1.21-.7'
    '-1.84-1.06-14.95-8.68-25.44-19.19-30.59-36-1.9-13.26-.35-25.85 7.75-36.88 '
    '17.57-21.44 43.9-21.45 66.09-6.43m228.871-5.274c2.02 1.45 3.87 2.98 5.72 '
    '4.64.61.51 1.21 1.01 1.83 1.52 8.02 7.18 12.62 17.85 13.39 28.48.43 14.55'
    '-4.03 26.78-13.97 37.5-35.73 33.85-97.7 41.13-144.25 49.5.71.14 1.42.27 '
    '2.16.41 98.75 18.95 98.75 18.95 125.84 55.66 7.55 11.69 10.51 24.99 7.89 '
    '38.76-3.53 12.6-10.16 21.1-21.23 27.73-8.46 4.6-18.61 4.78-27.84 2.32'
    '-35.78-12.49-54-59.52-70.19-90.41-4.88-9.28-9.9-18.43-15.36-27.38-.23-.38'
    '-.23-.38-1.37-2.3-.4-.64-.79-1.28-1.19-1.94-.92-2.4-.6-3.46.29-5.85.7-1.35 '
    '1.45-2.68 2.23-3.99.24-.39.24-.39 1.41-2.35.26-.42.26-.42 1.55-2.53.53-.88 '
    '1.07-1.76 1.62-2.67 62.44-102.54 62.44-102.54 98.19-111.46 11.36-2.66 '
    '23.17-1.66 33.28 4.36'
)
CROWN = (
    'M193.129 29.54c9.42 7.83 14.99 17.28 16.87 29.46 2.5 39.35-18.68 77.3-35 '
    '112h-2c-24.9-52.02-24.9-52.02-32-79-.33-1.27-.67-2.54-1.01-3.84-3.52-15.22'
    '-3.98-31.59 3.37-45.78 5.93-9.44 13.18-15.79 24.02-18.69 9.34-1.78 18.07.3 '
    '25.75 5.85'
)


def tokenize(d: str):
    out = []
    i = 0
    while i < len(d):
        c = d[i]
        if c in 'MmCcLlHhVvQqTtSsAaZz':
            out.append(c)
            i += 1
        elif c in ', \t\n\r':
            i += 1
        else:
            m = NUM.match(d, i)
            if not m:
                raise ValueError(repr(d[i:i + 20]))
            out.append(float(m.group()))
            i = m.end()
    return out


def expand(d: str):
    toks = tokenize(d)
    cmds = []
    i = 0
    cx = cy = sx = sy = 0.0

    def take(n):
        nonlocal i
        vals = toks[i:i + n]
        i += n
        return vals

    while i < len(toks):
        cmd = toks[i]
        if not isinstance(cmd, str):
            raise ValueError(f'expected cmd at {i}: {cmd}')
        i += 1
        if cmd == 'M':
            x, y = take(2)
            cx, cy = x, y
            sx, sy = x, y
            cmds.append(('M', x, y))
            while i < len(toks) and not isinstance(toks[i], str):
                x, y = take(2)
                cx, cy = x, y
                cmds.append(('L', x, y))
        elif cmd == 'm':
            dx, dy = take(2)
            cx, cy = cx + dx, cy + dy
            sx, sy = cx, cy
            cmds.append(('M', cx, cy))
            while i < len(toks) and not isinstance(toks[i], str):
                dx, dy = take(2)
                cx, cy = cx + dx, cy + dy
                cmds.append(('L', cx, cy))
        elif cmd == 'C':
            while i < len(toks) and not isinstance(toks[i], str):
                a, b, c, d_, e, f = take(6)
                cmds.append(('C', a, b, c, d_, e, f))
                cx, cy = e, f
        elif cmd == 'c':
            while i < len(toks) and not isinstance(toks[i], str):
                a, b, c, d_, e, f = take(6)
                cmds.append(('C', cx + a, cy + b, cx + c, cy + d_, cx + e, cy + f))
                cx, cy = cx + e, cy + f
        elif cmd == 'Q':
            while i < len(toks) and not isinstance(toks[i], str):
                a, b, c, d_ = take(4)
                c1x = cx + 2 / 3 * (a - cx)
                c1y = cy + 2 / 3 * (b - cy)
                c2x = c + 2 / 3 * (a - c)
                c2y = d_ + 2 / 3 * (b - d_)
                cmds.append(('C', c1x, c1y, c2x, c2y, c, d_))
                cx, cy = c, d_
        elif cmd == 'q':
            while i < len(toks) and not isinstance(toks[i], str):
                a, b, c, d_ = take(4)
                qx, qy = cx + a, cy + b
                ex, ey = cx + c, cy + d_
                c1x = cx + 2 / 3 * (qx - cx)
                c1y = cy + 2 / 3 * (qy - cy)
                c2x = ex + 2 / 3 * (qx - ex)
                c2y = ey + 2 / 3 * (qy - ey)
                cmds.append(('C', c1x, c1y, c2x, c2y, ex, ey))
                cx, cy = ex, ey
        elif cmd == 'L':
            while i < len(toks) and not isinstance(toks[i], str):
                x, y = take(2)
                cmds.append(('L', x, y))
                cx, cy = x, y
        elif cmd == 'l':
            while i < len(toks) and not isinstance(toks[i], str):
                dx, dy = take(2)
                cx, cy = cx + dx, cy + dy
                cmds.append(('L', cx, cy))
        elif cmd == 'H':
            while i < len(toks) and not isinstance(toks[i], str):
                x, = take(1)
                cmds.append(('L', x, cy))
                cx = x
        elif cmd == 'h':
            while i < len(toks) and not isinstance(toks[i], str):
                dx, = take(1)
                cx += dx
                cmds.append(('L', cx, cy))
        elif cmd == 'V':
            while i < len(toks) and not isinstance(toks[i], str):
                y, = take(1)
                cmds.append(('L', cx, y))
                cy = y
        elif cmd == 'v':
            while i < len(toks) and not isinstance(toks[i], str):
                dy, = take(1)
                cy += dy
                cmds.append(('L', cx, cy))
        elif cmd in 'Zz':
            cmds.append(('Z',))
            cx, cy = sx, sy
        else:
            raise ValueError(f'unsupported {cmd}')
    return cmds


def f(v: float) -> str:
    s = f'{v:.4f}'.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def dart_path(cmds, name: str) -> str:
    lines = [f'  static final Path {name} = Path()']
    for c in cmds:
        if c[0] == 'M':
            lines.append(f'    ..moveTo({f(c[1])}, {f(c[2])})')
        elif c[0] == 'L':
            lines.append(f'    ..lineTo({f(c[1])}, {f(c[2])})')
        elif c[0] == 'C':
            lines.append(
                f'    ..cubicTo({f(c[1])}, {f(c[2])}, {f(c[3])}, {f(c[4])}, {f(c[5])}, {f(c[6])})'
            )
        elif c[0] == 'Z':
            lines.append('    ..close()')
    return '\n'.join(lines) + ';'


def flatten(cmds, n=64):
    pts = []
    cur = None
    start = None
    for c in cmds:
        if c[0] == 'M':
            cur = (c[1], c[2])
            start = cur
            pts.append(cur)
        elif c[0] == 'L':
            cur = (c[1], c[2])
            pts.append(cur)
        elif c[0] == 'C':
            p0 = cur
            c1 = (c[1], c[2])
            c2 = (c[3], c[4])
            p3 = (c[5], c[6])
            for k in range(1, n + 1):
                t = k / n
                mt = 1 - t
                x = mt ** 3 * p0[0] + 3 * mt * mt * t * c1[0] + 3 * mt * t * t * c2[0] + t ** 3 * p3[0]
                y = mt ** 3 * p0[1] + 3 * mt * mt * t * c1[1] + 3 * mt * t * t * c2[1] + t ** 3 * p3[1]
                pts.append((x, y))
            cur = p3
        elif c[0] == 'Z' and start is not None:
            pts.append(start)
    return pts


def area_centroid(poly):
    a = cx = cy = 0.0
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        k = x0 * y1 - x1 * y0
        a += k
        cx += (x0 + x1) * k
        cy += (y0 + y1) * k
    a /= 2
    if abs(a) < 1e-12:
        return 0.0, poly[0][0], poly[0][1]
    return a, cx / (6 * a), cy / (6 * a)


def split_subpaths(cmds):
    subs = []
    cur = []
    for c in cmds:
        if c[0] == 'M' and cur:
            subs.append(cur)
            cur = [c]
        else:
            cur.append(c)
    if cur:
        subs.append(cur)
    return subs


def main():
    petals = expand(PETALS)
    crown = expand(CROWN)
    tot = cx = cy = 0.0
    xs = []
    ys = []
    for sub in split_subpaths(petals) + [crown]:
        pts = flatten(sub)
        xs += [p[0] for p in pts]
        ys += [p[1] for p in pts]
        a, x, y = area_centroid(pts)
        tot += a
        cx += a * x
        cy += a * y
    if abs(tot) < 1e-12:
        sys.exit('empty ink')
    cx, cy = cx / tot, cy / tot
    box = (min(xs), min(ys), max(xs), max(ys))
    w, h = box[2] - box[0], box[3] - box[1]

    out = f'''// GENERATED by tool/make_brand_mark.py from the XRK petal mark
// (same geometry as apps/web BrandMark / logo-mark.svg). Do not edit by hand;
// change the masters and re-run the tool.
//
// The XRK sunflower mark in the 348 design grid (scaled into the launcher's
// 108 grid by BrandMark / Android vector drawables).

// dart format off
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset, Path, Rect, Shader, Radius, RRect;

/// Paths, fills and measurements of the brand glyph (see `brand_mark.dart`).
abstract final class BrandGlyph {{
  /// Design grid of the petal masters.
  static const grid = 348.0;

  /// The glyph's ink box in the design grid.
  static const box = Rect.fromLTRB({f(box[0])}, {f(box[1])}, {f(box[2])}, {f(box[3])});

  /// Width / height of [box].
  static const aspect = {w / h:.6f};

  /// Visual centre: area centroid of the ink, in the design grid.
  static const centroid = Offset({f(cx)}, {f(cy)});

  /// The tile: the 72-unit visible square of the launcher icon (108 grid).
  static const tileBox = Rect.fromLTWH(18, 18, 72, 72);

  /// Side petals (cream / currentColor).
{dart_path(petals, 'petals')}

  /// Crown petal (amber accent).
{dart_path(crown, 'crown')}

  /// Rounded plate behind the mark on a tile.
  static final Path tile = Path()
    ..addRRect(RRect.fromRectAndRadius(tileBox, const Radius.circular(16)));

  static final Shader tileFill = ui.Gradient.linear(
    const Offset(18, 18),
    const Offset(90, 90),
    const [Color(0xFF141414), Color(0xFF2A2A2A)],
  );

  static const Color petalsLight = Color(0xFFE8E8E6);
  static const Color petalsDark = Color(0xFFE8E8E6);
  static const Color crownAccent = Color(0xFFEAB039);
}}
'''
    with open(OUT, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(out)
    print(
        f'wrote {os.path.relpath(OUT, APP)}: box {box}, aspect {w / h:.4f}, '
        f'centroid ({cx:.3f}, {cy:.3f}) = ({(cx - box[0]) / w:.4f}, {(cy - box[1]) / h:.4f}) of the box'
    )


if __name__ == '__main__':
    main()
