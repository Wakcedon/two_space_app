// User status indicator widget
import 'package:flutter/material.dart';

enum UserStatus {
  online,
  offline,
  typing,
}

class UserStatusIndicator extends StatelessWidget {
  final UserStatus status;
  final String? typingUser; // For 'typing' status: "User is typing..."

  const UserStatusIndicator({
    required this.status,
    this.typingUser,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    switch (status) {
      case UserStatus.online:
        return _buildStatusBadge(
          context,
          color: Colors.green,
          label: 'Онлайн',
          icon: Icons.circle,
        );
      case UserStatus.offline:
        return _buildStatusBadge(
          context,
          color: theme.colorScheme.outline,
          label: 'Оффлайн',
          icon: Icons.circle,
        );
      case UserStatus.typing:
        return _buildTypingIndicator(context, typingUser ?? 'Пользователь печатает...');
    }
  }

  Widget _buildStatusBadge(
    BuildContext context, {
    required Color color,
    required String label,
    required IconData icon,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 8, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTypingIndicator(BuildContext context, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 4),
        _TypingDots(),
      ],
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => __TypingDotsState();
}

class __TypingDotsState extends State<_TypingDots> with TickerProviderStateMixin {
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final value = _animationController.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < 3; i++)
              Opacity(
                opacity: (value * 3 - i).clamp(0.0, 1.0),
                child: const DotWidget(),
              ),
          ],
        );
      },
    );
  }
}

class DotWidget extends StatelessWidget {
  const DotWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}

// User status info model
class UserStatusInfo {
  final String userId;
  final UserStatus status;
  final DateTime lastSeen;
  final bool isTyping;

  UserStatusInfo({
    required this.userId,
    required this.status,
    required this.lastSeen,
    this.isTyping = false,
  });
}
