// Message grouping widget
import 'package:flutter/material.dart';

class MessageDateDivider extends StatelessWidget {
  final String dateLabel;

  const MessageDateDivider({required this.dateLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              dateLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
          Expanded(
            child: Divider(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
          ),
        ],
      ),
    );
  }
}

// Helper class for grouping messages by date
class GroupedMessages<T> {
  final Map<String, List<T>> groups;

  GroupedMessages({required this.groups});

  factory GroupedMessages.fromMessages(
    List<T> messages,
    DateTime Function(T) getTime,
    String Function(String) getLabel,
  ) {
    final grouped = <String, List<T>>{};
    
    for (final msg in messages) {
      final time = getTime(msg);
      final group = _getGroupKey(time);
      final label = getLabel(group);
      
      if (!grouped.containsKey(label)) {
        grouped[label] = [];
      }
      grouped[label]!.add(msg);
    }

    return GroupedMessages(groups: grouped);
  }

  static String _getGroupKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final checkDate = DateTime(date.year, date.month, date.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    if (checkDate == today) return 'today';
    if (checkDate == yesterday) return 'yesterday';
    if (checkDate.isAfter(weekAgo)) return 'week';
    return 'older:${checkDate.year}-${checkDate.month}-${checkDate.day}';
  }
}
