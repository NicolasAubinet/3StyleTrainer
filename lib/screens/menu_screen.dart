import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:three_style_trainer/practice_type.dart';
import 'package:three_style_trainer/screens/alg_set_selector_screen.dart';
import 'package:three_style_trainer/screens/alg_times_screen.dart';
import 'package:three_style_trainer/screens/letter_pairs_list_screen.dart';
import 'package:three_style_trainer/screens/settings_screen.dart';
import 'package:three_style_trainer/screens/timer_screen.dart';

import '../l10n/app_localizations.dart';
import '../theme/theme_scope.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/app_segmented_control.dart';
import '../widgets/cube_icons.dart';
import '../widgets/glass_panel.dart';
import '../widgets/keycap_button.dart';
import '../widgets/number_input_field.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  void _loadPreferences() async {
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
    }
    assert(algProvider != null, "Alg type not supported");
    return algProvider!;
  }

  void _onButtonPressed(BuildContext context, AlgType algType) async {
    int algsShownInAdvance = _showNextAlg ? 1 : 0;
    if (_practiceType == PracticeType.sets) {
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
      if (mounted && context.mounted) {
        List<String> skippedAlgs =
            await DatabaseManager().getExecutedTimeRaceAlgs(algType);
        AlgProvider algProvider =
            _constructAlgProvider(algType, skippedAlgs: skippedAlgs);
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
              skippedAlgs: skippedAlgs,
              recordTimes: _recordTimes,
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

  Widget _buildKeycapGrid(AppLocalizations l10n) {
    final letters = l10n.typeSubtitleLetters;
    // 2-Flips can't be listed as pairs; Custom only exists in Sets mode.
    final flipsEnabled = _practiceType != PracticeType.letterPairsList;
    final customEnabled = _practiceType == PracticeType.sets;

    Widget cap(AlgType type, String label, String subtitle,
        {IconData? icon,
        Widget Function(Color)? iconBuilder,
        bool enabled = true}) {
      return Expanded(
        child: KeycapButton(
          label: label,
          subtitle: subtitle,
          icon: icon,
          iconBuilder: iconBuilder,
          enabled: enabled,
          onTap: () => _onButtonPressed(context, type),
        ),
      );
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cap(AlgType.Corner, l10n.corners, letters,
                iconBuilder: (c) =>
                    CubePieceIcon(piece: CubePiece.corners, color: c)),
            const SizedBox(width: 12),
            cap(AlgType.Edge, l10n.edges, letters,
                iconBuilder: (c) =>
                    CubePieceIcon(piece: CubePiece.edges, color: c)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cap(AlgType.TwoFlip, l10n.flips, l10n.typeSubtitleFlips,
                icon: Icons.swap_horiz_rounded, enabled: flipsEnabled),
            const SizedBox(width: 12),
            cap(AlgType.Custom, l10n.custom, l10n.typeSubtitleCustom,
                icon: Icons.tune_rounded, enabled: customEnabled),
          ],
        ),
      ],
    );
  }

  Widget? _buildTimeField(AppLocalizations l10n) {
    final bool isSets = _practiceType == PracticeType.sets;
    final String label;
    final double value;
    final String prefKey;
    final double fallback;
    if (isSets) {
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
    return GlassField(
      label: label,
      trailing: Container(
        width: 64,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: p.inputFill,
          borderRadius: BorderRadius.circular(9),
        ),
        child: NumberInputField(
          decimal: true,
          defaultValue: value.toString(),
          onTapOutside: (text) {
            final parsed = double.tryParse(text) ?? fallback;
            _setPref((prefs) => prefs.setDouble(prefKey, parsed));
            setState(() {
              if (isSets) {
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

  Widget? _buildShowNextAlg(AppLocalizations l10n) {
    if (_practiceType == PracticeType.letterPairsList) return null;
    return GlassField(
      label: l10n.showNextAlg,
      trailing: Switch(
        value: _showNextAlg,
        onChanged: (v) {
          _setPref((prefs) => prefs.setBool("show_next_alg", v));
          setState(() => _showNextAlg = v);
        },
      ),
    );
  }

  Widget? _buildRecordTimes(AppLocalizations l10n) {
    if (_practiceType != PracticeType.timeRace) return null;
    final enabled = !_showNextAlg;
    final sw = Switch(
      value: enabled && _recordTimes,
      onChanged: enabled
          ? (v) {
              _setPref((prefs) => prefs.setBool("record_times", v));
              setState(() => _recordTimes = v);
            }
          : null,
    );
    return GlassField(
      label: l10n.recordTimes,
      trailing: enabled
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    final timeField = _buildTimeField(l10n);
    final showNext = _buildShowNextAlg(l10n);
    final recordTimes = _buildRecordTimes(l10n);

    return AppScaffold(
      title: "3-Style Trainer",
      showBack: false,
      actions: [
        IconButton(
          tooltip: l10n.algTimesTitle,
          icon: const Icon(Icons.bar_chart_rounded),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AlgTimesScreen())),
        ),
        IconButton(
          tooltip: l10n.settings,
          icon: const Icon(Icons.settings_rounded),
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => SettingsScreen())),
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
                    PracticeType.timeRace, l10n.practiceTypeTimeRace),
                SegmentOption(PracticeType.sets, l10n.practiceTypeSets),
                SegmentOption(PracticeType.letterPairsList,
                    l10n.practiceTypeLetterPairsShort),
              ],
              onChanged: (type) {
                _setPref((prefs) => prefs.setString("practice_type", type.name));
                setState(() => _practiceType = type);
              },
            ),
            const SizedBox(height: 18),
            _buildKeycapGrid(l10n),
            const SizedBox(height: 18),
            if (timeField != null) ...[timeField, const SizedBox(height: 10)],
            if (showNext != null) ...[showNext, const SizedBox(height: 10)],
            if (recordTimes != null) recordTimes,
          ],
        ),
      ),
    );
  }
}
