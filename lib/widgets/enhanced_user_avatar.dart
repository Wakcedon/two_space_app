import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class EnhancedUserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initials;
  final double radius;
  final List<Color>? gradientColors;

  const EnhancedUserAvatar({
    required this.initials,
    this.avatarUrl,
    this.radius = 20,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final defaultGradient = [
      Colors.blue.shade400,
      Colors.purple.shade400,
    ];

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: avatarUrl!,
        imageBuilder: (context, imageProvider) => CircleAvatar(
          radius: radius,
          backgroundImage: imageProvider,
        ),
        placeholder: (context, url) => _buildGradientAvatar(
          defaultGradient,
          initials,
          context,
        ),
        errorWidget: (context, url, error) => _buildGradientAvatar(
          defaultGradient,
          initials,
          context,
        ),
      );
    }

    return _buildGradientAvatar(
      gradientColors ?? defaultGradient,
      initials,
      context,
    );
  }

  Widget _buildGradientAvatar(List<Color> colors, String text, BuildContext context) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.first.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
