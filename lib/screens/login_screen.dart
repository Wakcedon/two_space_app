import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/environment.dart';
import 'sso_webview_screen.dart';
import '../services/appwrite_service.dart';
import '../widgets/section_card.dart';
import '../widgets/glass_card.dart';
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
  final theme = Theme.of(context);
  final themeFill = theme.inputDecorationTheme.fillColor ?? theme.colorScheme.surface;
  final primaryColor = Color(SettingsService.themeNotifier.value.primaryColorValue);
  final textColor = theme.textTheme.bodyLarge?.color ?? theme.colorScheme.onBackground;
  final hintColor = theme.hintColor;

  final canSubmit = !_loading && !_loginLocked && _validateEmailOrPhone(emailController.text) == null && _validatePassword(passwordController.text) == null;

  return Scaffold(
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 320, maxWidth: 520),
                child: Form(
                key: _formKey,
                child: GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
                    Text('Вход', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: textColor)),
                    const SizedBox(height: UITokens.spaceLg),

                    // Form fields
                    TextFormField(
                      controller: emailController,
                        validator: _validateEmailOrPhone,
                      onChanged: (v) => setState(() {}),
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Email или +7...',
                        hintStyle: TextStyle(color: hintColor),
                        filled: true,
                        fillColor: themeFill,
                        prefixIcon: emailController.text.trim().startsWith('+') ? Icon(Icons.phone, color: theme.colorScheme.onSurface.withAlpha(140)) : Icon(Icons.email, color: theme.colorScheme.onSurface.withAlpha(140)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(UITokens.cornerLg), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                      ),
                    ),
                    const SizedBox(height: UITokens.space),
                    TextFormField(
                      controller: passwordController,
                      obscureText: _obscure,
                      validator: _validatePassword,
                        style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Пароль',
                          hintStyle: TextStyle(color: hintColor),
                        filled: true,
                        fillColor: themeFill,
                          prefixIcon: Icon(Icons.lock, color: theme.colorScheme.onSurface.withAlpha(180)),
                          suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off, color: theme.colorScheme.onSurface.withAlpha(180)),
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
                      title: Text('Запомнить вход (для автоматического входа)', style: TextStyle(color: textColor)),
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
                        child: _loading ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary)) : Text('Войти', style: TextStyle(color: Theme.of(context).colorScheme.onPrimary)),
                      ),
                    ),
                    const SizedBox(height: UITokens.space),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/register'),
                          child: Text('Создать аккаунт', style: TextStyle(color: textColor.withAlpha((0.85 * 255).round()))),
                        ),
                      // SSO buttons (open homeserver SSO redirect in browser)
                      if (Environment.useMatrix)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Column(children: [
                            Text('Войти через SSO', style: TextStyle(color: textColor.withAlpha(200))),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              ElevatedButton.icon(
                                icon: const Icon(Icons.login),
                                label: const Text('Google'),
                                onPressed: () async {
                                  // in-app SSO via embedded WebView
                                  final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'google')));
                                  if (ok == true) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вход через Google завершён')));
                                  }
                                },
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                icon: const Icon(Icons.person),
                                label: const Text('Yandex'),
                                onPressed: () async {
                                  final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'yandex')));
                                  if (ok == true) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вход через Yandex завершён')));
                                  }
                                },
                              ),
                            ]),
                          ]),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(context, '/forgot'),
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
      ),
    );
  }
}
