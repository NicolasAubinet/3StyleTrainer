import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// A tactile 3D "keycap" button echoing the app icon. Used for the alg-type
/// choices on the main menu. Colors come from the active palette.
class KeycapButton extends StatefulWidget {
  final String label;
  final String subtitle;
  final IconData? icon;
  // Custom icon builder; receives the resolved (palette-aware) icon color.
  final Widget Function(Color color)? iconBuilder;
  final bool enabled;
  final VoidCallback onTap;

  const KeycapButton({
    super.key,
    required this.label,
    required this.subtitle,
    this.icon,
    this.iconBuilder,
    required this.onTap,
    this.enabled = true,
  }) : assert(icon != null || iconBuilder != null);

  @override
  State<KeycapButton> createState() => _KeycapButtonState();
}

class _KeycapButtonState extends State<KeycapButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.enabled;

    final top = enabled ? p.keycapTop : p.keycapDisabledTop;
    final ridge = enabled ? p.keycapBottom : p.keycapDisabledBottom;
    final textColor = enabled ? p.keycapText : p.keycapDisabledText;
    final subColor = enabled ? p.keycapSubtext : p.keycapDisabledText;
    final pressed = _down && enabled;

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: enabled ? widget.onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        transform: Matrix4.translationValues(0, pressed ? 4 : 0, 0),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
        decoration: BoxDecoration(
          color: top,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            // Raised ridge under the cap.
            BoxShadow(
              color: ridge,
              offset: Offset(0, pressed ? 1 : 5),
              blurRadius: 0,
            ),
            if (enabled)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                offset: Offset(0, pressed ? 5 : 9),
                blurRadius: 16,
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(widget.label,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: textColor,
                        letterSpacing: -0.2)),
                widget.iconBuilder != null
                    ? widget.iconBuilder!(textColor)
                    : Icon(widget.icon, size: 20, color: textColor),
              ],
            ),
            const SizedBox(height: 3),
            Text(widget.subtitle,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: subColor)),
          ],
        ),
      ),
    );
  }
}
