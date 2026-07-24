import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';

/// Swipe a row left to reveal a Delete button behind it; the row slides but is
/// not removed until the button is tapped (swiping back cancels). At most one
/// row is open at a time, coordinated through [openRow].
///
/// When [enabled] is false (nothing to delete) the row doesn't reveal a button;
/// a left-swipe instead fires [onDisabledSwipe].
///
/// [peekHint] rows briefly auto-reveal the button once, ever, to teach the
/// gesture — pass it on the first deletable row of a list (see [SwipeHint]).
class SwipeableRow extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final String deleteLabel;
  final VoidCallback onDelete;
  final VoidCallback? onDisabledSwipe;
  final Object rowId;
  final ValueNotifier<Object?> openRow;
  final double radius;
  final bool peekHint;

  const SwipeableRow({
    super.key,
    required this.child,
    required this.enabled,
    required this.deleteLabel,
    required this.onDelete,
    required this.rowId,
    required this.openRow,
    required this.radius,
    this.onDisabledSwipe,
    this.peekHint = false,
  });

  @override
  State<SwipeableRow> createState() => _SwipeableRowState();
}

class _SwipeableRowState extends State<SwipeableRow>
    with SingleTickerProviderStateMixin {
  static const double _revealWidth = 96;

  // 0 = closed, 1 = fully revealed.
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void initState() {
    super.initState();
    widget.openRow.addListener(_onOpenRowChanged);
    if (widget.enabled && widget.peekHint) _maybePeek();
  }

  @override
  void dispose() {
    widget.openRow.removeListener(_onOpenRowChanged);
    _ctrl.dispose();
    super.dispose();
  }

  // The first time any deletable list is shown, demonstrate the gesture once by
  // sliding this row partway open and settling it back. [SwipeHint] persists the
  // one-time flag so it never nags again.
  void _maybePeek() async {
    if (!await SwipeHint.claim()) return;
    if (!mounted) return;
    widget.openRow.value = widget.rowId;
    // Reveal the button fully, hold, then settle back — same travel as a manual
    // swipe so the demo matches what the gesture actually does.
    await _ctrl.animateTo(1, curve: Curves.easeOut);
    await Future.delayed(const Duration(milliseconds: 550));
    if (mounted) _close();
  }

  void _onOpenRowChanged() {
    if (widget.openRow.value != widget.rowId && _ctrl.value > 0) {
      _ctrl.animateTo(0, curve: Curves.easeOut);
    }
  }

  void _open() {
    widget.openRow.value = widget.rowId;
    _ctrl.animateTo(1, curve: Curves.easeOut);
  }

  void _close() {
    if (widget.openRow.value == widget.rowId) widget.openRow.value = null;
    _ctrl.animateTo(0, curve: Curves.easeOut);
  }

  // Accumulated horizontal drag over the current gesture, used to detect a
  // deliberate left-swipe.
  double _dragDx = 0;

  void _onDragStart(DragStartDetails d) {
    _dragDx = 0;
    // Claim the open slot up front so any other open row collapses before this
    // one reveals its button, rather than both showing at once.
    if (widget.enabled && widget.openRow.value != widget.rowId) {
      widget.openRow.value = widget.rowId;
    }
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dragDx += d.primaryDelta ?? 0;
    if (!widget.enabled) return;
    _ctrl.value = (_ctrl.value - d.primaryDelta! / _revealWidth).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (!widget.enabled) {
      if (_dragDx < -24 || v < -300) widget.onDisabledSwipe?.call();
      _dragDx = 0;
      return;
    }
    // Open on any deliberate left swipe (velocity, position, or distance) so a
    // quick swipe doesn't fold back.
    final openIt =
        v < -300 || (v <= 300 && (_ctrl.value > 0.5 || _dragDx < -24));
    if (openIt) {
      _open();
    } else {
      _close();
    }
    _dragDx = 0;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Tap the card to cancel (close) while it's open; no-op when closed.
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_ctrl.value > 0) _close();
      },
      child: widget.child,
    );
    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: AnimatedBuilder(
        animation: Listenable.merge([_ctrl, widget.openRow]),
        builder: (context, child) {
          // Only the row that owns the open slot shows its button, so a
          // superseded row hides it at once instead of during its slide-back.
          final showButton = widget.enabled &&
              _ctrl.value > 0 &&
              widget.openRow.value == widget.rowId;
          return Stack(
            children: [
              if (showButton)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerRight,
                    // Slide the button in from the right in step with the panel,
                    // so it's revealed progressively (Stack clips the rest).
                    child: Transform.translate(
                      offset: Offset(_revealWidth * (1 - _ctrl.value), 0),
                      child: _deleteButton(p),
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(-_revealWidth * _ctrl.value, 0),
                child: child,
              ),
            ],
          );
        },
        child: card,
      ),
    );
  }

  Widget _deleteButton(AppPalette p) {
    return Material(
      color: p.bad,
      borderRadius: BorderRadius.circular(widget.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.radius),
        onTap: widget.onDelete,
        child: SizedBox(
          width: _revealWidth,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.delete_outline, color: Colors.white, size: 20),
              const SizedBox(height: 2),
              Text(widget.deleteLabel,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one-time "swipe to delete" demonstration flag, shared across every list
/// that uses [SwipeableRow] so the hint plays once, ever.
class SwipeHint {
  static const String _prefKey = 'swipe_delete_hint_seen';
  static bool _claimedThisSession = false;

  /// Returns true at most once, ever: the first caller gets the demo and the
  /// flag is persisted so no later call — this session or any future one — does.
  static Future<bool> claim() async {
    if (_claimedThisSession) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefKey) ?? false) {
        _claimedThisSession = true;
        return false;
      }
      _claimedThisSession = true;
      await prefs.setBool(_prefKey, true);
      return true;
    } catch (_) {
      // Prefs momentarily unavailable — skip the demo rather than throw; a later
      // list can still show it.
      return false;
    }
  }
}
