import 'package:flutter/material.dart';

// Selects the entire contents of [controller].
void selectAllText(TextEditingController controller) {
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
}

// Drives the "first tap selects the whole field (easy to fully replace), a
// further tap positions the cursor where tapped" behaviour. Owns a [FocusNode]
// — wire it into the field, call [onTap] from the field's onTap, and [dispose]
// it alongside the field's State. Does not own [controller], so it never
// disposes it.
class TapSelectAll {
  final TextEditingController controller;
  final FocusNode focusNode;
  bool _hadFocus = false;

  TapSelectAll(this.controller) : focusNode = FocusNode() {
    focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!focusNode.hasFocus) _hadFocus = false;
  }

  // Runs after the field's own caret placement, so selecting all here wins on
  // the focusing tap; subsequent taps (already focused) leave the caret alone.
  void onTap() {
    if (!_hadFocus) {
      selectAllText(controller);
      _hadFocus = true;
    }
  }

  void dispose() {
    focusNode.removeListener(_onFocusChange);
    focusNode.dispose();
  }
}
