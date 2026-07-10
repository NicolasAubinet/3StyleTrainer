import 'package:flutter/material.dart';

import '../alg_structs.dart';
import '../l10n/app_localizations.dart';
import '../slowest.dart';
import '../theme/theme_scope.dart';
import 'app_segmented_control.dart';
import 'number_input_field.dart';

// Result of the sheet: the chosen mode/values (to persist) plus the alg names
// to drill. Null return means the user dismissed without starting.
class SlowestSelection {
  final SlowestMode mode;
  final int topN;
  final double thresholdSeconds;
  final List<String> algs;

  const SlowestSelection(this.mode, this.topN, this.thresholdSeconds, this.algs);
}

// Bottom sheet to configure a "Practice slowest" run for a given alg type. Shows
// the Top-N / threshold toggle, a value field, a live case count, and Start.
// [onChanged] fires whenever the mode/value changes so the caller can persist
// the choice even when the sheet is dismissed without starting.
Future<SlowestSelection?> showSlowestConfigSheet(
  BuildContext context, {
  required AlgType algType,
  required List<SlowestAlg> slowest,
  required SlowestMode mode,
  required int topN,
  required double thresholdSeconds,
  void Function(SlowestMode mode, int topN, double thresholdSeconds)? onChanged,
}) {
  return showModalBottomSheet<SlowestSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SlowestConfigSheet(
      algType: algType,
      slowest: slowest,
      initialMode: mode,
      initialTopN: topN,
      initialThresholdSeconds: thresholdSeconds,
      onChanged: onChanged,
    ),
  );
}

class _SlowestConfigSheet extends StatefulWidget {
  final AlgType algType;
  final List<SlowestAlg> slowest;
  final SlowestMode initialMode;
  final int initialTopN;
  final double initialThresholdSeconds;
  final void Function(SlowestMode mode, int topN, double thresholdSeconds)?
      onChanged;

  const _SlowestConfigSheet({
    required this.algType,
    required this.slowest,
    required this.initialMode,
    required this.initialTopN,
    required this.initialThresholdSeconds,
    this.onChanged,
  });

  @override
  State<_SlowestConfigSheet> createState() => _SlowestConfigSheetState();
}

class _SlowestConfigSheetState extends State<_SlowestConfigSheet> {
  late SlowestMode _mode = widget.initialMode;
  late int _topN = widget.initialTopN;
  late double _thresholdSeconds = widget.initialThresholdSeconds;

  List<String> get _selectedAlgs => selectSlowest(
        widget.slowest,
        mode: _mode,
        topN: _topN,
        thresholdMs: _thresholdSeconds * 1000,
      );

  void _notifyChanged() =>
      widget.onChanged?.call(_mode, _topN, _thresholdSeconds);

  void _start() {
    Navigator.pop(
      context,
      SlowestSelection(_mode, _topN, _thresholdSeconds, _selectedAlgs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedAlgs.length;

    final valueLabel = _mode == SlowestMode.topN
        ? l10n.slowestCountLabel
        : l10n.slowestThresholdLabel;
    final valueField = _mode == SlowestMode.topN
        ? NumberInputField(
            defaultValue: _topN.toString(),
            onCommit: (text) {
              final parsed = int.tryParse(text);
              if (parsed != null && parsed > 0) {
                setState(() => _topN = parsed);
                _notifyChanged();
              }
            },
          )
        : NumberInputField(
            decimal: true,
            defaultValue: _thresholdSeconds.toString(),
            onCommit: (text) {
              final parsed = double.tryParse(text);
              if (parsed != null && parsed > 0) {
                setState(() => _thresholdSeconds = parsed);
                _notifyChanged();
              }
            },
          );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: p.surfaceOpaque,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: p.panelBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.slowestSheetTitle(widget.algType.getLocalizedName(context)),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary),
              ),
              const SizedBox(height: 16),
              AppSegmentedControl<SlowestMode>(
                selected: _mode,
                options: [
                  SegmentOption(SlowestMode.topN, l10n.slowestModeTopN),
                  SegmentOption(SlowestMode.threshold, l10n.slowestModeThreshold),
                ],
                onChanged: (m) {
                  setState(() => _mode = m);
                  _notifyChanged();
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(valueLabel,
                        style: TextStyle(fontSize: 14, color: p.textMuted)),
                  ),
                  Container(
                    width: 64,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: p.inputFill,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: valueField,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l10n.slowestCasesCount(count),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: p.textMuted),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accent,
                  foregroundColor: p.onAccent,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                onPressed: count > 0 ? _start : null,
                child: Text(l10n.start),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
