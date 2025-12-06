// Enhanced avatar widget with initials and gradient backgrounds
import 'package:flutter/material.dart';

class EnhancedAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final bool showInitials;

  const EnhancedAvatar({
    this.imageUrl,
    required this.name,
    this.radius = 20,
    this.showInitials = true,
  });

  String _getInitials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.substring(0, 1).toUpperCase();
  }

  Color _getGradientColor(String name, {bool isSecondary = false}) {
    // Generate consistent color for user based on name
    final hash = name.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.purple,
      Colors.teal,
      Colors.cyan,
      Colors.indigo,
      Colors.pink,
      Colors.amber,
    ];
    final index = (hash.abs() % colors.length);
    if (isSecondary) {
      return colors[(index + 1) % colors.length];
    }
    return colors[index];
  }

  @override
  Widget build(BuildContext context) {
    final initials = _getInitials(name);
    final primaryColor = _getGradientColor(name);
    final secondaryColor = _getGradientColor(name, isSecondary: true);

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(imageUrl!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Fallback to initials with gradient background
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor, secondaryColor],
        ),
      ),
      child: showInitials
          ? Center(
              child: Text(
                initials,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: radius * 0.8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          : null,
    );
  }
}

// Group avatar with multiple user initials
class GroupAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final List<String> memberNames; // Top members for preview
  final double radius;

  const GroupAvatar({
    this.imageUrl,
    required this.name,
    this.memberNames = const [],
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          image: DecorationImage(
            image: NetworkImage(imageUrl!),
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    // Default: show group icon with member count
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Center(
        child: Icon(
          Icons.group,
          color: Theme.of(context).colorScheme.primary,
          size: radius,
        ),
      ),
    );
  }
}
