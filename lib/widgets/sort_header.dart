import 'package:flutter/material.dart';

import '../theme/theme_scope.dart';

/// Ascending / descending, with the arrow the column headers show.
enum SortDirection {
  ascending,
  descending;

  SortDirection get flipped =>
      this == ascending ? descending : ascending;

  bool get isAscending => this == ascending;

  String get arrow => this == ascending ? " ↑" : " ↓";
}

/// Which column a list is sorted by and in which direction, over a screen's own
/// column enum [C]. Shared by the lists that expose tappable sort headers.
class SortState<C> {
  C column;
  SortDirection direction;

  SortState({required this.column, required this.direction});

  bool isActive(C c) => column == c;

  /// Tapping the active column flips the direction; tapping another switches to
  /// it, starting from [whenSwitching].
  void toggle(C tapped, SortDirection whenSwitching) {
    if (column == tapped) {
      direction = direction.flipped;
    } else {
      column = tapped;
      direction = whenSwitching;
    }
  }
}

/// A tappable column header showing the label plus a sort arrow when active.
///
/// Pass [width] for a header sitting above a fixed-width value cell, so the
/// label lines up exactly with the values under it and the whole cell taps.
class SortHeader<C> extends StatelessWidget {
  final String label;
  final C column;
  final SortState<C> state;
  final ValueChanged<C> onSort;
  final double? width;
  final TextAlign align;

  const SortHeader({
    super.key,
    required this.label,
    required this.column,
    required this.state,
    required this.onSort,
    this.width,
    this.align = TextAlign.left,
  });

  // The labels are tiny, so the tap target is grown vertically instead — this
  // also keeps a mistap on a neighbouring control from hitting a header.
  static const double height = 34;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = state.isActive(column);
    final arrow = active ? state.direction.arrow : "";
    final text = Text(
      "$label$arrow",
      textAlign: align,
      maxLines: 1,
      overflow: TextOverflow.clip,
      style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: active ? p.accent : p.textMuted),
    );
    return InkWell(
      onTap: () => onSort(column),
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: height,
        child: Align(
          alignment: align == TextAlign.right
              ? Alignment.centerRight
              : Alignment.centerLeft,
          widthFactor: 1,
          child: width == null ? text : SizedBox(width: width, child: text),
        ),
      ),
    );
  }
}
