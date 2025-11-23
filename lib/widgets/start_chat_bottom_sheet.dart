import 'package:flutter/material.dart';

class StartChatBottomSheet extends StatelessWidget {
  final VoidCallback onCreateGroup;
  final VoidCallback onInviteUser;
  final VoidCallback onJoinByAddress;

  const StartChatBottomSheet({
    Key? key,
    required this.onCreateGroup,
    required this.onInviteUser,
    required this.onJoinByAddress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        vertical: 24,
        horizontal: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outline.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Начать чат',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 24),
          _buildMenuItem(
            context,
            icon: Icons.add_circle_outline,
            title: 'Создать новую комнату',
            subtitle: 'Приватная или публичная группа',
            onTap: () {
              Navigator.pop(context);
              onCreateGroup();
            },
          ),
          SizedBox(height: 12),
          _buildMenuItem(
            context,
            icon: Icons.person_add_alt_1_outlined,
            title: 'Пригласить пользователя',
            subtitle: 'Найти и написать пользователю',
            onTap: () {
              Navigator.pop(context);
              onInviteUser();
            },
          ),
          SizedBox(height: 12),
          _buildMenuItem(
            context,
            icon: Icons.link_outlined,
            title: 'Присоединиться по коду',
            subtitle: 'Присоединиться к комнате по пригласительному коду',
            onTap: () {
              Navigator.pop(context);
              onJoinByAddress();
            },
          ),
          SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.2),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(16),
            color: isDark
                ? theme.colorScheme.surface.withOpacity(0.5)
                : theme.colorScheme.primary.withOpacity(0.03),
          ),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withOpacity(0.2),
                      theme.colorScheme.primary.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: theme.colorScheme.outline.withOpacity(0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
