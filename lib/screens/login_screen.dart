import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_notifier.dart';
import '../widgets/sso_buttons.dart';
import '../utils/responsive.dart';
import 'otp_screen.dart';

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

  String? _validatePassword(String? v) {
    // Password is optional (for magic link flow)
    if (v == null || v.isEmpty) return null;
    if (v.length < 6) return 'Минимум 6 символов';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth state for errors and loading
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Вход'),
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 20.0 * Responsive.scaleWidth(context),
            vertical: 16.0,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 24 * Responsive.scaleHeight(context)),
                
                // App Icon
                _buildAppIcon(),
                SizedBox(height: 16 * Responsive.scaleHeight(context)),
                
                // App Title
                Text(
                  'TwoSpace',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: (Theme.of(context).textTheme.headlineMedium?.fontSize ?? 32) * 
                        Responsive.scaleFor(context),
                  ),
                ),
                SizedBox(height: 8 * Responsive.scaleHeight(context)),
                
                Text(
                  'Мессенджер нового поколения',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 32 * Responsive.scaleHeight(context)),
                
                // Email/Phone Input
                TextFormField(
                  controller: _emailCtl,
                  decoration: InputDecoration(
                    hintText: 'Email или номер телефона',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14 * Responsive.scaleHeight(context),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                  validator: _validateEmail,
                  keyboardType: TextInputType.emailAddress,
                ),
                SizedBox(height: 14 * Responsive.scaleHeight(context)),
                
                // Password Input
                TextFormField(
                  controller: _passCtl,
                  decoration: InputDecoration(
                    hintText: 'Пароль (опционально)',
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14 * Responsive.scaleHeight(context),
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surface,
                  ),
                  obscureText: true,
                  validator: _validatePassword,
                ),
                SizedBox(height: 8 * Responsive.scaleHeight(context)),
                
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      'Оставьте пароль пустым для входа по коду',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 24 * Responsive.scaleHeight(context)),
                
                // Login Button
                SizedBox(
                  width: double.infinity,
                  child: authState.isLoading
                      ? const SizedBox(
                          height: 50,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : ElevatedButton(
                          onPressed: _handleLogin,
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: 14 * Responsive.scaleHeight(context),
                            ),
                          ),
                          child: Text(
                            'Войти',
                            style: TextStyle(
                              fontSize: 16 * Responsive.scaleFor(context),
                            ),
                          ),
                        ),
                ),
                SizedBox(height: 12 * Responsive.scaleHeight(context)),
                
                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Theme.of(context).dividerColor)),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12 * Responsive.scaleWidth(context),
                      ),
                      child: Text('или', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    Expanded(child: Divider(color: Theme.of(context).dividerColor)),
                  ],
                ),
                SizedBox(height: 12 * Responsive.scaleHeight(context)),
                
                // SSO Buttons
                SsoButtons(
                  onSuccess: () {
                    // Navigation happens automatically via auth listener
                  },
                  disabled: authState.isLoading,
                ),
                
                SizedBox(height: 20 * Responsive.scaleHeight(context)),
                
                // Register Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Нет аккаунта? ",
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    TextButton(
                      onPressed: () => Navigator.pushNamed(context, '/register'),
                      child: const Text('Создать'),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
