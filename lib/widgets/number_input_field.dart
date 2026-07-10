import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tap_select_all.dart';

class NumberInputField extends StatefulWidget {
  final bool decimal;
  final bool signed;
  final Function(String)? onChanged;
  final Function(String)? onCommit;
  final String? defaultValue;

  const NumberInputField(
      {super.key,
      this.decimal = false,
      this.signed = false,
      this.onChanged,
      this.onCommit,
      this.defaultValue});

  @override
  State<NumberInputField> createState() => _NumberInputFieldState();
}

class _NumberInputFieldState extends State<NumberInputField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late String _lastCommitted;
  bool _hadFocus = false;

  @override
  void initState() {
    super.initState();
    _lastCommitted = widget.defaultValue ?? "";
    _controller = TextEditingController(text: _lastCommitted);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(NumberInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the field is reused for a different value (e.g. the menu flips the
    // same field between target and race time), follow the new default — but
    // only while unfocused, so we never clobber what the user is typing.
    if (!_focusNode.hasFocus && widget.defaultValue != oldWidget.defaultValue) {
      _lastCommitted = widget.defaultValue ?? "";
      _controller.text = _lastCommitted;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      _hadFocus = false;
      _commit();
    }
  }

  // Select all on the tap that focuses the field so it's easy to fully replace;
  // a further tap (already focused) positions the cursor where tapped.
  void _onTap() {
    if (!_hadFocus) {
      selectAllText(_controller);
      _hadFocus = true;
    }
  }

  void _commit() {
    var text = _controller.text;
    // Normalize a dangling trailing dot ("0." -> "0") so the parsed value is
    // clean whether the user committed with Tab, Enter or by tapping away.
    if (text.endsWith('.')) {
      text = text.substring(0, text.length - 1);
      _controller.text = text;
    }
    if (text == _lastCommitted) return;
    _lastCommitted = text;
    widget.onCommit?.call(text);
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      style: Theme.of(context).textTheme.labelSmall,
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(vertical: 4),
        border: InputBorder.none,
      ),
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.decimal,
        signed: widget.signed,
      ),
      onChanged: widget.onChanged,
      onTap: _onTap,
      // Tab, Enter and tapping outside all just drop focus; the focus listener
      // does the single commit, so a value can never revert on a rebuild.
      onTapOutside: (_) => _focusNode.unfocus(),
      onFieldSubmitted: (_) => _focusNode.unfocus(),
      controller: _controller,
      focusNode: _focusNode,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r"[0-9.]")),
        TextInputFormatter.withFunction((oldValue, newValue) {
          if (newValue.text.isEmpty) return newValue;
          if (!widget.decimal) {
            return int.tryParse(newValue.text) == null ? oldValue : newValue;
          }
          var value = newValue;
          // A leading "." is read as "0." so the user can start with the dot.
          if (value.text.startsWith('.')) {
            final base = value.selection.baseOffset;
            value = TextEditingValue(
              text: '0${value.text}',
              selection: TextSelection.collapsed(
                  offset: base >= 0 ? base + 1 : value.text.length + 1),
            );
          }
          // Allow intermediate states like "0." while typing; only reject a
          // genuinely malformed number (more than one decimal point).
          if ('.'.allMatches(value.text).length > 1) return oldValue;
          return value;
        }),
      ],
    );
  }
}
