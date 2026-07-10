import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:three_style_trainer/widgets/number_input_field.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  testWidgets('commits the typed value on focus loss (Tab / tap outside)',
      (tester) async {
    final committed = <String>[];
    await tester.pumpWidget(_host(Column(children: [
      NumberInputField(
        decimal: true,
        defaultValue: "1.5",
        onCommit: committed.add,
      ),
      const TextField(), // something else to move focus to
    ])));

    await tester.enterText(find.byType(NumberInputField), "2.75");
    expect(committed, isEmpty); // not committed while still focused

    // Move focus away, as Tab or a click outside would.
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();

    expect(committed, ["2.75"]);
  });

  testWidgets('pressing Tab moves focus off the field and commits',
      (tester) async {
    final committed = <String>[];
    await tester.pumpWidget(_host(Column(children: [
      NumberInputField(
        decimal: true,
        defaultValue: "1.5",
        onCommit: committed.add,
      ),
      const TextField(), // Tab lands here
    ])));

    await tester.enterText(find.byType(NumberInputField), "2.75");
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();

    expect(committed, ["2.75"]);
  });

  testWidgets('backspace deletes characters', (tester) async {
    await tester.pumpWidget(_host(NumberInputField(defaultValue: "12")));
    await tester.tap(find.byType(NumberInputField));
    await tester.pump();

    await tester.enterText(find.byType(NumberInputField), "125");
    expect(find.text("125"), findsOneWidget);

    // Simulate a backspace: the controller is the source of truth.
    await tester.enterText(find.byType(NumberInputField), "12");
    expect(find.text("12"), findsOneWidget);
    await tester.enterText(find.byType(NumberInputField), "");
    expect(find.text("12"), findsNothing);
  });

  testWidgets('typing "." in an empty decimal field yields "0."',
      (tester) async {
    await tester.pumpWidget(_host(NumberInputField(decimal: true)));
    await tester.tap(find.byType(NumberInputField));
    await tester.pump();

    await tester.enterText(find.byType(NumberInputField), ".");
    expect(find.text("0."), findsOneWidget);

    await tester.enterText(find.byType(NumberInputField), ".5");
    expect(find.text("0.5"), findsOneWidget);
  });

  testWidgets('a trailing dot is allowed while typing but normalized on commit',
      (tester) async {
    final committed = <String>[];
    await tester.pumpWidget(_host(Column(children: [
      NumberInputField(
          decimal: true, defaultValue: "1", onCommit: committed.add),
      const TextField(),
    ])));

    await tester.enterText(find.byType(NumberInputField), "3.");
    expect(find.text("3."), findsOneWidget); // allowed mid-edit

    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(committed, ["3"]); // trailing dot dropped on commit
  });

  testWidgets('rejects a second decimal point', (tester) async {
    await tester.pumpWidget(_host(NumberInputField(decimal: true)));
    await tester.tap(find.byType(NumberInputField));
    await tester.pump();

    await tester.enterText(find.byType(NumberInputField), "1.5");
    await tester.enterText(find.byType(NumberInputField), "1.5.");
    expect(find.text("1.5"), findsOneWidget); // second dot rejected
  });

  testWidgets('a rebuild while focused does not revert the typed value',
      (tester) async {
    final committed = <String>[];
    late StateSetter setOuter;
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return NumberInputField(
          decimal: true,
          defaultValue: "1.5",
          onCommit: committed.add,
        );
      },
    )));

    await tester.enterText(find.byType(NumberInputField), "2.75");
    setOuter(() {}); // force a rebuild with the same defaultValue
    await tester.pump();

    expect(find.text("2.75"), findsOneWidget); // still what the user typed
    expect(committed, isEmpty);
  });

  testWidgets('follows an externally changed defaultValue while unfocused',
      (tester) async {
    late StateSetter setOuter;
    String value = "1.5";
    await tester.pumpWidget(_host(StatefulBuilder(
      builder: (context, setState) {
        setOuter = setState;
        return NumberInputField(decimal: true, defaultValue: value);
      },
    )));

    expect(find.text("1.5"), findsOneWidget);

    setOuter(() => value = "3.0"); // e.g. menu flips target -> race time
    await tester.pump();

    expect(find.text("3.0"), findsOneWidget);
  });

  testWidgets('commits only once per change, not on an unchanged blur',
      (tester) async {
    final committed = <String>[];
    await tester.pumpWidget(_host(Column(children: [
      NumberInputField(defaultValue: "10", onCommit: committed.add),
      const TextField(),
    ])));

    // Focus then blur without editing -> no commit.
    await tester.tap(find.byType(NumberInputField));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(committed, isEmpty);

    // Edit then blur -> one commit.
    await tester.enterText(find.byType(NumberInputField), "20");
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(committed, ["20"]);
  });

  testWidgets('the focusing tap selects the whole value', (tester) async {
    await tester.pumpWidget(_host(NumberInputField(defaultValue: "12.34")));

    await tester.tap(find.byType(NumberInputField));
    await tester.pumpAndSettle();

    final selection =
        tester.widget<EditableText>(find.byType(EditableText)).controller.selection;
    expect(selection, const TextSelection(baseOffset: 0, extentOffset: 5));
  });

  testWidgets('re-focusing after a blur selects all again', (tester) async {
    await tester.pumpWidget(_host(Column(children: [
      NumberInputField(defaultValue: "12.34"),
      const TextField(),
    ])));

    await tester.tap(find.byType(NumberInputField));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField).last); // blur
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NumberInputField)); // focus again
    await tester.pumpAndSettle();

    final selection =
        tester.widget<EditableText>(find.byType(EditableText).first).controller.selection;
    expect(selection, const TextSelection(baseOffset: 0, extentOffset: 5));
  });
}
