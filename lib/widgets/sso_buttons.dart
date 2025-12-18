import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/sso_webview_screen.dart';

/// Reusable SSO buttons widget for Google and Yandex authentication
/// 
/// Usage:
/// ```dart
/// SsoButtons(
///   onSuccess: () => Navigator.pushReplacementNamed(context, '/home'),
///   disabled: isLoading,
/// )
/// ```
class SsoButtons extends ConsumerStatefulWidget {
  final VoidCallback? onSuccess;
  final bool disabled;

  const SsoButtons({
    super.key,
    this.onSuccess,
    this.disabled = false,
  });

  @override
  ConsumerState<SsoButtons> createState() => _SsoButtonsState();
}

class _SsoButtonsState extends ConsumerState<SsoButtons> {
  bool _loading = false;

  Future<void> _handleSsoLogin(String provider) async {
    if (_loading || widget.disabled) return;

    setState(() => _loading = true);
    try {
      final success = await Navigator.push<bool?>(
        context,
        MaterialPageRoute(
          builder: (_) => SsoWebviewScreen(idpId: provider),
        ),
      );

      if (success == true && mounted) {
        widget.onSuccess?.call();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка SSO: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 500;
    final isDisabled = _loading || widget.disabled;

    if (isSmallScreen) {
      return Column(
        children: [
          _buildSsoButton(
            icon: Icons.login,
            label: 'Войти через Google',
            onPressed: isDisabled ? null : () => _handleSsoLogin('google'),
          ),
          const SizedBox(height: 10),
          _buildSsoButton(
            icon: Icons.person,
            label: 'Войти через Yandex',
            onPressed: isDisabled ? null : () => _handleSsoLogin('yandex'),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: _buildSsoButton(
            icon: Icons.login,
            label: 'Google',
            onPressed: isDisabled ? null : () => _handleSsoLogin('google'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSsoButton(
            icon: Icons.person,
            label: 'Yandex',
            onPressed: isDisabled ? null : () => _handleSsoLogin('yandex'),
          ),
        ),
      ],
    );
  }

  Widget _buildSsoButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: _loading
          ? const SizedBox(
              height: 50,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
    );
  }
}
