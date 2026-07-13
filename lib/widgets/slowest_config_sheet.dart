import 'package:flutter/material.dart';

import '../alg_structs.dart';
import '../l10n/app_localizations.dart';
import '../slowest.dart';
import '../theme/theme_scope.dart';
import 'app_segmented_control.dart';
import 'number_input_field.dart';

// Result of the sheet: the chosen source/mode/values (to persist) plus the alg
// names to drill. Null return means the user dismissed without starting.
class SlowestSelection {
  final WeaknessSource source;
  final SlowestMode mode;
  final int topN;
  final double thresholdSeconds;
  final int minErrors;
  final List<String> algs;

  const SlowestSelection(this.source, this.mode, this.topN,
      this.thresholdSeconds, this.minErrors, this.algs);
}

typedef WeaknessConfigChanged = void Function(WeaknessSource source,
    SlowestMode mode, int topN, double thresholdSeconds, int minErrors);

// Bottom sheet to configure a "practice your weak cases" run for a given alg
// type: rank the cases by how slow they are or by how often they go wrong, then
// take the top N or everything past a threshold. Shows a live case count and
// Start. [onChanged] fires whenever a choice changes so the caller can persist
// it even when the sheet is dismissed without starting.
Future<SlowestSelection?> showSlowestConfigSheet(
  BuildContext context, {
  required AlgType algType,
  required List<SlowestAlg> slowest,
  required List<FailedAlg> mostFailed,
  required WeaknessSource source,
  required SlowestMode mode,
  required int topN,
  required double thresholdSeconds,
  required int minErrors,
  WeaknessConfigChanged? onChanged,
}) {
  return showModalBottomSheet<SlowestSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SlowestConfigSheet(
      algType: algType,
      slowest: slowest,
      mostFailed: mostFailed,
      initialSource: source,
      initialMode: mode,
      initialTopN: topN,
      initialThresholdSeconds: thresholdSeconds,
      initialMinErrors: minErrors,
      onChanged: onChanged,
    ),
  );
}

class _SlowestConfigSheet extends StatefulWidget {
  final AlgType algType;
  final List<SlowestAlg> slowest;
  final List<FailedAlg> mostFailed;
  final WeaknessSource initialSource;
  final SlowestMode initialMode;
  final int initialTopN;
  final double initialThresholdSeconds;
  final int initialMinErrors;
  final WeaknessConfigChanged? onChanged;

  const _SlowestConfigSheet({
    required this.algType,
    required this.slowest,
    required this.mostFailed,
    required this.initialSource,
    required this.initialMode,
    required this.initialTopN,
    required this.initialThresholdSeconds,
    required this.initialMinErrors,
    this.onChanged,
  });

  @override
  State<_SlowestConfigSheet> createState() => _SlowestConfigSheetState();
}

class _SlowestConfigSheetState extends State<_SlowestConfigSheet> {
  late WeaknessSource _source = widget.initialSource;
  late SlowestMode _mode = widget.initialMode;
  late int _topN = widget.initialTopN;
  late double _thresholdSeconds = widget.initialThresholdSeconds;
  late int _minErrors = widget.initialMinErrors;

  bool get _byErrors => _source == WeaknessSource.mostFailed;

  List<String> get _selectedAlgs => _byErrors
      ? selectMostFailed(widget.mostFailed,
          mode: _mode, topN: _topN, minErrors: _minErrors)
      : selectSlowest(widget.slowest,
          mode: _mode, topN: _topN, thresholdMs: _thresholdSeconds * 1000);

  void _notifyChanged() => widget.onChanged
      ?.call(_source, _mode, _topN, _thresholdSeconds, _minErrors);

  void _start() {
    Navigator.pop(
      context,
      SlowestSelection(
          _source, _mode, _topN, _thresholdSeconds, _minErrors, _selectedAlgs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    final count = _selectedAlgs.length;

    final valueLabel = _mode == SlowestMode.topN
        ? l10n.slowestCountLabel
        : (_byErrors ? l10n.failedThresholdLabel : l10n.slowestThresholdLabel);

    final Widget valueField;
    if (_mode == SlowestMode.topN) {
      valueField = NumberInputField(
        defaultValue: _topN.toString(),
        onCommit: (text) {
          final parsed = int.tryParse(text);
          if (parsed != null && parsed > 0) {
            setState(() => _topN = parsed);
            _notifyChanged();
          }
        },
      );
    } else if (_byErrors) {
      valueField = NumberInputField(
        defaultValue: _minErrors.toString(),
        onCommit: (text) {
          final parsed = int.tryParse(text);
          if (parsed != null && parsed > 0) {
            setState(() => _minErrors = parsed);
            _notifyChanged();
          }
        },
      );
    } else {
      valueField = NumberInputField(
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
    }

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
                _byErrors
                    ? l10n.mostFailedSheetTitle(
                        widget.algType.getLocalizedName(context))
                    : l10n.slowestSheetTitle(
                        widget.algType.getLocalizedName(context)),
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: p.textPrimary),
              ),
              const SizedBox(height: 16),
              // What "weak" means here: slow, or often botched.
              AppSegmentedControl<WeaknessSource>(
                selected: _source,
                options: [
                  SegmentOption(
                      WeaknessSource.slowestTime, l10n.weaknessSourceSlowest),
                  SegmentOption(
                      WeaknessSource.mostFailed, l10n.weaknessSourceMostFailed),
                ],
                onChanged: (s) {
                  setState(() => _source = s);
                  _notifyChanged();
                },
              ),
              const SizedBox(height: 10),
              // The threshold cuts on time when ranking by speed, on error count
              // when ranking by errors — so it says which.
              AppSegmentedControl<SlowestMode>(
                selected: _mode,
                options: [
                  SegmentOption(SlowestMode.topN, l10n.slowestModeTopN),
                  SegmentOption(
                      SlowestMode.threshold,
                      _byErrors
                          ? l10n.failedModeThreshold
                          : l10n.slowestModeThreshold),
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
