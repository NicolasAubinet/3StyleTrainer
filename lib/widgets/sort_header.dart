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
class SortHeader<C> extends StatelessWidget {
  final String label;
  final C column;
  final SortState<C> state;
  final ValueChanged<C> onSort;

  const SortHeader({
    super.key,
    required this.label,
    required this.column,
    required this.state,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final active = state.isActive(column);
    final arrow = active ? state.direction.arrow : "";
    return InkWell(
      onTap: () => onSort(column),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Text("$label$arrow",
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
                color: active ? p.accent : p.textMuted)),
      ),
    );
  }
}
