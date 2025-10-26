import 'package:flutter/cupertino.dart';

import 'l10n/app_localizations.dart';

enum PracticeType {
  sets,
  timeRace,
  letterPairsList;

  String getLocalizedName(BuildContext context) {
    if (this == sets) {
      return AppLocalizations.of(context)!.practiceTypeSets;
    } else if (this == timeRace) {
      return AppLocalizations.of(context)!.practiceTypeTimeRace;
    } else if (this == letterPairsList) {
      return AppLocalizations.of(context)!.practiceTypeLetterPairsList;
    } else {
      throw UnimplementedError();
    }
  }
}
