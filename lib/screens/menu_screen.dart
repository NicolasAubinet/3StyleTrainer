import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:three_style_trainer/alg_provider.dart';
import 'package:three_style_trainer/alg_structs.dart';
import 'package:three_style_trainer/database_manager.dart';
import 'package:three_style_trainer/practice_type.dart';
import 'package:three_style_trainer/screens/alg_set_selector_screen.dart';
import 'package:three_style_trainer/screens/settings_screen.dart';
import 'package:three_style_trainer/screens/timer_screen.dart';

import '../widgets/number_input_field.dart';

const double DEFAULT_TARGET_TIME = 2.0;

class MenuScreen extends StatefulWidget {
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  double _targetTime = DEFAULT_TARGET_TIME;
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
    });
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
            algType,
            customSets: customSets,
          ),
        ),
      );
    } else if (_practiceType == PracticeType.timeRace) {
      List<String> skippedAlgs =
          await DatabaseManager().getExecutedTimeRaceAlgs(algType);
      AlgProvider algProvider = algType == AlgType.Corner
          ? CornersAlgProvider(skippedAlgs: skippedAlgs)
          : EdgesAlgProvider(skippedAlgs: skippedAlgs);
      if (mounted && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TimerScreen(
              _practiceType,
              _targetTime,
              algProvider,
              algType,
              skippedAlgs: skippedAlgs,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

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
            onPressed: _practiceType == PracticeType.timeRace
                ? null
                : () => _onButtonPressed(context, AlgType.Custom),
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
          TargetTimeSelectionWidget(_targetTime, (targetTime) async {
            SharedPreferences prefs = await SharedPreferences.getInstance();
            prefs.setDouble("target_time", targetTime);
            setState(() {
              _targetTime = targetTime;
            });
          }),
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

class TargetTimeSelectionWidget extends StatefulWidget {
  final double _targetTime;
  final Function(double) _onTapOutside;

  TargetTimeSelectionWidget(this._targetTime, this._onTapOutside);

  @override
  State<TargetTimeSelectionWidget> createState() =>
      _TargetTimeSelectionWidgetState();
}

class _TargetTimeSelectionWidgetState extends State<TargetTimeSelectionWidget> {
  @override
  Widget build(BuildContext context) {
    var theme = Theme.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          AppLocalizations.of(context)!.targetTime,
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
