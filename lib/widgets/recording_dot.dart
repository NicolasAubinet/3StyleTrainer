import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// Small red dot shown while a session is recording solve times.
class RecordingDot extends StatelessWidget {
  final double size;

  const RecordingDot({super.key, this.size = 9});

  @override
  Widget build(BuildContext context) {
    final red = context.palette.bad;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: red,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: red.withValues(alpha: 0.5),
              blurRadius: 6,
              spreadRadius: 0.5),
        ],
      ),
    );
  }
}
