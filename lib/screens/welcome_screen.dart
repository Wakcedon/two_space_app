import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:two_space_app/constants/greeting_constants.dart';
import 'package:two_space_app/widgets/user_avatar.dart';

import 'home_screen.dart';

class WelcomeScreen extends StatefulWidget {
  final String name;
  final String? avatarUrl;
  final String? avatarFileId;
  final String? description;
  final String? phone;
  const WelcomeScreen({super.key, required this.name, this.avatarUrl, this.avatarFileId, this.description, this.phone});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;
  late Animation<double> _scale;
  Timer? _timer;
  late String _greeting;

  @override
  void initState() {
    super.initState();
    _greeting = GreetingConstants.greetings[Random().nextInt(GreetingConstants.greetings.length)];
    _ctrl = AnimationController(
      vsync: this,
      duration: GreetingConstants.animationDuration,
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _scale = Tween<double>(
      begin: GreetingConstants.scaleStart,
      end: GreetingConstants.scaleEnd,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    
    _ctrl.forward();
    
    // Transition to HomeScreen after displaying welcome message
    _timer = Timer(GreetingConstants.welcomeScreenDuration, _transitionToHome);
  }

  void _transitionToHome() {
    _ctrl.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(GreetingConstants.cardBorderRadius),
              ),
              elevation: GreetingConstants.cardElevation,
              child: Padding(
                padding: const EdgeInsets.all(GreetingConstants.cardPadding),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    UserAvatar(
                      avatarUrl: widget.avatarUrl,
                      avatarFileId: widget.avatarFileId,
                      fullName: widget.name,
                      radius: GreetingConstants.avatarRadius,
                    ),
                    const SizedBox(height: GreetingConstants.spacingLarge),
                    Text(
                      widget.name,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: GreetingConstants.spacingSmall),
                    if (widget.description != null && widget.description!.isNotEmpty)
                      Text(
                        widget.description!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (widget.phone != null && widget.phone!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: GreetingConstants.spacingSmall),
                        child: Text(
                          widget.phone!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withAlpha(
                              (GreetingConstants.subtleTextOpacity * 255).round(),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: GreetingConstants.spacingMedium),
                    Text(
                      _greeting,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
