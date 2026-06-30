import 'package:flutter/widgets.dart';

import 'l10n/app_localizations.dart';

// Date filter for the alg times screen
enum StatsDateRange {
  all,
  lastYear,
  lastMonth,
  lastWeek,
  today;

  String getLocalizedName(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (this) {
      case StatsDateRange.all:
        return l10n.dateRangeAll;
      case StatsDateRange.lastYear:
        return l10n.dateRangeLastYear;
      case StatsDateRange.lastMonth:
        return l10n.dateRangeLastMonth;
      case StatsDateRange.lastWeek:
        return l10n.dateRangeLastWeek;
      case StatsDateRange.today:
        return l10n.dateRangeToday;
    }
  }

  int? cutoffMs() {
    final now = DateTime.now();
    switch (this) {
      case StatsDateRange.all:
        return null;
      case StatsDateRange.lastYear:
        return now.subtract(Duration(days: 365)).millisecondsSinceEpoch;
      case StatsDateRange.lastMonth:
        return now.subtract(Duration(days: 30)).millisecondsSinceEpoch;
      case StatsDateRange.lastWeek:
        return now.subtract(Duration(days: 7)).millisecondsSinceEpoch;
      case StatsDateRange.today:
        return DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    }
  }
}
