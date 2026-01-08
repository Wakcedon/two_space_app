import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'otp_screen.dart';
import 'sso_webview_screen.dart';

/// Simplified LoginScreen using Riverpod for state management
/// All auth logic delegated to AuthNotifier
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final identifier = _emailCtl.text.trim();
    final password = _passCtl.text.trim();
    final notifier = ref.read(authNotifierProvider.notifier);

    try {
      // Phone number flow (starts with +)
      if (identifier.startsWith('+')) {
        await _handlePhoneLogin(identifier);
        return;
      }

      // Email with magic link (no password)
      if (password.isEmpty) {
        await _handleMagicLinkLogin(identifier);
        return;
      }

      // Standard email + password login
      await notifier.login(identifier, password);
      
      // Navigation happens automatically via auth listener
    } catch (e) {
      if (!mounted) return;
      _showError('Ошибка входа: $e');
    }
  }

  Future<void> _handlePhoneLogin(String phone) async {
    // For phone login, we need OTP flow
    // This could be moved to a separate provider in the future
    if (!mounted) return;
    
    final code = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => OtpScreen(phone: phone)),
    );
    
    if (code == null || code.isEmpty) return;
    
    // TODO: Implement phone verification in AuthNotifier
    _showError('Вход по телефону временно недоступен');
  }

  Future<void> _handleMagicLinkLogin(String email) async {
    if (!mounted) return;
    
    final code = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => OtpScreen(phone: email)),
    );
    
    if (code == null || code.isEmpty) return;
    
    // TODO: Implement magic link verification in AuthNotifier
    _showError('Вход по коду временно недоступен');
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Введите email или телефон';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = MediaQuery.of(context).size.width < 500;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _emailCtl,
              decoration: InputDecoration(
                hintText: 'Email',
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _passCtl,
              obscureText: true,
              decoration: InputDecoration(
                hintText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _login,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Login'),
            ),
            const SizedBox(height: 12),
            if (isSmallScreen) _ssoButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppIcon() {
    return Container(
      padding: EdgeInsets.all(20 * Responsive.scaleWidth(context)),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      ),
      child: Icon(
        Icons.chat,
        size: 48 * Responsive.scaleWidth(context),
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }
}
