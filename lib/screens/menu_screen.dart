import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:three_style_trainer/equalizing_selector.dart';
import 'package:three_style_trainer/practice_type.dart';
import 'package:three_style_trainer/screens/alg_set_selector_screen.dart';
import 'package:three_style_trainer/screens/alg_times_screen.dart';
import 'package:three_style_trainer/screens/letter_pairs_list_screen.dart';
import 'package:three_style_trainer/screens/settings_screen.dart';
import 'package:three_style_trainer/screens/timer_screen.dart';
import 'package:three_style_trainer/slowest.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme_scope.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_segmented_control.dart';
import '../widgets/cube_type_icon.dart';
import '../widgets/glass_panel.dart';
import '../widgets/keycap_button.dart';
import '../widgets/number_input_field.dart';
import '../widgets/slowest_config_sheet.dart';

const double DEFAULT_TARGET_TIME = 2.0;
const double DEFAULT_RACE_TIME = 1.0;

class MenuScreen extends StatefulWidget {
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  double _targetTime = DEFAULT_TARGET_TIME;
  double _raceTime = DEFAULT_RACE_TIME;
  bool _showNextAlg = false;
  bool _recordTimes = true;
  PracticeType _practiceType = PracticeType.sets;
  SlowestMode _slowestMode = SlowestMode.topN;
  int _slowestTopN = 20;
  double _slowestThresholdSeconds = DEFAULT_TARGET_TIME;
  bool _hasRecordedTimes = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() async {
    // Load prefs first so the flag check sees the persisted practice type.
    await _loadPreferences();
    _refreshRecordedTimesFlag();
  }

  void _refreshRecordedTimesFlag() async {
    final has = await DatabaseManager().hasAnyRecordedTimes();
    if (!mounted) return;
    setState(() {
      _hasRecordedTimes = has;
      // Don't leave the user stranded on a now-locked Slowest tab.
      if (!has && _practiceType == PracticeType.slowest) {
        _practiceType = PracticeType.timeRace;
      }
    });
  }

  Future<void> _loadPreferences() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _targetTime = prefs.getDouble("target_time") ?? DEFAULT_TARGET_TIME;
      _raceTime = prefs.getDouble("race_time") ?? DEFAULT_RACE_TIME;
      _showNextAlg = prefs.getBool("show_next_alg") ?? false;
      _recordTimes = prefs.getBool("record_times") ?? true;
      final practiceTypeName = prefs.getString("practice_type");
      if (practiceTypeName != null) {
        _practiceType = PracticeType.values.byName(practiceTypeName);
      }
      final slowestModeName = prefs.getString("slowest_mode");
      _slowestMode = SlowestMode.values.firstWhere(
          (m) => m.name == slowestModeName,
          orElse: () => SlowestMode.topN);
      _slowestTopN = prefs.getInt("slowest_top_n") ?? 20;
      _slowestThresholdSeconds =
          prefs.getDouble("slowest_threshold") ?? DEFAULT_TARGET_TIME;
    });
  }

  AlgProvider _constructAlgProvider(AlgType algType,
      {List<String> skippedAlgs = const []}) {
    AlgProvider? algProvider;
    if (algType == AlgType.Corner) {
      algProvider = CornersAlgProvider(skippedAlgs: skippedAlgs);
    } else if (algType == AlgType.Edge) {
      algProvider = EdgesAlgProvider(skippedAlgs: skippedAlgs);
    } else if (algType == AlgType.TwoFlip) {
      algProvider = TwoFlipsAlgProvider(skippedAlgs: skippedAlgs);
    } else if (algType == AlgType.TwoTwist) {
      algProvider = TwoTwistsAlgProvider(skippedAlgs: skippedAlgs);
    } else if (algType == AlgType.Parity) {
      algProvider = ParityAlgProvider(skippedAlgs: skippedAlgs);
    }
    assert(algProvider != null, "Alg type not supported");
    return algProvider!;
  }

  void _onButtonPressed(BuildContext context, AlgType algType) async {
    int algsShownInAdvance = _showNextAlg ? 1 : 0;
    if (_practiceType == PracticeType.sets) {
      if (algType == AlgType.Parity) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TimerScreen(
              PracticeType.sets,
              _targetTime,
              _raceTime,
              ParityAlgProvider(),
              algType,
              algsShownInAdvance,
            ),
          ),
        );
        return;
      }

      List<CustomSet> customSets = [];
      if (algType == AlgType.Custom) {
        customSets = await DatabaseManager().getCustomSets();
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AlgSetSelectorScreen(
            _targetTime,
            _raceTime,
            algType,
            algsShownInAdvance,
            customSets: customSets,
          ),
        ),
      );
    } else if (_practiceType == PracticeType.timeRace) {
      final Map<String, int> counts =
          await DatabaseManager().getAlgCounts(algType);
      if (mounted && context.mounted) {
        final recording = isRecordingRun(
          practiceType: PracticeType.timeRace,
          algType: algType,
          algsShownInAdvance: algsShownInAdvance,
          recordTimes: _recordTimes,
        );
        AlgProvider algProvider = EqualizingSelector(
          algs: enumerateAlgs(algType),
          counts: counts,
          recording: recording,
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TimerScreen(
              _practiceType,
              _targetTime,
              _raceTime,
              algProvider,
              algType,
              algsShownInAdvance,
              recordTimes: _recordTimes,
            ),
          ),
        ).then((_) => _refreshRecordedTimesFlag());
      }
    } else if (_practiceType == PracticeType.slowest) {
      final List<SlowestAlg> slowest =
          await DatabaseManager().getSlowestAlgs(algType);
      if (!mounted || !context.mounted) return;
      if (slowest.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.slowestNoTimes),
        ));
        return;
      }
      final selection = await showSlowestConfigSheet(
        context,
        algType: algType,
        slowest: slowest,
        mode: _slowestMode,
        topN: _slowestTopN,
        thresholdSeconds: _slowestThresholdSeconds,
        onChanged: _persistSlowestConfig,
      );
      if (selection == null || !mounted || !context.mounted) return;
      _persistSlowestConfig(
          selection.mode, selection.topN, selection.thresholdSeconds);
      if (selection.algs.isNotEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TimerScreen(
              PracticeType.slowest,
              _targetTime,
              _raceTime,
              CustomProvider(selection.algs),
              algType,
              algsShownInAdvance,
            ),
          ),
        );
      }
    } else if (_practiceType == PracticeType.letterPairsList) {
      AlgProvider algProvider = _constructAlgProvider(algType);
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => LetterPairsListScreen(algProvider)),
      );
    }
  }

  Future<void> _setPref(void Function(SharedPreferences) write) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    write(prefs);
  }

  // Remember the slowest-mode config as it changes in the sheet, so it's
  // restored next time even if the sheet is dismissed without starting.
  void _persistSlowestConfig(SlowestMode mode, int topN, double thresholdSeconds) {
    _slowestMode = mode;
    _slowestTopN = topN;
    _slowestThresholdSeconds = thresholdSeconds;
    _setPref((prefs) {
      prefs.setString("slowest_mode", mode.name);
      prefs.setInt("slowest_top_n", topN);
      prefs.setDouble("slowest_threshold", thresholdSeconds);
    });
  }

  Widget _buildKeycapGrid(AppLocalizations l10n) {
    final letters = l10n.typeSubtitleLetters;
    // 2-Flips / 2-Twists / Parity can't be listed as pairs; Custom only in Sets.
    final orientationEnabled = _practiceType != PracticeType.letterPairsList;
    final parityEnabled = _practiceType != PracticeType.letterPairsList;
    final customEnabled = _practiceType == PracticeType.sets;

    Widget cap(AlgType type, String label, String subtitle,
        {bool enabled = true}) {
      return Expanded(
        child: KeycapButton(
          label: label,
          subtitle: subtitle,
          iconWidget: CubeTypeIcon(type: type, size: 46),
          enabled: enabled,
          onTap: () => _onButtonPressed(context, type),
        ),
      );
    }

    Widget row(List<Widget> caps) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < caps.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              caps[i],
            ],
          ],
        );

    return Column(
      children: [
        row([
          cap(AlgType.Corner, l10n.corners, letters),
          cap(AlgType.Edge, l10n.edges, letters),
        ]),
        const SizedBox(height: 12),
        row([
          cap(AlgType.TwoFlip, l10n.flips, l10n.typeSubtitleFlips,
              enabled: orientationEnabled),
          cap(AlgType.TwoTwist, l10n.twists, l10n.typeSubtitleTwists,
              enabled: orientationEnabled),
        ]),
        const SizedBox(height: 12),
        row([
          cap(AlgType.Parity, l10n.parity, l10n.typeSubtitleParity,
              enabled: parityEnabled),
          cap(AlgType.Custom, l10n.custom, l10n.typeSubtitleCustom,
              enabled: customEnabled),
        ]),
      ],
    );
  }

  (String, Widget)? _buildTimeField(AppLocalizations l10n) {
    final bool isSetBased = _practiceType.isSetBased;
    final String label;
    final double value;
    final String prefKey;
    final double fallback;
    if (isSetBased) {
      label = l10n.targetTime;
      value = _targetTime;
      prefKey = "target_time";
      fallback = DEFAULT_TARGET_TIME;
    } else if (_practiceType == PracticeType.timeRace) {
      label = l10n.raceTime;
      value = _raceTime;
      prefKey = "race_time";
      fallback = DEFAULT_RACE_TIME;
    } else {
      return null;
    }

    final p = context.palette;
    return (
      label,
      Container(
        width: 64,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: p.inputFill,
          borderRadius: BorderRadius.circular(9),
        ),
        child: NumberInputField(
          decimal: true,
          defaultValue: value.toString(),
          onCommit: (text) {
            final parsed = double.tryParse(text) ?? fallback;
            _setPref((prefs) => prefs.setDouble(prefKey, parsed));
            setState(() {
              if (isSetBased) {
                _targetTime = parsed;
              } else {
                _raceTime = parsed;
              }
            });
            FocusManager.instance.primaryFocus?.unfocus();
          },
        ),
      ),
    );
  }

  (String, Widget)? _buildShowNextAlg(AppLocalizations l10n) {
    if (_practiceType == PracticeType.letterPairsList) return null;
    return (
      l10n.showNextAlg,
      Switch(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        value: _showNextAlg,
        onChanged: (v) {
          _setPref((prefs) => prefs.setBool("show_next_alg", v));
          setState(() => _showNextAlg = v);
        },
      ),
    );
  }

  (String, Widget)? _buildRecordTimes(AppLocalizations l10n) {
    if (_practiceType != PracticeType.timeRace) return null;
    final enabled = !_showNextAlg;
    final sw = Switch(
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      value: enabled && _recordTimes,
      onChanged: enabled
          ? (v) {
              _setPref((prefs) => prefs.setBool("record_times", v));
              setState(() => _recordTimes = v);
            }
          : null,
    );
    return (
      l10n.recordTimes,
      enabled
          ? sw
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(l10n.recordTimesDisabledReason),
              )),
              child: sw,
            ),
    );
  }

  /// One row inside the grouped options panel. Fixed height so every option
  /// lines up regardless of whether the control is a switch or a number field.
  Widget _optionRow(String label, Widget trailing) {
    final p = context.palette;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 14, color: p.textMuted)),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = context.palette;

    final options = [
      _buildTimeField(l10n),
      _buildShowNextAlg(l10n),
      _buildRecordTimes(l10n),
    ].whereType<(String, Widget)>().toList();

    return AppScaffold(
      title: "3-Style Trainer",
      showBack: false,
      leading: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 0, 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset('assets/icon/icon.png', width: 26, height: 26),
        ),
      ),
      leadingWidth: 48,
      actions: [
        IconButton(
          tooltip: l10n.algTimesTitle,
          icon: const Icon(Icons.bar_chart_rounded),
          onPressed: () async {
            await Navigator.push(context,
                MaterialPageRoute(builder: (_) => const AlgTimesScreen()));
            _refreshRecordedTimesFlag(); // times may have been cleared here
          },
        ),
        IconButton(
          tooltip: l10n.settings,
          icon: const Icon(Icons.settings_rounded),
          onPressed: () async {
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => SettingsScreen()));
            _loadPreferences(); // pick up any settings changed via import
            _refreshRecordedTimesFlag(); // import may have added/removed times
          },
        ),
        const SizedBox(width: 4),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSegmentedControl<PracticeType>(
              selected: _practiceType,
              options: [
                SegmentOption(
                    PracticeType.timeRace, l10n.practiceTypeTimeRaceShort),
                SegmentOption(PracticeType.sets, l10n.practiceTypeSets),
                SegmentOption(PracticeType.slowest, l10n.practiceTypeSlowest,
                    enabled: _hasRecordedTimes),
                SegmentOption(PracticeType.letterPairsList,
                    l10n.practiceTypeLetterPairsShort),
              ],
              onChanged: (type) {
                _setPref(
                    (prefs) => prefs.setString("practice_type", type.name));
                setState(() => _practiceType = type);
              },
              onDisabledTap: (_) => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.slowestLockedReason)),
              ),
            ),
            const SizedBox(height: 18),
            _buildKeycapGrid(l10n),
            if (options.isNotEmpty) ...[
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  l10n.optionsSection.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: p.textFaint,
                  ),
                ),
              ),
              GlassPanel(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    for (int i = 0; i < options.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: p.panelBorder,
                          indent: 16,
                          endIndent: 16,
                        ),
                      _optionRow(options[i].$1, options[i].$2),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
