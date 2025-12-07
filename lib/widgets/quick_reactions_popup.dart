import 'package:flutter/material.dart';

class QuickReactionsPopup extends StatefulWidget {
  final Function(String emoji) onEmojiSelected;
  final Offset position;

  const QuickReactionsPopup({
    required this.onEmojiSelected,
    required this.position,
  });

  @override
  State<QuickReactionsPopup> createState() => _QuickReactionsPopupState();
}

class _QuickReactionsPopupState extends State<QuickReactionsPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  
  // Most popular emoji reactions
  static const List<String> _quickEmojis = ['👍', '❤️', '😂', '😲', '😢', '🔥', '👏', '🎉'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Positioned(
        left: widget.position.dx,
        top: widget.position.dy - 60,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _quickEmojis
                    .asMap()
                    .entries
                    .map((entry) {
                      final index = entry.key;
                      final emoji = entry.value;
                      return GestureDetector(
                        onTap: () {
                          widget.onEmojiSelected(emoji);
                          Navigator.pop(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.8,
                              end: 1.0,
                            ).animate(
                              CurvedAnimation(
                                parent: _controller,
                                curve: Interval(
                                  (index * 0.1).clamp(0.0, 0.7),
                                  ((index + 1) * 0.1).clamp(0.1, 0.8),
                                  curve: Curves.easeOut,
                                ),
                              ),
                            ),
                            child: MouseRegion(
                              onEnter: (_) => setState(() {}),
                              child: Text(emoji, style: const TextStyle(fontSize: 24)),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
