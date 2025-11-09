import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
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
  final greetings = ['Приветствуем!', 'Ку-ку!', 'Здарова!', 'Привет!', 'Хэллоу!', 'Йоу!', 'Альфа-тест!'];
  String _g = '"Привет!"';

  @override
  void initState() {
    super.initState();
    _g = greetings[Random().nextInt(greetings.length)];
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _scale = Tween<double>(begin: 0.95, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
    // After a few seconds transition to HomeScreen with fade
    _timer = Timer(const Duration(seconds: 3), () {
      _ctrl.reverse().then((_) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      });
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
    return Scaffold(
  backgroundColor: Theme.of(context).colorScheme.surface,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  UserAvatar(avatarUrl: widget.avatarUrl, avatarFileId: widget.avatarFileId, fullName: widget.name, radius: 48),
                  const SizedBox(height: 12),
                  Text(widget.name, style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  if (widget.description != null && widget.description!.isNotEmpty) Text(widget.description!, style: Theme.of(context).textTheme.bodyMedium),
                  if (widget.phone != null && widget.phone!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6.0), child: Text(widget.phone!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).textTheme.bodySmall?.color?.withAlpha((0.8 * 255).round())))),
                  const SizedBox(height: 8),
                  Text(_g, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
