import 'package:flutter/material.dart';

import '../alg_structs.dart';

/// An isometric 3x3 cube whose highlighted stickers depict one [AlgType]:
/// corners, edges, a flipped edge pair, a twisted corner pair, or — for
/// Custom — a full colourful scramble. A muted grey is the "not this piece"
/// base so the coloured stickers read as the cases being drilled.
class CubeTypeIcon extends StatelessWidget {
  final AlgType type;
  final double size;

  const CubeTypeIcon({super.key, required this.type, this.size = 38});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CubePainter(_stickersFor(type))),
    );
  }
}

// Logical (unshaded) sticker colours; the painter darkens the side faces.
const Color _g = Color(0xFF8E8E88); // grey base ("not this piece")
const Color _w = Color(0xFFF2F2EA);
const Color _y = Color(0xFFFAC81E);
const Color _r = Color(0xFFE23A2C);
const Color _o = Color(0xFFF97316);
const Color _b = Color(0xFF2F6FE0);
const Color _n = Color(0xFF1FAE4D); // green

/// Three 3x3 faces (top, left, right) of logical sticker colours.
class _Stickers {
  final List<List<Color>> top;
  final List<List<Color>> left;
  final List<List<Color>> right;
  const _Stickers(this.top, this.left, this.right);
}

_Stickers _stickersFor(AlgType type) {
  switch (type) {
    case AlgType.Corner:
      // Every corner sticker coloured in its face colour.
      return const _Stickers(
        [
          [_w, _g, _w],
          [_g, _g, _g],
          [_w, _g, _w],
        ],
        [
          [_n, _g, _n],
          [_g, _g, _g],
          [_n, _g, _n],
        ],
        [
          [_r, _g, _r],
          [_g, _g, _g],
          [_r, _g, _r],
        ],
      );
    case AlgType.Edge:
      // Every edge sticker coloured in its face colour.
      return const _Stickers(
        [
          [_g, _w, _g],
          [_w, _g, _w],
          [_g, _w, _g],
        ],
        [
          [_g, _n, _g],
          [_n, _g, _n],
          [_g, _n, _g],
        ],
        [
          [_g, _r, _g],
          [_r, _g, _r],
          [_g, _r, _g],
        ],
      );
    case AlgType.TwoFlip:
      // Two edges shown flipped: the top (white) sticker moved onto the side
      // face, so white reads as "on the side". Rest of the cube stays grey.
      return const _Stickers(
        [
          [_g, _g, _g],
          [_g, _g, _r], // U-R edge: face colour sits on top
          [_g, _n, _g], // U-L edge: face colour sits on top
        ],
        [
          [_g, _w, _g], // U-L edge: white on the (left) side
          [_g, _g, _g],
          [_g, _g, _g],
        ],
        [
          [_g, _w, _g], // U-R edge: white on the (right) side
          [_g, _g, _g],
          [_g, _g, _g],
        ],
      );
    case AlgType.TwoTwist:
      // Two corners shown twisted: white rotated off the top onto a side face.
      // Rest of the cube stays grey.
      return const _Stickers(
        [
          [_g, _g, _r], // back-right corner: face colour on top
          [_g, _g, _g],
          [_g, _g, _n], // front corner: face colour on top
        ],
        [
          [_g, _g, _r], // front corner: red on the left side
          [_g, _g, _g],
          [_g, _g, _g],
        ],
        [
          [_w, _g, _w], // white twisted onto the right side (both corners)
          [_g, _g, _g],
          [_g, _g, _g],
        ],
      );
    case AlgType.Parity:
      // The exact sticker colours of a parity case (top=U, left=F, right=R).
      // UF/UR edges stay white-on-top (correctly oriented); UFR & URB corners
      // carry the swap — FUR shows blue. BUR (green) faces the hidden back.
      return const _Stickers(
        [
          [_g, _g, _r], // URB (U)
          [_g, _g, _w], // UR (U)
          [_g, _w, _r], // UF (U); UFR (U)
        ],
        [
          [_g, _r, _b], // FU (F); FUR (F)
          [_g, _g, _g],
          [_g, _g, _g],
        ],
        [
          [_w, _n, _w], // RUB (R); RU (green); RUF (R)
          [_g, _g, _g],
          [_g, _g, _g],
        ],
      );
    case AlgType.Custom:
      // A solved cube — clean, "your own complete sets".
      return const _Stickers(
        [
          [_w, _w, _w],
          [_w, _w, _w],
          [_w, _w, _w],
        ],
        [
          [_n, _n, _n],
          [_n, _n, _n],
          [_n, _n, _n],
        ],
        [
          [_r, _r, _r],
          [_r, _r, _r],
          [_r, _r, _r],
        ],
      );
  }
}

class _CubePainter extends CustomPainter {
  final _Stickers stickers;
  _CubePainter(this.stickers);

  static const double _cos30 = 0.8660254;
  static const double _gap = 0.12; // sticker inset toward its centre

  @override
  void paint(Canvas canvas, Size size) {
    final pad = size.width * 0.05;
    final u = (size.height - 2 * pad) / 6.0; // cube is ~6u tall
    final ax = Offset(_cos30 * u, 0.5 * u); // east-down
    final ay = Offset(-_cos30 * u, 0.5 * u); // west-down
    final dn = Offset(0, u); // straight down
    final apex = Offset(size.width / 2, pad);

    // Top brightest, right mid, left darkest — cheap directional shading.
    _drawFace(canvas, apex, ax, ay, stickers.top, 1.0);
    _drawFace(canvas, apex + ay * 3, ax, dn, stickers.left, 0.72);
    _drawFace(canvas, apex + ax * 3, ay, dn, stickers.right, 0.88);
  }

  void _drawFace(Canvas canvas, Offset origin, Offset uVec, Offset vVec,
      List<List<Color>> grid, double f) {
    // Dark backing shows through the sticker gaps and around the border.
    final bg = Path()
      ..moveTo(origin.dx, origin.dy)
      ..relativeLineTo(uVec.dx * 3, uVec.dy * 3)
      ..relativeLineTo(vVec.dx * 3, vVec.dy * 3)
      ..relativeLineTo(-uVec.dx * 3, -uVec.dy * 3)
      ..close();
    canvas.drawPath(bg, Paint()..color = _shade(const Color(0xFF17171C), f));

    for (int r = 0; r < 3; r++) {
      for (int c = 0; c < 3; c++) {
        final o = origin + uVec * c.toDouble() + vVec * r.toDouble();
        _drawSticker(canvas, o, uVec, vVec, _shade(grid[r][c], f));
      }
    }
  }

  void _drawSticker(
      Canvas canvas, Offset o, Offset uVec, Offset vVec, Color color) {
    final p0 = o;
    final p1 = o + uVec;
    final p2 = o + uVec + vVec;
    final p3 = o + vVec;
    final ctr = (p0 + p1 + p2 + p3) / 4;
    Offset ins(Offset p) => p + (ctr - p) * _gap;
    final a = ins(p0), b = ins(p1), cc = ins(p2), d = ins(p3);
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(cc.dx, cc.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  Color _shade(Color c, double f) =>
      Color.from(alpha: c.a, red: c.r * f, green: c.g * f, blue: c.b * f);

  @override
  bool shouldRepaint(_CubePainter old) => old.stickers != stickers;
}
