import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/number_input_field.dart';
import 'timer_screen.dart';

const double DEFAULT_TARGET_TIME = 2.0;

class MenuScreen extends StatefulWidget {
  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  double _targetTime = DEFAULT_TARGET_TIME;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
              child: Text(AppLocalizations.of(context)!.corners),
              onPressed: () {
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => TimerScreen(_targetTime)));
              }),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {},
            child: Text(AppLocalizations.of(context)!.edges),
          ),
          SizedBox(height: 50),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                AppLocalizations.of(context)!.targetTime,
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Container(
                color: Colors.black26,
                padding: EdgeInsets.symmetric(horizontal: 5.0),
                width: 50,
                // height: 30,
                child: NumberInputField(
                  decimal: true,
                  onChanged: (value) async {
                    SharedPreferences prefs =
                        await SharedPreferences.getInstance();
                    var doubleValue = double.tryParse(value);
                    if (doubleValue != null) {
                      prefs.setDouble("target_time", doubleValue);
                    } else {
                      prefs.remove("target_time");
                    }
                  },
                  defaultValue: _targetTime.toString(),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}
