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
  String selectSetsToPractice(Object count) {
    return 'Select sets to practice ($count selected)';
  }

  @override
  String get selectAtLeastOneSet => 'Select at least one set';

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
}
