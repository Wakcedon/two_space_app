import 'dart:async';
import 'package:flutter/material.dart';
import '../services/appwrite_service.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../widgets/app_logo.dart';
import 'welcome_screen.dart';
import 'otp_screen.dart';
import 'package:two_space_app/config/ui_tokens.dart';
import '../models/user.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _remember = false;
  bool _loginLocked = false; // temporary lock when rate-limited
  DateTime? _retryAt;
  Timer? _retryAtTimer;
  String? _errorMessage;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  final AuthService _auth = AuthService();

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final identifier = emailController.text.trim();
      
      if (identifier.startsWith('+')) {
        // Phone login via AuthService (uses SDK or REST fallback)
        final token = await _auth.sendPhoneToken(identifier);
        if (!mounted) return;

        // Navigate to OTP screen (returns the entered code or null)
        final code = await Navigator.push<String?>(
          context,
          MaterialPageRoute(builder: (_) => OtpScreen(phone: identifier)),
        );

        if (code == null || code.isEmpty || !mounted) {
          setState(() => _loading = false);
          return;
        }

        // Create session with the code
        await _auth.createSessionFromToken(token['userId'], code);
      } else {
        // Email login via AuthService (handles SDK or REST flows and JWT saving)
        await _auth.loginUser(identifier, passwordController.text.trim());
      }

      if (_remember) {
        await AppwriteService.saveCredentials(
          identifier, 
          passwordController.text.trim(),
        );
      }

      // Get user info and show welcome screen
  final account = await AppwriteService.getAccount();
  // getAccount() returns a Map<String, dynamic>; pass it directly to User.fromJson/fromMap
  final user = User.fromJson(Map<String, dynamic>.from(account as Map));

      if (!mounted) return;
      Navigator.pushReplacement(
        context, 
        MaterialPageRoute(
          builder: (_) => WelcomeScreen(
            name: user.displayName,
            avatarUrl: user.avatarUrl,
            avatarFileId: user.avatarFileId,
            description: user.description,
            phone: user.phone,
          ),
        ),
      );

    } catch (e) {
      if (!mounted) return;
      final error = AppwriteService.readableError(e);
      // If rate limit, temporarily lock the login button to avoid hammering the endpoint
      final lower = error.toLowerCase();
      if (lower.contains('rate limit') || lower.contains('429')) {
        // read server-provided retry-at if available
        final ra = await AppwriteService.getRateLimitRetryAt();
        if (ra != null && ra.isAfter(DateTime.now())) {
          _retryAt = ra;
        } else {
          _retryAt = DateTime.now().add(const Duration(seconds: 30));
        }
        _retryAtTimer?.cancel();
        _retryAtTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          if (_retryAt == null || DateTime.now().isAfter(_retryAt!)) {
            _retryAtTimer?.cancel();
            setState(() { _loginLocked = false; _retryAt = null; _errorMessage = null; });
          } else {
            final rem = _retryAt!.difference(DateTime.now());
            final ss = rem.inSeconds.remainder(60).toString().padLeft(2,'0');
            setState(() {
              _loginLocked = true;
              _errorMessage = 'Превышен лимит запросов. Повторите через ${rem.inMinutes}:$ss';
              _loading = false;
            });
          }
        });
      } else {
        setState(() {
          _errorMessage = 'Ошибка входа: $error';
          _loading = false;
        });
      }
    }
  }

  String? _validateEmailOrPhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Поле не может быть пустым';
    final val = v.trim();
    // simple email check
    final emailRegex = RegExp(r"^[^@\s]+@[^@\s]+\.[^@\s]+");
    final phoneRegex = RegExp(r"^\+?[0-9]{6,15}");
    if (!emailRegex.hasMatch(val) && !phoneRegex.hasMatch(val)) return 'Введите корректный email или телефон';
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'Введите пароль';
    if (v.length < 6) return 'Пароль должен быть не менее 6 символов';
    return null;
  }

  @override
  Widget build(BuildContext context) {
  const themeFill = Color(0xFF111217);
  final primaryColor = Color(SettingsService.themeNotifier.value.primaryColorValue);
  final primaryLuma = primaryColor.computeLuminance();
  final textColor = primaryLuma > 0.6 ? Colors.black : Colors.white;
  final hintColor = Theme.of(context).colorScheme.onSurface.withAlpha((0.65 * 255).round());

  final canSubmit = !_loading && !_loginLocked && _validateEmailOrPhone(emailController.text) == null && _validatePassword(passwordController.text) == null;

  return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12.0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8)),
                          child: Text(_errorMessage!, style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    if (_loading) const LinearProgressIndicator(minHeight: 3),
                    const Hero(tag: 'logo', child: AppLogo(large: true)),
                    const SizedBox(height: UITokens.spaceLg),
                    Text('Вход', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                    const SizedBox(height: UITokens.spaceLg),

                    // Form fields
                    TextFormField(
                      controller: emailController,
                      validator: _validateEmailOrPhone,
                      onChanged: (v) => setState(() {}),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Email или +7...',
                        hintStyle: TextStyle(color: hintColor),
                        filled: true,
                        fillColor: themeFill,
                        prefixIcon: emailController.text.trim().startsWith('+') ? const Icon(Icons.phone, color: Colors.white54) : const Icon(Icons.email, color: Colors.white54),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(UITokens.cornerLg), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      ),
                    ),
                    const SizedBox(height: UITokens.space),
                    TextFormField(
                      controller: passwordController,
                      obscureText: _obscure,
                      validator: _validatePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Пароль',
                        hintStyle: TextStyle(color: hintColor),
                        filled: true,
                        fillColor: themeFill,
                        prefixIcon: const Icon(Icons.lock, color: Colors.white54),
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: Colors.white54),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(UITokens.cornerLg), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      ),
                    ),
                    const SizedBox(height: UITokens.spaceLg),
                    CheckboxListTile(
                      value: _remember,
                      onChanged: (v) => setState(() => _remember = v ?? false),
                      title: const Text('Запомнить вход (для автоматического входа)'),
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: primaryColor,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: UITokens.spaceLg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UITokens.cornerLg)),
                        ),
                        onPressed: canSubmit ? _login : null,
                        child: _loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text('Войти', style: TextStyle(color: textColor)),
                      ),
                    ),
                    const SizedBox(height: UITokens.space),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/register'),
                          child: Text('Создать аккаунт', style: TextStyle(color: textColor.withAlpha((0.85 * 255).round()))),
                        ),
                        TextButton(
                          onPressed: () async {
                            // Simple forgot password guidance dialog
                            await showDialog<void>(context: context, builder: (c) => AlertDialog(
                              title: const Text('Сброс пароля'),
                              content: const Text('Если вы забыли пароль, обратитесь в поддержку: vaksedon@gmail.com или используйте восстановление на сервере (если доступно).'),
                              actions: [TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('ОК'))],
                            ));
                          },
                          child: Text('Забыли пароль?', style: TextStyle(color: textColor.withAlpha((0.85 * 255).round()))),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
