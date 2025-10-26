import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:three_style_trainer/practice_type.dart';
import 'package:three_style_trainer/screens/alg_set_selector_screen.dart';
import 'package:three_style_trainer/screens/letter_pairs_list_screen.dart';
import 'package:three_style_trainer/screens/settings_screen.dart';
import 'package:three_style_trainer/screens/timer_screen.dart';

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
              skippedAlgs: skippedAlgs,
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

  TimeSelectionWidget? _getTimeSelectionWidget() {
    if (_practiceType == PracticeType.sets) {
      return TimeSelectionWidget(
          AppLocalizations.of(context)!.targetTime, _targetTime,
          (targetTime) async {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setDouble("target_time", targetTime);
        setState(() {
          _targetTime = targetTime;
        });
      });
    } else if (_practiceType == PracticeType.timeRace) {
      return TimeSelectionWidget(
          AppLocalizations.of(context)!.raceTime, _raceTime, (raceTime) async {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        prefs.setDouble("race_time", raceTime);
        setState(() {
          _raceTime = raceTime;
        });
      });
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);
    final timeSelectionWidget = _getTimeSelectionWidget();

    return Scaffold(
      backgroundColor: theme.colorScheme.primary,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            child: Text(AppLocalizations.of(context)!.corners),
            onPressed: () => _onButtonPressed(context, AlgType.Corner),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            child: Text(AppLocalizations.of(context)!.edges),
            onPressed: () => _onButtonPressed(context, AlgType.Edge),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            child: Text(AppLocalizations.of(context)!.flips),
            onPressed: _practiceType == PracticeType.letterPairsList
                ? null
                : () => _onButtonPressed(context, AlgType.TwoFlip),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: _practiceType == PracticeType.sets
                ? () => _onButtonPressed(context, AlgType.Custom)
                : null,
            child: Text(AppLocalizations.of(context)!.custom),
          ),
          SizedBox(height: 50),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PracticeTypeSelectionWidget((PracticeType? type) {
                setState(() {
                  _practiceType = type ?? PracticeType.sets;
                });
              }),
            ],
          ),
          SizedBox(height: 10),
          if (timeSelectionWidget != null) timeSelectionWidget,
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: theme.colorScheme.secondary,
        tooltip: AppLocalizations.of(context)!.settings,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => SettingsScreen()),
          );
        },
        child: Icon(
          Icons.settings,
          color: theme.colorScheme.onSecondary,
          size: 28,
        ),
      ),
    );
  }
}

class PracticeTypeSelectionWidget extends StatefulWidget {
  final Function(PracticeType?) _onSelected;

  PracticeTypeSelectionWidget(this._onSelected);

  @override
  State<PracticeTypeSelectionWidget> createState() =>
      _PracticeTypeSelectionWidgetState();
}

class _PracticeTypeSelectionWidgetState
    extends State<PracticeTypeSelectionWidget> {
  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return DropdownMenu<PracticeType>(
      initialSelection: PracticeType.sets,
      label: Text(
        AppLocalizations.of(context)!.practiceType,
        style: theme.textTheme.labelSmall,
      ),
      onSelected: (PracticeType? type) {
        widget._onSelected(type);
      },
      textStyle: theme.textTheme.labelSmall,
      dropdownMenuEntries: PracticeType.values
          .map<DropdownMenuEntry<PracticeType>>((PracticeType type) {
        return DropdownMenuEntry<PracticeType>(
          value: type,
          label: type.getLocalizedName(context),
          style: MenuItemButton.styleFrom(
            textStyle: theme.textTheme.labelSmall,
          ),
        );
      }).toList(),
    );
  }
}

class TimeSelectionWidget extends StatefulWidget {
  final String _label;
  final double _targetTime;
  final Function(double) _onTapOutside;

  TimeSelectionWidget(this._label, this._targetTime, this._onTapOutside);

  @override
  State<TimeSelectionWidget> createState() => _TimeSelectionWidgetState();
}

class _TimeSelectionWidgetState extends State<TimeSelectionWidget> {
  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          widget._label,
          style: theme.textTheme.labelSmall,
        ),
        Container(
          color: Colors.black26,
          padding: EdgeInsets.symmetric(horizontal: 5.0),
          width: 50,
          // height: 30,
          child: NumberInputField(
            decimal: true,
            onTapOutside: (value) async {
              var doubleValue = double.tryParse(value);
              doubleValue ??= DEFAULT_TARGET_TIME;
              widget._onTapOutside(doubleValue);

              FocusManager.instance.primaryFocus?.unfocus();
            },
            defaultValue: widget._targetTime.toString(),
          ),
        ),
      ],
    );
  }
}
