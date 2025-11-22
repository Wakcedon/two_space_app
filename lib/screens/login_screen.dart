import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'otp_screen.dart';
import 'sso_webview_screen.dart';
import '../utils/responsive.dart';

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
  bool _ssoLoading = false;

  @override
  void dispose() {
    _emailCtl.dispose();
    _passCtl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loading || _ssoLoading) return; // Защита от двойного клика
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
    final isSmallScreen = MediaQuery.of(context).size.width < 500;
    
    if (isSmallScreen) {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading || _ssoLoading ? null : () async {
                if (_ssoLoading) return;
                setState(() => _ssoLoading = true);
                try {
                  final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'google')));
                  if (ok == true && mounted) Navigator.pushReplacementNamed(context, '/home');
                } finally {
                  if (mounted) setState(() => _ssoLoading = false);
                }
              },
              icon: const Icon(Icons.login),
              label: const Text('Войти через Google'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading || _ssoLoading ? null : () async {
                if (_ssoLoading) return;
                setState(() => _ssoLoading = true);
                try {
                  final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'yandex')));
                  if (ok == true && mounted) Navigator.pushReplacementNamed(context, '/home');
                } finally {
                  if (mounted) setState(() => _ssoLoading = false);
                }
              },
              icon: const Icon(Icons.person),
              label: const Text('Войти через Yandex'),
            ),
          ),
        ],
      );
    }
    
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _loading || _ssoLoading ? null : () async {
            if (_ssoLoading) return;
            setState(() => _ssoLoading = true);
            try {
              final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'google')));
              if (ok == true && mounted) Navigator.pushReplacementNamed(context, '/home');
            } finally {
              if (mounted) setState(() => _ssoLoading = false);
            }
          },
          icon: const Icon(Icons.login),
          label: const Text('Google'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton.icon(
          onPressed: _loading || _ssoLoading ? null : () async {
            if (_ssoLoading) return;
            setState(() => _ssoLoading = true);
            try {
              final ok = await Navigator.push<bool?>(context, MaterialPageRoute(builder: (_) => SsoWebviewScreen(idpId: 'yandex')));
              if (ok == true && mounted) Navigator.pushReplacementNamed(context, '/home');
            } finally {
              if (mounted) setState(() => _ssoLoading = false);
            }
          },
          icon: const Icon(Icons.person),
          label: const Text('Yandex'),
        ),
      ),
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
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(height: 24 * Responsive.scaleHeight(context)),
              // Header icon and text - масштабируемый
              Container(
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
              ),
              SizedBox(height: 16 * Responsive.scaleHeight(context)),
              Text(
                'TwoSpace',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: (Theme.of(context).textTheme.headlineMedium?.fontSize ?? 32) * Responsive.scaleFor(context),
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
              TextFormField(
                controller: _emailCtl,
                decoration: InputDecoration(
                  hintText: 'Email или номер',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14 * Responsive.scaleHeight(context)),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surface,
                ),
                validator: _validateEmail,
              ),
              SizedBox(height: 14 * Responsive.scaleHeight(context)),
              TextFormField(
                controller: _passCtl,
                decoration: InputDecoration(
                  hintText: 'Пароль',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14 * Responsive.scaleHeight(context)),
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
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  child: Text('Оставьте пароль пустым для одноразового кода', style: Theme.of(context).textTheme.bodySmall),
                ),
              ),
              SizedBox(height: 24 * Responsive.scaleHeight(context)),
              SizedBox(
                width: double.infinity,
                child: _loading
                    ? const SizedBox(height: 50, child: Center(child: CircularProgressIndicator()))
                    : ElevatedButton(
                        onPressed: _ssoLoading ? null : _login,
                        style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(vertical: 14 * Responsive.scaleHeight(context))),
                        child: Text('Войти', style: TextStyle(fontSize: 16 * Responsive.scaleFor(context))),
                      ),
              ),
              SizedBox(height: 12 * Responsive.scaleHeight(context)),
              Row(children: [
                Expanded(child: Divider(color: Theme.of(context).dividerColor)),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12 * Responsive.scaleWidth(context)),
                  child: Text('или', style: Theme.of(context).textTheme.bodySmall),
                ),
                Expanded(child: Divider(color: Theme.of(context).dividerColor)),
              ]),
              SizedBox(height: 12 * Responsive.scaleHeight(context)),
              _ssoButtons(),
              SizedBox(height: 20 * Responsive.scaleHeight(context)),
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