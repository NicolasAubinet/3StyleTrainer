import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NumberInputField extends StatelessWidget {
  final bool decimal;
  final bool signed;
  final Function(String)? onChanged;
  final String? defaultValue;
  final textController = TextEditingController();

  NumberInputField(
      {this.decimal = false,
      this.signed = false,
      this.onChanged,
      this.defaultValue});

  @override
  Widget build(BuildContext context) {
    textController.text = defaultValue ?? "";

    return TextFormField(
      style: Theme.of(context).textTheme.labelSmall,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimal,
        signed: signed,
      ),
      onChanged: onChanged,
      controller: textController,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r"[0-9.]")),
        TextInputFormatter.withFunction((oldValue, newValue) {
          final text = newValue.text;
          if (text.isEmpty) {
            return newValue;
          } else if (decimal) {
            return double.tryParse(text) == null ? oldValue : newValue;
          } else {
            return int.tryParse(text) == null ? oldValue : newValue;
          }
        }),
      ],
    );
  }
}
