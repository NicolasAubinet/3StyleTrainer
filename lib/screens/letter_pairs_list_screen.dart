import 'dart:async' as async;

import 'package:flutter/material.dart';
import 'package:smartcube/smartcube.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';

import '../l10n/app_localizations.dart';
import '../settings.dart';
import '../smart_cube/cube_orientation.dart';
import '../smart_cube/cube_run.dart';
import '../smart_cube/three_style_geometry.dart';
import '../smart_cube_manager.dart';
import '../theme/theme_scope.dart';
import '../utils.dart';
import '../widgets/app_scaffold.dart';

class LetterPairsListScreen extends StatefulWidget {
  final AlgProvider algProvider;
  final AlgType algType;

  const LetterPairsListScreen(this.algProvider, this.algType, {super.key});

  @override
  State<LetterPairsListScreen> createState() => _LetterPairsListScreenState();
}

class _LetterPairsListScreenState extends State<LetterPairsListScreen> {
  final List<Alg> _algs = [];
  final _scrollController = ScrollController();

  // Cube-driven ordered drill, active only when a cube is connected and the type
  // maps to geometry (else the screen is the plain static list). The next alg is
  // highlighted and greys out once the cube reports it executed.
  AlgType? _cubeAlgType;
  CubeRunController? _cubeRun;
  List<String> _pairPool = const [];
  async.StreamSubscription<CubeState>? _stateSub;
  async.StreamSubscription<CubeMove>? _moveSub;
  async.StreamSubscription<CubeState>? _resyncSub;

  // Index of the next alg the user should execute; everything before it is done.
  int _cursor = 0;
  // The pair the cube saw executed instead of the demanded one; kept until the
  // user turns again, so it can be read.
  String? _wrongExecuted;
  bool _carriedWrong = false;
  // Brief red pulse on the highlighted cell when a wrong case lands.
  bool _flash = false;
  async.Timer? _flashTimer;
  async.Timer? _feedbackTimer;

  // Grid metrics captured during layout, for scrolling the cursor into view.
  int _crossAxisCount = 0;
  double _itemHeight = 0;

  // How long the cube must sit still before a non-completing state is judged.
  // Matches the timer.
  static const Duration _quietPeriod = Duration(milliseconds: 500);

  bool get _cubeDriven => _cubeRun != null;
  bool get _done => _cursor >= _algs.length;
  String? get _currentPair => _done ? null : _algs[_cursor].name;

  @override
  void initState() {
    super.initState();
    Alg? alg;
    while ((alg = widget.algProvider.getNextAlg()) != null) {
      _algs.add(alg!);
    }
    widget.algProvider.reset();

    final mgr = SmartCubeManager();
    if (mgr.isConnected && _algs.isNotEmpty && _mappable(widget.algType)) {
      _cubeAlgType = widget.algType;
      _cubeRun = CubeRunController(_cubeAlgType!);
      _pairPool = enumerateAlgs(_cubeAlgType!);
      _stateSub = mgr.states.listen(_onCubeState);
      _moveSub = mgr.moves.listen(_onCubeMove);
      _resyncSub = mgr.resyncs.listen(_onCubeResync);
      _armCase();
    }
  }

  // Whether every pair of [type] resolves to cube geometry.
  bool _mappable(AlgType type) {
    if (!CubeRunController.supports(type)) return false;
    final pool = enumerateAlgs(type);
    return pool.isNotEmpty &&
        pool.every((p) =>
            ThreeStyleGeometry.expectedAfterPair(
                CubeState.solvedFacelets, p, type) !=
            null);
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _moveSub?.cancel();
    _resyncSub?.cancel();
    _flashTimer?.cancel();
    _feedbackTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  String get _rawFacelets =>
      SmartCubeManager().cube?.currentState.facelets ??
      CubeState.solvedFacelets;

  String _normalise(String facelets) => CubeOrientation.normaliseFacelets(
        facelets,
        top: Settings().getCubeTopColour(),
        front: Settings().getCubeFrontColour(),
      );

  String get _currentFacelets => _normalise(_rawFacelets);

  void _armCase() {
    final pair = _currentPair;
    if (pair == null) return;
    _cubeRun!.startCase(pair, _currentFacelets);
    _verifyBaseline(pair);
  }

  // Pull the cube's real state as the case opens (as the timer does) so drift we
  // failed to see costs one baseline, not the rest of the drill.
  void _verifyBaseline(String pair) async {
    final cube = SmartCubeManager().cube;
    if (cube == null) return;
    final state = await cube.requestState();
    if (!mounted || _currentPair != pair) return;
    if (_cubeRun!.phase != CubePhase.recognition) return;
    final norm = _normalise(state.facelets);
    if (norm == _cubeRun!.startFacelets) return;
    _cubeRun!.rebaseline(pair, norm);
  }

  void _onCubeState(CubeState state) {
    if (!mounted || !_cubeDriven || _done) return;
    final norm = _normalise(state.facelets);
    if (_cubeRun!.onState(norm) != null) {
      _onCaseComplete();
      return;
    }
    _scheduleFeedback(norm);
  }

  void _onCaseComplete() {
    _feedbackTimer?.cancel();
    final endState = _cubeRun!.expectedFacelets ?? _currentFacelets;
    setState(() {
      _wrongExecuted = null;
      _carriedWrong = false;
      _cursor++;
    });
    _scrollToCursor();
    if (_done) return;
    _cubeRun!.startCase(_currentPair!, endState);
  }

  void _onCubeMove(CubeMove move) {
    if (!mounted || !_cubeDriven || _done) return;
    // Still turning: the last settled state wasn't the end of anything.
    _feedbackTimer?.cancel();
    _cubeRun!.onMove();
    // Turning again means the carried wrong-case message has been read.
    if (_carriedWrong) {
      setState(() {
        _carriedWrong = false;
        _wrongExecuted = null;
      });
    }
  }

  // Diagnose only once the turning stops: many algs pass through another case's
  // finished state mid-execution, so a match seen while turning means nothing.
  void _scheduleFeedback(String normFacelets) {
    _feedbackTimer?.cancel();
    _feedbackTimer = async.Timer(_quietPeriod, () {
      if (!mounted || !_cubeDriven || _done) return;
      _updateFeedback(normFacelets);
    });
  }

  void _updateFeedback(String normFacelets) {
    final shown = _currentPair;
    final start = _cubeRun!.startFacelets;
    if (shown == null || start == null) return;
    if (_cubeRun!.phase != CubePhase.execution) return;

    final wrong = ThreeStyleGeometry.matchingPair(
        normFacelets, start, _cubeAlgType!, _pairPool);
    if (wrong != null && wrong != shown) {
      // A full, clean case — just not the demanded one. Keep demanding it, and
      // remember this state so the shown pair can be executed from here.
      _cubeRun!.addBaseline(shown, normFacelets);
      setState(() {
        _wrongExecuted = wrong;
        _carriedWrong = true;
      });
      _flashError();
      return;
    }

    // A pause mid-alg or a botch: remember it as a baseline so finishing — or
    // redoing — the shown pair from here still completes.
    _cubeRun!.addBaseline(shown, normFacelets);
  }

  void _flashError() {
    _flashTimer?.cancel();
    setState(() => _flash = true);
    _flashTimer = async.Timer(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _flash = false);
    });
  }

  // The cube re-anchored (lost moves or a reconnect): earlier baselines are
  // stale, so re-baseline the current case on where the cube actually is.
  void _onCubeResync(CubeState state) {
    if (!mounted || !_cubeDriven || _done) return;
    final shown = _currentPair;
    if (shown == null) return;
    _feedbackTimer?.cancel();
    _cubeRun!.rebaseline(shown, _normalise(state.facelets));
  }

  void _restart() {
    setState(() {
      _cursor = 0;
      _wrongExecuted = null;
      _carriedWrong = false;
      _flash = false;
    });
    if (_cubeDriven) _armCase();
    if (_scrollController.hasClients) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    }
  }

  void _scrollToCursor() {
    if (!_scrollController.hasClients || _crossAxisCount == 0) return;
    final row = _cursor ~/ _crossAxisCount;
    // Keep one row of lead-in above the current cell.
    final target = (row - 1) * _itemHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      _scrollController.animateTo(target.clamp(0.0, max),
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const double crossAxisExtent = 80.0;
    const double childAspectRatio = 2.0;

    return AppScaffold(
      title: AppLocalizations.of(context)!.practiceTypeLetterPairsList,
      body: Column(
        children: [
          if (_cubeDriven) _statusBar(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
              child: Card(
                clipBehavior: Clip.antiAlias,
                color: p.panel,
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final crossAxisCount =
                        (constraints.maxWidth / crossAxisExtent).ceil();
                    final rowCount = (_algs.length / crossAxisCount).ceil();
                    final itemHeight =
                        (constraints.maxWidth / crossAxisCount) /
                            childAspectRatio;
                    _crossAxisCount = crossAxisCount;
                    _itemHeight = itemHeight;

                    return Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: false,
                      child: ListView.builder(
                        controller: _scrollController,
                        itemCount: rowCount,
                        itemBuilder: (context, rowIndex) {
                          final List<Widget> rowChildren = [];
                          final startIndex = rowIndex * crossAxisCount;

                          for (int i = 0; i < crossAxisCount; i++) {
                            final itemIndex = startIndex + i;
                            rowChildren.add(Expanded(
                              child: itemIndex < _algs.length
                                  ? _cell(itemIndex)
                                  : Container(),
                            ));
                          }

                          return Container(
                            color: rowIndex.isEven
                                ? Colors.transparent
                                : p.panelBorder,
                            height: itemHeight,
                            child: Row(children: rowChildren),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(int index) {
    final theme = Theme.of(context);
    final name = _algs[index].name;
    final baseStyle = theme.textTheme.displaySmall!;

    // Static list (no cube): every pair with its é/è vowel colouring.
    if (!_cubeDriven) {
      return Center(child: Text.rich(algTextSpan(name, baseStyle)));
    }

    final isDone = index < _cursor;
    final isCurrent = index == _cursor;

    if (isDone) {
      // Executed — greyed out, like a struck-through scramble.
      return Center(
        child: Text(name,
            style: baseStyle.copyWith(color: theme.disabledColor)),
      );
    }

    if (!isCurrent) {
      return Center(child: Text.rich(algTextSpan(name, baseStyle)));
    }

    // The next alg: amber text (red while a wrong case flashes). algTextSpan
    // keeps the é/è vowel colours dominant over this base colour.
    final accent = _flash ? Colors.red : Colors.amber;
    return Center(
      child: Text.rich(algTextSpan(name, baseStyle.copyWith(color: accent))),
    );
  }

  Widget _statusBar(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;
    final theme = Theme.of(context);

    if (_done) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        color: p.panel,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(l10n.letterPairsAllDone,
                style: theme.textTheme.titleMedium),
            TextButton.icon(
              onPressed: _restart,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.letterPairsRestart),
            ),
          ],
        ),
      );
    }

    // A wrong case is loud (red); otherwise a quiet prompt of what's next.
    final wrong = _wrongExecuted;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: wrong != null ? p.bad.withValues(alpha: 0.15) : p.panel,
      child: Text(
        wrong != null
            ? l10n.smartCubeWrongCase(wrong)
            : l10n.letterPairsNextPrompt(_currentPair!),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          color: wrong != null ? p.bad : null,
        ),
      ),
    );
  }
}
