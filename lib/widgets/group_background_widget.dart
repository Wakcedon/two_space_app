import 'package:flutter/material.dart';

class GroupBackgroundWidget extends StatelessWidget {
  final String? backgroundColor;
  final String? backgroundImageUrl;
  final Widget child;

  const GroupBackgroundWidget({
    Key? key,
    this.backgroundColor,
    this.backgroundImageUrl,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Парсим HEX цвет
    Color? bgColor;
    if (backgroundColor != null) {
      try {
        bgColor = Color(int.parse(backgroundColor!.replaceFirst('#', '0xff')));
      } catch (e) {
        bgColor = null;
      }
    }

    // Если есть только цвет
    if (bgColor != null && backgroundImageUrl == null) {
      return Container(
        color: bgColor,
        child: child,
      );
    }

    // Если есть изображение
    if (backgroundImageUrl != null) {
      return Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: NetworkImage(backgroundImageUrl!),
            fit: BoxFit.cover,
            colorFilter: bgColor != null
                ? ColorFilter.mode(bgColor.withOpacity(0.3), BlendMode.overlay)
                : null,
          ),
        ),
        child: child,
      );
    }

    // Если ничего нет, просто возвращаем child
    return child;
  }
}
