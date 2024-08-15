import 'package:flutter/cupertino.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

enum PracticeType {
  sets,
  timeRace;

  String getLocalizedName(BuildContext context) {
    if (this == sets) {
      return AppLocalizations.of(context)!.practiceTypeSets;
    } else if (this == timeRace) {
      return AppLocalizations.of(context)!.practiceTypeTimeRace;
    } else {
      throw UnimplementedError();
    }
  }
}
