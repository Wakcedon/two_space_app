import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'otp_screen.dart';
import 'sso_webview_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtl = TextEditingController();
  final _passCtl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  final _auth = AuthService();

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final identifier = _emailCtl.text.trim();
      // Phone flow
      if (identifier.startsWith('+')) {
        final token = await _auth.sendPhoneToken(identifier);
        if (!mounted) return;
        final code = await Navigator.push<String?>(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: identifier)));
        if (code == null || code.isEmpty) return;
        await _auth.createSessionFromToken(token is Map && token.containsKey('userId') ? token['userId'] : identifier, code);
      } else {
        final password = _passCtl.text.trim();
        if (password.isEmpty) {
          final token = await _auth.sendEmailToken(identifier);
          if (!mounted) return;
          final code = await Navigator.push<String?>(context, MaterialPageRoute(builder: (_) => OtpScreen(phone: identifier)));
          if (code == null || code.isEmpty) return;
          await _auth.createSessionFromToken(token is Map && token.containsKey('userId') ? token['userId'] : identifier, code);
        } else {
          await _auth.loginUser(identifier, password);
        }
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Login failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _ssoButtons() {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      ElevatedButton.icon(onPressed: () async { final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'google'))); if (ok == true) Navigator.pushReplacementNamed(context, '/home'); }, icon: const Icon(Icons.login), label: const Text('Google')),
      const SizedBox(width: 8),
      ElevatedButton.icon(onPressed: () async { final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'yandex'))); if (ok == true) Navigator.pushReplacementNamed(context, '/home'); }, icon: const Icon(Icons.person), label: const Text('Yandex')),
    ]);
  }

  String? _validateEmail(String? v) => (v == null || v.trim().isEmpty) ? 'Введите email' : null;
  // Password may be empty to trigger magic link flow. If provided, it must be non-empty.
  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return null;
    if (v.length < 6) return 'Пароль должен быть не менее 6 символов';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Вход'), elevation: 0, backgroundColor: Theme.of(context).colorScheme.surface),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(height: 20),
              TextFormField(
                controller: _emailCtl,
                decoration: InputDecoration(
                  hintText: 'Email или номер',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                validator: _validateEmail,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _passCtl,
                decoration: InputDecoration(
                  hintText: 'Пароль',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                obscureText: true,
                validator: _validatePassword,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text('Оставьте пароль пустым для одноразового кода', style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: _loading
                    ? const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()))
                    : ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('Войти', style: TextStyle(fontSize: 16)),
                      ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Divider(color: Theme.of(context).dividerColor)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('или', style: Theme.of(context).textTheme.bodySmall),
                ),
                Expanded(child: Divider(color: Theme.of(context).dividerColor)),
              ]),
              const SizedBox(height: 12),
              _ssoButtons(),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text("Нет аккаунта? ", style: Theme.of(context).textTheme.bodyMedium),
                TextButton(onPressed: () => Navigator.pushNamed(context, '/register'), child: const Text('Создать')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}