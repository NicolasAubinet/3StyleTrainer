// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get sessionSummary => 'Session summary';

  @override
  String get timer => 'Timer';

  @override
  String get repeatAll => 'Repeat all';

  @override
  String get practiceType => 'Practice type';

  @override
  String get practiceTypeSets => 'Sets';

  @override
  String get practiceTypeTimeRace => 'Time race';

  @override
  String get practiceTypeLetterPairsList => 'Letter pairs list';

  @override
  String get completedAlgs => 'Completed algs: ';

  @override
  String get again => 'Again';

  @override
  String get targetTime => 'Target time (seconds): ';

  @override
  String get raceTime => 'Race time (minutes): ';

  @override
  String get showNextAlg => 'Show next alg';

  @override
  String get back => 'Back';

  @override
  String allCasesWereSubTarget(Object targetTime) {
    return 'All cases were sub $targetTime';
  }

  @override
  String repeatTargetTime(Object targetTime) {
    return 'Repeat cases above ${targetTime}s';
  }

  @override
  String get corners => 'Corners';

  @override
  String get edges => 'Edges';

  @override
  String get flips => '2Flips';

  @override
  String get start => 'Start';

  @override
  String get algSet => 'Alg set';

  @override
  String selectSetsToPractice(int count, int algCount) {
    return 'Select sets to practice ($count selected, $algCount algs)';
  }

  @override
  String get selectAtLeastOneSet => 'Select at least one set';

  @override
  String get selectAll => 'Select all';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String average(Object average) {
    return 'Average: $average';
  }

  @override
  String get invertedAlgs => 'Inverted algs';

  @override
  String get createCustomSet => 'Create custom set';

  @override
  String get editCustomSet => 'Edit custom set';

  @override
  String get customSetName => 'Name';

  @override
  String get customSetAlgs => 'Algs (coma or newline separated)';

  @override
  String get emptyCustomSetName => 'Custom set name cannot be empty';

  @override
  String get customSetNameAlreadyExists => 'Custom set name already exists';

  @override
  String get customSetNoAlgs => 'Add some algs before saving';

  @override
  String get deleteCustomSetConfirmTitle => 'Confirm';

  @override
  String deleteCustomSetConfirmMessage(Object name) {
    return 'Are you sure you want to delete set \'$name\'?';
  }

  @override
  String get delete => 'Delete';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get save => 'Save';

  @override
  String get custom => 'Custom';

  @override
  String get settings => 'Settings';

  @override
  String get cornersScheme => 'Corners scheme';

  @override
  String get edgesScheme => 'Edges scheme';

  @override
  String get cornersPiecesOrder =>
      'UBL UBR UFR UFL LUB LUF LDF LDB FUL FUR FDR FDL RUF RUB RDB RDF BUR BUL BDL BDR DFL DFR DBR DBL';

  @override
  String get edgesPiecesOrder =>
      'UB UR UF UL LU LF LD LB FU FR FD FL RU RB RD RF BU BL BD BR DF DR DB DL';

  @override
  String get enterScheme => 'Enter scheme text (one letter per sticker)';

  @override
  String invalidSchemeSize(Object size) {
    return 'Invalid scheme size (expected $size characters)';
  }

  @override
  String get schemeCannotHaveDuplicates => 'Scheme cannot have duplicates';

  @override
  String get cornerBuffer => 'Corner buffer';

  @override
  String get edgeBuffer => 'Edge buffer';

  @override
  String get algTimesTitle => 'Alg times';

  @override
  String get statsType => 'Type';

  @override
  String get statsPeriod => 'Period';

  @override
  String get dateRangeAll => 'All';

  @override
  String get dateRangeLastYear => 'Last year';

  @override
  String get dateRangeLastMonth => 'Last month';

  @override
  String get dateRangeLastWeek => 'Last week';

  @override
  String get dateRangeToday => 'Today';

  @override
  String get noRecordedTimes => 'No recorded times';

  @override
  String get recordTimes => 'Record times';

  @override
  String get recordTimesDisabledReason =>
      'Turn off \'Show next alg\' to record times';

  @override
  String get deleteTimeConfirmTitle => 'Delete time';

  @override
  String get deleteTimeConfirmMessage => 'Delete this recorded time?';

  @override
  String get clearAllTimes => 'Clear all times';

  @override
  String get clearAllTimesConfirmMessage =>
      'Are you sure you want to delete ALL your times?';

  @override
  String get allTimesCleared => 'All times deleted';

  @override
  String get columnAlg => 'Alg';

  @override
  String get columnCount => 'Num';

  @override
  String get columnMin => 'Min';

  @override
  String get columnMax => 'Max';

  @override
  String get columnAvg => 'Avg';

  @override
  String get columnDateTime => 'Date - time';

  @override
  String get columnResult => 'Result';

  @override
  String get appearance => 'Appearance';

  @override
  String get theme => 'Theme';

  @override
  String get themeKeycap => 'Keycap';

  @override
  String get themeSlate => 'Slate';

  @override
  String get themeCubeFace => 'Cube Face';

  @override
  String get schemesSection => 'Lettering schemes';

  @override
  String get buffersSection => 'Buffers';

  @override
  String get practiceTypeLetterPairsShort => 'Pairs';

  @override
  String get typeSubtitleLetters => '24-letter scheme';

  @override
  String get typeSubtitleFlips => 'edge-flip cases';

  @override
  String get typeSubtitleTwists => 'corner-twist cases';

  @override
  String get typeSubtitleCustom => 'Sets mode only';

  @override
  String get twists => '2Twists';

  @override
  String get parity => 'Parity';

  @override
  String get typeSubtitleParity => 'UF/UR + 2 corners';

  @override
  String statsSolvesRange(Object count, Object max, Object min) {
    return '$count solves · $min–${max}s';
  }

  @override
  String totalSolves(Object count) {
    return 'Total solves: $count';
  }

  @override
  String globalAvg(Object avg) {
    return 'Global avg: $avg';
  }

  @override
  String totalTime(Object time) {
    return 'Total time: $time';
  }

  @override
  String get optionsSection => 'Options';
}
