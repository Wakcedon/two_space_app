import 'package:flutter/material.dart';

class SsoButtons extends StatelessWidget {
  const SsoButtons({Key? key}) : super(key: key);

  void _handleSsoLogin(String provider) {
    // Handle SSO login for the given provider
  }

  Widget _buildSsoButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        minimumSize: Size(double.infinity, 50), // Make button full width
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 500;
    return isSmallScreen
        ? Column(
            children: [
              _buildSsoButton(
                icon: Icons.login,
                label: 'Login with Google',
                onPressed: () => _handleSsoLogin('google'),
              ),
              const SizedBox(height: 12),
              _buildSsoButton(
                icon: Icons.person,
                label: 'Login with Yandex',
                onPressed: () => _handleSsoLogin('yandex'),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: _buildSsoButton(
                  icon: Icons.login,
                  label: 'Google',
                  onPressed: () => _handleSsoLogin('google'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSsoButton(
                  icon: Icons.person,
                  label: 'Yandex',
                  onPressed: () => _handleSsoLogin('yandex'),
                ),
              ),
            ],
          );
  }
}
