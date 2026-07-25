import 'dart:async';
import 'dart:math';

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
import '../widgets/swipeable_row.dart';

const int BUTTON_PRESS_DELAY_MS = 250;

// Sets rows fill toward a fixed target tick; under-target fills stop short of it.
const double _TARGET_TICK_FRAC = 0.65;
// The fastest cases keep this much fill, so they stay visible.
const double _METER_FLOOR_FRAC = 0.05;
// Floor on the over-target span, as a fraction of the target: a case at
// 1 + this multiple of the target fills the track, unless the session holds
// something slower. Without it the session's slowest fills the track by
// definition, so a lone case a hair over target pegs like a disastrous one.
const double _METER_OVER_SPAN_FRAC = 0.5;

/// Fraction of a Sets row's meter track to fill for [timeMs].
///
/// The target tick ([_TARGET_TICK_FRAC]) anchors the scale. Under-target times
/// fill in proportion to the target itself, so 2.9s against a 3s target reads as
/// nearly there whatever else the session holds; over-target ones spread between
/// the tick and [slowestMs], so one bad case can't peg every other.
///
/// Deliberately absolute below the tick: anchoring the low end on the session's
/// *fastest* pinned every best case to the floor however near target it was, and
/// left a single-time run with no signal at all (5% under target, 100% over,
/// whatever the time). Standing within the session is the colour's job
/// (`_distributionColor`), not the bar's.
double meterFrac(int timeMs,
    {required double targetMs, required int slowestMs}) {
  if (targetMs <= 0) return _TARGET_TICK_FRAC;
  if (timeMs >= targetMs) {
    final span = max(slowestMs - targetMs, targetMs * _METER_OVER_SPAN_FRAC);
    final f = ((timeMs - targetMs) / span).clamp(0.0, 1.0);
    return _TARGET_TICK_FRAC + (1.0 - _TARGET_TICK_FRAC) * f;
  }
  final f = (timeMs / targetMs).clamp(0.0, 1.0);
  return max(_METER_FLOOR_FRAC, _TARGET_TICK_FRAC * f);
}

enum _SortColumn { order, recognition, execution, time }

class SessionSummaryScreen extends StatefulWidget {
  final List<AlgTime> algTimes;
  // Cases that went wrong (cube-driven runs only). They have no honest time, so
  // they stay out of the times list and its stats, and get their own section.
  final List<AlgMistake> mistakes;
  // The cube drove the run: it alone can spot mistakes, so it alone gets the
  // errors tile — shown even at zero, so the summary keeps one shape.
  final bool cubeDriven;
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

  // Fires when the target is edited here, so the session keeps the new value
  // instead of reverting to the one it was started with.
  final void Function(double)? onTargetTimeChanged;

  const SessionSummaryScreen(
      {super.key,
      required this.algTimes,
      this.mistakes = const [],
      this.cubeDriven = false,
      required this.algType,
      this.onTargetTimeChanged,
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
        content: Text.rich(algTextSpan(
            l10n.deletedTime(
                algTime.alg.name, timeToString(algTime.timeMs, fractionDigits: 2)),
            const TextStyle())),
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

  double _meterFrac(int timeMs) => meterFrac(timeMs,
      targetMs: _targetTime * 1000, slowestMs: _hiMs);

  String _formattedAverage() {
    if (widget.algTimes.isEmpty) return "–";
    final total =
        widget.algTimes.fold<int>(0, (sum, a) => sum + a.timeMs);
    return timeToString((total / widget.algTimes.length).round(),
        fractionDigits: 2);
  }

  // Best attempt per case: with "Repeat until under target" one case can
  // appear several times, and target stats are about cases, not attempts.
  Map<String, int> get _bestTimeByAlg {
    final best = <String, int>{};
    for (final a in widget.algTimes) {
      final t = best[a.alg.name];
      if (t == null || a.timeMs < t) best[a.alg.name] = a.timeMs;
    }
    return best;
  }

  int get _underTargetCount => _bestTimeByAlg.values
      .where((t) => isUnderTargetTime(t, _targetTime))
      .length;

  void _onRepeatTargetTimePressed() {
    final allBelow = _bestTimeByAlg.values
        .every((t) => isUnderTargetTime(t, _targetTime));
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
    widget.onTargetTimeChanged?.call(newTarget);
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
            // Keeps the taller header tap targets clear of the action buttons.
            const SizedBox(height: 14),
            _sortHeaderRow(l10n),
            const SizedBox(height: 4),
            Expanded(
              child: ListView.builder(
                itemCount: widget.algTimes.length + _errorSectionRows,
                itemBuilder: (context, i) {
                  if (i < widget.algTimes.length) {
                    return _algRow(widget.algTimes[i], p);
                  }
                  final j = i - widget.algTimes.length;
                  return j == 0
                      ? _errorsHeader(p, l10n)
                      : _mistakeRow(_mistakeGroups[j - 1], j, p, l10n);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statHeader(AppPalette p, AppLocalizations l10n) {
    // IntrinsicHeight + stretch so all tiles match the tallest, even though the
    // Spread value uses a smaller font than the single numbers.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _solvedTile(p, l10n)),
          const SizedBox(width: 5),
          Expanded(
            child: _statTile(p, l10n.statAverage,
                value: _formattedAverage(), valueColor: p.accent),
          ),
          const SizedBox(width: 5),
          Expanded(
            child: _isTimeRace
                ? _spreadTile(p, l10n)
                : _statTile(p, l10n.statHitTarget,
                    value: "$_underTargetCount/${_bestTimeByAlg.length}",
                    valueColor: p.good),
          ),
        ],
      ),
    );
  }

  // Solved count, with the error total folded in as a red parenthetical —
  // on cube-driven runs (a cube detects errors) and whenever errors exist
  // (review-mode skips happen without a cube too).
  Widget _solvedTile(AppPalette p, AppLocalizations l10n) {
    final solved = widget.algTimes.length;
    final mistakes = widget.mistakes.length;
    final valueWidget = widget.cubeDriven || mistakes > 0
        ? Text.rich(TextSpan(children: [
            TextSpan(text: solved.toString(), style: _mono(20, p.textPrimary)),
            TextSpan(
                text: " ($mistakes)",
                style: _mono(14, mistakes == 0 ? p.textFaint : p.bad)),
          ]))
        : null;
    return _statTile(p, l10n.statSolved,
        value: solved.toString(), valueWidget: valueWidget);
  }

  // The errors section: a header plus one row per errored case, below the times.
  // A case botched more than once is one row carrying all its attempts, so the
  // list reads as "the cases you got wrong", not "every time you slipped".
  late final List<List<AlgMistake>> _mistakeGroups = _groupMistakes();

  List<List<AlgMistake>> _groupMistakes() {
    final groups = <String, List<AlgMistake>>{};
    for (final m in widget.mistakes) {
      groups.putIfAbsent(m.alg.name, () => []).add(m);
    }
    return groups.values.toList();
  }

  int get _errorSectionRows =>
      _mistakeGroups.isEmpty ? 0 : _mistakeGroups.length + 1;

  Widget _errorsHeader(AppPalette p, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_cardContentInset, 10, 0, 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 15, color: p.bad),
          const SizedBox(width: 6),
          Text(
            "${l10n.summaryErrors.toUpperCase()} (${widget.mistakes.length})",
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
                color: p.bad),
          ),
        ],
      ),
    );
  }

  String _mistakeLabel(AlgMistake m, AppLocalizations l10n) {
    switch (m.kind) {
      case AlgMistakeKind.wrongCase:
        return l10n.mistakeExecuted(m.executed!);
      case AlgMistakeKind.skipped:
        return l10n.mistakeSkipped;
      case AlgMistakeKind.requeued:
        return l10n.mistakeRequeued;
      case AlgMistakeKind.recovered:
        return l10n.mistakeRecovered;
    }
  }

  // An errored case: the pair that was shown, how many times it went wrong, and
  // what the cube saw each time — the pair actually executed, or nothing
  // recognizable (the user requeued it) — plus the moves it saw you turn. The
  // moves are clipped to one line; tapping the row shows every attempt in full.
  // No time and no swipe-to-delete: nothing was recorded.
  Widget _mistakeRow(
      List<AlgMistake> group, int row, AppPalette p, AppLocalizations l10n) {
    // Identical attempts collapse: two GA slips read "Executed GA", not twice.
    final detail =
        <String>{for (final m in group) _mistakeLabel(m, l10n)}.join(" · ");
    final moves = group.lastWhere((m) => m.moves != null,
        orElse: () => group.first).moves;

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: GlassPanel(
        radius: 10,
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: moves == null ? null : () => _showMistakeMoves(group, l10n),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      child: Text(row.toString(),
                          style:
                              _mono(12, p.textFaint, weight: FontWeight.w400)),
                    ),
                    const SizedBox(width: 6),
                    Text.rich(algTextSpan(group.first.alg.name, _mono(17, p.bad)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (group.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Text("(${group.length})",
                            maxLines: 1,
                            style: _mono(13, p.bad, weight: FontWeight.w400)),
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text.rich(
                        algTextSpan(
                            detail,
                            TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: p.textMuted)),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (moves != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, top: 4),
                    child: Text(
                      moves,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _mono(12, p.textFaint, weight: FontWeight.w400),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // A one-line disclaimer under moves the parser did not fully reconstruct:
  // the notation is the raw face-by-face reading, so slices appear as the
  // opposite-face turn pairs the cube reported.
  Widget _rawNote(AppPalette p, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Text(l10n.rawMovesNote,
          style: TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: p.textFaint)),
    );
  }

  // The moves of one clean solve, on tap of its time row.
  void _showSolveMoves(AlgTime algTime) {
    final p = context.palette;
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text.rich(algTextSpan(algTime.alg.name, _mono(20, p.textPrimary))),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              algTime.moves!,
              style: _mono(14, p.textMuted, weight: FontWeight.w400),
            ),
            if (!algTime.movesReconstructed) _rawNote(p, l10n),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  // Every attempt on this case: what it was read as, and the moves in full.
  void _showMistakeMoves(List<AlgMistake> group, AppLocalizations l10n) {
    final p = context.palette;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text.rich(
            algTextSpan(group.first.alg.name, _mono(20, p.textPrimary))),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in group) ...[
                Text.rich(algTextSpan(
                    _mistakeLabel(m, l10n),
                    TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: p.bad))),
                const SizedBox(height: 4),
                SelectableText(
                  m.moves ?? l10n.mistakeNoMoves,
                  style: _mono(14, p.textMuted, weight: FontWeight.w400),
                ),
                if (m.moves != null && !m.movesReconstructed) _rawNote(p, l10n),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  static const double _statLabelHeight = 12;

  Widget _statTile(AppPalette p, String label,
      {String value = "", Color? valueColor, Widget? valueWidget}) {
    return GlassPanel(
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // One line in a fixed box, shrunk to fit if need be. The tiles are tight
          // on a phone, and a label that wrapped (or merely scaled) would drag its
          // value out of line with the others'.
          SizedBox(
            height: _statLabelHeight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Text(label.toUpperCase(),
                  maxLines: 1,
                  style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: p.textFaint)),
            ),
          ),
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
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
            filled: false,
            onPressed: () => Navigator.pop(context, 'repeat_all')),
        const SizedBox(height: 8),
        _blockButton(p,
            label: l10n.repeatTargetTime(_targetTime),
            filled: true,
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

  // Column widths shared by the header cells and the value cells so the numbers
  // line up under their labels. The header row is inset to match the card's
  // content box (GlassPanel: 12px padding + 1px border).
  static const double _splitCellWidth = 52;
  static const double _timeCellWidth = 58;
  static const double _cardContentInset = 13;

  Widget _headerCell(String label, _SortColumn column,
          {double? width, TextAlign align = TextAlign.right}) =>
      SortHeader(
          label: label,
          column: column,
          state: _sort,
          onSort: _onSort,
          width: width,
          align: align);

  Widget _sortHeaderRow(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _cardContentInset),
      child: Row(
        children: [
          _headerCell(l10n.columnNumber, _SortColumn.order,
              width: 24, align: TextAlign.left),
          const Spacer(),
          if (_hasSplits) ...[
            _headerCell(l10n.columnRecognition.toUpperCase(),
                _SortColumn.recognition,
                width: _splitCellWidth),
            _headerCell(l10n.columnExecution.toUpperCase(), _SortColumn.execution,
                width: _splitCellWidth),
            const SizedBox(width: 8),
          ],
          _headerCell(l10n.columnTime.toUpperCase(), _SortColumn.time,
              width: _timeCellWidth),
        ],
      ),
    );
  }

  Widget _algRow(AlgTime algTime, AppPalette p) {
    final color = _rowColor(algTime.timeMs, p);

    final body = Column(
        children: [
          LayoutBuilder(builder: (context, constraints) {
            final showPills =
                !_hasSplits || constraints.maxWidth >= _pillsMinRowWidth;
            return Row(
              children: [
                SizedBox(
                  width: 18,
                  child: Text(algTime.index.toString(),
                      style: _mono(12, p.textFaint, weight: FontWeight.w400)),
                ),
                const SizedBox(width: 6),
                _nameCell(algTime, p, showPills),
                if (_hasSplits) ...[
                  _splitCell(algTime.recognitionMs, p),
                  _splitCell(algTime.executionMs, p),
                  const SizedBox(width: 8),
                ] else
                  const SizedBox(width: 8),
                SizedBox(
                  width: _timeCellWidth,
                  child: Text(timeToString(algTime.timeMs, fractionDigits: 2),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: _mono(17, color)),
                ),
              ],
            );
          }),
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
      );

    // Cube-driven solves carry their moves (session-only); tap to see them.
    // A tap on a swiped-open row folds it back instead.
    final card = GlassPanel(
      radius: 10,
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: algTime.moves == null
            ? null
            : () {
                if (_openRow.value != null) {
                  _openRow.value = null;
                  return;
                }
                _showSolveMoves(algTime);
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
          child: body,
        ),
      ),
    );

    return Padding(
      key: ValueKey(algTime),
      padding: const EdgeInsets.only(bottom: 7),
      child: SwipeableRow(
        rowId: algTime,
        openRow: _openRow,
        enabled: _isRecording,
        peekHint: _isRecording && algTime == widget.algTimes.first,
        deleteLabel: AppLocalizations.of(context)!.delete,
        radius: 10,
        onDelete: () => _deleteRow(algTime),
        onDisabledSwipe: _showNotRecordedToast,
        child: card,
      ),
    );
  }

  // Below this row width a split row can't fit the name, a pill and all three
  // columns, so the pills are dropped there (the total's colour still flags the
  // fastest/slowest). Wider rows — including every desktop — keep the pills.
  static const double _pillsMinRowWidth = 280;

  // The alg name plus its fastest/slowest pill, taking the row's free width.
  Widget _nameCell(AlgTime algTime, AppPalette p, bool showPills) {
    final l10n = AppLocalizations.of(context)!;
    final isFastest = showPills && identical(algTime, _fastest);
    final isSlowest = showPills &&
        identical(algTime, _slowest) &&
        !identical(_slowest, _fastest);
    return Expanded(
      child: Row(
        children: [
          Flexible(
            child: Text.rich(algTextSpan(algTime.alg.name, _mono(17, p.textPrimary)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
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
        maxLines: 1,
        overflow: TextOverflow.clip,
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
