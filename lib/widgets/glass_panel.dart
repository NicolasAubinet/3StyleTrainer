import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// A frosted-glass style panel: translucent fill + hairline border.
class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(15),
    this.radius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: p.panel,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.panelBorder),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// A single-row glass field: a label on the left and a trailing control.
class GlassField extends StatelessWidget {
  final String label;
  final Widget trailing;

  const GlassField({super.key, required this.label, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 14, color: p.textMuted)),
          ),
          trailing,
        ],
      ),
    );
  }
}
