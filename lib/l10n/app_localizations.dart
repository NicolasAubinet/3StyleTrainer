import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @sessionSummary.
  ///
  /// In en, this message translates to:
  /// **'Session summary'**
  String get sessionSummary;

  /// No description provided for @timer.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get timer;

  /// No description provided for @repeatAll.
  ///
  /// In en, this message translates to:
  /// **'Repeat all'**
  String get repeatAll;

  /// No description provided for @practiceType.
  ///
  /// In en, this message translates to:
  /// **'Practice type'**
  String get practiceType;

  /// No description provided for @practiceTypeSets.
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get practiceTypeSets;

  /// No description provided for @practiceTypeTimeRace.
  ///
  /// In en, this message translates to:
  /// **'Time race'**
  String get practiceTypeTimeRace;

  /// No description provided for @practiceTypeLetterPairsList.
  ///
  /// In en, this message translates to:
  /// **'Letter pairs list'**
  String get practiceTypeLetterPairsList;

  /// No description provided for @completedAlgs.
  ///
  /// In en, this message translates to:
  /// **'Completed algs: '**
  String get completedAlgs;

  /// No description provided for @again.
  ///
  /// In en, this message translates to:
  /// **'Again'**
  String get again;

  /// No description provided for @targetTime.
  ///
  /// In en, this message translates to:
  /// **'Target time (seconds): '**
  String get targetTime;

  /// No description provided for @raceTime.
  ///
  /// In en, this message translates to:
  /// **'Race time (minutes): '**
  String get raceTime;

  /// No description provided for @showNextAlg.
  ///
  /// In en, this message translates to:
  /// **'Show next alg'**
  String get showNextAlg;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @allCasesWereSubTarget.
  ///
  /// In en, this message translates to:
  /// **'All cases were sub {targetTime}'**
  String allCasesWereSubTarget(Object targetTime);

  /// No description provided for @repeatTargetTime.
  ///
  /// In en, this message translates to:
  /// **'Repeat cases above {targetTime}s'**
  String repeatTargetTime(Object targetTime);

  /// No description provided for @corners.
  ///
  /// In en, this message translates to:
  /// **'Corners'**
  String get corners;

  /// No description provided for @edges.
  ///
  /// In en, this message translates to:
  /// **'Edges'**
  String get edges;

  /// No description provided for @flips.
  ///
  /// In en, this message translates to:
  /// **'2Flips'**
  String get flips;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @algSet.
  ///
  /// In en, this message translates to:
  /// **'Alg set'**
  String get algSet;

  /// No description provided for @selectSetsToPractice.
  ///
  /// In en, this message translates to:
  /// **'Select sets to practice ({count} selected, {algCount} algs)'**
  String selectSetsToPractice(int count, int algCount);

  /// No description provided for @selectAtLeastOneSet.
  ///
  /// In en, this message translates to:
  /// **'Select at least one set'**
  String get selectAtLeastOneSet;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @average.
  ///
  /// In en, this message translates to:
  /// **'Average: {average}'**
  String average(Object average);

  /// No description provided for @invertedAlgs.
  ///
  /// In en, this message translates to:
  /// **'Inverted algs'**
  String get invertedAlgs;

  /// No description provided for @createCustomSet.
  ///
  /// In en, this message translates to:
  /// **'Create custom set'**
  String get createCustomSet;

  /// No description provided for @editCustomSet.
  ///
  /// In en, this message translates to:
  /// **'Edit custom set'**
  String get editCustomSet;

  /// No description provided for @customSetName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get customSetName;

  /// No description provided for @customSetAlgs.
  ///
  /// In en, this message translates to:
  /// **'Algs'**
  String get customSetAlgs;

  /// No description provided for @customSetAlgsHelper.
  ///
  /// In en, this message translates to:
  /// **'Comma or newline separated'**
  String get customSetAlgsHelper;

  /// No description provided for @emptyCustomSetName.
  ///
  /// In en, this message translates to:
  /// **'Custom set name cannot be empty'**
  String get emptyCustomSetName;

  /// No description provided for @customSetNameAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'Custom set name already exists'**
  String get customSetNameAlreadyExists;

  /// No description provided for @customSetNoAlgs.
  ///
  /// In en, this message translates to:
  /// **'Add some algs before saving'**
  String get customSetNoAlgs;

  /// No description provided for @deleteCustomSetConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get deleteCustomSetConfirmTitle;

  /// No description provided for @deleteCustomSetConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete set \'{name}\'?'**
  String deleteCustomSetConfirmMessage(Object name);

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @cornersScheme.
  ///
  /// In en, this message translates to:
  /// **'Corners scheme'**
  String get cornersScheme;

  /// No description provided for @edgesScheme.
  ///
  /// In en, this message translates to:
  /// **'Edges scheme'**
  String get edgesScheme;

  /// No description provided for @cornersPiecesOrder.
  ///
  /// In en, this message translates to:
  /// **'UBL UBR UFR UFL LUB LUF LDF LDB FUL FUR FDR FDL RUF RUB RDB RDF BUR BUL BDL BDR DFL DFR DBR DBL'**
  String get cornersPiecesOrder;

  /// No description provided for @edgesPiecesOrder.
  ///
  /// In en, this message translates to:
  /// **'UB UR UF UL LU LF LD LB FU FR FD FL RU RB RD RF BU BL BD BR DF DR DB DL'**
  String get edgesPiecesOrder;

  /// No description provided for @enterScheme.
  ///
  /// In en, this message translates to:
  /// **'Enter scheme text (one letter per sticker)'**
  String get enterScheme;

  /// No description provided for @invalidSchemeSize.
  ///
  /// In en, this message translates to:
  /// **'Invalid scheme size (expected {size} characters)'**
  String invalidSchemeSize(Object size);

  /// No description provided for @schemeCannotHaveDuplicates.
  ///
  /// In en, this message translates to:
  /// **'Scheme cannot have duplicates'**
  String get schemeCannotHaveDuplicates;

  /// No description provided for @cornerBuffer.
  ///
  /// In en, this message translates to:
  /// **'Corner buffer'**
  String get cornerBuffer;

  /// No description provided for @edgeBuffer.
  ///
  /// In en, this message translates to:
  /// **'Edge buffer'**
  String get edgeBuffer;

  /// No description provided for @algTimesTitle.
  ///
  /// In en, this message translates to:
  /// **'Alg times'**
  String get algTimesTitle;

  /// No description provided for @statsType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get statsType;

  /// No description provided for @statsPeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get statsPeriod;

  /// No description provided for @dateRangeAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get dateRangeAll;

  /// No description provided for @dateRangeLastYear.
  ///
  /// In en, this message translates to:
  /// **'Last year'**
  String get dateRangeLastYear;

  /// No description provided for @dateRangeLastMonth.
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get dateRangeLastMonth;

  /// No description provided for @dateRangeLastWeek.
  ///
  /// In en, this message translates to:
  /// **'Last week'**
  String get dateRangeLastWeek;

  /// No description provided for @dateRangeToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dateRangeToday;

  /// No description provided for @noRecordedTimes.
  ///
  /// In en, this message translates to:
  /// **'No recorded times'**
  String get noRecordedTimes;

  /// No description provided for @recordTimes.
  ///
  /// In en, this message translates to:
  /// **'Record times'**
  String get recordTimes;

  /// No description provided for @recordTimesDisabledReason.
  ///
  /// In en, this message translates to:
  /// **'Turn off \'Show next alg\' to record times'**
  String get recordTimesDisabledReason;

  /// No description provided for @deleteTimeConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete time'**
  String get deleteTimeConfirmTitle;

  /// No description provided for @deleteTimeConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete this recorded time?'**
  String get deleteTimeConfirmMessage;

  /// No description provided for @exportData.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get exportData;

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(Object error);

  /// No description provided for @clearAllTimes.
  ///
  /// In en, this message translates to:
  /// **'Clear all times'**
  String get clearAllTimes;

  /// No description provided for @clearAllTimesConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete ALL your times?'**
  String get clearAllTimesConfirmMessage;

  /// No description provided for @allTimesCleared.
  ///
  /// In en, this message translates to:
  /// **'All times deleted'**
  String get allTimesCleared;

  /// No description provided for @columnAlg.
  ///
  /// In en, this message translates to:
  /// **'Alg'**
  String get columnAlg;

  /// No description provided for @columnCount.
  ///
  /// In en, this message translates to:
  /// **'Num'**
  String get columnCount;

  /// No description provided for @columnMin.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get columnMin;

  /// No description provided for @columnMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get columnMax;

  /// No description provided for @columnAvg.
  ///
  /// In en, this message translates to:
  /// **'Avg'**
  String get columnAvg;

  /// No description provided for @columnDateTime.
  ///
  /// In en, this message translates to:
  /// **'Date - time'**
  String get columnDateTime;

  /// No description provided for @columnResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get columnResult;

  /// No description provided for @columnNumber.
  ///
  /// In en, this message translates to:
  /// **'#'**
  String get columnNumber;

  /// No description provided for @columnTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get columnTime;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @themeKeycap.
  ///
  /// In en, this message translates to:
  /// **'Keycap'**
  String get themeKeycap;

  /// No description provided for @themeSlate.
  ///
  /// In en, this message translates to:
  /// **'Slate'**
  String get themeSlate;

  /// No description provided for @themeCubeFace.
  ///
  /// In en, this message translates to:
  /// **'Cube Face'**
  String get themeCubeFace;

  /// No description provided for @schemesSection.
  ///
  /// In en, this message translates to:
  /// **'Lettering schemes'**
  String get schemesSection;

  /// No description provided for @buffersSection.
  ///
  /// In en, this message translates to:
  /// **'Buffers'**
  String get buffersSection;

  /// No description provided for @practiceTypeLetterPairsShort.
  ///
  /// In en, this message translates to:
  /// **'Pairs'**
  String get practiceTypeLetterPairsShort;

  /// No description provided for @typeSubtitleLetters.
  ///
  /// In en, this message translates to:
  /// **'24-letter scheme'**
  String get typeSubtitleLetters;

  /// No description provided for @typeSubtitleFlips.
  ///
  /// In en, this message translates to:
  /// **'edge-flip cases'**
  String get typeSubtitleFlips;

  /// No description provided for @typeSubtitleTwists.
  ///
  /// In en, this message translates to:
  /// **'corner-twist cases'**
  String get typeSubtitleTwists;

  /// No description provided for @typeSubtitleCustom.
  ///
  /// In en, this message translates to:
  /// **'Sets mode only'**
  String get typeSubtitleCustom;

  /// No description provided for @twists.
  ///
  /// In en, this message translates to:
  /// **'2Twists'**
  String get twists;

  /// No description provided for @parity.
  ///
  /// In en, this message translates to:
  /// **'Parity'**
  String get parity;

  /// No description provided for @typeSubtitleParity.
  ///
  /// In en, this message translates to:
  /// **'UF/UR + 2 corners'**
  String get typeSubtitleParity;

  /// No description provided for @statsSolvesRange.
  ///
  /// In en, this message translates to:
  /// **'{count} solves · {min}–{max}s'**
  String statsSolvesRange(Object count, Object max, Object min);

  /// No description provided for @totalSolves.
  ///
  /// In en, this message translates to:
  /// **'Total solves: {count}'**
  String totalSolves(Object count);

  /// No description provided for @globalAvg.
  ///
  /// In en, this message translates to:
  /// **'Global avg: {avg}'**
  String globalAvg(Object avg);

  /// No description provided for @totalTime.
  ///
  /// In en, this message translates to:
  /// **'Total time: {time}'**
  String totalTime(Object time);

  /// No description provided for @optionsSection.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get optionsSection;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
