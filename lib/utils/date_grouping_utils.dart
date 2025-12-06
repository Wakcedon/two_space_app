// Date grouping utilities
import 'package:intl/intl.dart';

enum DateGroup {
  today,
  yesterday,
  thisWeek,
  older,
}

class DateGroupingUtils {
  static DateGroup getDateGroup(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    if (checkDate == today) return DateGroup.today;
    if (checkDate == yesterday) return DateGroup.yesterday;
    if (checkDate.isAfter(weekAgo)) return DateGroup.thisWeek;
    return DateGroup.older;
  }

  static String getDateGroupLabel(DateGroup group) {
    switch (group) {
      case DateGroup.today:
        return 'Сегодня';
      case DateGroup.yesterday:
        return 'Вчера';
      case DateGroup.thisWeek:
        return 'На этой неделе';
      case DateGroup.older:
        return 'Раньше';
    }
  }

  static String formatMessageTime(DateTime time) {
    final now = DateTime.now();
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return DateFormat('HH:mm').format(time);
    }
    return DateFormat('dd.MM.yyyy HH:mm').format(time);
  }
}
