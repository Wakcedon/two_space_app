import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:two_space_app/config/environment.dart';
import 'package:two_space_app/services/dev_logger.dart';
import 'package:two_space_app/screens/dev_menu_screen.dart';
import 'package:two_space_app/services/navigation_service.dart';

/// Draggable floating square FAB used to open developer menu.
class DevFab extends StatefulWidget {
  const DevFab({super.key});

  @override
  State<DevFab> createState() => _DevFabState();
}

class _DevFabState extends State<DevFab> {
  Offset _pos = const Offset(16, 120);
  late final DevLogger _logger = DevLogger('DevFab');

  @override
  void initState() {
    super.initState();
    _logger.info('DevFab initialized');
  }

  void _openDevMenu() {
    _logger.debug('DevFab tapped');
    // Use postFrameCallback to avoid navigator issues during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = appNavigatorKey.currentState;
      if (nav != null && mounted) {
        nav.push(MaterialPageRoute(builder: (_) => const _DevMenuHost()));
      } else if (mounted) {
        try {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _DevMenuHost()));
        } catch (e) {
          _logger.error('DevFab: navigation failed: $e');
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Only show when enabled via env or in debug
    if (!(kDebugMode || Environment.enableDevTools)) return const SizedBox.shrink();

    return Positioned(
      left: _pos.dx,
      top: _pos.dy,
      child: GestureDetector(
          onTap: _openDevMenu,
        // Implement drag via pan gestures to avoid depending on an Overlay for Draggable.feedback
        onPanUpdate: (details) {
          final sz = MediaQuery.of(context).size;
          final dx = (_pos.dx + details.delta.dx).clamp(8.0, sz.width - 64.0);
          final dy = (_pos.dy + details.delta.dy).clamp(8.0, sz.height - 64.0 - MediaQuery.of(context).padding.top);
          setState(() => _pos = Offset(dx, dy));
        },
        child: _buildButton(),
      ),
    );
  }

  Widget _buildButton({double opacity = 1.0}) {
    final base = Theme.of(context).colorScheme.primary;
    return Material(
      color: base.withAlpha((opacity * 255).round()),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      elevation: 8,
      child: SizedBox(
        width: 56,
        height: 56,
        child: Center(child: Icon(Icons.developer_mode, color: Theme.of(context).colorScheme.onPrimary)),
      ),
    );
  }
}

class _DevMenuHost extends StatelessWidget {
  const _DevMenuHost({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Immediately navigate to DevMenuScreen when this host is pushed so
    // the FAB's push can show a loading scaffold momentarily.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const DevMenuScreen()));
    });
    return Scaffold(appBar: AppBar(title: const Text('Dev Menu')), body: const Center(child: CircularProgressIndicator()));
  }
}

// dev menu screen imported above
