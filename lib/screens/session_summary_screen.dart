import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_style_trainer/practice_type.dart';

import '../alg_structs.dart';
import '../l10n/app_localizations.dart';
import '../settings.dart';
import '../theme/app_palette.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/glass_panel.dart';
import '../widgets/number_input_field.dart';
import '../widgets/recording_dot.dart';
import '../widgets/sort_header.dart';

const int BUTTON_PRESS_DELAY_MS = 250;

// Sets rows fill toward a fixed target tick; under-target fills stop short of it.
const double _TARGET_TICK_FRAC = 0.65;

enum _SortColumn { order, recognition, execution, time }

class SessionSummaryScreen extends StatefulWidget {
  final List<AlgTime> algTimes;
  final AlgType algType;
  final double targetTime;
  final PracticeType practiceType;
  final int totalTimeMs;

  // Persistence hooks for recorded runs. When [onDeleteFromDb] is non-null, rows
  // are swipe-to-delete (recording run); it removes the recorded DB row and
  // [onRestoreToDb] re-inserts it on undo. Both null on non-recording runs,
  // where swiping a row just explains there's nothing recorded to delete.
  final void Function(AlgTime)? onDeleteFromDb;
  final void Function(AlgTime)? onRestoreToDb;

  const SessionSummaryScreen(
      {super.key,
      required this.algTimes,
      required this.algType,
      required this.targetTime,
      required this.practiceType,
      required this.totalTimeMs,
      this.onDeleteFromDb,
      this.onRestoreToDb});

  @override
  State<SessionSummaryScreen> createState() => _SessionSummaryScreenState();
}

class _SessionSummaryScreenState extends State<SessionSummaryScreen> {
  // Sort: by occurrence order (default) or by solve time.
  final SortState<_SortColumn> _sort = SortState(
      column: _SortColumn.order, direction: SortDirection.ascending);
  bool _canPressButtons = false;
  late Timer _buttonsActivationTimer;

  // Distribution anchors over the session times (min / median / max), used to
  // color the times and scale the speed bars in Time-race.
  int _loMs = 0;
  int _medMs = 0;
  int _hiMs = 0;
  AlgTime? _fastest;
  AlgTime? _slowest;

  final ValueNotifier<Object?> _openRow = ValueNotifier<Object?>(null);

  // Editable copy of the target (Feature 7); starts from the passed-in value.
  late double _targetTime = widget.targetTime;

  bool get _isTimeRace => widget.practiceType == PracticeType.timeRace;

  TextStyle _mono(double size, Color color,
          {FontWeight weight = FontWeight.w700}) =>
      TextStyle(
          fontFamily: MONO_FONT, fontSize: size, fontWeight: weight, color: color);

  @override
  void initState() {
    super.initState();
    _computeAnchors();
    _applySort();

    _buttonsActivationTimer = Timer(
        Duration(milliseconds: BUTTON_PRESS_DELAY_MS),
        () => setState(() {
              _canPressButtons = true;
            }));
  }

  @override
  void dispose() {
    _buttonsActivationTimer.cancel();
    _openRow.dispose();
    super.dispose();
  }

  bool get _isRecording => widget.onDeleteFromDb != null;

  void _deleteRow(AlgTime algTime) {
    final l10n = AppLocalizations.of(context)!;
    final int index = widget.algTimes.indexOf(algTime);
    if (index < 0) return;

    setState(() {
      widget.algTimes.removeAt(index);
      _openRow.value = null;
      _computeAnchors();
    });
    widget.onDeleteFromDb?.call(algTime);

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(l10n.deletedTime(
            algTime.alg.name, timeToString(algTime.timeMs, fractionDigits: 2))),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () {
            setState(() {
              widget.algTimes.add(algTime);
              _applySort();
              _computeAnchors();
            });
            widget.onRestoreToDb?.call(algTime);
          },
        ),
      ));
  }

  void _showNotRecordedToast() {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
          SnackBar(content: Text(l10n.deleteUnavailableNotRecorded)));
  }

  void _computeAnchors() {
    if (widget.algTimes.isEmpty) return;
    final sorted = widget.algTimes.map((a) => a.timeMs).toList()..sort();
    _loMs = sorted.first;
    _hiMs = sorted.last;
    final m = sorted.length ~/ 2;
    _medMs = sorted.length.isOdd
        ? sorted[m]
        : ((sorted[m - 1] + sorted[m]) / 2).round();
    _fastest =
        widget.algTimes.reduce((a, b) => a.timeMs <= b.timeMs ? a : b);
    _slowest =
        widget.algTimes.reduce((a, b) => a.timeMs >= b.timeMs ? a : b);
  }

  // The split columns only appear once the session has smart-cube solves; like
  // the stats screen, the summary is otherwise exactly as it was.
  bool get _hasSplits => widget.algTimes.any((a) => a.recognitionMs != null);

  void _applySort() {
    final hasSplits = _hasSplits;
    widget.algTimes.sort((a, b) {
      if (_sort.column == _SortColumn.order) {
        final cmp = a.index.compareTo(b.index);
        return _sort.direction.isAscending ? cmp : -cmp;
      }
      // Solves with no split (null) always sort last, either direction.
      final va = _sortValue(a, hasSplits), vb = _sortValue(b, hasSplits);
      if (va == null || vb == null) {
        if (va == vb) return 0;
        return va == null ? 1 : -1;
      }
      final cmp = va.compareTo(vb);
      return _sort.direction.isAscending ? cmp : -cmp;
    });
  }

  int? _sortValue(AlgTime a, bool hasSplits) {
    switch (_sort.column) {
      case _SortColumn.recognition:
        return hasSplits ? a.recognitionMs : a.timeMs;
      case _SortColumn.execution:
        return hasSplits ? a.executionMs : a.timeMs;
      default:
        return a.timeMs;
    }
  }

  void _onSort(_SortColumn column) {
    setState(() {
      // All columns start ascending: order -> as they occurred, times ->
      // fastest first.
      _sort.toggle(column, SortDirection.ascending);
      _applySort();
    });
  }

  // Green (fastest) -> textPrimary (median) -> red (slowest), anchored on the
  // session min / median / max so the middle case reads neutral.
  Color _distributionColor(int timeMs, AppPalette p) {
    if (_hiMs <= _loMs) return p.textPrimary;
    final v = timeMs.toDouble();
    double t;
    if (v <= _medMs) {
      final span = _medMs - _loMs;
      t = span <= 0 ? 0.5 : 0.5 * ((v - _loMs) / span).clamp(0.0, 1.0);
    } else {
      final span = _hiMs - _medMs;
      final frac = span <= 0 ? 1.0 : ((v - _medMs) / span).clamp(0.0, 1.0);
      t = 0.5 + 0.5 * frac;
    }
    return t <= 0.5
        ? Color.lerp(p.good, p.textPrimary, t / 0.5)!
        : Color.lerp(p.textPrimary, p.bad, (t - 0.5) / 0.5)!;
  }

  Color _rowColor(int timeMs, AppPalette p) => _isTimeRace
      ? _distributionColor(timeMs, p)
      : (isUnderTargetTime(timeMs, _targetTime) ? p.good : p.bad);

  // Time-race speed bar: fraction of track filled, scaled across the session
  // (fastest gets a small floor so it stays visible).
  double _speedFrac(int timeMs) {
    if (_hiMs <= _loMs) return 1.0;
    final f = (timeMs - _loMs) / (_hiMs - _loMs);
    return (0.15 + 0.70 * f).clamp(0.0, 1.0);
  }

  // Sets success meter: fills toward the target tick; over-target overflows it.
  double _meterFrac(int timeMs) {
    if (_targetTime <= 0) return _TARGET_TICK_FRAC;
    final f = (timeMs / 1000) / _targetTime * _TARGET_TICK_FRAC;
    return f.clamp(0.05, 1.0);
  }

  String _formattedAverage() {
    if (widget.algTimes.isEmpty) return "–";
    final total =
        widget.algTimes.fold<int>(0, (sum, a) => sum + a.timeMs);
    return timeToString((total / widget.algTimes.length).round(),
        fractionDigits: 2);
  }

  int get _underTargetCount => widget.algTimes
      .where((a) => isUnderTargetTime(a.timeMs, _targetTime))
      .length;

  void _onRepeatTargetTimePressed() {
    final allBelow = widget.algTimes
        .every((a) => isUnderTargetTime(a.timeMs, _targetTime));
    if (allBelow) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!
            .allCasesWereSubTarget(_targetTime)),
      ));
    } else {
      Navigator.pop(context, 'repeat_target_time');
    }
  }

  // Feature 7: edit the target inline; recolours rows, moves the success-meter
  // tick, updates the repeat label, and persists so the menu picks it up too.
  Future<void> _editTargetTime() async {
    final l10n = AppLocalizations.of(context)!;
    String text = _targetTime.toStringAsFixed(2);
    final newTarget = await showDialog<double>(
      context: context,
      builder: (context) {
        final p = context.palette;
        return AlertDialog(
          title: Text(l10n.editTargetTime),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: p.inputFill,
              borderRadius: BorderRadius.circular(9),
            ),
            child: NumberInputField(
              decimal: true,
              defaultValue: text,
              onChanged: (v) => text = v,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () {
                final parsed = double.tryParse(text);
                if (parsed != null && parsed > 0) Navigator.pop(context, parsed);
              },
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
    if (newTarget == null) return;
    setState(() => _targetTime = newTarget);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble("target_time", newTarget);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;

    return AppScaffold(
      title: sessionTitle(context, widget.algType, widget.practiceType),
      titleLeading: (_isRecording && Settings().getShowRecordingDot())
          ? const RecordingDot()
          : null,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Center(
            child: Text(
              l10n.totalTime(totalTimeToString(widget.totalTimeMs)),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: p.textMuted),
            ),
          ),
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _statHeader(p, l10n),
            const SizedBox(height: 8),
            _isTimeRace ? _timeRaceActions(p, l10n) : _setsActions(p, l10n),
            const SizedBox(height: 8),
            _sortHeaderRow(l10n),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: widget.algTimes.length,
                itemBuilder: (context, i) => _algRow(widget.algTimes[i], p),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statHeader(AppPalette p, AppLocalizations l10n) {
    // IntrinsicHeight + stretch so all three tiles match the tallest, even
    // though the Spread value uses a smaller font than the single numbers.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _statTile(p, l10n.statCompleted,
                value: widget.algTimes.length.toString()),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statTile(p, l10n.statAverage,
                value: _formattedAverage(), valueColor: p.accent),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _isTimeRace
                ? _spreadTile(p, l10n)
                : _statTile(p, l10n.statUnderTarget,
                    value: "$_underTargetCount/${widget.algTimes.length}",
                    valueColor: p.good),
          ),
        ],
      ),
    );
  }

  Widget _statTile(AppPalette p, String label,
      {String value = "", Color? valueColor, Widget? valueWidget}) {
    return GlassPanel(
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: p.textFaint)),
          const SizedBox(height: 3),
          valueWidget ?? Text(value, style: _mono(20, valueColor ?? p.textPrimary)),
        ],
      ),
    );
  }

  // Spread: min → max on one line (green best, faint arrow, red worst).
  Widget _spreadTile(AppPalette p, AppLocalizations l10n) {
    final value = widget.algTimes.isEmpty
        ? const SizedBox.shrink()
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Text(timeToString(_loMs, fractionDigits: 2),
                    style: _mono(16, p.good)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Text("→",
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: p.textFaint)),
                ),
                Text(timeToString(_hiMs, fractionDigits: 2),
                    style: _mono(16, p.bad)),
              ],
            ),
          );
    return _statTile(p, l10n.statSpread, valueWidget: value);
  }

  Widget _timeRaceActions(AppPalette p, AppLocalizations l10n) {
    return Center(
      child: _pillButton(
        p,
        label: l10n.again,
        icon: Icons.refresh,
        onPressed: () => Navigator.pop(context, 'again'),
      ),
    );
  }

  Widget _setsActions(AppPalette p, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Target line with an inline edit control (Feature 7).
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                      text: "${l10n.summaryTarget}  ",
                      style: TextStyle(fontSize: 13, color: p.textMuted)),
                  TextSpan(
                    text: _targetTime.toStringAsFixed(2),
                    style: _mono(14, p.textPrimary),
                  ),
                  TextSpan(
                      text: "s",
                      style: TextStyle(fontSize: 13, color: p.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: _editTargetTime,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.edit, size: 15, color: p.accent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _blockButton(p,
            label: l10n.repeatAll,
            filled: true,
            onPressed: () => Navigator.pop(context, 'repeat_all')),
        const SizedBox(height: 8),
        _blockButton(p,
            label: l10n.repeatTargetTime(_targetTime),
            filled: false,
            onPressed: _onRepeatTargetTimePressed),
      ],
    );
  }

  Widget _pillButton(AppPalette p,
      {required String label,
      required IconData icon,
      required VoidCallback onPressed}) {
    return Material(
      color: p.accent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: _canPressButtons ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: p.onAccent),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: p.onAccent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _blockButton(AppPalette p,
      {required String label,
      required bool filled,
      required VoidCallback onPressed}) {
    return Material(
      color: filled ? p.accent : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: _canPressButtons ? onPressed : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                      color: p.accent.withValues(alpha: 0.55))),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: filled ? p.onAccent : p.accent)),
        ),
      ),
    );
  }

  // Column widths shared by the split header cells and value cells so the R / E
  // numbers line up under their labels, right beside the total.
  static const double _splitCellWidth = 52;

  Widget _splitHeader(String label, _SortColumn column) {
    return SizedBox(
      width: _splitCellWidth,
      child: Align(
        alignment: Alignment.centerRight,
        child: SortHeader(
            label: label.toUpperCase(),
            column: column,
            state: _sort,
            onSort: _onSort),
      ),
    );
  }

  Widget _sortHeaderRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          SortHeader(
              label: l10n.columnNumber,
              column: _SortColumn.order,
              state: _sort,
              onSort: _onSort),
          const Spacer(),
          if (_hasSplits) ...[
            _splitHeader(l10n.columnRecognition, _SortColumn.recognition),
            _splitHeader(l10n.columnExecution, _SortColumn.execution),
            const SizedBox(width: 8),
          ],
          SortHeader(
              label: l10n.columnTime.toUpperCase(),
              column: _SortColumn.time,
              state: _sort,
              onSort: _onSort),
        ],
      ),
    );
  }

  Widget _algRow(AlgTime algTime, AppPalette p) {
    final color = _rowColor(algTime.timeMs, p);

    final card = GlassPanel(
      radius: 10,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                child: Text(algTime.index.toString(),
                    style: _mono(12, p.textFaint, weight: FontWeight.w400)),
              ),
              const SizedBox(width: 6),
              _nameCell(algTime, p),
              if (_hasSplits) ...[
                _splitCell(algTime.recognitionMs, p),
                _splitCell(algTime.executionMs, p),
                const SizedBox(width: 8),
              ] else
                const SizedBox(width: 8),
              Text(timeToString(algTime.timeMs, fractionDigits: 2),
                  style: _mono(17, color)),
            ],
          ),
          const SizedBox(height: 8),
          _bar(
            p,
            frac: _isTimeRace
                ? _speedFrac(algTime.timeMs)
                : _meterFrac(algTime.timeMs),
            color: color,
            tickFrac: _isTimeRace ? null : _TARGET_TICK_FRAC,
          ),
        ],
      ),
    );

    return Padding(
      key: ValueKey(algTime),
      padding: const EdgeInsets.only(bottom: 7),
      child: _SwipeableRow(
        rowId: algTime,
        openRow: _openRow,
        enabled: _isRecording,
        deleteLabel: AppLocalizations.of(context)!.delete,
        radius: 10,
        onDelete: () => _deleteRow(algTime),
        onDisabledSwipe: _showNotRecordedToast,
        child: card,
      ),
    );
  }

  // The alg name plus its fastest/slowest pill, taking the row's free width. In
  // a split session the pills are dropped (the split columns need the width, and
  // the colour of the total already flags the fastest/slowest).
  Widget _nameCell(AlgTime algTime, AppPalette p) {
    final l10n = AppLocalizations.of(context)!;
    final showPills = !_hasSplits;
    final isFastest = showPills && identical(algTime, _fastest);
    final isSlowest = showPills &&
        identical(algTime, _slowest) &&
        !identical(_slowest, _fastest);
    return Expanded(
      child: Row(
        children: [
          Flexible(
            child: Text(algTime.alg.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono(17, p.textPrimary)),
          ),
          if (isFastest) _rowPill(p, l10n.pillFastest, p.good),
          if (isSlowest) _rowPill(p, l10n.pillSlowest, p.bad),
        ],
      ),
    );
  }

  // A right-aligned recognition/execution value under its header; a faint dash
  // for a press-timed solve within a split session.
  Widget _splitCell(int? ms, AppPalette p) {
    return SizedBox(
      width: _splitCellWidth,
      child: Text(
        ms == null ? "–" : timeToString(ms, fractionDigits: 2),
        textAlign: TextAlign.right,
        style: ms == null
            ? _mono(13, p.textFaint, weight: FontWeight.w400)
            : _mono(13, p.textMuted, weight: FontWeight.w400),
      ),
    );
  }

  Widget _rowPill(AppPalette p, String label, Color bg) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(5)),
        child: Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: p.brightness == Brightness.dark
                    ? const Color(0xFF10201A)
                    : Colors.white)),
      ),
    );
  }

  Widget _bar(AppPalette p,
      {required double frac, required Color color, double? tickFrac}) {
    final track = color.withValues(alpha: 0.10);
    return SizedBox(
      height: 10,
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                    color: track, borderRadius: BorderRadius.circular(4)),
              ),
            ),
          ),
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: frac.clamp(0.0, 1.0),
                heightFactor: 1,
                child: Center(
                  child: Container(
                    height: 6,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              ),
            ),
          ),
          if (tickFrac != null)
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: tickFrac,
                  heightFactor: 1,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(width: 2, height: 10, color: p.textMuted),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Swipe a row left to reveal a Delete button behind it; the row slides but is
/// not removed until the button is tapped (swiping back cancels). At most one
/// row is open at a time, coordinated through [openRow].
///
/// When [enabled] is false (non-recording run, nothing to delete) the row
/// doesn't reveal a button; a left-swipe instead fires [onDisabledSwipe].
class _SwipeableRow extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final String deleteLabel;
  final VoidCallback onDelete;
  final VoidCallback? onDisabledSwipe;
  final Object rowId;
  final ValueNotifier<Object?> openRow;
  final double radius;

  const _SwipeableRow({
    required this.child,
    required this.enabled,
    required this.deleteLabel,
    required this.onDelete,
    required this.onDisabledSwipe,
    required this.rowId,
    required this.openRow,
    required this.radius,
  });

  @override
  State<_SwipeableRow> createState() => _SwipeableRowState();
}

class _SwipeableRowState extends State<_SwipeableRow>
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
  }

  @override
  void dispose() {
    widget.openRow.removeListener(_onOpenRowChanged);
    _ctrl.dispose();
    super.dispose();
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
