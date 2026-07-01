import 'package:flutter/material.dart';

/// Which piece type the icon depicts.
enum CubePiece { corners, edges }

/// A square border with four marks inside it. For [CubePiece.corners] the marks
/// sit in the four corners; for [CubePiece.edges] they sit at the middle of
/// each side. The two are identical except for the mark placement, so the
/// Corners and Edges keycaps read as opposites.
class CubePieceIcon extends StatelessWidget {
  final CubePiece piece;
  final Color color;
  final double size;

  const CubePieceIcon({
    super.key,
    required this.piece,
    required this.color,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CubePiecePainter(piece, color)),
    );
  }
}

class _CubePiecePainter extends CustomPainter {
  final CubePiece piece;
  final Color color;
  _CubePiecePainter(this.piece, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final stroke = w * 0.09;

    // Square border.
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final rect = Rect.fromLTWH(
        stroke / 2, stroke / 2, w - stroke, size.height - stroke);
    canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(w * 0.16)), border);

    // Marks.
    final fill = Paint()..color = color;
    final m = w * 0.22; // mark side
    final inset = w * 0.16; // distance of a mark from the border
    final r = Radius.circular(w * 0.05);
    final mid = (w - m) / 2;
    final far = w - inset - m;

    final List<Offset> spots = piece == CubePiece.corners
        ? [
            Offset(inset, inset),
            Offset(far, inset),
            Offset(inset, far),
            Offset(far, far),
          ]
        : [
            Offset(mid, inset), // top
            Offset(mid, far), // bottom
            Offset(inset, mid), // left
            Offset(far, mid), // right
          ];

    for (final s in spots) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(s.dx, s.dy, m, m), r),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_CubePiecePainter old) =>
      old.color != color || old.piece != piece;
}
