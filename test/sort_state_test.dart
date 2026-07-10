import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/widgets/sort_header.dart';

enum _Col { a, b }

void main() {
  test('tapping the active column flips direction', () {
    final s = SortState(column: _Col.a, direction: SortDirection.ascending);
    s.toggle(_Col.a, SortDirection.ascending);
    expect(s.column, _Col.a);
    expect(s.direction, SortDirection.descending);
    s.toggle(_Col.a, SortDirection.ascending);
    expect(s.direction, SortDirection.ascending);
  });

  test('tapping another column switches to it with the given direction', () {
    final s = SortState(column: _Col.a, direction: SortDirection.descending);
    s.toggle(_Col.b, SortDirection.descending);
    expect(s.column, _Col.b);
    expect(s.direction, SortDirection.descending);
    expect(s.isActive(_Col.b), isTrue);
    expect(s.isActive(_Col.a), isFalse);
  });

  test('SortDirection helpers', () {
    expect(SortDirection.ascending.isAscending, isTrue);
    expect(SortDirection.ascending.flipped, SortDirection.descending);
    expect(SortDirection.descending.arrow, " ↓");
  });
}
