import 'package:flutter/cupertino.dart';

import 'alg_structs.dart';
import 'l10n/app_localizations.dart';

enum PracticeType {
  sets,
  timeRace,
  slowest,
  letterPairsList;

  bool get isSetBased => this == sets || this == slowest;

  String getLocalizedName(BuildContext context) {
    if (this == sets) {
      return AppLocalizations.of(context)!.practiceTypeSets;
    } else if (this == timeRace) {
      return AppLocalizations.of(context)!.practiceTypeTimeRace;
    } else if (this == slowest) {
      return AppLocalizations.of(context)!.practiceTypeSlowest;
    } else if (this == letterPairsList) {
      return AppLocalizations.of(context)!.practiceTypeLetterPairsList;
    } else {
      throw UnimplementedError();
    }
  }
}

/// Screen title combining practice type and alg type, always practice-first for
/// consistency ("Time race · Corners", "Sets · Corners").
String sessionTitle(
    BuildContext context, AlgType algType, PracticeType practiceType) {
  final type = algType.getLocalizedName(context);
  final practice = practiceType.getLocalizedName(context);
  return "$practice · $type";
}

/// Whether a run records solve times
bool isRecordingRun({
  required PracticeType practiceType,
  required AlgType algType,
  required int algsShownInAdvance,
  required bool recordTimes,
}) {
  return practiceType == PracticeType.timeRace &&
      algsShownInAdvance == 0 &&
      algType != AlgType.Custom &&
      recordTimes;
}
