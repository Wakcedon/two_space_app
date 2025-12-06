// Chat list item widget with preview and unread badge
import 'package:flutter/material.dart';
import '../models/chat.dart';

class ChatListItem extends StatelessWidget {
  final Chat chat;
  final bool isSelected;
  final VoidCallback onTap;
  final Function(Chat)? onLongPress;

  const ChatListItem({
    required this.chat,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
  });

  String _getPreview(String text) {
    if (text.isEmpty) return '(нет сообщений)';
    if (text.length > 50) return '${text.substring(0, 50)}...';
    return text;
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    if (time.year == now.year && time.month == now.month && time.day == now.day) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    return '${time.day}.${time.month}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _getPreview(chat.lastMessage);
    final timeStr = _formatTime(chat.lastMessageTime);

    return ListTile(
      selected: isSelected,
      onTap: onTap,
      onLongPress: onLongPress != null ? () => onLongPress!(chat) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundImage: chat.avatarUrl != null
                ? NetworkImage(chat.avatarUrl!)
                : null,
            child: chat.avatarUrl == null
                ? Text(chat.name.isEmpty ? '?' : chat.name[0])
                : null,
          ),
          if (chat.unreadCount > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      title: Text(
        chat.name,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: chat.unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        preview,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
          fontWeight: chat.unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeStr,
            style: theme.textTheme.bodySmall,
          ),
          if (chat.members.length > 1) ...[
            const SizedBox(height: 2),
            Text(
              '${chat.members.length} участников',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
